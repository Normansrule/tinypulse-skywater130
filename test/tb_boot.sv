// tb_boot.sv — the UART bootloader, end to end, from the pins.
//
// The testbench plays the PC on the far side of a USB-UART bridge:
//   hold ui_in[7] high through reset  -> the core starts in the boot ROM
//   expect "TP>" on uo_out[4]
//   send a 4-byte length and the hello-world program on ui_in[3]
//   expect the checksum byte and 'K'
//   expect the program, now running from RAM, to print "Hi TinyPulse\n"
//
// The UART divider is overridden to 64 clocks per bit so this runs in
// seconds; on silicon it is 434 (115,200 baud at 50 MHz). Each received byte
// costs the bootloader about 150 clocks (eight nibble-serial instructions and
// a QSPI RAM write), so at 434 there is a 25x margin; at 16 there would be
// none, and bytes would overrun.
`default_nettype none
`timescale 1ns/1ps

module tb_boot;
    localparam int DIV = 64;   // 640 clocks per byte: slower than this and the loop has margin
    reg        clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'h88;               // ui[7] = boot strap, ui[3] = RX idle high
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
    defparam dut.u_soc.u_periph.DIV_RESET = DIV;

    qspi_flash_model #(.DUMMY(4), .WORDS(64)) u_flash (
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

    // ---- the host's UART ----
    task host_send(input [7:0] b);
        integer i;
        begin
            ui_in[3] = 1'b0; repeat (DIV) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin ui_in[3] = b[i]; repeat (DIV) @(posedge clk); end
            ui_in[3] = 1'b1; repeat (DIV) @(posedge clk);
        end
    endtask

    task host_recv(input integer div, output [7:0] b);
        integer i, t;
        begin
            t = 0;
            while (uo_out[4] !== 1'b0) begin
                @(posedge clk); t = t + 1;
                if (t > 200000) begin $display("  FAIL  timed out waiting for a byte"); errors = errors + 1; $finish; end
            end
            repeat (div / 2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin repeat (div) @(posedge clk); b[i] = uo_out[4]; end
            repeat (div) @(posedge clk);
        end
    endtask

    reg  [31:0] image [0:127];
    integer     nwords, i, k, sum;
    reg  [7:0]  b, got_sum, got_k;
    reg  [8*16:1] banner, text;
    reg  [31:0] w;

    initial begin
        $dumpfile("tb_boot.vcd");
        $dumpvars(0, tb_boot);
        for (i = 0; i < 128; i = i + 1) image[i] = 32'hxxxx_xxxx;
        $readmemh("hello.hex", image);
        nwords = 0;
        while (nwords < 128 && image[nwords] !== 32'hxxxx_xxxx) nwords = nwords + 1;

        $display("\n=== TinyPulse UART bootloader ===");
        $display("  program: hello.hex, %0d bytes, sent at %0d clocks per bit", 4 * nwords, DIV);
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        banner = 0;
        for (k = 0; k < 3; k = k + 1) begin host_recv(DIV, b); banner = {banner[8*15:1], b}; end
        chk(banner[24:1] == "TP>", "boot ROM announces itself with TP>");
        chk(dut.u_soc.g_cpu.u_core.pc[31:28] == 4'h4, "the core is executing from the boot ROM");

        // length, little endian, then the bytes
        for (k = 0; k < 4; k = k + 1) host_send((4 * nwords) >> (8 * k));
        sum = 0;
        for (i = 0; i < nwords; i = i + 1) begin
            w = image[i];
            for (k = 0; k < 4; k = k + 1) begin
                host_send(w[8*k +: 8]);
                sum = sum + w[8*k +: 8];
            end
        end

        chk(dut.u_soc.u_periph.u_uart.rx_overrun === 1'b0, "no byte overran the bootloader while loading");
        host_recv(DIV, got_sum);
        host_recv(DIV, got_k);
        chk(got_sum == sum[7:0], "checksum byte matches what was sent");
        chk(got_k == "K", "bootloader acknowledges with K");

        begin : ram_check
            integer bad;
            bad = 0;
            for (i = 0; i < nwords; i = i + 1)
                if ({u_psram.mem[4*i+3], u_psram.mem[4*i+2], u_psram.mem[4*i+1], u_psram.mem[4*i]} !== image[i])
                    bad = bad + 1;
            chk(bad == 0, "RAM A holds the program byte for byte");
        end

        // the loaded program switches the UART to 8 clocks per bit and prints
        text = 0;
        for (k = 0; k < 13; k = k + 1) begin host_recv(8, b); text = {text[8*15:1], b}; end
        chk(text[8*13:1] == "Hi TinyPulse\n", "the loaded program runs from RAM and prints Hi TinyPulse");
        $display("        it said: \"%0s\"", text[8*13:9]);

        k = 0;
        while (!dut.u_soc.g_cpu.u_core.halted && k < 20000) begin @(posedge clk); k = k + 1; end
        chk(dut.u_soc.g_cpu.u_core.halted === 1'b1, "the loaded program ran to its ECALL");
        chk(dut.u_soc.g_cpu.u_core.pc[31:28] == 4'h1, "and it halted at an address in RAM (0x1xxx_xxxx)");
        chk(dut.u_soc.g_cpu.u_core.illegal_q === 1'b0, "no illegal instructions anywhere along the way");

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("BOOTLOADER TEST PASSED\n");
        else             $display("BOOTLOADER TEST FAILED\n");
        $finish;
    end
endmodule
