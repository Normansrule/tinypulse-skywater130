// tb_act.sv — runs one official RISC-V architecture test on TinyPulse.
// Driven by act/run_act.py, which assembles each test, loads it here, and
// compares the signature this bench writes with the reference signature.
`default_nettype none
`timescale 1ns/1ps

module tb_act;
    reg        clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'h08;
    wire [7:0] uo_out, uio_out, uio_oe;
    always #5 clk = ~clk;

    wire sck  = uio_out[3];
    wire cs_f = uio_out[0];
    wire cs_r = uio_out[6];                 // RAM A, 0x1000_0000
    wire cs_b = uio_out[7];                 // RAM B, 0x1080_0000
    wire [3:0] flash_sd, psram_sd, psramb_sd;
    wire [3:0] sd_bus = uio_oe[1] ? {uio_out[5], uio_out[4], uio_out[2], uio_out[1]}
                      : (!cs_f ? flash_sd : (!cs_r ? psram_sd : (!cs_b ? psramb_sd : 4'hF)));
    wire [7:0] uio_in = {2'b00, sd_bus[3], sd_bus[2], 1'b0, sd_bus[1], sd_bus[0], 1'b0};

    tt_um_normansrule_tinypulse dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n));
    qspi_flash_model #(.DUMMY(4), .WORDS(64)) u_flash (
        .cs_n(cs_f), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(flash_sd));
    // Both 8 MB RAMs: some tests (jal-01's 1 MB jumps) need 14.7 MB of code,
    // which runs across RAM A into RAM B.
    qspi_psram_model #(.DUMMY(6), .BYTES(1 << 23)) u_psram (
        .cs_n(cs_r), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(psram_sd));
    qspi_psram_model #(.DUMMY(6), .BYTES(1 << 23)) u_psramb (
        .cs_n(cs_b), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(psramb_sd));
    function [7:0] ram_byte(input integer a);
        ram_byte = (a < (1 << 23)) ? u_psram.mem[a] : u_psramb.mem[a - (1 << 23)];
    endfunction

    integer sig_begin, sig_end, n, fd, a, maxclk;
    initial begin
        if (!$value$plusargs("SIG_BEGIN=%d", sig_begin)) sig_begin = 0;
        if (!$value$plusargs("SIG_END=%d", sig_end))     sig_end   = 0;
        if (!$value$plusargs("MAXCLK=%d", maxclk))       maxclk    = 4000000;
        u_flash.mem[0] = 32'h100002b7;          // lui  x5, 0x10000
        u_flash.mem[1] = 32'h00028067;          // jalr x0, 0(x5)   -> the test, in RAM
        $readmemh("act_image.hex", u_psram.mem);
        if ($test$plusargs("RAMB")) $readmemh("act_image_b.hex", u_psramb.mem);
        repeat (10) @(posedge clk); rst_n = 1'b1;
        n = 0;
        while (!dut.u_soc.g_cpu.u_core.halted && n < maxclk) begin @(posedge clk); n = n + 1; end
        fd = $fopen("act_signature.txt", "w");
        for (a = sig_begin; a < sig_end; a = a + 4)
            $fdisplay(fd, "%02x%02x%02x%02x", ram_byte(a+3), ram_byte(a+2), ram_byte(a+1), ram_byte(a));
        $fclose(fd);
        $display("ACT halted=%0d illegal=%0d ramtiming=%0d clocks=%0d", dut.u_soc.g_cpu.u_core.halted,
                 dut.u_soc.g_cpu.u_core.illegal_q, u_psram.violations + u_psramb.violations, n);
        $finish;
    end
endmodule
