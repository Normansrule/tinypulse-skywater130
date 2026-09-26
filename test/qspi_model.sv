// qspi_model.sv — behavioural QSPI flash and PSRAM for simulation.
//
// These match the parts on the Tiny Tapeout QSPI Pmod: a Winbond W25Q128JV
// flash and AP Memory APS6404L PSRAMs. They are deliberately STRICT about
// the state the real chips power up in. Both start in plain single-bit SPI
// mode and do not understand the fast four-bit transactions TinyPulse uses
// until they have been woken up with the right commands. An earlier version
// of these models accepted fast transactions from time zero, which hid the
// fact that the chip never woke the memories up: it simulated perfectly and
// would not have run a single instruction on a real board.
//
// Byte order: the flash streams ascending addresses and RV32 is little
// endian, so the first byte on the wire is the LEAST significant byte of the
// word, high nibble first.
//
// Edge convention: the controller changes its output on the falling edge of
// sck and samples on the falling edge, so the device drives on the rising
// edge and holds through the high period.
`default_nettype none

// ---------------------------------------------------------------------
// Flash (W25Q128JV), read only. Holds the program.
//
// Power-up: SPI mode. The only command modelled is
//     0xEB on IO0, one bit per clock          Fast Read Quad I/O
//     addr[23:0] + mode byte, four bits per clock
// If the mode byte's bits [5:4] are 2'b10 (0xA0), the flash stays in
// CONTINUOUS READ: every following transaction starts directly with the
// address, which is what the controller relies on. A transaction whose mode
// bits are anything else (0xFF, say) leaves continuous read — that is the
// datasheet's mode-reset mechanism.
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
    reg [2:0]  stage;        // 0 addr+mode, 1 dummy, 2 data, 3 SPI command, 4 ignore
    reg        cont;         // continuous-read mode
    reg [7:0]  cmd;
    integer    i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0000_0013; // NOP
        cont = 1'b0; cmd = 8'd0; dev_sd = 4'h0; prefix = 32'd0;
        base = 24'd0; nib_cnt = 32'd0; cnt = 6'd0; stage = 3'd4;
    end

    function [3:0] nibble_at(input [23:0] b, input [31:0] n);
        reg [31:0] w;
        begin
            w = mem[((b + ((n >> 3) << 2)) >> 2) % WORDS];
            case (n[2:0])
                3'd0: nibble_at = w[7:4];   3'd1: nibble_at = w[3:0];
                3'd2: nibble_at = w[15:12]; 3'd3: nibble_at = w[11:8];
                3'd4: nibble_at = w[23:20]; 3'd5: nibble_at = w[19:16];
                3'd6: nibble_at = w[31:28]; default: nibble_at = w[27:24];
            endcase
        end
    endfunction

    always @(negedge cs_n) begin
        cnt   = 6'd0;
        stage = cont ? 3'd0 : 3'd3;
    end

    always @(posedge sck) begin
        if (!cs_n) begin
            case (stage)
                3'd3: begin                                  // SPI command byte
                    cmd = {cmd[6:0], ctrl_sd[0]};
                    if (cnt == 6'd7) begin
                        cnt   = 6'd0;
                        stage = (cmd == 8'hEB) ? 3'd0 : 3'd4;
                    end else cnt = cnt + 6'd1;
                end
                3'd0: begin                                  // address + mode, quad
                    prefix = {prefix[27:0], ctrl_sd};
                    if (cnt == 6'd7) begin
                        base    = prefix[31:8];
                        cont    = (prefix[5:4] == 2'b10);
                        nib_cnt = 32'd0;
                        cnt     = 6'd0;
                        stage   = (DUMMY == 0) ? 3'd2 : 3'd1;
                    end else cnt = cnt + 6'd1;
                end
                3'd1: begin
                    if (cnt == DUMMY[5:0] - 6'd1) begin
                        cnt = 6'd0; stage = 3'd2; nib_cnt = 32'd0;
                    end else cnt = cnt + 6'd1;
                end
                3'd2: begin
                    dev_sd  = nibble_at(base, nib_cnt);
                    nib_cnt = nib_cnt + 32'd1;
                end
                default: ;                                   // ignored command
            endcase
        end
    end
endmodule

// ---------------------------------------------------------------------
// PSRAM (APS6404L): read 0xEB and write 0x38, byte addressable.
//
// Power-up: SPI mode. 0x35 on IO0, one bit per clock (Enter Quad Mode),
// switches it to QPI, where every command is sent four bits per clock:
//     cmd (2 nibbles) then addr[23:0] (6 nibbles)
// In QPI, the two-nibble command 0xF5 (Exit Quad Mode) switches it back.
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
    reg [2:0]  stage;        // 0 QPI cmd+addr, 1 wait, 2 data, 3 SPI command, 4 ignore
    reg        is_write, nib_phase, qpi;
    reg [3:0]  hi_nib;
    reg [7:0]  cmd;
    integer    i;

    initial begin
        for (i = 0; i < BYTES; i = i + 1) mem[i] = 8'h00;
        qpi = 1'b0; cmd = 8'd0; dev_sd = 4'h0; prefix = 32'd0; addr = 24'd0;
        nib_cnt = 32'd0; cnt = 6'd0; stage = 3'd4; is_write = 1'b0; nib_phase = 1'b0;
    end

    function [3:0] rd_nibble(input [23:0] a, input [31:0] n);
        reg [31:0] w;
        begin
            w = {mem[(a + ((n >> 3) << 2) + 3) % BYTES], mem[(a + ((n >> 3) << 2) + 2) % BYTES],
                 mem[(a + ((n >> 3) << 2) + 1) % BYTES], mem[(a + ((n >> 3) << 2))     % BYTES]};
            case (n[2:0])
                3'd0: rd_nibble = w[7:4];   3'd1: rd_nibble = w[3:0];
                3'd2: rd_nibble = w[15:12]; 3'd3: rd_nibble = w[11:8];
                3'd4: rd_nibble = w[23:20]; 3'd5: rd_nibble = w[19:16];
                3'd6: rd_nibble = w[31:28]; default: rd_nibble = w[27:24];
            endcase
        end
    endfunction

    always @(negedge cs_n) begin
        cnt       = 6'd0;
        stage     = qpi ? 3'd0 : 3'd3;
        nib_phase = 1'b0;
    end

    // a QPI transaction that ends after exactly two nibbles of 0xF5 exits QPI
    always @(posedge cs_n) begin
        if (qpi && stage == 3'd0 && cnt == 6'd2 && prefix[7:0] == 8'hF5) qpi = 1'b0;
    end

    always @(posedge sck) begin
        if (!cs_n) begin
            case (stage)
                3'd3: begin                                  // SPI command byte
                    cmd = {cmd[6:0], ctrl_sd[0]};
                    if (cnt == 6'd7) begin
                        if (cmd == 8'h35) qpi = 1'b1;
                        cnt = 6'd0; stage = 3'd4;
                    end else cnt = cnt + 6'd1;
                end
                3'd0: begin                                  // QPI cmd + addr
                    prefix = {prefix[27:0], ctrl_sd};
                    if (cnt == 6'd7) begin
                        addr     = prefix[23:0];
                        is_write = (prefix[31:24] == 8'h38);
                        nib_cnt  = 32'd0;
                        cnt      = 6'd0;
                        stage    = is_write ? 3'd2 : ((DUMMY == 0) ? 3'd2 : 3'd1);
                    end else cnt = cnt + 6'd1;
                end
                3'd1: begin
                    if (cnt == DUMMY[5:0] - 6'd1) begin
                        cnt = 6'd0; stage = 3'd2; nib_cnt = 32'd0;
                    end else cnt = cnt + 6'd1;
                end
                3'd2: begin
                    if (is_write) begin
                        if (!nib_phase) begin
                            hi_nib = ctrl_sd; nib_phase = 1'b1;
                        end else begin
                            mem[addr % BYTES] = {hi_nib, ctrl_sd};
                            addr = addr + 24'd1; nib_phase = 1'b0;
                        end
                    end else begin
                        dev_sd  = rd_nibble(addr, nib_cnt);
                        nib_cnt = nib_cnt + 32'd1;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule
