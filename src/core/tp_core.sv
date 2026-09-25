// tp_core.sv — TinyPulse-RV: a 2-stage RV32I core with the Xpulse time
// extension. This file is glue and the execute state machine only; every
// datapath element lives in its own file.
//
// Pipeline
// --------
//   F  : tp_fetch     — PC, one instruction buffer, prediction
//   DX : this module      — decode, register read, execute, writeback
//
// Everything in DX happens in one cycle for the common case, which is why
// there is no forwarding unit (see tp_hazard.sv for why that is sound).
// Four things can hold DX for longer than a cycle, and each has a state:
//
//   EX_SHIFT : the iterative shifter is running
//   EX_MEM   : a load or store is outstanding on the data bus
//   EX_WAIT  : a TWAIT is parked on a deadline
//   EX_HALT  : ECALL or EBREAK retired
//
// Critical path (what sets Fmax): register file read -> ALU 33-bit adder ->
// writeback mux -> register file write. Shifts, branch comparison and target
// formation are all off that path by construction.
`default_nettype none

module tp_core
#(
    parameter int          NREG     = 16,           // 16 = RV32E
    parameter int          AW       = 4,            // $clog2(NREG)
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter bit          BARREL   = 1'b0,
    parameter bit          BIMODAL  = 1'b0,
    parameter int          NENT     = 16,
    parameter int          NIDX     = 4
) (
    input  wire  logic        clk,
    input  wire  logic        rst,

    // instruction bus (read only)
    output logic              imem_req,
    output logic [31:0]       imem_addr,
    input  wire  logic        imem_rvalid,
    input  wire  logic [31:0] imem_rdata,

    // data bus
    output logic              dmem_req,
    output logic [31:0]       dmem_addr,
    output logic              dmem_we,
    output logic [31:0]       dmem_wdata,
    output logic [3:0]        dmem_be,
    input  wire  logic        dmem_rvalid,
    input  wire  logic [31:0] dmem_rdata,

    // sync unit port (Xpulse instructions reach the timebase through here)
    output logic              t_valid,     // strobe for side-effecting ops
    output logic [2:0]        t_op,
    output logic [6:0]        t_sub,
    output logic [31:0]       t_rs1,
    output logic [31:0]       t_rs2,
    input  wire  logic [31:0] t_rdata,     // combinational read result
    input  wire  logic [31:0] t_now,       // live timebase, for TWAIT

    // status / debug
    output logic              halted,
    output logic              illegal,
    output logic [31:0]       dbg_pc
);

    // -----------------------------------------------------------------
    // Execute state encoding (declared first: the datapath references it)
    // -----------------------------------------------------------------
    localparam logic [2:0] EX_RUN   = 3'd0;
    localparam logic [2:0] EX_SHIFT = 3'd1;
    localparam logic [2:0] EX_MEM   = 3'd2;
    localparam logic [2:0] EX_WAIT  = 3'd3;
    localparam logic [2:0] EX_HALT  = 3'd4;

    logic [2:0]    state;
    logic [AW-1:0] rd_q;
    logic          load_q;
    logic [31:0]   deadline_q;
    logic          illegal_q;
    logic [2:0]    funct3_q;
    logic [1:0]    addr_lo_q;
    logic [31:0]   mem_addr_q, mem_wdata_q;
    logic [3:0]    mem_be_q;
    logic          mem_we_q;

    // -----------------------------------------------------------------
    // Fetch
    // -----------------------------------------------------------------
    logic        if_valid, if_ready, if_flush;
    logic [31:0] if_instr, if_pc, if_next_pc;
    logic        redirect;
    logic [31:0] redirect_pc;
    logic        upd_valid, upd_taken;

    tp_fetch #(
        .RESET_PC(RESET_PC), .BIMODAL(BIMODAL), .NENT(NENT), .NIDX(NIDX)
    ) u_fetch (
        .clk        (clk),
        .rst        (rst),
        .imem_req   (imem_req),
        .imem_addr  (imem_addr),
        .imem_rvalid(imem_rvalid),
        .imem_rdata (imem_rdata),
        .if_valid   (if_valid),
        .if_instr   (if_instr),
        .if_pc      (if_pc),
        .if_next_pc (if_next_pc),
        .if_ready   (if_ready),
        .redirect   (redirect),
        .redirect_pc(redirect_pc),
        .upd_valid  (upd_valid),
        .upd_pc     (if_pc),
        .upd_taken  (upd_taken)
    );

    // -----------------------------------------------------------------
    // Decode
    // -----------------------------------------------------------------
    logic [tp_pkg::CTRL_W-1:0] ctrl;
    logic [31:0] imm;

    // Unpacked control fields. This concatenation mirrors the one at the
    // bottom of tp_decode.sv; if they ever disagree the test suite
    // fails immediately and loudly, which is the point of packing in one
    // place instead of nineteen.
    logic       c_legal, c_rf_we;
    logic [2:0] c_wb_sel;
    logic [3:0] c_alu_op;
    logic [1:0] c_shift_op;
    logic       c_alu_a_pc, c_alu_b_imm;
    logic [2:0] c_imm_sel;
    logic       c_is_branch, c_is_jal, c_is_jalr;
    logic       c_mem_read, c_mem_write;
    logic [2:0] c_funct3;
    logic       c_is_time;
    logic [2:0] c_time_op;
    logic [6:0] c_time_sub;
    logic       c_is_fence, c_is_system;

    assign {c_legal, c_rf_we, c_wb_sel, c_alu_op, c_shift_op,
            c_alu_a_pc, c_alu_b_imm, c_imm_sel, c_is_branch,
            c_is_jal, c_is_jalr, c_mem_read, c_mem_write, c_funct3,
            c_is_time, c_time_op, c_time_sub, c_is_fence,
            c_is_system} = ctrl;

    tp_decode u_decode (
        .instr(if_instr),
        .ctrl (ctrl)
    );

    tp_imm_gen u_imm (
        .instr(if_instr),
        .sel  (c_imm_sel),
        .imm  (imm)
    );

    // RV32E uses the low AW bits of each 5-bit specifier. A specifier above
    // x15 is illegal; TinyPulse ignores the top bit and raises the ILLEGAL
    // status bit rather than paying for a trap unit.
    logic [AW-1:0] rd_idx, rs1_idx, rs2_idx;
    assign rd_idx  = if_instr[7  +: AW];
    assign rs1_idx = if_instr[15 +: AW];
    assign rs2_idx = if_instr[20 +: AW];

    logic uses_rs1, uses_rs2, spec_violation;
    always_comb begin
        uses_rs1 = !((if_instr[6:0] == tp_pkg::OPC_LUI)   ||
                     (if_instr[6:0] == tp_pkg::OPC_AUIPC) ||
                     (if_instr[6:0] == tp_pkg::OPC_JAL));
        uses_rs2 =  ((if_instr[6:0] == tp_pkg::OPC_OP)     ||
                     (if_instr[6:0] == tp_pkg::OPC_BRANCH) ||
                     (if_instr[6:0] == tp_pkg::OPC_STORE)  ||
                     (c_is_time && (c_time_op == tp_pkg::TF3_ARM)));
        if (AW >= 5)
            spec_violation = 1'b0;
        else
            spec_violation = (c_rf_we  && if_instr[11]) ||
                             (uses_rs1    && if_instr[19]) ||
                             (uses_rs2    && if_instr[24]);
    end

    // -----------------------------------------------------------------
    // Register file
    // -----------------------------------------------------------------
    logic          rf_we;
    logic [AW-1:0] rf_waddr;
    logic [31:0]   rf_wdata, rs1_val, rs2_val;

    tp_regfile #(.NREG(NREG), .AW(AW)) u_rf (
        .clk   (clk),
        .we    (rf_we),
        .waddr (rf_waddr),
        .wdata (rf_wdata),
        .raddr1(rs1_idx),
        .raddr2(rs2_idx),
        .rdata1(rs1_val),
        .rdata2(rs2_val)
    );

    // -----------------------------------------------------------------
    // Execute datapath
    // -----------------------------------------------------------------
    logic [31:0] alu_a, alu_b, alu_y;

    assign alu_a = c_alu_a_pc  ? if_pc : rs1_val;
    assign alu_b = c_alu_b_imm ? imm   : rs2_val;

    tp_alu u_alu (
        .a (alu_a),
        .b (alu_b),
        .op(c_alu_op),
        .y (alu_y)
    );

    logic ctp_eq, ctp_lt, ctp_ltu;
    logic br_taken;

    tp_branch_comp u_bcmp (
        .rs1    (rs1_val),
        .rs2    (rs2_val),
        .ctp_eq (ctp_eq),
        .ctp_lt (ctp_lt),
        .ctp_ltu(ctp_ltu)
    );

    tp_branch_unit u_bunit (
        .funct3 (c_funct3),
        .ctp_eq (ctp_eq),
        .ctp_lt (ctp_lt),
        .ctp_ltu(ctp_ltu),
        .taken  (br_taken)
    );

    logic        sh_start, sh_busy;
    logic [31:0] sh_y;
    logic [4:0]  shamt;

    assign shamt = c_alu_b_imm ? if_instr[24:20] : rs2_val[4:0];

    tp_shifter #(.BARREL(BARREL)) u_shift (
        .clk  (clk),
        .rst  (rst),
        .start(sh_start),
        .a    (rs1_val),
        .shamt(shamt),
        .op   (c_shift_op),
        .y    (sh_y),
        .busy (sh_busy)
    );

    // One LSU instance serves both directions. In EX_RUN it sees the live
    // instruction (store lane placement, computed at `fire` and latched);
    // in EX_MEM it sees the latched funct3/offset (load sign extension).
    logic [2:0]  lsu_funct3;
    logic [1:0]  lsu_addr_lo;
    logic [31:0] lsu_wdata, lsu_load;
    logic [3:0]  lsu_be;

    assign lsu_funct3  = (state == EX_RUN) ? c_funct3 : funct3_q;
    assign lsu_addr_lo = (state == EX_RUN) ? alu_y[1:0]  : addr_lo_q;

    tp_lsu u_lsu (
        .funct3    (lsu_funct3),
        .addr_lo   (lsu_addr_lo),
        .store_data(rs2_val),
        .mem_wdata (lsu_wdata),
        .mem_be    (lsu_be),
        .mem_rdata (dmem_rdata),
        .load_data (lsu_load)
    );

    // -----------------------------------------------------------------
    // Hazard / stall policy
    // -----------------------------------------------------------------
    logic fire, ex_ready, ex_stall, mem_busy, wait_busy;

    assign ex_ready  = (state == EX_RUN);
    assign mem_busy  = (state == EX_MEM);
    assign wait_busy = (state == EX_WAIT);

    tp_hazard u_hazard (
        .if_valid  (if_valid),
        .ex_ready  (ex_ready),
        .shift_busy(state == EX_SHIFT),
        .mem_busy  (mem_busy),
        .wait_busy (wait_busy),
        .halted    (state == EX_HALT),
        .redirect  (redirect),
        .if_ready  (if_ready),
        .if_flush  (if_flush),
        .ex_stall  (ex_stall)
    );

    assign fire = if_ready;

    // -----------------------------------------------------------------
    // Time comparisons. Both use a signed difference so the test stays
    // correct across the 2^32 rollover of the timebase.
    // -----------------------------------------------------------------
    logic deadline_reached, twait_now;
    assign deadline_reached = ($signed(t_now - deadline_q) >= 0);
    assign twait_now        = ($signed(t_now - rs1_val)    >= 0);

    // -----------------------------------------------------------------
    // Next-PC resolution. A redirect is raised only when the resolved
    // next PC differs from the one fetch already went after, so a correct
    // prediction costs nothing.
    // -----------------------------------------------------------------
    logic [31:0] target, actual_next_pc;
    always_comb begin
        target = c_is_jalr ? {alu_y[31:1], 1'b0} : alu_y;
        if (c_is_jal || c_is_jalr)
            actual_next_pc = target;
        else if (c_is_branch && br_taken)
            actual_next_pc = target;
        else
            actual_next_pc = if_pc + 32'd4;
    end

    assign redirect    = fire && (actual_next_pc != if_next_pc);
    assign redirect_pc = actual_next_pc;
    assign upd_valid   = fire && c_is_branch;
    assign upd_taken   = br_taken;

    // which multi-cycle path does this instruction take?
    logic go_shift, go_mem, go_wait;
    assign go_shift = (c_shift_op != tp_pkg::SH_NONE) && sh_busy;
    assign go_mem   = c_mem_read || c_mem_write;
    assign go_wait  = c_is_time && (c_time_op == tp_pkg::TF3_WAIT) && !twait_now;

    assign sh_start = fire && (c_shift_op != tp_pkg::SH_NONE);

    // -----------------------------------------------------------------
    // Sync unit strobe: only ops with side effects pulse it
    // -----------------------------------------------------------------
    always_comb begin
        t_valid = 1'b0;
        if (fire && c_is_time) begin
            unique case (c_time_op)
                tp_pkg::TF3_POP, tp_pkg::TF3_ARM, tp_pkg::TF3_PULSE, tp_pkg::TF3_MARK, tp_pkg::TF3_CTL: t_valid = 1'b1;
                default:                                        t_valid = 1'b0;
            endcase
        end
    end

    assign t_op  = c_time_op;
    assign t_sub = c_time_sub;
    assign t_rs1 = rs1_val;
    assign t_rs2 = rs2_val;

    // -----------------------------------------------------------------
    // Writeback
    // -----------------------------------------------------------------
    logic [31:0] wb_single;
    always_comb begin
        unique case (c_wb_sel)
            tp_pkg::WB_ALU:   wb_single = alu_y;
            tp_pkg::WB_SHIFT: wb_single = sh_y;
            tp_pkg::WB_MEM:   wb_single = lsu_load;
            tp_pkg::WB_PC4:   wb_single = if_pc + 32'd4;
            tp_pkg::WB_TIME:  wb_single = t_rdata;
            default:  wb_single = alu_y;
        endcase
    end

    always_comb begin
        rf_we    = 1'b0;
        rf_waddr = rd_q;
        rf_wdata = wb_single;

        if (fire && c_rf_we && !go_shift && !go_mem) begin
            rf_we    = 1'b1;
            rf_waddr = rd_idx;
            rf_wdata = wb_single;
        end else if ((state == EX_SHIFT) && !sh_busy) begin
            rf_we    = 1'b1;
            rf_wdata = sh_y;
        end else if ((state == EX_MEM) && dmem_rvalid && load_q) begin
            rf_we    = 1'b1;
            rf_wdata = lsu_load;
        end
    end

    // -----------------------------------------------------------------
    // Data bus: one driver, fed entirely from the latched request
    // -----------------------------------------------------------------
    assign dmem_req   = (state == EX_MEM);
    assign dmem_addr  = mem_addr_q;
    assign dmem_we    = mem_we_q;
    assign dmem_wdata = mem_wdata_q;
    assign dmem_be    = mem_be_q;

    // -----------------------------------------------------------------
    // Sequential
    // -----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= EX_RUN;
            rd_q        <= '0;
            load_q      <= 1'b0;
            deadline_q  <= 32'd0;
            illegal_q   <= 1'b0;
            funct3_q    <= 3'd0;
            addr_lo_q   <= 2'd0;
            mem_addr_q  <= 32'd0;
            mem_wdata_q <= 32'd0;
            mem_be_q    <= 4'd0;
            mem_we_q    <= 1'b0;
        end else begin
            unique case (state)

                EX_RUN: begin
                    if (fire) begin
                        rd_q      <= rd_idx;
                        funct3_q  <= c_funct3;
                        addr_lo_q <= alu_y[1:0];

                        if (!c_legal || spec_violation)
                            illegal_q <= 1'b1;

                        if (c_is_system) begin
                            state <= EX_HALT;
                        end else if (go_shift) begin
                            state <= EX_SHIFT;
                        end else if (go_mem) begin
                            state       <= EX_MEM;
                            load_q      <= c_mem_read;
                            mem_addr_q  <= {alu_y[31:2], 2'b00};
                            mem_we_q    <= c_mem_write;
                            mem_wdata_q <= lsu_wdata;
                            mem_be_q    <= lsu_be;
                        end else if (go_wait) begin
                            state      <= EX_WAIT;
                            deadline_q <= rs1_val;
                        end
                    end
                end

                EX_SHIFT: if (!sh_busy)         state <= EX_RUN;
                EX_MEM:   if (dmem_rvalid)      state <= EX_RUN;
                EX_WAIT:  if (deadline_reached) state <= EX_RUN;
                EX_HALT:                        state <= EX_HALT;
                default:                        state <= EX_RUN;
            endcase
        end
    end

    assign halted  = (state == EX_HALT);
    assign illegal = illegal_q;
    assign dbg_pc  = if_pc;

    // c_is_fence is decoded for documentation and for a future ordering
    // unit; with one core, one bus and no cache there is nothing to order,
    // so FENCE retires through the normal single-cycle path.
    wire _unused = &{1'b0, if_flush, ex_stall, imm[31], c_is_fence, 1'b0};

endmodule : tp_core
