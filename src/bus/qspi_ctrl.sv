// qspi_ctrl.sv — four-bit-wide external memory interface.
//
// TinyPulse has no on-chip program memory, because it cannot have one: a 32-word
// instruction RAM built from flip-flops is 1024 flops, which is more than a
// 1x2 tile holds in total. So code lives in an external QSPI flash and data
// in an external QSPI pseudo-static RAM, and this controller is the thing
// that makes the core's speed real rather than theoretical.
//
// Transaction shapes (every prefix is exactly 8 nibbles, which is why the
// sequencer is this small):
//
//   flash read   : addr[23:0] + mode 0xA0            + 4 dummy + 8 data in
//   PSRAM read   : cmd 0xEB   + addr[23:0]           + 6 dummy + 8 data in
//   PSRAM write  : cmd 0x38   + addr[23:0]           + 0 dummy + 2*n data out
//
// Streaming is the important optimisation. The flash is left in continuous
// read mode, so a SEQUENTIAL instruction fetch keeps chip select low and
// clocks out the next word directly: 8 nibble-cycles instead of 20. Straight
// line code therefore runs 2.5x faster than it would if every fetch
// re-issued an address, and a taken branch is what costs you the preamble
// back. That is the whole reason tp_bpred earns its flip-flops.
//
// Byte order: the flash streams ascending addresses and RV32 is little
// endian, so the first byte on the wire is the least significant byte of the
// word. Within a byte the high nibble goes first.
`default_nettype none

module qspi_ctrl #(
    parameter int DUMMY_FLASH = 4,
    parameter int DUMMY_RAM   = 6,
    // Clocks to hold chip select high between transactions. A flash in
    // continuous read mode only accepts a new address after chip select
    // rises; leaving it low and clocking an address just feeds the address
    // into the open stream, which misaligns every fetch after the first
    // taken branch. Real parts also specify a minimum deselect time
    // (tSHSL, tens of nanoseconds), so 2 clocks is the floor, not a target.
    parameter int CS_HIGH     = 2,
    parameter logic [7:0] FLASH_MODE = 8'hA0,
    parameter logic [7:0] RAM_READ   = 8'hEB,
    parameter logic [7:0] RAM_WRITE  = 8'h38
) (
    input  wire  logic        clk,
    input  wire  logic        rst,

    // bus side
    input  wire  logic        req,
    input  wire  logic [23:0] addr,
    input  wire  logic        we,
    input  wire  logic [31:0] wdata,
    input  wire  logic [3:0]  be,
    input  wire  logic        dev,        // 0 = flash, 1 = PSRAM
    // Extra sck cycles inserted before the data phase. A real flash launches
    // its output on the falling edge of sck, so the word the controller
    // samples arrives one to three cycles later than the ideal model; this
    // is the knob that corrects for it. Sampled from the capture pins while
    // reset is asserted, exactly so it is fixable on the bench instead of
    // being frozen into the mask. Getting this wrong is the single most
    // common way a QSPI-boot tapeout comes back dead.
    input  wire  logic [2:0]  rd_latency,
    output logic              rvalid,
    output logic [31:0]       rdata,

    // pins
    output logic              sck,
    output logic              cs_flash_n,
    output logic              cs_ram_n,
    output logic [3:0]        sd_out,
    output logic [3:0]        sd_oe,
    input  wire  logic [3:0]  sd_in
);

    localparam logic [2:0] Q_IDLE   = 3'd0;
    localparam logic [2:0] Q_PREFIX = 3'd1;
    localparam logic [2:0] Q_DUMMY  = 3'd2;
    localparam logic [2:0] Q_DATA   = 3'd3;
    localparam logic [2:0] Q_END    = 3'd4;
    localparam logic [2:0] Q_DESEL  = 3'd5;

    logic [2:0]  state;
    logic        phase;              // 0 = sck low, 1 = sck high
    logic [31:0] tx;                 // prefix / write-data shift register
    logic [31:0] rx;
    logic [3:0]  nib_cnt;            // nibbles remaining in the current phase
    logic [3:0]  dummy_cnt;
    logic        cur_dev, cur_we;
    logic [23:0] cur_addr;           // latched: the bus may move on mid-burst
    logic [31:0] prefix_q;           // latched prefix, sent after deselect
    logic [2:0]  desel_cnt;
    logic [23:0] next_seq_addr;      // address the stream is positioned at
    logic        stream_open;        // flash chip select is low and streaming
    logic [1:0]  wr_start;
    logic [2:0]  wr_bytes;

    // number of contiguous bytes a write touches, and where it starts
    always_comb begin
        unique case (be)
            4'b0001: begin wr_start = 2'd0; wr_bytes = 3'd1; end
            4'b0010: begin wr_start = 2'd1; wr_bytes = 3'd1; end
            4'b0100: begin wr_start = 2'd2; wr_bytes = 3'd1; end
            4'b1000: begin wr_start = 2'd3; wr_bytes = 3'd1; end
            4'b0011: begin wr_start = 2'd0; wr_bytes = 3'd2; end
            4'b1100: begin wr_start = 2'd2; wr_bytes = 3'd2; end
            default: begin wr_start = 2'd0; wr_bytes = 3'd4; end
        endcase
    end

    // write payload, shifted out most significant nibble first, lowest
    // addressed byte first
    logic [31:0] wr_payload;
    always_comb begin
        unique case (wr_start)
            2'd0:    wr_payload = {wdata[7:0],   wdata[15:8],
                                   wdata[23:16], wdata[31:24]};
            2'd1:    wr_payload = {wdata[15:8],  wdata[23:16],
                                   wdata[31:24], 8'd0};
            2'd2:    wr_payload = {wdata[23:16], wdata[31:24], 16'd0};
            default: wr_payload = {wdata[31:24], 24'd0};
        endcase
    end

    // A sub-word write addresses the first byte it actually touches, so the
    // PSRAM only sees the bytes the store meant to change.
    logic [23:0] eff_addr;
    assign eff_addr = (dev && we) ? {addr[23:2], wr_start} : addr;

    logic [31:0] prefix_word;
    assign prefix_word = dev ? {(we ? RAM_WRITE : RAM_READ), eff_addr}
                             : {eff_addr, FLASH_MODE};

    logic can_stream;
    assign can_stream = stream_open && !dev && !we && (addr == next_seq_addr);

    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= Q_IDLE;
            phase         <= 1'b0;
            tx            <= 32'd0;
            rx            <= 32'd0;
            nib_cnt       <= 4'd0;
            dummy_cnt     <= 4'd0;
            cur_dev       <= 1'b0;
            cur_we        <= 1'b0;
            next_seq_addr <= 24'hFFFFFF;
            stream_open   <= 1'b0;
            prefix_q      <= 32'd0;
            desel_cnt     <= 3'd0;
            rvalid        <= 1'b0;
            cs_flash_n    <= 1'b1;
            cs_ram_n      <= 1'b1;
            sck           <= 1'b0;
        end else begin
            rvalid <= 1'b0;

            unique case (state)

                Q_IDLE: begin
                    phase <= 1'b0;
                    sck   <= 1'b0;
                    if (req) begin
                        cur_dev  <= dev;
                        cur_we   <= we;
                        cur_addr <= eff_addr;
                        if (can_stream) begin
                            // chip select already low, the stream continues.
                            // No preamble and no latency: the flash has been
                            // clocking bytes out continuously.
                            state     <= Q_DATA;
                            nib_cnt   <= 4'd8;
                            rx        <= 32'd0;
                        end else begin
                            // Deselect first. Whatever stream was open has
                            // to be ended before a new address means
                            // anything to the device.
                            cs_flash_n  <= 1'b1;
                            cs_ram_n    <= 1'b1;
                            stream_open <= 1'b0;
                            prefix_q    <= prefix_word;
                            dummy_cnt   <= we ? 4'd0
                                        : (dev ? (DUMMY_RAM[3:0]   + {1'b0, rd_latency})
                                               : (DUMMY_FLASH[3:0] + {1'b0, rd_latency}));
                            desel_cnt   <= CS_HIGH[2:0];
                            state       <= Q_DESEL;
                        end
                    end
                end

                Q_DESEL: begin
                    sck   <= 1'b0;
                    phase <= 1'b0;
                    if (desel_cnt != 3'd0) begin
                        desel_cnt <= desel_cnt - 3'd1;
                    end else begin
                        cs_flash_n <= cur_dev;      // low only for flash
                        cs_ram_n   <= ~cur_dev;
                        tx         <= prefix_q;
                        nib_cnt    <= 4'd8;
                        state      <= Q_PREFIX;
                    end
                end

                Q_PREFIX: begin
                    sck <= ~phase;
                    if (phase) begin
                        tx      <= {tx[27:0], 4'd0};
                        nib_cnt <= nib_cnt - 4'd1;
                        if (nib_cnt == 4'd1) begin
                            if (dummy_cnt != 4'd0) begin
                                state <= Q_DUMMY;
                            end else begin
                                state   <= Q_DATA;
                                nib_cnt <= cur_we ? {wr_bytes, 1'b0} : 4'd8;
                                tx      <= wr_payload;
                                rx      <= 32'd0;
                            end
                        end
                    end
                    phase <= ~phase;
                end

                Q_DUMMY: begin
                    sck <= ~phase;
                    if (phase) begin
                        dummy_cnt <= dummy_cnt - 4'd1;
                        if (dummy_cnt == 4'd1) begin
                            state   <= Q_DATA;
                            nib_cnt <= 4'd8;
                            rx      <= 32'd0;
                        end
                    end
                    phase <= ~phase;
                end

                Q_DATA: begin
                    sck <= ~phase;
                    if (phase) begin
                        rx      <= {rx[27:0], sd_in};
                        tx      <= {tx[27:0], 4'd0};
                        nib_cnt <= nib_cnt - 4'd1;
                        if (nib_cnt == 4'd1)
                            state <= Q_END;
                    end
                    phase <= ~phase;
                end

                Q_END: begin
                    sck    <= 1'b0;
                    phase  <= 1'b0;
                    rvalid <= 1'b1;
                    state  <= Q_IDLE;
                    if (!cur_dev && !cur_we) begin
                        // leave the flash stream open and remember where it is
                        stream_open   <= 1'b1;
                        next_seq_addr <= {cur_addr[23:2], 2'b00} + 24'd4;
                    end else begin
                        cs_flash_n  <= 1'b1;
                        cs_ram_n    <= 1'b1;
                        stream_open <= 1'b0;
                    end
                end

                default: state <= Q_IDLE;
            endcase
        end
    end

    // byte swap: rx[31:24] is the lowest addressed byte
    assign rdata  = {rx[7:0], rx[15:8], rx[23:16], rx[31:24]};

    assign sd_out = tx[31:28];
    // drive the bus during the prefix always, and during data only on writes
    assign sd_oe  = ((state == Q_PREFIX) ||
                     ((state == Q_DATA) && cur_we)) ? 4'b1111 : 4'b0000;

    // cur_addr[1:0] is a byte offset inside a word; the streaming check only
    // cares about word addresses.
    wire _unused = &{1'b0, cur_addr[1:0], 1'b0};

endmodule : qspi_ctrl
