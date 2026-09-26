// tp_periph.sv — GPIO and UART registers, at 0x3000_0000.
//
//   offset  name        access  meaning
//   0x00    GPIO_OUT    RW      value driven on uo_out[7:0] (pins in GPIO mode)
//   0x04    GPIO_IN     R       ui_in[7:0], synchronized
//   0x08    GPIO_SEL    RW      per pin: 1 = built-in function, 0 = GPIO_OUT
//                               (reset 0xFF: every pin shows its function)
//   0x0C    UART_DATA   W       send a byte (ignored while TX_BUSY)
//                       R       last received byte; reading clears
//                               RX_VALID and RX_OVERRUN
//   0x10    UART_STAT   R       bit 0 TX_BUSY, 1 RX_VALID, 2 RX_OVERRUN
//   0x14    UART_DIV    RW      clocks per bit, reset 434 (115,200 @ 50 MHz)
//   0x18    GPIO_SET    W       GPIO_OUT |=  value
//   0x1C    GPIO_CLR    W       GPIO_OUT &= ~value
//   0x20    GPIO_XOR    W       GPIO_OUT ^=  value
//
// SET/CLR/XOR are the RP2040's trick: changing one pin is a single store,
// with no read-modify-write and no race against other code touching other
// pins. They cost a few gates.
//
// Every access completes in the clock it is issued, like the sync unit's
// registers.
`default_nettype none

module tp_periph #(
    // clocks per UART bit after reset: 434 = 115,200 baud at 50 MHz.
    // Simulation overrides it to keep bootloader tests short.
    parameter logic [11:0] DIV_RESET = 12'd434
) (
    input  wire  logic        clk,
    input  wire  logic        rst,
    // bus slave
    input  wire  logic        req,
    input  wire  logic [3:0]  addr,       // word offset
    input  wire  logic        we,
    input  wire  logic [31:0] wdata,
    output logic [31:0]       rdata,
    // pins
    input  wire  logic [7:0]  gpio_in,    // already synchronized
    output logic [7:0]        gpio_out,
    output logic [7:0]        gpio_sel,
    output logic              uart_tx,
    input  wire  logic        uart_rx     // already synchronized
);
    localparam logic [3:0] R_OUT  = 4'd0;
    localparam logic [3:0] R_IN   = 4'd1;
    localparam logic [3:0] R_SEL  = 4'd2;
    localparam logic [3:0] R_DATA = 4'd3;
    localparam logic [3:0] R_STAT = 4'd4;
    localparam logic [3:0] R_DIV  = 4'd5;
    localparam logic [3:0] R_SET  = 4'd6;
    localparam logic [3:0] R_CLR  = 4'd7;
    localparam logic [3:0] R_XOR  = 4'd8;

    logic        wr, rd;
    assign wr = req &&  we;
    assign rd = req && !we;

    logic [11:0] div;
    logic        tx_busy, rx_valid, rx_overrun;
    logic [7:0]  rx_data;

    always_ff @(posedge clk) begin
        if (rst) begin
            gpio_out <= 8'h00;
            gpio_sel <= 8'hFF;
            div      <= DIV_RESET;
        end else if (wr) begin
            unique case (addr)
                R_OUT:   gpio_out <= wdata[7:0];
                R_SEL:   gpio_sel <= wdata[7:0];
                R_DIV:   div      <= wdata[11:0];
                R_SET:   gpio_out <= gpio_out |  wdata[7:0];
                R_CLR:   gpio_out <= gpio_out & ~wdata[7:0];
                R_XOR:   gpio_out <= gpio_out ^  wdata[7:0];
                default: ;
            endcase
        end
    end

    tp_uart u_uart (
        .clk       (clk),
        .rst       (rst),
        .div       (div),
        .tx_start  (wr && addr == R_DATA),
        .tx_data   (wdata[7:0]),
        .tx_busy   (tx_busy),
        .tx        (uart_tx),
        .rx        (uart_rx),
        .rx_ack    (rd && addr == R_DATA),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .rx_overrun(rx_overrun)
    );

    always_comb begin
        unique case (addr)
            R_OUT:   rdata = {24'd0, gpio_out};
            R_IN:    rdata = {24'd0, gpio_in};
            R_SEL:   rdata = {24'd0, gpio_sel};
            R_DATA:  rdata = {24'd0, rx_data};
            R_STAT:  rdata = {29'd0, rx_overrun, rx_valid, tx_busy};
            R_DIV:   rdata = {20'd0, div};
            default: rdata = 32'd0;
        endcase
    end

    wire _unused = &{1'b0, wdata[31:12], 1'b0};
endmodule : tp_periph
