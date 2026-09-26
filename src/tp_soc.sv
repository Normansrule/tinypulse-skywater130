// tp_soc.sv — the TinyPulse microcontroller: core, bus, external memory,
// timing unit, GPIO and UART.
//
//   0x0000_0000  flash      16 MB   QSPI Pmod CS0   code and constants
//   0x1000_0000  RAM A       8 MB   QSPI Pmod CS1   data
//   0x1080_0000  RAM B       8 MB   QSPI Pmod CS2   data
//   0x2000_0000  (timing unit: reached by Xpulse instructions, see below)
//   0x3000_0000  GPIO and UART registers
//   0x4000_0000  boot ROM: the UART bootloader (sw/mkboot.py)
//
// Boot: if ui_in[7] is high while reset is released, the core starts in the
// boot ROM, which loads a program over the UART into RAM A and runs it.
// Otherwise it starts at flash address 0.
//
// Output pins: each uo_out pin either shows a built-in function or is a
// plain GPIO, selected per pin by GPIO_SEL. At reset every pin shows its
// function, so a freshly powered chip is observable with no software:
//
//   pin  function                     pin  function
//   0    TRIG0 compare output         4    UART TX
//   1    TRIG1 compare output         5    HALT (ECALL/EBREAK reached)
//   2    EVT   event queue not empty  6    ILLEGAL instruction seen
//   3    OVF   event queue overflowed 7    HEARTBEAT, ~3 Hz at 50 MHz
`default_nettype none

module tp_soc
#(
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter int          NCH      = 8,
    parameter int          NCMP     = 2,
    parameter int          DEPTH    = 2,
    parameter int          PTRW     = 1,
    parameter int          FRACW    = 24,
    parameter int          FILTW    = 0,
    // The timing unit also has a memory-mapped register port, which the
    // serial build (no CPU) needs. Here every timing operation is one Xpulse
    // instruction, so the port is left unconnected and synthesis removes the
    // decode and read multiplexer behind it. sync_unit.sv itself is unchanged
    // and byte-identical to the serial repo's copy.
    parameter bit          SYNC_MMIO = 1'b0
) (
    input  wire  logic            clk,
    input  wire  logic            rst,
    input  wire  logic [7:0]      ui,        // input pins
    output logic       [7:0]      uo,        // output pins
    // QSPI Pmod
    output logic                  sck,
    output logic                  cs_flash_n,
    output logic                  cs_rama_n,
    output logic                  cs_ramb_n,
    output logic [3:0]            sd_out,
    output logic [3:0]            sd_oe,
    input  wire  logic [3:0]      sd_in
);
    logic        imem_req, imem_rvalid;
    logic [31:0] imem_addr, imem_rdata;
    logic        dmem_req, dmem_we, dmem_rvalid;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_be;
    logic        t_valid;
    logic [2:0]  t_op;
    logic [6:0]  t_sub;
    logic [31:0] t_rs1, t_rs2, t_rdata, t_now;
    logic        q_req, q_we, q_dev, q_rvalid;
    logic [23:0] q_addr;
    logic [31:0] q_wdata, q_rdata;
    logic [3:0]  q_be;
    logic [2:0]  rd_latency;
    logic [31:0] sync_status, sync_head, dbg_pc;
    logic        reg_req, reg_we, p_req, p_we;
    logic [3:0]  reg_addr, p_addr;
    logic [31:0] reg_wdata, reg_rdata, p_wdata, p_rdata;
    logic        halted, illegal, cs_ram_n, waking;
    logic [NCMP-1:0] trig;
    logic [5:0]  rom_addr;
    logic [31:0] rom_data;
    logic        evt_pending, ovf;

    // Named block kept so testbench paths (u_soc.g_cpu.u_core) survive.
    generate if (1) begin : g_cpu
        tp_ncore #(.RESET_PC(RESET_PC)) u_core (
            .clk        (clk),
            .rst        (rst),
            .boot       (ui[7]),
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
    end endgenerate

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
        .reg_rdata  (reg_rdata),
        .p_req      (p_req),
        .p_addr     (p_addr),
        .p_we       (p_we),
        .p_wdata    (p_wdata),
        .p_rdata    (p_rdata),
        .rom_addr   (rom_addr),
        .rom_data   (rom_data)
    );

    tp_bootrom u_rom (.addr(rom_addr), .data(rom_data));

    // Read latency comes from ui_in[2:0] while reset is held, so a board can
    // match whatever flash and RAM are fitted without a respin.
    always_ff @(posedge clk) begin
        if (rst) rd_latency <= ui[2:0];
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
        .sd_in     (sd_in),
        .waking    (waking)
    );

    // The Pmod carries two 8 MB RAMs. Address bit 23 picks one; it is
    // sampled while the RAM chip select is high, so it cannot change under
    // a transaction that is already on the wire.
    logic ramb;
    always_ff @(posedge clk) begin
        if (rst)           ramb <= 1'b0;
        else if (cs_ram_n) ramb <= q_addr[23];
    end
    // During the QSPI wake-up sequence both RAMs are selected together, so
    // one pair of commands puts both into quad mode.
    assign cs_rama_n = cs_ram_n || ( ramb && !waking);
    assign cs_ramb_n = cs_ram_n || (!ramb && !waking);

    logic        s_req, s_we;
    logic [3:0]  s_addr;
    logic [31:0] s_wdata, s_rdata;
    generate if (SYNC_MMIO) begin : g_mmio
        assign s_req = reg_req;  assign s_we = reg_we;
        assign s_addr = reg_addr; assign s_wdata = reg_wdata;
        assign reg_rdata = s_rdata;
    end else begin : g_no_mmio
        assign s_req = 1'b0;     assign s_we = 1'b0;
        assign s_addr = 4'd0;    assign s_wdata = 32'd0;
        assign reg_rdata = 32'd0;          // loads from 0x2000_0000 read zero
    end endgenerate

    sync_unit #(
        .NCH(NCH), .NCMP(NCMP), .DEPTH(DEPTH), .PTRW(PTRW),
        .FRACW(FRACW), .FILTW(FILTW)
    ) u_sync (
        .clk        (clk),
        .rst        (rst),
        .cap_pin    (ui[NCH-1:0]),
        .trig_pin   (trig),
        .evt_pending(evt_pending),
        .ovf_pin    (ovf),
        .t_valid    (t_valid),
        .t_op       (t_op),
        .t_sub      (t_sub),
        .t_rs1      (t_rs1),
        .t_rs2      (t_rs2),
        .t_rdata    (t_rdata),
        .t_now      (t_now),
        .reg_req    (s_req),
        .reg_addr   (s_addr),
        .reg_we     (s_we),
        .reg_wdata  (s_wdata),
        .reg_rdata  (s_rdata),
        .status_out (sync_status),
        .head_out   (sync_head)
    );

    // The capture unit already synchronizes every input pin; GPIO_IN and the
    // UART receiver reuse those flip-flops instead of adding their own.
    logic [7:0] pin_sync;
    assign pin_sync = sync_status[23:16];

    logic [7:0] gpio_out, gpio_sel;
    logic       uart_tx;
    tp_periph u_periph (
        .clk     (clk),
        .rst     (rst),
        .req     (p_req),
        .addr    (p_addr),
        .we      (p_we),
        .wdata   (p_wdata),
        .rdata   (p_rdata),
        .gpio_in (pin_sync),
        .gpio_out(gpio_out),
        .gpio_sel(gpio_sel),
        .uart_tx (uart_tx),
        .uart_rx (pin_sync[3])
    );

    logic [7:0] func;
    assign func = {t_now[23], illegal, halted, uart_tx, ovf, evt_pending, trig[1:0]};
    assign uo   = (gpio_sel & func) | (~gpio_sel & gpio_out);

    wire _unused_soc = &{1'b0, dbg_pc, s_rdata, reg_req, reg_we, reg_addr, reg_wdata, sync_status[31:24], sync_status[15:0],
                         sync_head, 1'b0};
endmodule : tp_soc
