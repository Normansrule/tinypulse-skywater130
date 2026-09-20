// qspi_model.sv — behavioural QSPI flash and PSRAM for simulation.
//
// These match qspi_ctrl exactly, including the byte order that trips
// everybody up: the flash streams ascending addresses and RV32 is little
// endian, so the first byte on the wire is the LEAST significant byte of the
// word, high nibble first.
//
// Edge convention: the controller changes its output on the falling edge of
// sck and samples on the falling edge, so the device drives on the rising
// edge and holds through the high period. Real flash launches later than
// this; `rd_latency` on the chip is the knob that makes up the difference.
// See the bring-up section of the README.
`default_nettype none
`timescale 1ns/1ps

// ---------------------------------------------------------------------
// Flash: read only, continuous-read stream. Holds the program.
//   prefix = addr[23:0] (6 nibbles) then mode 0xA0 (2 nibbles)
// ---------------------------------------------------------------------
module qspi_flash_model #(
    parameter int DUMMY = 4,
    parameter int WORDS = 512
) (
    input  wire       cs_n,
    input  wire       sck,
    input  wire [3:0] ctrl_sd,
    output reg  [3:0] dev_sd
);

    reg [31:0] mem [0:WORDS-1];
    reg [31:0] prefix;
    reg [23:0] base;
    reg [31:0] nib_cnt;
    reg [5:0]  cnt;
    reg [1:0]  stage;        // 0 prefix, 1 dummy, 2 data
    integer    i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0000_0013; // NOP
        dev_sd  = 4'h0;
        prefix  = 32'd0;
        base    = 24'd0;
        nib_cnt = 32'd0;
        cnt     = 6'd0;
        stage   = 2'd0;
    end

    function [3:0] nibble_at(input [23:0] b, input [31:0] n);
        reg [31:0] w;
        begin
            w = mem[((b + ((n >> 3) << 2)) >> 2) % WORDS];
            case (n[2:0])
                3'd0: nibble_at = w[7:4];
                3'd1: nibble_at = w[3:0];
                3'd2: nibble_at = w[15:12];
                3'd3: nibble_at = w[11:8];
                3'd4: nibble_at = w[23:20];
                3'd5: nibble_at = w[19:16];
                3'd6: nibble_at = w[31:28];
                default: nibble_at = w[27:24];
            endcase
        end
    endfunction

    always @(negedge cs_n) begin
        cnt   = 6'd0;
        stage = 2'd0;
    end

    always @(posedge sck) begin
        if (!cs_n) begin
            case (stage)
                2'd0: begin
                    prefix = {prefix[27:0], ctrl_sd};
                    if (cnt == 6'd7) begin
                        base    = prefix[31:8];
                        nib_cnt = 32'd0;
                        cnt     = 6'd0;
                        stage   = (DUMMY == 0) ? 2'd2 : 2'd1;
                    end else begin
                        cnt = cnt + 6'd1;
                    end
                end
                2'd1: begin
                    if (cnt == DUMMY[5:0] - 6'd1) begin
                        cnt     = 6'd0;
                        stage   = 2'd2;
                        nib_cnt = 32'd0;
                    end else begin
                        cnt = cnt + 6'd1;
                    end
                end
                default: begin
                    dev_sd  = nibble_at(base, nib_cnt);
                    nib_cnt = nib_cnt + 32'd1;
                end
            endcase
        end
    end

endmodule

// ---------------------------------------------------------------------
// PSRAM: read 0xEB and write 0x38, byte addressable.
//   prefix = cmd (2 nibbles) then addr[23:0] (6 nibbles)
// ---------------------------------------------------------------------
module qspi_psram_model #(
    parameter int DUMMY = 6,
    parameter int BYTES = 4096
) (
    input  wire       cs_n,
    input  wire       sck,
    input  wire [3:0] ctrl_sd,
    output reg  [3:0] dev_sd
);

    reg [7:0]  mem [0:BYTES-1];
    reg [31:0] prefix;
    reg [23:0] addr;
    reg [31:0] nib_cnt;
    reg [5:0]  cnt;
    reg [1:0]  stage;
    reg        is_write, nib_phase;
    reg [3:0]  hi_nib;
    integer    i;

    initial begin
        for (i = 0; i < BYTES; i = i + 1) mem[i] = 8'h00;
        dev_sd    = 4'h0;
        prefix    = 32'd0;
        addr      = 24'd0;
        nib_cnt   = 32'd0;
        cnt       = 6'd0;
        stage     = 2'd0;
        is_write  = 1'b0;
        nib_phase = 1'b0;
    end

    function [3:0] rd_nibble(input [23:0] a, input [31:0] n);
        reg [31:0] w;
        begin
            w = {mem[(a + ((n >> 3) << 2) + 3) % BYTES],
                 mem[(a + ((n >> 3) << 2) + 2) % BYTES],
                 mem[(a + ((n >> 3) << 2) + 1) % BYTES],
                 mem[(a + ((n >> 3) << 2))     % BYTES]};
            case (n[2:0])
                3'd0: rd_nibble = w[7:4];
                3'd1: rd_nibble = w[3:0];
                3'd2: rd_nibble = w[15:12];
                3'd3: rd_nibble = w[11:8];
                3'd4: rd_nibble = w[23:20];
                3'd5: rd_nibble = w[19:16];
                3'd6: rd_nibble = w[31:28];
                default: rd_nibble = w[27:24];
            endcase
        end
    endfunction

    always @(negedge cs_n) begin
        cnt       = 6'd0;
        stage     = 2'd0;
        nib_phase = 1'b0;
    end

    always @(posedge sck) begin
        if (!cs_n) begin
            case (stage)
                2'd0: begin
                    prefix = {prefix[27:0], ctrl_sd};
                    if (cnt == 6'd7) begin
                        addr     = prefix[23:0];
                        is_write = (prefix[31:24] == 8'h38);
                        nib_cnt  = 32'd0;
                        cnt      = 6'd0;
                        stage    = is_write ? 2'd2 : ((DUMMY == 0) ? 2'd2 : 2'd1);
                    end else begin
                        cnt = cnt + 6'd1;
                    end
                end
                2'd1: begin
                    if (cnt == DUMMY[5:0] - 6'd1) begin
                        cnt     = 6'd0;
                        stage   = 2'd2;
                        nib_cnt = 32'd0;
                    end else begin
                        cnt = cnt + 6'd1;
                    end
                end
                default: begin
                    if (is_write) begin
                        if (!nib_phase) begin
                            hi_nib    = ctrl_sd;
                            nib_phase = 1'b1;
                        end else begin
                            mem[addr % BYTES] = {hi_nib, ctrl_sd};
                            addr      = addr + 24'd1;
                            nib_phase = 1'b0;
                        end
                    end else begin
                        dev_sd  = rd_nibble(addr, nib_cnt);
                        nib_cnt = nib_cnt + 32'd1;
                    end
                end
            endcase
        end
    end

endmodule
