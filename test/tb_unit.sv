// tb_unit.sv — self-checking unit tests for each block on its own.
//
// The system test in tb_soc.sv proves the parts work together. This proves
// each part is right in isolation, including the cases a program is unlikely
// to hit: signed/unsigned compare boundaries, a zero shift amount, a queue
// overflow, a timebase rate trim.
//
// Run with:  iverilog -g2012 -o tb_unit.vvp -s tb_unit <sources> && vvp tb_unit.vvp
`default_nettype none
`timescale 1ns/1ps

module tb_unit;
    import tp_pkg::*;

    integer errors = 0;
    integer checks = 0;

    task chk(input cond, input string name);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  FAIL  %0s", name);
            end
        end
    endtask

    task section(input string name);
        $display("\n[%0s]", name);
    endtask

    reg clk = 1'b0;
    always #5 clk = ~clk;

    // =================================================================
    // ALU
    // =================================================================
    reg  [31:0] a_in, b_in;
    reg  [3:0]  aop;
    wire [31:0] alu_y;

    tp_alu u_alu (.a(a_in), .b(b_in), .op(aop), .y(alu_y));

    task alu_case(input [31:0] a, input [31:0] b, input [3:0] op,
                  input [31:0] expect_y, input string name);
        begin
            a_in = a; b_in = b; aop = op;
            #1;
            chk(alu_y === expect_y, name);
            if (alu_y !== expect_y)
                $display("        a=%08x b=%08x got=%08x want=%08x",
                         a, b, alu_y, expect_y);
        end
    endtask

    // =================================================================
    // Immediate generator
    // =================================================================
    reg  [31:0] ig_instr;
    reg  [2:0]  ig_sel;
    wire [31:0] ig_imm;

    tp_imm_gen u_imm (.instr(ig_instr), .sel(ig_sel), .imm(ig_imm));

    // =================================================================
    // Branch comparator + branch unit
    // =================================================================
    reg  [31:0] br_a, br_b;
    reg  [2:0]  br_f3;
    wire        bc_eq, bc_lt, bc_ltu;
    wire        br_taken;

    tp_branch_comp u_bc (.rs1(br_a), .rs2(br_b),
                             .ctp_eq(bc_eq), .ctp_lt(bc_lt), .ctp_ltu(bc_ltu));
    tp_branch_unit u_bu (.funct3(br_f3), .ctp_eq(bc_eq), .ctp_lt(bc_lt),
                             .ctp_ltu(bc_ltu), .taken(br_taken));

    task br_case(input [31:0] x, input [31:0] y, input [2:0] f3,
                 input expect_t, input string name);
        begin
            br_a = x; br_b = y; br_f3 = f3;
            #1;
            chk(br_taken === expect_t, name);
        end
    endtask

    // =================================================================
    // Load/store unit
    // =================================================================
    reg  [2:0]  ls_f3;
    reg  [1:0]  ls_lo;
    reg  [31:0] ls_store, ls_rdata;
    wire [31:0] ls_wdata, ls_load;
    wire [3:0]  ls_be;

    tp_lsu u_lsu (
        .funct3(ls_f3), .addr_lo(ls_lo), .store_data(ls_store),
        .mem_wdata(ls_wdata), .mem_be(ls_be),
        .mem_rdata(ls_rdata), .load_data(ls_load)
    );

    // =================================================================
    // Shifter (iterative build, the one that goes on the tile)
    // =================================================================
    reg         sh_rst = 1'b1, sh_start = 1'b0;
    reg  [31:0] sh_a;
    reg  [4:0]  sh_amt;
    reg  [1:0]  sh_op;
    wire [31:0] sh_y;
    wire        sh_busy;

    tp_shifter #(.BARREL(1'b0)) u_sh (
        .clk(clk), .rst(sh_rst), .start(sh_start),
        .a(sh_a), .shamt(sh_amt), .op(sh_op), .y(sh_y), .busy(sh_busy)
    );

    task sh_case(input [31:0] a, input [4:0] amt, input [1:0] op,
                 input [31:0] expect_y, input string name);
        integer guard;
        begin
            @(negedge clk);
            sh_a = a; sh_amt = amt; sh_op = op; sh_start = 1'b1;
            @(negedge clk);
            sh_start = 1'b0;
            guard = 0;
            while (sh_busy && guard < 64) begin
                @(negedge clk);
                guard = guard + 1;
            end
            chk(sh_y === expect_y, name);
            if (sh_y !== expect_y)
                $display("        a=%08x amt=%0d got=%08x want=%08x",
                         a, amt, sh_y, expect_y);
        end
    endtask

    // =================================================================
    // Timebase
    // =================================================================
    reg         tb_rst = 1'b1, tb_rate_we = 1'b0, tb_adj_we = 1'b0;
    reg  [31:0] tb_rate = 32'd0, tb_adj = 32'd0;
    wire [31:0] tb_now;

    sync_timebase #(.FRACW(24)) u_tb (
        .clk(clk), .rst(tb_rst),
        .rate_we(tb_rate_we), .rate_in(tb_rate),
        .adj_we(tb_adj_we), .adj_in(tb_adj), .now(tb_now)
    );

    // =================================================================
    // Event queue
    // =================================================================
    reg         fq_rst = 1'b1, fq_push = 1'b0, fq_pop = 1'b0;
    reg  [31:0] fq_wdata = 32'd0;
    wire [31:0] fq_rdata;
    wire        fq_empty, fq_full, fq_ovf;
    wire [1:0]  fq_count;

    sync_event_fifo #(.DEPTH(2), .PTRW(1)) u_fq (
        .clk(clk), .rst(fq_rst), .push(fq_push), .wdata(fq_wdata),
        .pop(fq_pop), .rdata(fq_rdata), .empty(fq_empty), .full(fq_full),
        .count(fq_count), .overflow(fq_ovf)
    );

    // =================================================================
    // Capture lane
    // =================================================================
    reg        cp_rst = 1'b1;
    reg  [7:0] cp_pin = 8'h00;
    wire [7:0] cp_evt, cp_rise, cp_level;

    sync_capture #(.NCH(8), .FILTW(0)) u_cp (
        .clk(clk), .rst(cp_rst), .pin(cp_pin),
        .en(8'hFF), .fall(8'h00), .both(1'b0),
        .evt(cp_evt), .evt_rise(cp_rise), .level(cp_level)
    );

    // =================================================================
    // Register file. The no-bypass behaviour below is the regression
    // test for the combinational loop that Verilator caught: a
    // write-through bypass here fed an instruction its own result as
    // its own operand.
    // =================================================================
    reg         rf_we = 1'b0;
    reg  [3:0]  rf_waddr = 4'd0, rf_ra1 = 4'd0, rf_ra2 = 4'd0;
    reg  [31:0] rf_wdata = 32'd0;
    wire [31:0] rf_rd1, rf_rd2;

    tp_regfile #(.NREG(16), .AW(4)) u_rf (
        .clk(clk), .we(rf_we), .waddr(rf_waddr), .wdata(rf_wdata),
        .raddr1(rf_ra1), .raddr2(rf_ra2), .rdata1(rf_rd1), .rdata2(rf_rd2)
    );

    task rf_write(input [3:0] a, input [31:0] d);
        begin
            @(negedge clk);
            rf_we = 1'b1; rf_waddr = a; rf_wdata = d;
            @(negedge clk);
            rf_we = 1'b0;
        end
    endtask

    // =================================================================
    // Hazard policy (pure combinational)
    // =================================================================
    reg  hz_if_valid, hz_ex_ready, hz_shift, hz_mem, hz_wait, hz_halt, hz_redir;
    wire hz_if_ready, hz_if_flush, hz_ex_stall;

    tp_hazard u_hz (
        .if_valid(hz_if_valid), .ex_ready(hz_ex_ready),
        .shift_busy(hz_shift), .mem_busy(hz_mem), .wait_busy(hz_wait),
        .halted(hz_halt), .redirect(hz_redir),
        .if_ready(hz_if_ready), .if_flush(hz_if_flush), .ex_stall(hz_ex_stall)
    );

    task hz_set(input v, input r, input sh, input mm, input wt,
                input hl, input rd);
        begin
            hz_if_valid = v; hz_ex_ready = r; hz_shift = sh; hz_mem = mm;
            hz_wait = wt; hz_halt = hl; hz_redir = rd;
            #1;
        end
    endtask

    // =================================================================
    // Bimodal branch predictor (the 2x2 profile's setting, which no
    // other directed test exercises)
    // =================================================================
    reg         bp_rst = 1'b1, bp_upd = 1'b0, bp_taken = 1'b0;
    reg  [31:0] bp_instr = 32'd0, bp_pc = 32'd0, bp_upd_pc = 32'd0;
    wire        bp_pred;
    wire [31:0] bp_target;

    tp_bpred #(.BIMODAL(1'b1), .NENT(16), .NIDX(4)) u_bp (
        .clk(clk), .rst(bp_rst), .instr(bp_instr), .pc(bp_pc),
        .predict_taken(bp_pred), .predict_target(bp_target),
        .upd_valid(bp_upd), .upd_pc(bp_upd_pc), .upd_taken(bp_taken)
    );

    task bp_train(input [31:0] pc_in, input taken);
        begin
            @(negedge clk);
            bp_upd = 1'b1; bp_upd_pc = pc_in; bp_taken = taken;
            @(negedge clk);
            bp_upd = 1'b0;
        end
    endtask

    integer i, latency;
    reg [31:0] t_mark;

    initial begin
        $display("\n=== TinyPulse-Skywater130 unit tests ===");

        // -------------------------------------------------------------
        section("tp_alu");
        alu_case(32'd7, 32'd5, ALU_ADD,  32'd12,        "ADD");
        alu_case(32'd7, 32'd5, ALU_SUB,  32'd2,         "SUB");
        alu_case(32'h0000_0000, 32'h0000_0001, ALU_SUB,
                 32'hFFFF_FFFF, "SUB borrows across zero");
        alu_case(32'hF0F0_F0F0, 32'h0FF0_0FF0, ALU_AND,
                 32'h00F0_00F0, "AND");
        alu_case(32'hF0F0_0000, 32'h0000_0F0F, ALU_OR,
                 32'hF0F0_0F0F, "OR");
        alu_case(32'hFFFF_0000, 32'hFFFF_FFFF, ALU_XOR,
                 32'h0000_FFFF, "XOR");
        alu_case(32'd5, 32'd9, ALU_SLT,  32'd1, "SLT positive pair");
        alu_case(32'hFFFF_FFFF, 32'd1, ALU_SLT, 32'd1,
                 "SLT -1 < 1 (signed)");
        alu_case(32'hFFFF_FFFF, 32'd1, ALU_SLTU, 32'd0,
                 "SLTU 0xFFFFFFFF > 1 (unsigned)");
        alu_case(32'h8000_0000, 32'h7FFF_FFFF, ALU_SLT, 32'd1,
                 "SLT survives signed overflow");
        alu_case(32'h8000_0000, 32'h7FFF_FFFF, ALU_SLTU, 32'd0,
                 "SLTU on the same pair");
        alu_case(32'd3, 32'd3, ALU_SLT, 32'd0, "SLT equal is false");
        alu_case(32'hDEAD_BEEF, 32'h1234_5678, ALU_COPY_B,
                 32'h1234_5678, "COPY_B (LUI)");
        alu_case(32'hDEAD_BEEF, 32'h1234_5678, ALU_COPY_A,
                 32'hDEAD_BEEF, "COPY_A");

        // -------------------------------------------------------------
        section("tp_imm_gen");
        // addi x2, x0, 400  ->  0x19000113, I-immediate = 400
        ig_instr = 32'h1900_0113; ig_sel = IMM_I; #1;
        chk(ig_imm === 32'd400, "I-type +400");
        // addi x2, x0, -1   ->  0xFFF00113
        ig_instr = 32'hFFF0_0113; ig_sel = IMM_I; #1;
        chk(ig_imm === 32'hFFFF_FFFF, "I-type sign extends -1");
        // sw x6, 4(x7)      ->  0x0063A223, S-immediate = 4
        ig_instr = 32'h0063_A223; ig_sel = IMM_S; #1;
        chk(ig_imm === 32'd4, "S-type +4");
        // lui x7, 0x10000   ->  0x100003B7
        ig_instr = 32'h1000_03B7; ig_sel = IMM_U; #1;
        chk(ig_imm === 32'h1000_0000, "U-type << 12");
        // bne x1,x2,-8      ->  B-immediate = -8
        ig_instr = 32'hFE20_9CE3; ig_sel = IMM_B; #1;
        chk(ig_imm === 32'hFFFF_FFF8, "B-type -8 (backward branch)");
        // jal x0, +16       ->  0x0100006F
        ig_instr = 32'h0100_006F; ig_sel = IMM_J; #1;
        chk(ig_imm === 32'd16, "J-type +16");
        ig_sel = IMM_NONE; #1;
        chk(ig_imm === 32'd0, "no immediate selected reads zero");

        // -------------------------------------------------------------
        section("tp_branch_unit");
        br_case(32'd5, 32'd5, 3'b000, 1'b1, "BEQ equal");
        br_case(32'd5, 32'd6, 3'b000, 1'b0, "BEQ unequal");
        br_case(32'd5, 32'd6, 3'b001, 1'b1, "BNE");
        br_case(32'hFFFF_FFFF, 32'd0, 3'b100, 1'b1, "BLT -1 < 0");
        br_case(32'hFFFF_FFFF, 32'd0, 3'b110, 1'b0, "BLTU -1 not < 0");
        // signed: 0 >= -1 is true. unsigned: 0 >= 0xFFFFFFFF is false.
        br_case(32'd0, 32'hFFFF_FFFF, 3'b101, 1'b1, "BGE 0 >= -1 signed");
        br_case(32'd0, 32'hFFFF_FFFF, 3'b111, 1'b0, "BGEU 0 >= 0xFFFFFFFF false");
        br_case(32'd7, 32'd7, 3'b101, 1'b1, "BGE equal is taken");
        br_case(32'd7, 32'd7, 3'b111, 1'b1, "BGEU equal is taken");
        br_case(32'd7, 32'd7, 3'b010, 1'b0, "reserved funct3 never taken");

        // -------------------------------------------------------------
        section("tp_lsu");
        ls_f3 = 3'b000; ls_lo = 2'b10; ls_store = 32'h0000_00AB; #1;
        chk(ls_be === 4'b0100,           "SB byte enable at offset 2");
        chk(ls_wdata[23:16] === 8'hAB,   "SB data lands in lane 2");

        ls_f3 = 3'b001; ls_lo = 2'b10; ls_store = 32'h0000_BEEF; #1;
        chk(ls_be === 4'b1100,           "SH byte enable at offset 2");
        chk(ls_wdata[31:16] === 16'hBEEF,"SH data lands in the high half");

        ls_f3 = 3'b010; ls_lo = 2'b00; ls_store = 32'hDEAD_BEEF; #1;
        chk(ls_be === 4'b1111,           "SW byte enable");
        chk(ls_wdata === 32'hDEAD_BEEF,  "SW data passes through");

        ls_rdata = 32'h8090_A0FF;
        ls_f3 = 3'b000; ls_lo = 2'b00; #1;
        chk(ls_load === 32'hFFFF_FFFF,   "LB sign extends 0xFF");
        ls_f3 = 3'b100; ls_lo = 2'b00; #1;
        chk(ls_load === 32'h0000_00FF,   "LBU zero extends 0xFF");
        ls_f3 = 3'b000; ls_lo = 2'b11; #1;
        chk(ls_load === 32'hFFFF_FF80,   "LB sign extends 0x80");
        ls_f3 = 3'b001; ls_lo = 2'b10; #1;
        chk(ls_load === 32'hFFFF_8090,   "LH sign extends the high half");
        ls_f3 = 3'b101; ls_lo = 2'b10; #1;
        chk(ls_load === 32'h0000_8090,   "LHU zero extends the high half");
        ls_f3 = 3'b010; #1;
        chk(ls_load === 32'h8090_A0FF,   "LW passes through");

        // -------------------------------------------------------------
        section("tp_shifter (iterative)");
        @(negedge clk); sh_rst = 1'b0;
        sh_case(32'h0000_0001, 5'd4,  SH_SLL, 32'h0000_0010, "SLL by 4");
        sh_case(32'h8000_0000, 5'd31, SH_SRL, 32'h0000_0001, "SRL by 31");
        sh_case(32'h8000_0000, 5'd4,  SH_SRA, 32'hF800_0000, "SRA keeps sign");
        sh_case(32'h7FFF_FFFF, 5'd4,  SH_SRA, 32'h07FF_FFFF, "SRA positive");
        sh_case(32'hDEAD_BEEF, 5'd0,  SH_SLL, 32'hDEAD_BEEF,
                "shift by zero returns the operand");
        sh_case(32'h0000_0001, 5'd31, SH_SLL, 32'h8000_0000, "SLL by 31");

        // -------------------------------------------------------------
        section("sync_timebase");
        @(negedge clk); tb_rst = 1'b0;
        @(negedge clk);
        t_mark = tb_now;
        repeat (100) @(negedge clk);
        chk((tb_now - t_mark) === 32'd100,
            "free running: exactly one tick per clock");

        // a step of +1000 applies in a single clock and loses no tick
        @(negedge clk);
        t_mark = tb_now;
        tb_adj = 32'd1000; tb_adj_we = 1'b1;
        @(negedge clk);
        tb_adj_we = 1'b0;
        chk((tb_now - t_mark) === 32'd1001, "TADJ steps by +1000 plus the tick");

        // rate trim: 2^23 means one extra tick every two clocks
        @(negedge clk);
        tb_rate = 32'h0080_0000; tb_rate_we = 1'b1;
        @(negedge clk);
        tb_rate_we = 1'b0;
        @(negedge clk);
        t_mark = tb_now;
        repeat (100) @(negedge clk);
        chk((tb_now - t_mark) === 32'd150,
            "rate +2^23 adds 50 extra ticks in 100 clocks");

        // -------------------------------------------------------------
        section("sync_event_fifo");
        @(negedge clk); fq_rst = 1'b0;
        chk(fq_empty === 1'b1, "empty after reset");
        @(negedge clk); fq_wdata = 32'hAAAA_0001; fq_push = 1'b1;
        @(negedge clk); fq_wdata = 32'hBBBB_0002;
        @(negedge clk); fq_push = 1'b0;
        #1;
        chk(fq_count === 2'd2, "two entries queued");
        chk(fq_full  === 1'b1, "queue reports full");
        chk(fq_rdata === 32'hAAAA_0001, "head is the oldest entry");
        chk(fq_ovf   === 1'b0, "no overflow yet");

        @(negedge clk); fq_wdata = 32'hCCCC_0003; fq_push = 1'b1;
        @(negedge clk); fq_push = 1'b0;
        #1;
        chk(fq_ovf === 1'b1, "pushing into a full queue sets overflow");

        @(negedge clk); fq_pop = 1'b1;
        @(negedge clk); fq_pop = 1'b0;
        #1;
        chk(fq_rdata === 32'hBBBB_0002, "pop advances to the next entry");
        @(negedge clk); fq_pop = 1'b1;
        @(negedge clk); fq_pop = 1'b0;
        #1;
        chk(fq_empty === 1'b1, "queue drains to empty");

        // -------------------------------------------------------------
        section("sync_capture");
        @(negedge clk); cp_rst = 1'b0;
        repeat (4) @(negedge clk);
        chk(cp_evt === 8'h00, "idle produces no events");

        latency = 0;
        @(negedge clk); cp_pin[3] = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            #1;
            if (cp_evt[3] && latency == 0) latency = i + 1;
        end
        // two flops of synchroniser, so the event appears on the second
        // clock after the pin moves — and always on the second, which is
        // the property that makes the timestamp calibratable.
        chk(latency == 2, "rising edge detected 2 clocks after the pin moves");
        if (latency != 2)
            $display("        latency was %0d clocks, expected 2", latency);

        @(negedge clk);
        chk(cp_level[3] === 1'b1, "filtered level follows the pin");
        chk(cp_evt === 8'h00, "the event is a one-clock pulse");

        // falling edge must not fire while `fall` is low
        @(negedge clk); cp_pin[3] = 1'b0;
        repeat (4) @(negedge clk);
        chk(cp_evt === 8'h00, "falling edge ignored when not selected");

        // -------------------------------------------------------------
        section("tp_regfile");
        rf_write(4'd5, 32'hDEAD_BEEF);
        @(negedge clk); rf_ra1 = 4'd5; #1;
        chk(rf_rd1 === 32'hDEAD_BEEF, "write then read back");

        rf_write(4'd0, 32'h1234_5678);
        @(negedge clk); rf_ra1 = 4'd0; #1;
        chk(rf_rd1 === 32'd0, "x0 ignores writes and always reads zero");

        rf_write(4'd7, 32'hAAAA_1111);
        rf_write(4'd9, 32'h5555_2222);
        @(negedge clk); rf_ra1 = 4'd7; rf_ra2 = 4'd9; #1;
        chk(rf_rd1 === 32'hAAAA_1111 && rf_rd2 === 32'h5555_2222,
            "both read ports work independently");

        // THE regression: a read of the register being written in the
        // same cycle must return the OLD value. A bypass here is a
        // combinational loop in this pipeline.
        @(negedge clk);
        rf_we = 1'b1; rf_waddr = 4'd7; rf_wdata = 32'hBBBB_2222;
        rf_ra1 = 4'd7;
        #1;
        chk(rf_rd1 === 32'hAAAA_1111,
            "same-cycle read returns the OLD value (no write-through bypass)");
        if (rf_rd1 !== 32'hAAAA_1111)
            $display("        got %08x, wanted AAAA1111 — the bypass is back",
                     rf_rd1);
        @(negedge clk); rf_we = 1'b0; #1;
        chk(rf_rd1 === 32'hBBBB_2222, "the write lands on the next cycle");

        // -------------------------------------------------------------
        section("tp_hazard");
        hz_set(1,1,0,0,0,0,0);
        chk(hz_if_ready && !hz_ex_stall, "idle: fetch is consumed");
        hz_set(0,1,0,0,0,0,0);
        chk(!hz_if_ready, "no instruction means nothing is consumed");
        hz_set(1,0,0,0,0,0,0);
        chk(!hz_if_ready, "execute not ready blocks the handshake");
        hz_set(1,1,1,0,0,0,0);
        chk(hz_ex_stall && !hz_if_ready, "shifter busy stalls execute");
        hz_set(1,1,0,1,0,0,0);
        chk(hz_ex_stall && !hz_if_ready, "memory busy stalls execute");
        hz_set(1,1,0,0,1,0,0);
        chk(hz_ex_stall && !hz_if_ready, "TWAIT stalls execute");
        hz_set(1,1,0,0,0,1,0);
        chk(hz_ex_stall && !hz_if_ready, "halted stalls execute");
        hz_set(1,1,0,0,0,0,1);
        chk(hz_if_flush, "redirect raises flush");
        hz_set(1,1,0,0,0,0,0);
        chk(!hz_if_flush, "no redirect, no flush");

        // -------------------------------------------------------------
        section("tp_bpred (bimodal)");
        @(negedge clk); bp_rst = 1'b0;
        // a FORWARD branch: static prediction would say not-taken
        bp_instr = 32'h0020_8463;      // beq x1, x2, +8
        bp_pc    = 32'h0000_0040;
        #1;
        chk(bp_pred === 1'b0, "starts weakly not-taken");
        chk(bp_target === 32'h0000_0048, "target is pc + 8");

        // Standard two-bit counter: 00 strong NT, 01 weak NT, 10 weak T,
        // 11 strong T, and the prediction is the top bit. So one taken
        // update from 01 reaches 10 and already predicts taken.
        bp_train(32'h0000_0040, 1'b1);
        #1;
        chk(bp_pred === 1'b1, "one taken update reaches weakly-taken (01 -> 10)");
        bp_train(32'h0000_0040, 1'b1);
        bp_train(32'h0000_0040, 1'b1);
        #1;
        chk(bp_pred === 1'b1, "counter saturates at strongly-taken and stays");

        bp_train(32'h0000_0040, 1'b0);
        #1;
        chk(bp_pred === 1'b1, "one not-taken update (11 -> 10) still predicts taken");
        bp_train(32'h0000_0040, 1'b0);
        #1;
        chk(bp_pred === 1'b0, "a second not-taken update (10 -> 01) flips it back");

        // an unconditional jump is always predicted taken
        bp_instr = 32'h0100_006F;      // jal x0, +16
        bp_pc    = 32'h0000_0040;
        #1;
        chk(bp_pred === 1'b1, "JAL is always predicted taken");
        chk(bp_target === 32'h0000_0050, "JAL target is pc + 16");

        // a non-branch falls through
        bp_instr = 32'h0000_0013;      // nop
        #1;
        chk(bp_pred === 1'b0 && bp_target === 32'h0000_0044,
            "a non-branch predicts pc + 4");

        // -------------------------------------------------------------
        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("UNIT TESTS PASSED\n");
        else             $display("UNIT TESTS FAILED\n");
        $finish;
    end

endmodule
