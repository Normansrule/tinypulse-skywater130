// tp_fetch.sv — program counter, instruction request, prediction.
//
// A three-state machine with a one-instruction buffer:
//   F_IDLE -> issue a read for pc_req
//   F_REQ  -> hold the request until the bus answers
//   F_FULL -> present the instruction to DX until DX takes it
//
// Fetch and execute deliberately do not overlap. A sequential 32-bit fetch is
// about 16 core clocks, execute is usually 1, so overlapping would recover one
// clock in seventeen and would cost a second 32-bit buffer (64 flip-flops,
// about 1250 um^2). On a tile that is a bad trade.
//
// `if_next_pc` is the address fetch has already gone on to request. DX
// compares its own resolved next-PC against it and redirects only when they
// differ, which is what makes the predictor pay off.
`default_nettype none

import tp_pkg::*;

module tp_fetch
#(
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter bit          BIMODAL  = 1'b0,
    parameter int          NENT     = 16,
    parameter int          NIDX     = 4
) (
    input  wire  logic        clk,
    input  wire  logic        rst,

    // instruction bus (read only)
    output logic              imem_req,
    output logic [31:0]       imem_addr,
    input  wire  logic        imem_rvalid,
    input  wire  logic [31:0] imem_rdata,

    // to execute
    output logic              if_valid,
    output logic [31:0]       if_instr,
    output logic [31:0]       if_pc,
    output logic [31:0]       if_next_pc,
    input  wire  logic        if_ready,

    // redirect from execute
    input  wire  logic        redirect,
    input  wire  logic [31:0] redirect_pc,

    // predictor update from execute
    input  wire  logic        upd_valid,
    input  wire  logic [31:0] upd_pc,
    input  wire  logic        upd_taken
);

    localparam logic [1:0] F_IDLE = 2'd0;
    localparam logic [1:0] F_REQ  = 2'd1;
    localparam logic [1:0] F_FULL = 2'd2;

    logic [1:0]  state;
    logic [31:0] pc_req;
    logic        drop;          // an in-flight fetch was invalidated

    logic        predict_taken;
    logic [31:0] predict_target;
    logic [31:0] next_pc_pred;

    tp_bpred #(
        .BIMODAL(BIMODAL), .NENT(NENT), .NIDX(NIDX)
    ) u_bpred (
        .clk           (clk),
        .rst           (rst),
        .instr         (imem_rdata),     // predict on the word as it lands
        .pc            (pc_req),
        .predict_taken (predict_taken),
        .predict_target(predict_target),
        .upd_valid     (upd_valid),
        .upd_pc        (upd_pc),
        .upd_taken     (upd_taken)
    );

    assign next_pc_pred = predict_taken ? predict_target : (pc_req + 32'd4);

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= F_IDLE;
            pc_req     <= RESET_PC;
            drop       <= 1'b0;
            if_valid   <= 1'b0;
            if_instr   <= 32'd0;
            if_pc      <= 32'd0;
            if_next_pc <= 32'd0;
        end else begin
            unique case (state)

                F_IDLE: begin
                    if (redirect) pc_req <= redirect_pc;
                    state <= F_REQ;
                end

                F_REQ: begin
                    if (redirect) begin
                        pc_req <= redirect_pc;
                        drop   <= 1'b1;           // discard the answer in flight
                    end
                    if (imem_rvalid) begin
                        if (drop || redirect) begin
                            drop  <= 1'b0;
                            state <= F_IDLE;      // re-issue at the new PC
                        end else begin
                            if_valid   <= 1'b1;
                            if_instr   <= imem_rdata;
                            if_pc      <= pc_req;
                            if_next_pc <= next_pc_pred;
                            pc_req     <= next_pc_pred;
                            state      <= F_FULL;
                        end
                    end
                end

                F_FULL: begin
                    if (redirect) begin
                        pc_req   <= redirect_pc;
                        if_valid <= 1'b0;
                        state    <= F_IDLE;
                    end else if (if_ready) begin
                        if_valid <= 1'b0;
                        state    <= F_IDLE;
                    end
                end

                default: state <= F_IDLE;
            endcase
        end
    end

    // The request is held for the whole F_REQ state; the bus answers with
    // a single-cycle rvalid.
    assign imem_req  = (state == F_REQ);
    assign imem_addr = pc_req;

endmodule : tp_fetch
