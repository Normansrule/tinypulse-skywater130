// sync_capture.sv — pin -> clean edge event, one lane per capture channel.
//
// Each lane is: two-flop synchroniser (the pins are asynchronous to the core
// clock), then an optional N-sample glitch filter, then edge detect. The
// synchroniser costs two clocks of latency and that latency is CONSTANT,
// which is the whole point: a fixed offset can be calibrated out of a
// timestamp, jitter cannot.
//
// FILTW = 0 disables the filter (2-clock latency, 1 clock of uncertainty).
// FILTW = n requires n+1 stable samples (n+2 clock latency, still constant).
`default_nettype none

module sync_capture #(
    parameter int NCH   = 8,
    parameter int FILTW = 0
) (
    input  wire  logic            clk,
    input  wire  logic            rst,
    input  wire  logic [NCH-1:0]  pin,
    input  wire  logic [NCH-1:0]  en,        // channel enable
    input  wire  logic [NCH-1:0]  fall,      // 0 = capture rising, 1 = falling
    input  wire  logic            both,      // capture both edges
    output logic [NCH-1:0]        evt,       // one-clock pulse
    output logic [NCH-1:0]        evt_rise,  // polarity of that edge
    output logic [NCH-1:0]        level      // filtered live level
);

    logic [NCH-1:0] sync0, sync1, stable, stable_q;

    genvar c;
    generate
    for (c = 0; c < NCH; c = c + 1) begin : g_lane

        if (FILTW == 0) begin : g_nofilt
            always_ff @(posedge clk) begin
                if (rst) begin
                    sync0[c] <= 1'b0;
                    sync1[c] <= 1'b0;
                end else begin
                    sync0[c] <= pin[c];
                    sync1[c] <= sync0[c];
                end
            end
            assign stable[c] = sync1[c];

        end else begin : g_filt
            logic [FILTW:0] shift;
            always_ff @(posedge clk) begin
                if (rst) begin
                    sync0[c] <= 1'b0;
                    sync1[c] <= 1'b0;
                    shift    <= '0;
                end else begin
                    sync0[c] <= pin[c];
                    sync1[c] <= sync0[c];
                    shift    <= {shift[FILTW-1:0], sync1[c]};
                end
            end
            // change the filtered level only when every sample agrees
            always_ff @(posedge clk) begin
                if (rst)                    stable[c] <= 1'b0;
                else if (&shift)            stable[c] <= 1'b1;
                else if (~(|shift))         stable[c] <= 1'b0;
            end
        end

        always_ff @(posedge clk) begin
            if (rst) stable_q[c] <= 1'b0;
            else     stable_q[c] <= stable[c];
        end

    end
    endgenerate

    logic [NCH-1:0] rise, falling;
    assign rise    =  stable & ~stable_q;
    assign falling = ~stable &  stable_q;

    assign evt      = en & (both ? (rise | falling)
                                 : ((fall & falling) | (~fall & rise)));
    assign evt_rise = rise;
    assign level    = stable;

endmodule : sync_capture
