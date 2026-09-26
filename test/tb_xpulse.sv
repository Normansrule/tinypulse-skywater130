// tb_xpulse.sv — every one of the eleven Xpulse instructions, executed.
//
// A coverage audit found that TSTAT, TPULSE and TRATE had never been run
// by any test program. They decoded correctly in tp_decode's tables and
// nothing had ever proved they did the right thing to the hardware.
//
// This also checks the one thing only TRATE can show: that the timebase
// can be made to run at a rate other than one tick per clock. The
// testbench counts clocks independently and compares.
//
// Run with:  make xpulse
`default_nettype none
`timescale 1ns/1ps

module tb_xpulse;

    localparam int TIMEOUT = 200000;

    reg        clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'h00;
    wire [7:0] uo_out, uio_out, uio_oe;

    integer errors = 0, checks = 0;

    task chk(input cond, input string name);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  FAIL  %0s", name);
            end else
                $display("  ok    %0s", name);
        end
    endtask

    always #5 clk = ~clk;

    wire trig0 = uo_out[0];
    wire trig1 = uo_out[1];
    wire halt  = uo_out[5];
    wire ill   = uo_out[6];
    wire sck   = uio_out[3];
    wire cs_f  = uio_out[0];
    wire cs_r  = uio_out[6];

    wire [3:0] flash_sd, psram_sd;
    wire [3:0] sd_bus = uio_oe[1] ? {uio_out[5], uio_out[4], uio_out[2], uio_out[1]}
                      : (!cs_f ? flash_sd : (!cs_r ? psram_sd : 4'hF));
    wire [7:0] uio_in = {2'b00, sd_bus[3], sd_bus[2], 1'b0, sd_bus[1], sd_bus[0], 1'b0};

    tt_um_normansrule_tinypulse dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    qspi_flash_model #(.DUMMY(4), .WORDS(512)) u_flash (
        .cs_n(cs_f), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(flash_sd));
    qspi_psram_model #(.DUMMY(6), .BYTES(4096)) u_psram (
        .cs_n(cs_r), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(psram_sd));

    wire [31:0] now = dut.u_soc.u_sync.now;

    // watch the trigger pins so TPULSE can be proved at the pin, not
    // just in the status word
    reg trig0_seen = 1'b0, trig1_seen = 1'b0;
    always @(posedge clk) begin
        if (trig0) trig0_seen <= 1'b1;
        if (trig1) trig1_seen <= 1'b1;
    end

    integer cyc, clocks_run;
    reg [31:0] stat0, stat1, t0, t1, ev;

    initial begin
        $dumpfile("tb_xpulse.vcd");
        $dumpvars(0, tb_xpulse);
        #1 $readmemh("xpulse.hex", u_flash.mem);

        $display("\n=== TinyPulse-Skywater130 Xpulse instruction coverage ===");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        cyc = 0;
        while (!halt && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        clocks_run = cyc;

        stat0 = {u_psram.mem[3],  u_psram.mem[2],  u_psram.mem[1],  u_psram.mem[0]};
        stat1 = {u_psram.mem[7],  u_psram.mem[6],  u_psram.mem[5],  u_psram.mem[4]};
        t0    = {u_psram.mem[11], u_psram.mem[10], u_psram.mem[9],  u_psram.mem[8]};
        t1    = {u_psram.mem[15], u_psram.mem[14], u_psram.mem[13], u_psram.mem[12]};
        ev    = {u_psram.mem[19], u_psram.mem[18], u_psram.mem[17], u_psram.mem[16]};

        $display("  clocks run       = %0d", clocks_run);
        $display("  timebase now     = %0d", now);
        $display("  TSTAT (idle)     = %08x", stat0);
        $display("  TSTAT (pulsing)  = %08x", stat1);
        $display("  t0 / t1          = %0d / %0d", t0, t1);
        $display("  popped event     = %08x", ev);

        chk(halt, "program halted");
        chk(!ill, "no illegal instruction: all 11 Xpulse opcodes decoded");

        // ---- TSTAT ----
        chk(stat0[4] === 1'b1,  "TSTAT reports the queue empty at startup");
        chk(stat0[3:0] === 4'd0, "TSTAT reports a queue count of zero");
        chk(stat0[6] === 1'b0,  "TSTAT reports no overflow");

        // ---- TPULSE ----
        chk(stat1[13:12] !== 2'd0,
            "TSTAT shows trigger channels active after TPULSE");
        chk(trig0_seen, "TPULSE drove TRIG0 at the pin");
        chk(trig1_seen, "TPULSE drove TRIG1 at the pin");
        // (the 2x2 build has two compare channels, so there is no third
        //  trigger for the mask to leave alone)

        // ---- TRATE ----
        // rate 2^23 with FRACW=24 is +0.5 tick per clock, so the timebase
        // must end up ahead of the clock count.
        chk(now > clocks_run,
            "TRATE made the timebase run faster than one tick per clock");
        if (!(now > clocks_run))
            $display("        now=%0d vs clocks=%0d — rate had no effect",
                     now, clocks_run);

        // ---- TIME / TWAIT ----
        chk(t1 >= t0 + 32'd300,
            "TWAIT resumed at or after the programmed deadline");
        chk(t1 - t0 < 32'd400, "TWAIT did not overshoot");

        // ---- TMARK / TPOP ----
        chk(ev[31] === 1'b1, "the popped event is marked as software");
        chk(ev[30:28] === 3'd5, "TMARK carried tag 5 into the queue");
        chk(ev[26:0] !== 27'd0, "TMARK stamped a non-zero time");

        // ---- TADJ and TCFG and TPW ran without upsetting anything ----
        chk(!ill, "TADJ, TCFG and TPW all retired legally");

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("XPULSE COVERAGE PASSED\n");
        else             $display("XPULSE COVERAGE FAILED\n");
        $finish;
    end

endmodule
