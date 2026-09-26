// tp_uart.sv — 8N1 transmitter and receiver sharing one programmable divider.
//
// `div` is the number of clocks per bit. At 50 MHz, 434 gives 115,200 baud
// (0.04% error); at 10 MHz, 87 gives 114,943 (0.2%). Anything within about
// 2% works with any PC serial port.
//
// The receiver expects `rx` to be synchronized already. TinyPulse feeds it
// from the capture unit, which runs every ui_in pin through two flip-flops
// anyway, so the UART does not pay for its own synchronizer.
//
// Transmit: pulse `tx_start` with `tx_data` while `tx_busy` is low. There
// is no FIFO; software polls TX_BUSY. At 115,200 baud a byte takes 87 us,
// roughly 4,300 instructions' worth of time — polling is not a burden.
//
// Receive: when a byte lands, `rx_data` holds it and `rx_valid` rises. A
// second byte arriving before software reads the first sets `rx_overrun`
// and replaces the old byte. `rx_ack` clears both.
`default_nettype none

module tp_uart (
    input  wire  logic        clk,
    input  wire  logic        rst,
    input  wire  logic [11:0] div,
    // transmit
    input  wire  logic        tx_start,
    input  wire  logic [7:0]  tx_data,
    output logic              tx_busy,
    output logic              tx,
    // receive
    input  wire  logic        rx,
    input  wire  logic        rx_ack,
    output logic [7:0]        rx_data,
    output logic              rx_valid,
    output logic              rx_overrun
);
    // ---------------- transmitter ----------------
    // One shift register holds the whole frame: stop, 8 data bits, start.
    // Shifting right with 1s coming in leaves the line idle-high afterwards.
    logic [9:0]  tsh;
    logic [3:0]  tbits;
    logic [11:0] tcnt;

    assign tx_busy = (tbits != 4'd0);
    assign tx      = tx_busy ? tsh[0] : 1'b1;

    always_ff @(posedge clk) begin
        if (rst) begin
            tbits <= 4'd0;
            tsh   <= 10'h3FF;
            tcnt  <= 12'd0;
        end else if (!tx_busy) begin
            if (tx_start) begin
                tsh   <= {1'b1, tx_data, 1'b0};
                tbits <= 4'd10;
                tcnt  <= div;
            end
        end else if (tcnt <= 12'd1) begin
            tsh   <= {1'b1, tsh[9:1]};
            tbits <= tbits - 4'd1;
            tcnt  <= div;
        end else begin
            tcnt  <= tcnt - 12'd1;
        end
    end

    // ---------------- receiver ----------------
    // Idle until the line falls. Wait half a bit and check it is still low
    // (a real start bit, not a glitch), then sample every `div` clocks: eight
    // data bits and the stop bit, landing each sample in the middle of its bit.
    logic        rbusy;
    logic [3:0]  rbits;       // samples still to take after the start check
    logic [11:0] rcnt;
    logic [7:0]  rsh;

    always_ff @(posedge clk) begin
        if (rst) begin
            rbusy      <= 1'b0;
            rbits      <= 4'd0;
            rcnt       <= 12'd0;
            rsh        <= 8'd0;
            rx_data    <= 8'd0;
            rx_valid   <= 1'b0;
            rx_overrun <= 1'b0;
        end else begin
            if (rx_ack) begin
                rx_valid   <= 1'b0;
                rx_overrun <= 1'b0;
            end

            if (!rbusy) begin
                if (!rx) begin
                    rbusy <= 1'b1;
                    rbits <= 4'd10;                   // start check + 8 data + stop
                    rcnt  <= {1'b0, div[11:1]};       // half a bit
                end
            end else if (rcnt <= 12'd1) begin
                rcnt  <= div;
                rbits <= rbits - 4'd1;
                if (rbits == 4'd10) begin
                    if (rx) rbusy <= 1'b0;            // glitch: not a start bit
                end else if (rbits == 4'd1) begin
                    rbusy <= 1'b0;
                    if (rx) begin                     // good stop bit
                        rx_data    <= rsh;
                        rx_valid   <= 1'b1;
                        rx_overrun <= rx_valid && !rx_ack;
                    end
                end else begin
                    rsh <= {rx, rsh[7:1]};            // LSB arrives first
                end
            end else begin
                rcnt <= rcnt - 12'd1;
            end
        end
    end
endmodule : tp_uart
