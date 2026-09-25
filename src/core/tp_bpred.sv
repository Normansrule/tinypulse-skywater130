// tp_bpred.sv — next-fetch-address prediction.
//
// Why a predictor earns its area here: instruction fetch is the bottleneck,
// not execution. A sequential 32-bit fetch costs 8 QSPI cycles; a mispredicted
// branch throws away a whole fetch AND pays the 12-cycle address preamble to
// restart the flash stream. One correct prediction saves ~20 QSPI cycles, so
// 16 flip-flops of history buy back far more than they cost.
//
// The predictor sees the instruction as it lands in the fetch buffer (not
// before it), so this is a pre-decode predictor: no BTB is needed because the
// target is computable straight from the immediate field.
//
// BIMODAL=0: static backwards-taken / forwards-not-taken. Zero state.
// BIMODAL=1: NENT 2-bit saturating counters indexed by pc[NIDX+1:2].
`default_nettype none

module tp_bpred
#(
    parameter bit BIMODAL = 1'b0,
    parameter int NENT    = 16,
    parameter int NIDX    = 4      // $clog2(NENT)
) (
    input  wire  logic        clk,
    input  wire  logic        rst,
    // lookup: the instruction that just arrived in the fetch buffer
    input  wire  logic [31:0] instr,
    input  wire  logic [31:0] pc,
    output logic              predict_taken,
    output logic [31:0]       predict_target,
    // update: resolved in execute
    input  wire  logic        upd_valid,
    input  wire  logic [31:0] upd_pc,
    input  wire  logic        upd_taken
);

    logic [6:0]  opcode;
    logic [31:0] imm_b, imm_j;
    logic        is_branch, is_jal;

    assign opcode    = instr[6:0];
    assign is_branch = (opcode == tp_pkg::OPC_BRANCH);
    assign is_jal    = (opcode == tp_pkg::OPC_JAL);

    assign imm_b = {{19{instr[31]}}, instr[31], instr[7],
                    instr[30:25], instr[11:8], 1'b0};
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                    instr[20], instr[30:21], 1'b0};

    logic cond_taken;

    generate
    if (BIMODAL) begin : g_bimodal
        logic [1:0] ctr [NENT-1:0];
        logic [NIDX-1:0] rd_idx, wr_idx;

        assign rd_idx = pc[NIDX+1:2];
        assign wr_idx = upd_pc[NIDX+1:2];

        integer i;
        always_ff @(posedge clk) begin
            if (rst) begin
                for (i = 0; i < NENT; i = i + 1)
                    ctr[i] <= 2'b01;             // weakly not-taken
            end else if (upd_valid) begin
                if (upd_taken && (ctr[wr_idx] != 2'b11))
                    ctr[wr_idx] <= ctr[wr_idx] + 2'b01;
                else if (!upd_taken && (ctr[wr_idx] != 2'b00))
                    ctr[wr_idx] <= ctr[wr_idx] - 2'b01;
            end
        end

        assign cond_taken = ctr[rd_idx][1];
    end else begin : g_static
        // backwards branch (negative displacement) predicted taken
        assign cond_taken = imm_b[31];
        wire _unused_static = &{1'b0, clk, rst, upd_valid, upd_pc, upd_taken};
    end
    endgenerate

    always_comb begin
        if (is_jal) begin
            predict_taken  = 1'b1;               // unconditional, target known
            predict_target = pc + imm_j;
        end else if (is_branch) begin
            predict_taken  = cond_taken;
            predict_target = pc + imm_b;
        end else begin
            // JALR is not predicted: it falls through and the core redirects.
            predict_taken  = 1'b0;
            predict_target = pc + 32'd4;
        end
    end

endmodule : tp_bpred
