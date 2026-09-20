// tp_soc.sv — TinyPulse-Skywater130: core + bus + external memory + sync unit.
//
// Everything above the Tiny Tapeout pin wrapper lives here, so the same SoC
// drops onto an FPGA board unchanged (see fpga/).
//
// The three build profiles in the README are just different parameter sets
// on this module. Nothing else changes between them.
`default_nettype none

import tp_pkg::*;

module tp_soc
#(
    // --- core ---
    parameter int          NREG     = 16,    // 16 = RV32E
    parameter int          AW       = 4,
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter bit          BARREL   = 1'b0,
    parameter bit          BIMODAL  = 1'b0,
    parameter bit          HAS_CPU  = 1'b1,  // 0 = sync-only 1x1 profile
    // --- sync ---
    parameter int          NCH      = 8,
    parameter int          NCMP     = 3,
    parameter int          DEPTH    = 2,
    parameter int          PTRW     = 1,
    parameter int          FRACW    = 24,
    parameter int          FILTW    = 0
) (
    input  wire  logic            clk,
    input  wire  logic            rst,

    // capture inputs
    input  wire  logic [NCH-1:0]  cap_pin,

    // trigger outputs
    output logic [NCMP-1:0]       trig_pin,

    // status outputs
    output logic                  evt_pending,
    output logic                  evt_pulse,
    output logic                  ovf_pin,
    output logic                  halted,
    output logic                  illegal,
    output logic                  heartbeat,

    // QSPI pins
    output logic                  sck,
    output logic                  cs_flash_n,
    output logic                  cs_ram_n,
    output logic [3:0]            sd_out,
    output logic [3:0]            sd_oe,
    input  wire  logic [3:0]      sd_in
);

    // ---- core <-> bus ----
    logic        imem_req, imem_rvalid;
    logic [31:0] imem_addr, imem_rdata;
    logic        dmem_req, dmem_we, dmem_rvalid;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_be;

    // ---- core <-> sync ----
    logic        t_valid;
    logic [2:0]  t_op;
    logic [6:0]  t_sub;
    logic [31:0] t_rs1, t_rs2, t_rdata, t_now;

    // ---- bus <-> slaves ----
    logic        q_req, q_we, q_dev, q_rvalid;
    logic [23:0] q_addr;
    logic [31:0] q_wdata, q_rdata;
    logic [3:0]  q_be;
    logic [2:0]  rd_latency;
    logic [31:0] dbg_pc;
    logic        reg_req, reg_we;
    logic [3:0]  reg_addr;
    logic [31:0] reg_wdata, reg_rdata;

    generate
    if (HAS_CPU) begin : g_cpu
        tp_core #(
            .NREG(NREG), .AW(AW), .RESET_PC(RESET_PC),
            .BARREL(BARREL), .BIMODAL(BIMODAL)
        ) u_core (
            .clk        (clk),
            .rst        (rst),
            .imem_req   (imem_req),
            .imem_addr  (imem_addr),
            .imem_rvalid(imem_rvalid),
            .imem_rdata (imem_rdata),
            .dmem_req   (dmem_req),
            .dmem_addr  (dmem_addr),
            .dmem_we    (dmem_we),
            .dmem_wdata (dmem_wdata),
            .dmem_be    (dmem_be),
            .dmem_rvalid(dmem_rvalid),
            .dmem_rdata (dmem_rdata),
            .t_valid    (t_valid),
            .t_op       (t_op),
            .t_sub      (t_sub),
            .t_rs1      (t_rs1),
            .t_rs2      (t_rs2),
            .t_rdata    (t_rdata),
            .t_now      (t_now),
            .halted     (halted),
            .illegal    (illegal),
            .dbg_pc     (dbg_pc)
        );
    end else begin : g_nocpu
        // The 1x1 profile: no core. The sync unit is still fully functional
        // and is driven over the memory-mapped port by an external host.
        assign imem_req  = 1'b0;
        assign imem_addr = 32'd0;
        assign dmem_req  = 1'b0;
        assign dmem_addr = 32'd0;
        assign dmem_we   = 1'b0;
        assign dmem_wdata= 32'd0;
        assign dmem_be   = 4'd0;
        assign t_valid   = 1'b0;
        assign t_op      = 3'd0;
        assign t_sub     = 7'd0;
        assign t_rs1     = 32'd0;
        assign t_rs2     = 32'd0;
        assign halted    = 1'b1;
        assign illegal   = 1'b0;
    end
    endgenerate

    tp_bus u_bus (
        .clk        (clk),
        .rst        (rst),
        .imem_req   (imem_req),
        .imem_addr  (imem_addr),
        .imem_rvalid(imem_rvalid),
        .imem_rdata (imem_rdata),
        .dmem_req   (dmem_req),
        .dmem_addr  (dmem_addr),
        .dmem_we    (dmem_we),
        .dmem_wdata (dmem_wdata),
        .dmem_be    (dmem_be),
        .dmem_rvalid(dmem_rvalid),
        .dmem_rdata (dmem_rdata),
        .q_req      (q_req),
        .q_addr     (q_addr),
        .q_we       (q_we),
        .q_wdata    (q_wdata),
        .q_be       (q_be),
        .q_dev      (q_dev),
        .q_rvalid   (q_rvalid),
        .q_rdata    (q_rdata),
        .reg_req    (reg_req),
        .reg_addr   (reg_addr),
        .reg_we     (reg_we),
        .reg_wdata  (reg_wdata),
        .reg_rdata  (reg_rdata)
    );

    // The QSPI read latency is sampled from the low three capture pins while
    // reset is held. Hold them at the value the board needs, release reset,
    // and they go back to being capture inputs.
    always_ff @(posedge clk) begin
        if (rst) rd_latency <= cap_pin[2:0];
    end

    qspi_ctrl u_qspi (
        .clk       (clk),
        .rst       (rst),
        .rd_latency(rd_latency),
        .req       (q_req),
        .addr      (q_addr),
        .we        (q_we),
        .wdata     (q_wdata),
        .be        (q_be),
        .dev       (q_dev),
        .rvalid    (q_rvalid),
        .rdata     (q_rdata),
        .sck       (sck),
        .cs_flash_n(cs_flash_n),
        .cs_ram_n  (cs_ram_n),
        .sd_out    (sd_out),
        .sd_oe     (sd_oe),
        .sd_in     (sd_in)
    );

    sync_unit #(
        .NCH(NCH), .NCMP(NCMP), .DEPTH(DEPTH), .PTRW(PTRW),
        .FRACW(FRACW), .FILTW(FILTW)
    ) u_sync (
        .clk        (clk),
        .rst        (rst),
        .cap_pin    (cap_pin),
        .trig_pin   (trig_pin),
        .evt_pending(evt_pending),
        .ovf_pin    (ovf_pin),
        .t_valid    (t_valid),
        .t_op       (t_op),
        .t_sub      (t_sub),
        .t_rs1      (t_rs1),
        .t_rs2      (t_rs2),
        .t_rdata    (t_rdata),
        .t_now      (t_now),
        .reg_req    (reg_req),
        .reg_addr   (reg_addr),
        .reg_we     (reg_we),
        .reg_wdata  (reg_wdata),
        .reg_rdata  (reg_rdata)
    );

    // A one-clock pulse every time the queue gains an entry: the cheapest
    // possible scope trigger for measuring pin-to-timestamp latency.
    logic evt_pending_q;
    always_ff @(posedge clk) begin
        if (rst) evt_pending_q <= 1'b0;
        else     evt_pending_q <= evt_pending;
    end
    assign evt_pulse = evt_pending && !evt_pending_q;

    // heartbeat: timebase bit 23. At 64 MHz that is a 3.8 Hz square wave,
    // visible on an LED and countable on a scope to check the rate trim.
    assign heartbeat = t_now[23];

    // dbg_pc has no pin on a tile; it exists so a testbench or an FPGA build
    // can watch the program counter without reaching into the hierarchy.
    wire _unused_soc = &{1'b0, dbg_pc, 1'b0};

endmodule : tp_soc
