// tb_wrap.sv — the 2^32 timebase rollover, at system level.
//
// tb_stress.sv proves the compare unit survives the wrap with a directly
// driven timebase. This proves the whole chip does: a real program uses
// TADJ to park the timebase just below the rollover, arms a trigger on the
// far side of it, and parks in TWAIT. If either comparison used an
// unsigned >=, the TWAIT would fall straight through and the trigger would
// fire about 85 seconds early.
//
// Run with:  make wrap
`default_nettype none
`timescale 1ns/1ps

module tb_wrap;

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

    wire [31:0] now   = dut.u_soc.u_sync.now;
    wire [2:0]  state = dut.u_soc.g_cpu.u_core.state;

    reg [31:0] trig_tick = 32'hFFFF_FFFF;
    reg        trig_seen = 1'b0, trig_q = 1'b0;
    always @(posedge clk) begin
        trig_q <= trig0;
        if (trig0 && !trig_q && !trig_seen) begin
            trig_tick <= now;
            trig_seen <= 1'b1;
        end
    end

    integer cyc, wait_entered, wait_left;
    reg [31:0] t0, deadline, t1;

    initial begin
        $dumpfile("tb_wrap.vcd");
        $dumpvars(0, tb_wrap);
        #1 $readmemh("wrap.hex", u_flash.mem);

        $display("\n=== TinyPulse-Skywater130 rollover test ===");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        // find the clock TWAIT is entered on
        cyc = 0;
        while (state !== 3'd3 && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        chk(cyc < TIMEOUT, "core reached TWAIT");
        wait_entered = cyc;

        // and the clock it leaves on
        while (state === 3'd3 && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        wait_left = cyc;

        while (!halt && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        t0       = {u_psram.mem[3],  u_psram.mem[2],  u_psram.mem[1],  u_psram.mem[0]};
        deadline = {u_psram.mem[7],  u_psram.mem[6],  u_psram.mem[5],  u_psram.mem[4]};
        t1       = {u_psram.mem[11], u_psram.mem[10], u_psram.mem[9],  u_psram.mem[8]};

        $display("  t0        = %08x", t0);
        $display("  deadline  = %08x", deadline);
        $display("  t1        = %08x", t1);
        $display("  trig tick = %08x", trig_tick);
        $display("  TWAIT held for %0d clocks", wait_left - wait_entered);

        chk(halt, "program halted");
        chk(!ill, "no illegal instruction");
        chk(t0[31] === 1'b1, "t0 really is just below the rollover");
        chk(deadline[31] === 1'b0, "the deadline really did wrap past zero");
        chk(deadline < t0, "the deadline is numerically SMALLER than t0");

        // the actual point of the test
        chk((wait_left - wait_entered) > 1000,
            "TWAIT held across the wrap instead of falling through");
        chk(trig_seen, "trigger fired");
        chk(trig_tick === deadline,
            "trigger fired on the exact deadline, past the rollover");
        chk($signed(t1 - deadline) >= 0 && $signed(t1 - deadline) < 32'sd200,
            "execution resumed just after the deadline");

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("ROLLOVER TEST PASSED\n");
        else             $display("ROLLOVER TEST FAILED\n");
        $finish;
    end

endmodule
