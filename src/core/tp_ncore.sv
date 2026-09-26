// tp_ncore.sv — nibble-serial RV32E core with the Xpulse timing instructions.
//
// Every value moves through the datapath four bits per clock, least
// significant nibble first. A 32-bit add is eight clocks through a 4-bit
// adder with a carry flip-flop between them. That sounds slow, and would be
// on a chip with on-die memory, but TinyPulse fetches every instruction over
// a 4-bit QSPI bus: a word takes at least 16 clocks to arrive. An 8-clock
// execute is not the bottleneck. What it buys is area: one 4-bit adder
// instead of 32-bit ones, 4-bit register read ports instead of 32-bit ones,
// and no barrel shifter. The whole core is about a third of the 32-bit one
// it replaced, and that is the difference between a 4x2 chip (560 EUR) and
// a 2x2 chip (280 EUR).
//
// The idea is the same one TinyQV (Michael Bell) uses to fit a RISC-V
// microcontroller in 2x2 tiles. This implementation is independent.
//
// Execution model
// ---------------
// `phase` is a free-running 3-bit counter locked to the register file's
// rotation (see tp_nregfile.sv). All arithmetic happens in PASSes: eight
// clocks with phase = 0..7. A pass may only begin at phase 0, so after an
// instruction arrives the core waits in ALIGN for the counter to come round.
//
//   FETCH  --instr-->  ALIGN  -->  PASS (first)  -->  one of:
//        next instruction                          (most ALU ops, jumps, branches)
//        SHIFT -> ALIGN -> PASS (second)          (shifts)
//        MEM ----> ALIGN -> PASS (second)         (loads)   / FETCH (stores)
//        XP  ----> ALIGN -> PASS (second)         (Xpulse ops that return a value)
//        XP  ----> TWAIT                          (TWAIT not yet due)
//        ALIGN -> PASS (second)                   (SLT family: result known at the end)
//        HALT                                     (ECALL, EBREAK)
//
// The second pass copies the 32-bit `mdr` register into rd, a nibble per
// clock. It exists because some results are only known after all eight
// nibbles have been seen — a comparison, a load, a shift — and rd's nibble 0
// is written first.
//
// Registers outside the register file
//   ir   32  the instruction
//   pc   30  word address of the instruction (bits 1:0 are always zero)
//   mar  32  assembles an address or rs1 value a nibble at a time
//   mdr  32  assembles rs2 / holds load data / is the shift register
//
// Timing unit
// -----------
// Xpulse instructions (custom-0 opcode) run a first pass that assembles rs1
// into `mar` and rs2 into `mdr`, then spend one clock in XP presenting both
// to the sync unit as 32-bit values. That is the same interface the 32-bit
// core used, so sync_unit.sv did not change.
//
// Not implemented, by design: interrupts, CSRs, misaligned access traps.
// An illegal instruction is skipped and latches the ILLEGAL status bit.
`default_nettype none

module tp_ncore #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter logic [31:0] BOOT_PC  = 32'h4000_0000
) (
    input  wire  logic        clk,
    input  wire  logic        rst,
    input  wire  logic        boot,       // sampled during reset: start in the boot ROM
    // instruction port
    output logic              imem_req,
    output logic [31:0]       imem_addr,
    input  wire  logic        imem_rvalid,
    input  wire  logic [31:0] imem_rdata,
    // data port
    output logic              dmem_req,
    output logic [31:0]       dmem_addr,
    output logic              dmem_we,
    output logic [31:0]       dmem_wdata,
    output logic [3:0]        dmem_be,
    input  wire  logic        dmem_rvalid,
    input  wire  logic [31:0] dmem_rdata,
    // timing unit
    output logic              t_valid,
    output logic [2:0]        t_op,
    output logic [6:0]        t_sub,
    output logic [31:0]       t_rs1,
    output logic [31:0]       t_rs2,
    input  wire  logic [31:0] t_rdata,
    input  wire  logic [31:0] t_now,
    // status
    output logic              halted,
    output logic              illegal,
    output logic [31:0]       dbg_pc
);
    // TWAIT keeps encoding 3 so testbenches that wait for "parked on a
    // deadline" work unchanged across the core rewrite.
    localparam logic [2:0] S_FETCH = 3'd0;
    localparam logic [2:0] S_ALIGN = 3'd1;
    localparam logic [2:0] S_PASS  = 3'd2;
    localparam logic [2:0] S_TWAIT = 3'd3;
    localparam logic [2:0] S_HALT  = 3'd4;
    localparam logic [2:0] S_MEM   = 3'd5;
    localparam logic [2:0] S_XP    = 3'd6;
    localparam logic [2:0] S_SHIFT = 3'd7;

    logic [2:0]  state;
    logic [2:0]  phase;
    logic        second;          // the current/next pass is the write-back pass
    logic [31:0] ir;
    logic [31:2] pc;
    logic [31:0] mar, mdr;
    logic [4:0]  shamt;
    logic        carry_q, acarry_q, eq_q;
    logic        illegal_q;

    // ------------------------------------------------------------------
    // Decode (combinational, from ir)
    // ------------------------------------------------------------------
    logic [6:0] opc;
    logic [2:0] f3;
    logic [6:0] f7;
    assign opc = ir[6:0];
    assign f3  = ir[14:12];
    assign f7  = ir[31:25];

    logic is_lui, is_auipc, is_jal, is_jalr, is_br, is_ld, is_st;
    logic is_opi, is_op, is_fence, is_sys, is_xp;
    assign is_lui   = (opc == tp_pkg::OPC_LUI);
    assign is_auipc = (opc == tp_pkg::OPC_AUIPC);
    assign is_jal   = (opc == tp_pkg::OPC_JAL);
    assign is_jalr  = (opc == tp_pkg::OPC_JALR);
    assign is_br    = (opc == tp_pkg::OPC_BRANCH);
    assign is_ld    = (opc == tp_pkg::OPC_LOAD);
    assign is_st    = (opc == tp_pkg::OPC_STORE);
    assign is_opi   = (opc == tp_pkg::OPC_OPIMM);
    assign is_op    = (opc == tp_pkg::OPC_OP);
    assign is_fence = (opc == tp_pkg::OPC_FENCE);
    assign is_sys   = (opc == tp_pkg::OPC_SYSTEM);
    assign is_xp    = (opc == tp_pkg::OPC_CUSTOM0);

    logic is_alu, is_shift, is_slt;
    assign is_alu   = is_op || is_opi;
    assign is_shift = is_alu && (f3 == 3'b001 || f3 == 3'b101);
    assign is_slt   = is_alu && (f3 == 3'b010 || f3 == 3'b011);

    // Which register specifiers the instruction actually uses. RV32E has
    // x0..x15, so a specifier with bit 4 set is illegal.
    logic uses_rd, uses_rs1, uses_rs2;
    assign uses_rd  = is_lui || is_auipc || is_jal || is_jalr || is_ld || is_alu ||
                      (is_xp && (f3 == tp_pkg::TF3_TIME || f3 == tp_pkg::TF3_POP ||
                                 f3 == tp_pkg::TF3_STAT || f3 == tp_pkg::TF3_MARK));
    assign uses_rs1 = is_jalr || is_br || is_ld || is_st || is_alu ||
                      (is_xp && !(f3 == tp_pkg::TF3_TIME || f3 == tp_pkg::TF3_POP ||
                                  f3 == tp_pkg::TF3_STAT));
    assign uses_rs2 = is_br || is_st || is_op || (is_xp && f3 == tp_pkg::TF3_ARM);

    logic legal;
    always_comb begin
        unique case (1'b1)
            is_lui, is_auipc, is_jal, is_fence: legal = 1'b1;
            is_jalr: legal = (f3 == 3'b000);
            is_br:   legal = (f3 != 3'b010) && (f3 != 3'b011);
            is_ld:   legal = (f3 == 3'b000) || (f3 == 3'b001) || (f3 == 3'b010) ||
                             (f3 == 3'b100) || (f3 == 3'b101);
            is_st:   legal = (f3 == 3'b000) || (f3 == 3'b001) || (f3 == 3'b010);
            is_opi:  legal = (f3 == 3'b001) ? (f7 == 7'h00)
                           : (f3 == 3'b101) ? (f7 == 7'h00 || f7 == 7'h20)
                           : 1'b1;
            is_op:   legal = (f7 == 7'h00) ||
                             (f7 == 7'h20 && (f3 == 3'b000 || f3 == 3'b101));
            is_sys:  legal = (f3 == 3'b000);          // ECALL / EBREAK
            is_xp:   legal = (f3 != tp_pkg::TF3_CTL) ||
                             (f7 == tp_pkg::TCTL_ADJ) || (f7 == tp_pkg::TCTL_RATE) ||
                             (f7 == tp_pkg::TCTL_CFG) || (f7 == tp_pkg::TCTL_PW);
            default: legal = 1'b0;
        endcase
        if ((uses_rd && ir[11]) || (uses_rs1 && ir[19]) || (uses_rs2 && ir[24]))
            legal = 1'b0;
    end

    // Immediate, then the nibble of it that belongs to this phase.
    logic [31:0] imm;
    always_comb begin
        if (is_st)                  imm = {{20{ir[31]}}, ir[31:25], ir[11:7]};
        else if (is_br)             imm = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
        else if (is_lui || is_auipc) imm = {ir[31:12], 12'd0};
        else if (is_jal)            imm = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};
        else                        imm = {{20{ir[31]}}, ir[31:20]};
    end

    logic [31:0] pc_full, pc4_full;
    assign pc_full  = {pc, 2'b00};
    assign pc4_full = {pc + 30'd1, 2'b00};

    logic [3:0] imm_n, pc_n, pc4_n;
    assign imm_n = imm     [{phase, 2'b00} +: 4];
    assign pc_n  = pc_full [{phase, 2'b00} +: 4];
    assign pc4_n = pc4_full[{phase, 2'b00} +: 4];

    // ------------------------------------------------------------------
    // Register file
    // ------------------------------------------------------------------
    logic [3:0] rs1_n, rs2_n, rf_wd;
    logic       rf_we;
    tp_nregfile u_rf (
        .clk(clk),
        .ra (ir[18:15]), .rb(ir[23:20]),
        .qa (rs1_n),     .qb(rs2_n),
        .we (rf_we),     .wa(ir[10:7]), .wd(rf_wd)
    );

    // ------------------------------------------------------------------
    // Nibble datapath
    // ------------------------------------------------------------------
    logic in_pass, last;
    assign in_pass = (state == S_PASS);
    assign last    = (phase == 3'd7);

    // Main adder: ALU, comparisons, and rs1+imm addresses.
    logic       sub;
    logic [3:0] a_n, b_n, bx_n, sum_n;
    logic       cin, cout;
    assign sub  = (is_op && f3 == 3'b000 && ir[30]) || is_slt || is_br;
    assign a_n  = is_auipc ? pc_n : is_lui ? 4'd0 : rs1_n;
    assign b_n  = (is_op || is_br) ? rs2_n : is_xp ? 4'd0 : imm_n;
    assign bx_n = b_n ^ {4{sub}};
    assign cin  = (phase == 3'd0) ? sub : carry_q;
    assign {cout, sum_n} = {1'b0, a_n} + {1'b0, bx_n} + {4'd0, cin};

    // Target adder: pc + imm for JAL and branches, alongside the compare.
    logic [3:0] tgt_n;
    logic       acin, acout;
    assign acin = (phase == 3'd0) ? 1'b0 : acarry_q;
    assign {acout, tgt_n} = {1'b0, pc_n} + {1'b0, imm_n} + {4'd0, acin};

    // Comparison, valid on the last nibble.
    logic eq_all, lt_s, lt_u;
    assign eq_all = ((phase == 3'd0) ? 1'b1 : eq_q) && (a_n == b_n);
    assign lt_u   = !cout;
    assign lt_s   = (a_n[3] != b_n[3]) ? a_n[3] : sum_n[3];

    logic taken;
    always_comb begin
        unique case (f3)
            3'b000:  taken =  eq_all;
            3'b001:  taken = !eq_all;
            3'b100:  taken =  lt_s;
            3'b101:  taken = !lt_s;
            3'b110:  taken =  lt_u;
            3'b111:  taken = !lt_u;
            default: taken = 1'b0;
        endcase
    end

    // Result nibble for instructions that finish in one pass.
    logic [3:0] res_n;
    always_comb begin
        if (is_jal || is_jalr) res_n = pc4_n;
        else if (is_alu) begin
            unique case (f3)
                3'b100:  res_n = a_n ^ b_n;
                3'b110:  res_n = a_n | b_n;
                3'b111:  res_n = a_n & b_n;
                default: res_n = sum_n;
            endcase
        end else res_n = sum_n;               // LUI, AUIPC
    end

    logic single_write;
    assign single_write = is_lui || is_auipc || is_jal || is_jalr ||
                          (is_alu && !is_shift && !is_slt);

    assign rf_we = in_pass && (ir[10:7] != 4'd0) && legal &&
                   (second || single_write);
    assign rf_wd = second ? mdr[3:0] : res_n;

    // The value `mar` will hold after this clock — on the last nibble of a
    // pass, that is the finished 32-bit address or target.
    logic [3:0]  mar_in;
    logic [31:0] mar_next;
    assign mar_in   = (is_jal || is_br) ? tgt_n : sum_n;
    assign mar_next = {mar_in, mar[31:4]};

    // ------------------------------------------------------------------
    // Load / store lanes (same conventions as the 32-bit LSU: store data is
    // replicated across lanes and the byte enables pick the lanes)
    // ------------------------------------------------------------------
    logic [31:0] ld_val;
    logic [7:0]  ld_byte;
    logic [15:0] ld_half;
    assign ld_byte = dmem_rdata[{mar[1:0], 3'b000} +: 8];
    assign ld_half = mar[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    always_comb begin
        unique case (f3)
            3'b000:  ld_val = {{24{ld_byte[7]}},  ld_byte};
            3'b001:  ld_val = {{16{ld_half[15]}}, ld_half};
            3'b100:  ld_val = {24'd0, ld_byte};
            3'b101:  ld_val = {16'd0, ld_half};
            default: ld_val = dmem_rdata;
        endcase
    end

    always_comb begin
        unique case (f3[1:0])
            2'b00:   begin dmem_wdata = {4{mdr[7:0]}};  dmem_be = 4'b0001 << mar[1:0]; end
            2'b01:   begin dmem_wdata = {2{mdr[15:0]}}; dmem_be = mar[1] ? 4'b1100 : 4'b0011; end
            default: begin dmem_wdata = mdr;            dmem_be = 4'b1111; end
        endcase
    end

    assign dmem_req  = (state == S_MEM);
    assign dmem_addr = {mar[31:2], 2'b00};
    assign dmem_we   = is_st;

    assign imem_req  = (state == S_FETCH);
    assign imem_addr = pc_full;

    // ------------------------------------------------------------------
    // Timing unit port
    // ------------------------------------------------------------------
    logic xp_writes, xp_side;
    assign xp_writes = (f3 == tp_pkg::TF3_TIME) || (f3 == tp_pkg::TF3_POP) ||
                       (f3 == tp_pkg::TF3_STAT) || (f3 == tp_pkg::TF3_MARK);
    assign xp_side   = (f3 == tp_pkg::TF3_POP)  || (f3 == tp_pkg::TF3_ARM) ||
                       (f3 == tp_pkg::TF3_PULSE)|| (f3 == tp_pkg::TF3_MARK) ||
                       (f3 == tp_pkg::TF3_CTL);

    assign t_valid = (state == S_XP) && xp_side;
    assign t_op    = f3;
    assign t_sub   = f7;
    assign t_rs1   = mar;
    assign t_rs2   = mdr;

    // signed(now - deadline) >= 0, wrap-safe: only the sign bit matters
    logic [31:0] t_delta;
    logic        deadline_reached;
    assign t_delta          = t_now - mar;
    assign deadline_reached = !t_delta[31];
    wire  _unused_delta     = &{1'b0, t_delta[30:0], 1'b0};

    // ------------------------------------------------------------------
    // Shifter step (on mdr)
    // ------------------------------------------------------------------
    // Where to go to start the write-back pass: straight in if the next
    // clock is phase 0, otherwise wait for it.
    logic [2:0] to_wb;
    assign to_wb = (phase == 3'd7) ? S_PASS : S_ALIGN;

    logic sh_left, sh_fill, sh_big;
    assign sh_left = (f3 == 3'b001);
    assign sh_fill = ir[30] && mdr[31];          // SRA keeps the sign
    assign sh_big  = (shamt >= 5'd4);

    // ------------------------------------------------------------------
    // Sequential
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        phase <= rst ? 3'd0 : phase + 3'd1;

        if (rst) begin
            state     <= S_FETCH;
            pc        <= boot ? BOOT_PC[31:2] : RESET_PC[31:2];
            second    <= 1'b0;
            illegal_q <= 1'b0;
            ir        <= 32'h0000_0013;           // NOP until the first fetch
        end else begin
            // carries and the equality chain advance during every pass
            if (in_pass) begin
                carry_q  <= cout;
                acarry_q <= acout;
                eq_q     <= eq_all;
            end

            unique case (state)
                S_FETCH: if (imem_rvalid) begin
                    ir     <= imem_rdata;
                    second <= 1'b0;
                    state  <= (phase == 3'd7) ? S_PASS : S_ALIGN;
                end

                S_ALIGN: if (phase == 3'd7) state <= S_PASS;

                S_PASS: begin
                    if (second) begin
                        mdr <= {4'd0, mdr[31:4]};
                        if (last) state <= S_FETCH;
                    end else begin
                        mar <= mar_next;
                        mdr <= {is_shift ? rs1_n : rs2_n, mdr[31:4]};
                        if (phase == 3'd0)
                            shamt <= is_op ? {1'b0, rs2_n} : ir[24:20];
                        else if (phase == 3'd1 && is_op)
                            shamt[4] <= rs2_n[0];

                        if (last) begin
                            pc <= pc + 30'd1;          // default: fall through
                            if (!legal) begin
                                illegal_q <= 1'b1;
                                state     <= S_FETCH;
                            end else if (is_sys) begin
                                pc    <= pc;           // PC stays on the ECALL
                                state <= S_HALT;
                            end else if (is_jal || is_jalr ||
                                         (is_br && taken)) begin
                                pc    <= mar_next[31:2];
                                state <= S_FETCH;
                            end else if (is_slt) begin
                                // result is ready exactly as phase 0 comes
                                // round, so the write-back pass follows at once
                                mdr    <= {31'd0, (f3 == 3'b010) ? lt_s : lt_u};
                                second <= 1'b1;
                                state  <= S_PASS;
                            end else if (is_shift) begin
                                state  <= S_SHIFT;
                            end else if (is_ld || is_st) begin
                                state  <= S_MEM;
                            end else if (is_xp) begin
                                state  <= S_XP;
                            end else begin
                                state  <= S_FETCH;
                            end
                        end
                    end
                end

                S_SHIFT: begin
                    if (shamt == 5'd0) begin
                        second <= 1'b1;
                        state  <= to_wb;
                    end else if (sh_big) begin
                        mdr   <= sh_left ? {mdr[27:0], 4'd0} : {{4{sh_fill}}, mdr[31:4]};
                        shamt <= shamt - 5'd4;
                    end else begin
                        mdr   <= sh_left ? {mdr[30:0], 1'b0} : {sh_fill, mdr[31:1]};
                        shamt <= shamt - 5'd1;
                    end
                end

                S_MEM: if (dmem_rvalid) begin
                    if (is_ld) begin
                        mdr    <= ld_val;
                        second <= 1'b1;
                        state  <= to_wb;
                    end else begin
                        state  <= S_FETCH;
                    end
                end

                S_XP: begin
                    mdr <= t_rdata;
                    if (f3 == tp_pkg::TF3_WAIT) begin
                        state <= deadline_reached ? S_FETCH : S_TWAIT;
                    end else if (xp_writes) begin
                        second <= 1'b1;
                        state  <= to_wb;
                    end else begin
                        state  <= S_FETCH;
                    end
                end

                S_TWAIT: if (deadline_reached) state <= S_FETCH;

                S_HALT: state <= S_HALT;

                default: state <= S_FETCH;
            endcase
        end
    end

    assign halted  = (state == S_HALT);
    assign illegal = illegal_q;
    assign dbg_pc  = pc_full;

    // fence needs no action: one core, one bus, no cache, nothing to order
    wire _unused = &{1'b0, is_fence, 1'b0};
endmodule : tp_ncore
