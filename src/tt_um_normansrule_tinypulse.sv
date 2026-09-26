// tt_um_normansrule_tinypulse.sv — Tiny Tapeout pin wrapper.
//
//   ui_in[7:0]   GPIO inputs, all eight also timestamp-capture channels.
//                ui_in[3] is the UART receive line (the demo board's RP2040
//                UART TX is wired here). ui_in[2:0] set the QSPI read
//                latency while reset is held.
//   uo_out[7:0]  GPIO outputs, or per pin a built-in function (see tp_soc).
//                uo_out[4] is UART transmit (to the RP2040's UART RX).
//   uio[7:0]     the Tiny Tapeout QSPI Pmod, in its standard pinout:
//                  0 CS0 flash   1 SD0   2 SD1   3 SCK
//                  4 SD2         5 SD3   6 CS1 RAM A   7 CS2 RAM B
//
// While rst_n is low every uio pin is an input. That lets the demo board's
// RP2040 program the flash through the same Pmod without unplugging it or
// fighting the chip for the bus.
`default_nettype none

module tt_um_normansrule_tinypulse (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire rst = ~rst_n;

    wire       sck, cs_flash_n, cs_rama_n, cs_ramb_n;
    wire [3:0] sd_out, sd_oe;

    tp_soc u_soc (
        .clk       (clk),
        .rst       (rst),
        .ui        (ui_in),
        .uo        (uo_out),
        .sck       (sck),
        .cs_flash_n(cs_flash_n),
        .cs_rama_n (cs_rama_n),
        .cs_ramb_n (cs_ramb_n),
        .sd_out    (sd_out),
        .sd_oe     (sd_oe),
        .sd_in     ({uio_in[5], uio_in[4], uio_in[2], uio_in[1]})
    );

    assign uio_out = {cs_ramb_n, cs_rama_n, sd_out[3], sd_out[2],
                      sck,       sd_out[1], sd_out[0], cs_flash_n};
    assign uio_oe  = rst ? 8'h00
                         : {1'b1, 1'b1, sd_oe[3], sd_oe[2],
                            1'b1, sd_oe[1], sd_oe[0], 1'b1};

    wire _unused = &{1'b0, ena, uio_in[7:6], uio_in[3], uio_in[0], 1'b0};
endmodule : tt_um_normansrule_tinypulse
