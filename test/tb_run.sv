// tb_run.sv — run any compiled program on the simulated TinyPulse and show
// its UART output live, like a serial terminal on a real board.
//
//   cd test && make run PROG=../sw/examples/hello.c
//
// The program is built for flash with BAUD_DIV=8, loaded into the flash
// model, and the chip runs from reset exactly as silicon would: the memory
// wake-up sequence, fetches over QSPI, everything. Output is printed as each
// byte arrives. The run ends when main() returns (HALT) or after +MAXCLK
// clocks (default 20 million = 0.4 s of chip time at 50 MHz).
`default_nettype none
`timescale 1ns/1ps

module tb_run;
    localparam int DIV = 8;
    reg        clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'h08;
    wire [7:0] uo_out, uio_out, uio_oe;
    always #10 clk = ~clk;                 // 50 MHz

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
    qspi_flash_model #(.DUMMY(4), .WORDS(16384)) u_flash (
        .cs_n(cs_f), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(flash_sd));
    qspi_psram_model #(.DUMMY(6), .BYTES(1 << 20)) u_psram (
        .cs_n(cs_r), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(psram_sd));

    // A simulated SPI flash (Winbond W25Q128) on the software-SPI pins of
    // sw/tp_spi.h, enabled with +spi_flash: SCK uo_out[1], MOSI uo_out[2],
    // CS uo_out[3], MISO ui_in[4]. It answers the JEDEC ID command 0x9F with
    // EF 40 18, changing MISO on falling clock edges (SPI mode 0).
    reg  [7:0] spi_cmd; reg [23:0] spi_out; integer spi_bits = 0;
    wire spi_sck = uo_out[1], spi_mosi = uo_out[2], spi_cs = uo_out[3];
    always @(negedge spi_cs) if ($test$plusargs("spi_flash")) begin spi_bits = 0; spi_cmd = 0; end
    always @(posedge spi_sck) if ($test$plusargs("spi_flash") && !spi_cs) begin
        if (spi_bits < 8) spi_cmd = {spi_cmd[6:0], spi_mosi};
        spi_bits = spi_bits + 1;
    end
    always @(negedge spi_sck) if ($test$plusargs("spi_flash") && !spi_cs) begin
        if (spi_bits == 8) spi_out = (spi_cmd == 8'h9F) ? 24'hEF4018 : 24'h000000;
        if (spi_bits >= 8) begin ui_in[4] = spi_out[23]; spi_out = {spi_out[22:0], 1'b0}; end
    end

    integer n = 0, maxclk, nbytes = 0;
    always begin : terminal
        integer i; reg [7:0] b;
        @(posedge clk);
        if (rst_n && uo_out[4] === 1'b0) begin
            repeat (DIV / 2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin repeat (DIV) @(posedge clk); b[i] = uo_out[4]; end
            repeat (DIV) @(posedge clk);
            $write("%c", b); $fflush();
            nbytes = nbytes + 1;
        end
    end

    initial begin
        if (!$value$plusargs("MAXCLK=%d", maxclk)) maxclk = 20000000;
        $readmemh("run.hex", u_flash.mem);
        $display("--- TinyPulse (simulated RTL, 50 MHz) ---");
        repeat (10) @(posedge clk); rst_n = 1'b1;
        while (!dut.u_soc.g_cpu.u_core.halted && n < maxclk) begin @(posedge clk); n = n + 1; end
        repeat (40 * DIV) @(posedge clk);
        $display("--- %s after %0d clocks (%0.2f ms at 50 MHz), %0d bytes printed%s ---",
                 dut.u_soc.g_cpu.u_core.halted ? "main() returned" : "stopped (MAXCLK)",
                 n, n * 0.00002, nbytes,
                 dut.u_soc.g_cpu.u_core.illegal_q ? ", ILLEGAL instruction seen" : "");
        $finish;
    end
endmodule
