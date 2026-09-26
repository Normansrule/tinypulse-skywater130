// tb_wake.sv — the QSPI wake-up sequence, in every starting state a real
// board can present:
//   cold   both chips fresh from power-up (plain SPI)
//   warm   reset pressed while they are in the fast modes the last run set
//   primed they were put in the fast modes by something else (a demo-board
//          script, a TinyQV-style setup) before this chip ever ran
// In each case the sequence must leave the flash in continuous read and the
// RAM in QPI, and the self-test program must then run to completion.
`default_nettype none
`timescale 1ns/1ps

module tb_wake;
    reg        clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'h00;
    wire [7:0] uo_out, uio_out, uio_oe;
    integer errors = 0, checks = 0;
    always #5 clk = ~clk;

    wire halt = uo_out[5];
    wire ill  = uo_out[6];
    wire sck  = uio_out[3];
    wire cs_f = uio_out[0];
    wire cs_r = uio_out[6];
    wire [3:0] flash_sd, psram_sd;
    wire [3:0] sd_bus = uio_oe[1] ? {uio_out[5], uio_out[4], uio_out[2], uio_out[1]}
                      : (!cs_f ? flash_sd : (!cs_r ? psram_sd : 4'hF));
    wire [7:0] uio_in = {2'b00, sd_bus[3], sd_bus[2], 1'b0, sd_bus[1], sd_bus[0], 1'b0};

    tt_um_normansrule_tinypulse dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n));
    qspi_flash_model #(.DUMMY(4), .WORDS(512)) u_flash (
        .cs_n(cs_f), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(flash_sd));
    qspi_psram_model #(.DUMMY(6), .BYTES(4096)) u_psram (
        .cs_n(cs_r), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(psram_sd));

    task chk(input cond, input [8*72:1] msg);
        begin
            checks = checks + 1;
            if (cond) $display("  ok    %0s", msg);
            else begin errors = errors + 1; $display("  FAIL  %0s", msg); end
        end
    endtask

    task run_from_reset(input [8*16:1] name);
        integer n;
        begin
            rst_n = 1'b0; repeat (8) @(posedge clk); rst_n = 1'b1;
            n = 0;
            while (dut.u_soc.u_qspi.waking && n < 2000) begin @(posedge clk); n = n + 1; end
            chk(!dut.u_soc.u_qspi.waking, {name, ": wake-up sequence finished"});
            $display("        (%0d clocks, %0.2f us at 50 MHz)", n, n * 0.02);
            chk(u_flash.cont === 1'b1, {name, ": flash is in continuous read"});
            chk(u_psram.qpi  === 1'b1, {name, ": RAM is in QPI mode"});
            n = 0;
            while (!halt && n < 400000) begin @(posedge clk); n = n + 1; end
            chk(halt === 1'b1 && ill === 1'b0, {name, ": the program ran to ECALL"});
        end
    endtask

    initial begin
        $dumpfile("tb_wake.vcd");
        $dumpvars(0, tb_wake);
        #1 $readmemh("prog.hex", u_flash.mem);
        $display("\n=== TinyPulse QSPI wake-up ===");

        $display("[cold: both chips straight from power-up]");
        chk(u_flash.cont === 1'b0 && u_psram.qpi === 1'b0, "cold: models start in plain SPI");
        run_from_reset("cold");

        $display("[warm: reset pressed with both chips still in fast modes]");
        chk(u_flash.cont === 1'b1 && u_psram.qpi === 1'b1, "warm: chips are still in fast modes");
        run_from_reset("warm");

        $display("[primed: something else set the fast modes first]");
        rst_n = 1'b0;
        u_flash.cont = 1'b1; u_psram.qpi = 1'b1;
        run_from_reset("primed");

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("WAKE-UP TEST PASSED\n");
        else             $display("WAKE-UP TEST FAILED\n");
        $finish;
    end
endmodule
