// tt_um_normansrule_tinypulse.sv — Tiny Tapeout submission top for TinyPulse-Skywater130.
//
// Maps tp_soc onto the fixed Tiny Tapeout pin interface. Every one of the
// 24 signals is used; there are no spares, which is the honest situation on a
// tile.
//
// Pin map
// -------
//   ui_in[7:0]   CAP0..CAP7   capture inputs, timestamped in hardware
//
//   uo_out[0]    TRIG0        compare/trigger output
//   uo_out[1]    TRIG1        compare/trigger output
//   uo_out[2]    EVT          event queue not empty (interrupt to a host)
//   uo_out[3]    OVF          event queue overflowed (sticky)
//   uo_out[4]    HALT         core retired ECALL/EBREAK
//   uo_out[5]    ILL          an illegal instruction was decoded (sticky)
//   uo_out[6]    HB           heartbeat, timebase bit 23
//   uo_out[7]    SCK          QSPI clock
//
//   uio[0]       SD0          QSPI data 0   (bidirectional)
//   uio[1]       SD1          QSPI data 1   (bidirectional)
//   uio[2]       SD2          QSPI data 2   (bidirectional)
//   uio[3]       SD3          QSPI data 3   (bidirectional)
//   uio[4]       CSF          flash chip select, active low   (output)
//   uio[5]       CSR          PSRAM chip select, active low   (output)
//   uio[6]       TRIG2        compare/trigger output          (output)
//   uio[7]       EVTP         one-clock pulse on event capture (output)
//
// Tiny Tapeout convention: `ena` is high while this design is selected. The
// design is not gated on it (the harness handles selection); it is tied into
// the unused net so the linter stays quiet.
`default_nettype none

module tt_um_normansrule_tinypulse (
    input  wire [7:0] ui_in,     // dedicated inputs
    output wire [7:0] uo_out,    // dedicated outputs
    input  wire [7:0] uio_in,    // bidirectional: input path
    output wire [7:0] uio_out,   // bidirectional: output path
    output wire [7:0] uio_oe,    // bidirectional: output enable (1 = drive)
    input  wire       ena,       // high when the design is selected
    input  wire       clk,       // system clock
    input  wire       rst_n      // active-low reset
);

    wire rst = ~rst_n;

    wire [2:0] trig;
    wire       evt_pending, evt_pulse, ovf, halted, illegal, heartbeat;
    wire       sck, cs_flash_n, cs_ram_n;
    wire [3:0] sd_out, sd_oe;

    tp_soc #(
        .NREG(16), .AW(4), .RESET_PC(32'h0000_0000),
        .BARREL(1'b0), .BIMODAL(1'b0), .HAS_CPU(1'b1),
        .NCH(8), .NCMP(3), .DEPTH(2), .PTRW(1), .FRACW(24), .FILTW(0)
    ) u_soc (
        .clk        (clk),
        .rst        (rst),
        .cap_pin    (ui_in),
        .trig_pin   (trig),
        .evt_pending(evt_pending),
        .evt_pulse  (evt_pulse),
        .ovf_pin    (ovf),
        .halted     (halted),
        .illegal    (illegal),
        .heartbeat  (heartbeat),
        .sck        (sck),
        .cs_flash_n (cs_flash_n),
        .cs_ram_n   (cs_ram_n),
        .sd_out     (sd_out),
        .sd_oe      (sd_oe),
        .sd_in      (uio_in[3:0])
    );

    // ---- dedicated outputs ----
    assign uo_out[0] = trig[0];
    assign uo_out[1] = trig[1];
    assign uo_out[2] = evt_pending;
    assign uo_out[3] = ovf;
    assign uo_out[4] = halted;
    assign uo_out[5] = illegal;
    assign uo_out[6] = heartbeat;
    assign uo_out[7] = sck;

    // ---- bidirectional bank ----
    // low nibble is the QSPI data bus, direction driven by the controller;
    // the high nibble is always driven out.
    assign uio_oe      = {4'b1111, sd_oe};
    assign uio_out[3:0] = sd_out;
    assign uio_out[4]   = cs_flash_n;
    assign uio_out[5]   = cs_ram_n;
    assign uio_out[6]   = trig[2];
    assign uio_out[7]   = evt_pulse;

    wire _unused = &{1'b0, ena, uio_in[7:4], 1'b0};

endmodule : tt_um_normansrule_tinypulse
