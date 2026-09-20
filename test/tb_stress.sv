// tb_stress.sv — the two cases most likely to be wrong and least likely to
// be hit by an ordinary program.
//
//   1. Eight capture channels edging on the SAME clock. They must all be
//      queued, all carry the same timestamp, and come out in channel order.
//      A design that drops seven of them looks fine on any normal test and
//      is useless on a robot, where sensors genuinely do fire together.
//
//   2. The 2^32 timebase rollover. Every deadline comparison in this design
//      is a signed difference specifically so an armed trigger survives the
//      wrap. If that is wrong, the chip works perfectly for 85 seconds and
//      then fires a trigger 85 seconds early.
//
// Run with:  make stress
`default_nettype none
`timescale 1ns/1ps

module tb_stress;
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

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;

    // =================================================================
    // A deep-queue sync unit: DEPTH 8, so all eight channels fit
    // =================================================================
    reg  [7:0]  pin_a = 8'h00;
    wire [3:0]  trig_a;
    wire        evt_a, ovf_a;
    reg         req_a = 1'b0, we_a = 1'b0;
    reg  [3:0]  addr_a = 4'd0;
    reg  [31:0] wdata_a = 32'd0;
    wire [31:0] rdata_a, tnow_a, trd_a;

    sync_unit #(
        .NCH(8), .NCMP(4), .DEPTH(8), .PTRW(3), .FRACW(24), .FILTW(0)
    ) u_deep (
        .clk(clk), .rst(rst),
        .cap_pin(pin_a), .trig_pin(trig_a),
        .evt_pending(evt_a), .ovf_pin(ovf_a),
        .t_valid(1'b0), .t_op(3'd0), .t_sub(7'd0),
        .t_rs1(32'd0), .t_rs2(32'd0), .t_rdata(trd_a), .t_now(tnow_a),
        .reg_req(req_a), .reg_addr(addr_a), .reg_we(we_a),
        .reg_wdata(wdata_a), .reg_rdata(rdata_a)
    );

    // =================================================================
    // A shallow-queue unit: DEPTH 2, to prove overflow is reported and
    // that the unit keeps working afterwards rather than wedging
    // =================================================================
    reg  [7:0]  pin_b = 8'h00;
    wire [1:0]  trig_b;
    wire        evt_b, ovf_b;
    reg         req_b = 1'b0, we_b = 1'b0;
    reg  [3:0]  addr_b = 4'd0;
    reg  [31:0] wdata_b = 32'd0;
    wire [31:0] rdata_b, tnow_b, trd_b;

    sync_unit #(
        .NCH(8), .NCMP(2), .DEPTH(2), .PTRW(1), .FRACW(24), .FILTW(0)
    ) u_shallow (
        .clk(clk), .rst(rst),
        .cap_pin(pin_b), .trig_pin(trig_b),
        .evt_pending(evt_b), .ovf_pin(ovf_b),
        .t_valid(1'b0), .t_op(3'd0), .t_sub(7'd0),
        .t_rs1(32'd0), .t_rs2(32'd0), .t_rdata(trd_b), .t_now(tnow_b),
        .reg_req(req_b), .reg_addr(addr_b), .reg_we(we_b),
        .reg_wdata(wdata_b), .reg_rdata(rdata_b)
    );

    // =================================================================
    // sync_compare with a directly driven timebase, so the 2^32 wrap can
    // be reached in simulation instead of in 85 seconds of real time
    // =================================================================
    reg  [31:0] now_c = 32'd0;
    reg         arm_c = 1'b0, pulse_c = 1'b0, pw_c = 1'b0;
    reg  [31:0] armt_c = 32'd0, pwin_c = 32'd0;
    reg  [1:0]  sel_c = 2'd0;
    wire [1:0]  trig_c, armed_c;

    sync_compare #(.NCMP(2), .PWW(16)) u_cmp (
        .clk(clk), .rst(rst), .now(now_c),
        .arm_we(arm_c), .arm_time(armt_c), .arm_sel(sel_c),
        .pulse_we(pulse_c), .pulse_mask(2'b00),
        .pw_we(pw_c), .pw_in(pwin_c),
        .trig(trig_c), .armed(armed_c)
    );

    // ---- helpers -------------------------------------------------
    task wr_a(input [3:0] a, input [31:0] d);
        begin
            @(negedge clk);
            req_a = 1'b1; we_a = 1'b1; addr_a = a; wdata_a = d;
            @(negedge clk);
            req_a = 1'b0; we_a = 1'b0;
        end
    endtask

    task wr_b(input [3:0] a, input [31:0] d);
        begin
            @(negedge clk);
            req_b = 1'b1; we_b = 1'b1; addr_b = a; wdata_b = d;
            @(negedge clk);
            req_b = 1'b0; we_b = 1'b0;
        end
    endtask

    // read SR_EVENT, which pops
    task pop_a(output [31:0] d);
        begin
            @(negedge clk);
            req_a = 1'b1; we_a = 1'b0; addr_a = SR_EVENT;
            #1 d = rdata_a;
            @(negedge clk);
            req_a = 1'b0;
        end
    endtask

    task pop_b(output [31:0] d);
        begin
            @(negedge clk);
            req_b = 1'b1; we_b = 1'b0; addr_b = SR_EVENT;
            #1 d = rdata_b;
            @(negedge clk);
            req_b = 1'b0;
        end
    endtask

    integer     i;
    reg [31:0]  ev [0:7];
    reg [31:0]  st;
    reg [26:0]  ts0;
    reg         same_ts, order_ok, all_rising, all_hw;
    integer     fire_tick;
    reg         seen;

    initial begin
        $dumpfile("tb_stress.vcd");
        $dumpvars(0, tb_stress);
        $display("\n=== TinyPulse-Skywater130 stress tests ===");

        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------
        $display("\n[eight channels on the same clock, queue depth 8]");
        wr_a(SR_CFG, 32'h0000_00FF);      // enable all 8, rising edge
        repeat (4) @(negedge clk);

        @(negedge clk);
        pin_a = 8'hFF;                    // every channel rises together
        repeat (16) @(negedge clk);       // let the drain finish
        pin_a = 8'hFF;                    // hold: no second edge

        @(negedge clk);
        req_a = 1'b1; we_a = 1'b0; addr_a = SR_STAT;
        #1 st = rdata_a;
        @(negedge clk); req_a = 1'b0;

        chk(st[3:0] == 4'd8, "all eight events are queued");
        chk(st[6] == 1'b0,   "no overflow with a depth-8 queue");
        if (st[3:0] != 4'd8)
            $display("        queue holds %0d", st[3:0]);

        for (i = 0; i < 8; i = i + 1) pop_a(ev[i]);

        ts0        = ev[0][26:0];
        same_ts    = 1'b1;
        order_ok   = 1'b1;
        all_rising = 1'b1;
        all_hw     = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            if (ev[i][26:0] !== ts0)          same_ts    = 1'b0;
            if (ev[i][30:28] !== i[2:0])      order_ok   = 1'b0;
            if (ev[i][27] !== 1'b1)           all_rising = 1'b0;
            if (ev[i][31] !== 1'b0)           all_hw     = 1'b0;
        end

        chk(same_ts,    "coincident events share one timestamp");
        chk(order_ok,   "events drain in channel order 0..7");
        chk(all_rising, "every event is marked rising");
        chk(all_hw,     "every event is marked as a hardware capture");

        if (!order_ok)
            for (i = 0; i < 8; i = i + 1)
                $display("        ev[%0d] = %08x", i, ev[i]);

        @(negedge clk);
        req_a = 1'b1; we_a = 1'b0; addr_a = SR_STAT;
        #1 st = rdata_a;
        @(negedge clk); req_a = 1'b0;
        chk(st[4] == 1'b1, "queue is empty after draining all eight");

        // -------------------------------------------------------------
        $display("\n[same burst into a depth-2 queue]");
        wr_b(SR_CFG, 32'h0000_00FF);
        repeat (4) @(negedge clk);

        @(negedge clk);
        pin_b = 8'hFF;
        repeat (16) @(negedge clk);

        @(negedge clk);
        req_b = 1'b1; we_b = 1'b0; addr_b = SR_STAT;
        #1 st = rdata_b;
        @(negedge clk); req_b = 1'b0;

        chk(st[6] == 1'b1, "overflow is reported, not hidden");
        chk(st[3:0] == 4'd2, "the queue holds what it can and no more");

        // it must still work after overflowing
        pop_b(ev[0]);
        pop_b(ev[1]);
        chk(ev[0][30:28] == 3'd0, "first surviving event is channel 0");
        chk(ev[1][30:28] == 3'd1, "second surviving event is channel 1");

        @(negedge clk); pin_b = 8'h00;
        repeat (6) @(negedge clk);
        @(negedge clk); pin_b = 8'h01;      // one fresh edge on channel 0
        repeat (6) @(negedge clk);
        pop_b(ev[2]);
        chk(ev[2][30:28] == 3'd0, "the unit still captures after an overflow");

        // -------------------------------------------------------------
        $display("\n[deadline comparison across the 2^32 rollover]");
        // park the timebase just below the wrap
        @(negedge clk);
        now_c  = 32'hFFFF_FFF0;
        pwin_c = 32'd4;
        pw_c   = 1'b1;
        @(negedge clk);
        pw_c = 1'b0;

        // arm for 0x00000010, which is 32 ticks away THROUGH the wrap
        @(negedge clk);
        armt_c = 32'h0000_0010;
        sel_c  = 2'd0;
        arm_c  = 1'b1;
        @(negedge clk);
        arm_c = 1'b0;

        chk(armed_c[0] === 1'b1, "channel armed across the wrap");
        chk(trig_c[0] === 1'b0,
            "a deadline on the far side of the wrap does not fire early");

        // walk the timebase through the rollover one tick per clock
        seen      = 1'b0;
        fire_tick = -1;
        for (i = 0; i < 48; i = i + 1) begin
            @(negedge clk);
            now_c = now_c + 32'd1;
            #1;
            if (trig_c[0] && !seen) begin
                seen      = 1'b1;
                fire_tick = $signed(now_c);
            end
        end

        chk(seen, "the trigger fired after the wrap");
        chk(fire_tick == 32'sh0000_0010,
            "it fired on exactly the programmed tick, past the rollover");
        if (fire_tick != 32'sh0000_0010)
            $display("        fired at %08x, wanted 00000010",
                     fire_tick[31:0]);
        chk(armed_c[0] === 1'b0, "the channel disarmed after firing");

        // and it must not fire a second time
        seen = 1'b0;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk);
            now_c = now_c + 32'd1;
            #1;
            if (trig_c[0]) seen = 1'b1;
        end
        chk(!seen, "a disarmed channel stays quiet");

        // -------------------------------------------------------------
        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("STRESS TESTS PASSED\n");
        else             $display("STRESS TESTS FAILED\n");
        $finish;
    end

endmodule
