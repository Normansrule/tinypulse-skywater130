// tb.v — cocotb testbench wrapper (Tiny Tapeout standard shape).
// Instantiates the submission top with the fixed pin interface, hangs the
// behavioural QSPI flash and PSRAM off the bidirectional bank, and dumps a VCD.
`default_nettype none
`timescale 1ns/1ps

module tb ();
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end

    reg        clk;
    reg        rst_n;
    reg        ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    wire sck  = uo_out[7];
    wire cs_f = uio_out[4];
    wire cs_r = uio_out[5];

    // shared QSPI nibble: the controller drives it when sd_oe is set,
    // otherwise whichever device has its chip select low drives it
    wire [3:0] flash_sd, psram_sd;
    wire [3:0] sd_bus = uio_oe[0] ? uio_out[3:0]
                      : (!cs_f ? flash_sd : (!cs_r ? psram_sd : 4'hF));
    wire [7:0] uio_in = {4'h0, sd_bus};

    tt_um_normansrule_tinypulse user_project (
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
        .cs_n(cs_f), .sck(sck), .ctrl_sd(uio_out[3:0]), .dev_sd(flash_sd)
    );

    qspi_psram_model #(.DUMMY(6), .BYTES(4096)) u_psram (
        .cs_n(cs_r), .sck(sck), .ctrl_sd(uio_out[3:0]), .dev_sd(psram_sd)
    );

    initial begin
        #1 $readmemh("prog.hex", u_flash.mem);
    end
endmodule
