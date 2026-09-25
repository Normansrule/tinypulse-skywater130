// tp_shifter.sv — SLL / SRL / SRA, split out of the ALU.
//
// BARREL=0 (default, the 1x2 tile build): an iterative shifter, one bit per
// clock. Costs shamt+2 clocks but roughly 500 gate-equivalents less than a
// barrel, and it keeps the shift network off the ALU adder chain, which is
// what lets the ALU path set Fmax.
// BARREL=1 (the 2x2 build): a one-cycle log shifter, `busy` tied low.
//
// Handshake: pulse `start` with the operands valid on that cycle. The
// operands are latched, so the caller may change them immediately after.
// The result is valid on `y` from the cycle `busy` falls until the next start.
`default_nettype none

module tp_shifter
#(
    parameter bit BARREL = 1'b0
) (
    input  wire  logic        clk,
    input  wire  logic        rst,
    input  wire  logic        start,
    input  wire  logic [31:0] a,
    input  wire  logic [4:0]  shamt,
    input  wire  logic [1:0]  op,
    output logic [31:0]       y,
    output logic              busy
);

    generate
    if (BARREL) begin : g_barrel
        always_comb begin
            unique case (op)
                tp_pkg::SH_SLL:  y = a << shamt;
                tp_pkg::SH_SRL:  y = a >> shamt;
                tp_pkg::SH_SRA:  y = $signed(a) >>> shamt;
                default: y = a;
            endcase
        end
        assign busy = 1'b0;
        wire _unused_barrel = &{1'b0, clk, rst, start};

    end else begin : g_iter
        logic [31:0] acc;
        logic [4:0]  cnt;
        logic        running;
        logic [1:0]  op_q;

        always_ff @(posedge clk) begin
            if (rst) begin
                running <= 1'b0;
                acc     <= 32'd0;
                cnt     <= 5'd0;
                op_q    <= tp_pkg::SH_NONE;
            end else if (start && !running) begin
                // load cycle: always taken, so shamt == 0 is handled uniformly
                acc     <= a;
                cnt     <= shamt;
                op_q    <= op;
                running <= 1'b1;
            end else if (running) begin
                if (cnt == 5'd0) begin
                    running <= 1'b0;
                end else begin
                    unique case (op_q)
                        tp_pkg::SH_SLL:  acc <= {acc[30:0], 1'b0};
                        tp_pkg::SH_SRL:  acc <= {1'b0, acc[31:1]};
                        tp_pkg::SH_SRA:  acc <= {acc[31], acc[31:1]};
                        default: acc <= acc;
                    endcase
                    cnt <= cnt - 5'd1;
                end
            end
        end

        assign y    = acc;
        assign busy = running || start;
    end
    endgenerate

endmodule : tp_shifter
