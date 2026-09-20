// tb_soc.sv — self-checking system test. Runs a real program out of a
// modelled QSPI flash and checks the things the datasheet claims.
//
// What this proves, and it is the claim the whole chip rests on:
//   the trigger output edge lands on the EXACT timebase tick that was
//   programmed, with zero cycles of jitter, while the core is busy doing
//   something else.
//
// Run with:   iverilog -g2012 -o tb_soc.vvp -s tb_soc <sources> && vvp tb_soc.vvp
`default_nettype none
`timescale 1ns/1ps

module tb_soc;

    localparam int TIMEOUT = 200000;

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg        ena   = 1'b1;
    reg  [7:0] ui_in = 8'h00;       // also sets rd_latency = 0 during reset

    wire [7:0] uo_out, uio_out, uio_oe;
    wire [7:0] uio_in;

    integer errors = 0;
    integer checks = 0;

    task check(input cond, input string name);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  FAIL  %0s", name);
            end else begin
                $display("  ok    %0s", name);
            end
        end
    endtask

    always #5 clk = ~clk;           // 100 MHz simulation clock

    // ---- pin aliases ----
    wire trig0 = uo_out[0];
    wire trig1 = uo_out[1];
    wire evt   = uo_out[2];
    wire ovf   = uo_out[3];
    wire halt  = uo_out[4];
    wire ill   = uo_out[5];
    wire sck   = uo_out[7];
    wire cs_f  = uio_out[4];
    wire cs_r  = uio_out[5];

    // ---- shared QSPI data nibble ----
    wire [3:0] flash_sd, psram_sd;
    wire       ctrl_drives = uio_oe[0];
    wire [3:0] sd_bus = ctrl_drives ? uio_out[3:0]
                      : (!cs_f ? flash_sd : (!cs_r ? psram_sd : 4'hF));
    assign uio_in = {4'h0, sd_bus};

    tt_um_normansrule_tinypulse dut (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (ena),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    qspi_flash_model #(.DUMMY(4), .WORDS(512)) u_flash (
        .cs_n   (cs_f),
        .sck    (sck),
        .ctrl_sd(uio_out[3:0]),
        .dev_sd (flash_sd)
    );

    qspi_psram_model #(.DUMMY(6), .BYTES(4096)) u_psram (
        .cs_n   (cs_r),
        .sck    (sck),
        .ctrl_sd(uio_out[3:0]),
        .dev_sd (psram_sd)
    );

    // ---- observation ----
    wire [31:0] now = dut.u_soc.u_sync.now;

    reg [31:0] trig_rise_time = 32'hFFFF_FFFF;
    reg        trig_seen      = 1'b0;
    reg        trig0_q        = 1'b0;

    always @(posedge clk) begin
        trig0_q <= trig0;
        if (trig0 && !trig0_q && !trig_seen) begin
            trig_rise_time <= now;
            trig_seen      <= 1'b1;
        end
    end

    reg [31:0] cap_edge_time = 32'hFFFF_FFFF;

    integer cyc;

    initial begin
        $dumpfile("tb_soc.vcd");
        $dumpvars(0, tb_soc);

        #1 $readmemh("prog.hex", u_flash.mem);   // after the model's init

        $display("\n=== TinyPulse-Skywater130 system test ===");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        // Wait until the core is actually parked in TWAIT (EX_WAIT = 3),
        // then produce a hardware capture edge on CAP1. Probing the state
        // rather than counting clocks keeps the test honest if the fetch
        // timing changes.
        cyc = 0;
        while (dut.u_soc.g_cpu.u_core.state !== 3'd3 && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        check(cyc < TIMEOUT, "core reached the TWAIT state");

        repeat (20) @(posedge clk);
        cap_edge_time = now;
        ui_in[1] = 1'b1;
        repeat (20) @(posedge clk);
        ui_in[1] = 1'b0;

        // run to halt
        cyc = 0;
        while (!halt && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        $display("\n--- results ---");
        check(halt, "core reached ECALL and halted");
        check(!ill, "no illegal instruction was decoded");
        check(!ovf, "event queue did not overflow");
        check(trig_seen, "trigger 0 fired");

        begin : results
            reg [31:0] t0, evword, markts;
            t0     = {u_psram.mem[3],  u_psram.mem[2],  u_psram.mem[1],  u_psram.mem[0]};
            evword = {u_psram.mem[7],  u_psram.mem[6],  u_psram.mem[5],  u_psram.mem[4]};
            markts = {u_psram.mem[11], u_psram.mem[10], u_psram.mem[9],  u_psram.mem[8]};

            $display("  t0 (TIME)        = %0d", t0);
            $display("  trigger fired at = %0d  (expected %0d)", trig_rise_time, t0 + 400);
            $display("  event word       = %08x", evword);
            $display("  capture edge at  = %0d", cap_edge_time);
            $display("  TMARK timestamp  = %0d", markts);

            check(t0 != 0, "TIME returned a running timebase");
            // the headline claim: the edge lands on the programmed tick
            check(trig_rise_time == (t0 + 32'd400),
                  "trigger edge is on the exact programmed tick (zero jitter)");
            check(evword[31] == 1'b0, "queued event came from hardware capture");
            check(evword[30:28] == 3'd1, "event channel is CAP1");
            check(evword[27] == 1'b1, "event edge is rising");
            check(markts > t0, "TMARK timestamp is after t0");
            check(evword[26:0] >= cap_edge_time[26:0] &&
                  evword[26:0] <= cap_edge_time[26:0] + 27'd6,
                  "capture timestamp is within the synchroniser latency");
        end

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("SYSTEM TEST PASSED\n");
        else             $display("SYSTEM TEST FAILED\n");
        $finish;
    end

endmodule
