// tb_c.sv — a real C program, compiled by Clang, running on the chip.
//
// sw/examples/c_selftest.c is built twice by the Makefile: linked for flash
// (c_flash.hex) and for RAM (c_ram.hex). This bench runs both the ways you
// would program a real board:
//   1. from flash: the program is in the flash model at reset
//   2. over the UART: warm reset with ui_in[7] high, the boot ROM prints TP>,
//      the testbench sends c_ram.bin over the serial pin, the program runs
//      from RAM
// Each time it decodes the UART and compares every character with what the
// program must print if crt0, the linker scripts, the runtime helpers, the
// compiler and the chip all agree.
`default_nettype none
`timescale 1ns/1ps

module tb_c;
    localparam int BOOT_DIV = 32;       // bootloader baud in simulation (434 on silicon)
    localparam int PROG_DIV = 8;        // what the program sets (BAUD_DIV=8 build)
    reg        clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'h08;           // UART RX idle high
    wire [7:0] uo_out, uio_out, uio_oe;
    integer errors = 0, checks = 0;
    always #5 clk = ~clk;

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
    defparam dut.u_soc.u_periph.DIV_RESET = BOOT_DIV;
    qspi_flash_model #(.DUMMY(4), .WORDS(2048)) u_flash (
        .cs_n(cs_f), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(flash_sd));
    qspi_psram_model #(.DUMMY(6), .BYTES(1 << 20)) u_psram (
        .cs_n(cs_r), .sck(sck), .ctrl_sd({uio_out[5], uio_out[4], uio_out[2], uio_out[1]}), .dev_sd(psram_sd));

    task chk(input cond, input [8*72:1] msg);
        begin
            checks = checks + 1;
            if (cond) $display("  ok    %0s", msg);
            else begin errors = errors + 1; $display("  FAIL  %0s", msg); end
        end
    endtask

    // ---- the PC end of the serial line ----
    reg [7:0] rx_buf [0:255];
    integer   rx_n;
    reg       rx_on = 1'b0;
    integer   rx_div = PROG_DIV;
    always begin : receiver
        integer i; reg [7:0] b;
        @(posedge clk);
        if (rx_on && uo_out[4] === 1'b0) begin
            repeat (rx_div / 2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin repeat (rx_div) @(posedge clk); b[i] = uo_out[4]; end
            repeat (rx_div) @(posedge clk);
            if (rx_n < 256) rx_buf[rx_n] = b;
            rx_n = rx_n + 1;
        end
    end

    task host_send(input [7:0] b);
        integer i;
        begin
            ui_in[3] = 1'b0; repeat (BOOT_DIV) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin ui_in[3] = b[i]; repeat (BOOT_DIV) @(posedge clk); end
            ui_in[3] = 1'b1; repeat (BOOT_DIV) @(posedge clk);
        end
    endtask

    reg [8*200:1] expect_s;
    integer exp_len;
    task compare(input [8*24:1] how);
        integer i, bad;
        reg [7:0] c;
        begin
            $write("        UART: \"");
            for (i = 0; i < rx_n && i < 256; i = i + 1)
                if (rx_buf[i] == 8'h0a) $write("\\n"); else $write("%c", rx_buf[i]);
            $display("\"");
            chk(rx_n == exp_len, {how, ": printed exactly the expected number of characters"});
            bad = 0;
            for (i = 0; i < exp_len && i < rx_n; i = i + 1) begin
                c = expect_s[8*(exp_len - i) -: 8];
                if (rx_buf[i] !== c) bad = bad + 1;
            end
            chk(bad == 0, {how, ": every character matches"});
        end
    endtask

    task wait_halt(input [8*24:1] how);
        integer n, maxclk;
        begin
            if (!$value$plusargs("MAXCLK=%d", maxclk)) maxclk = 6000000;
            n = 0;
            while (!dut.u_soc.g_cpu.u_core.halted && n < maxclk) begin @(posedge clk); n = n + 1; end
            repeat (40 * PROG_DIV) @(posedge clk);
            chk(dut.u_soc.g_cpu.u_core.halted === 1'b1, {how, ": main() returned and crt0 halted"});
            chk(dut.u_soc.g_cpu.u_core.illegal_q === 1'b0, {how, ": no illegal instruction"});
            $display("        (%0d clocks = %0.1f ms at 50 MHz)", n, n * 0.00002);
        end
    endtask

    reg [31:0] img [0:2047];
    integer nw, i, k;
    reg [31:0] w;

    initial begin
        $dumpfile("tb_c.vcd");
        $dumpvars(0, tb_c);
        expect_s = "Hi from C\ndata 42\nbss 0\nmul -69104\ndiv -22\nmod -2\nfib 144\nfn 42\nwait Y\ndone\n";
        exp_len = 0;
        for (i = 1; i <= 200; i = i + 1) if (expect_s[8*i -: 8] != 8'h00) exp_len = i;
        $readmemh("c_flash.hex", u_flash.mem);
        $display("\n=== C on TinyPulse (compiled by Clang, RV32E) ===");

        $display("[1: from flash]");
        rx_n = 0; rx_on = 1'b1; rx_div = PROG_DIV;
        repeat (10) @(posedge clk); rst_n = 1'b1;
        wait_halt("flash");
        compare("flash");

        if ($test$plusargs("flash_only")) begin
            $display("\n%0d checks, %0d failures", checks, errors);
            if (errors == 0) $display("C PROGRAM TEST PASSED (flash only)\n");
            else             $display("C PROGRAM TEST FAILED\n");
            $finish;
        end

        $display("[2: over the UART bootloader into RAM]");
        for (i = 0; i < 2048; i = i + 1) img[i] = 32'hxxxx_xxxx;
        $readmemh("c_ram.hex", img);
        nw = 0; while (nw < 2048 && img[nw] !== 32'hxxxx_xxxx) nw = nw + 1;
        rx_on = 1'b0;
        rst_n = 1'b0; ui_in[7] = 1'b1;                  // boot strap
        repeat (10) @(posedge clk); rst_n = 1'b1;
        rx_n = 0; rx_div = BOOT_DIV; rx_on = 1'b1;
        while (rx_n < 3) @(posedge clk);                 // TP>
        chk(rx_buf[0] == "T" && rx_buf[1] == "P" && rx_buf[2] == ">", "uart: bootloader ready");
        rx_on = 1'b0;
        for (k = 0; k < 4; k = k + 1) host_send((4 * nw) >> (8 * k));
        for (i = 0; i < nw; i = i + 1) begin
            w = img[i];
            for (k = 0; k < 4; k = k + 1) host_send(w[8*k +: 8]);
        end
        rx_n = 0; rx_on = 1'b1;
        while (rx_n < 2) @(posedge clk);                 // checksum, K
        chk(rx_buf[1] == "K", "uart: program accepted");
        rx_on = 1'b0;
        repeat (12 * BOOT_DIV) @(posedge clk);           // K finishes; program switches baud
        rx_n = 0; rx_div = PROG_DIV; rx_on = 1'b1;
        wait_halt("uart");
        compare("uart");
        chk(dut.u_soc.g_cpu.u_core.pc[31:28] == 4'h1, "uart: the program ran from RAM");
        chk(u_psram.violations == 0, "RAM timing: selected under 8 us, deselected at least 18 ns, always");

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("C PROGRAM TEST PASSED\n");
        else             $display("C PROGRAM TEST FAILED\n");
        $finish;
    end
endmodule
