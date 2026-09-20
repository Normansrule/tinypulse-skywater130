// tp_alu.sv — single shared adder/subtractor ALU.
// ADD, SUB, SLT and SLTU all reuse one 33-bit adder. Shifts are deliberately
// NOT here: they live in tp_shifter, so this module's worst path is one
// 32-bit carry chain. That is what sets Fmax for the whole core.
`default_nettype none

import tp_pkg::*;

module tp_alu
(
    input  wire  logic [31:0] a,
    input  wire  logic [31:0] b,
    input  wire  logic [3:0]  op,
    output logic [31:0]       y
);

    logic        sub_mode;
    logic [32:0] addsub;      // bit 32 is carry-out, used by SLTU
    logic        slt_bit, sltu_bit;

    always_comb begin
        sub_mode = (op == ALU_SUB) || (op == ALU_SLT) || (op == ALU_SLTU);
        addsub   = {1'b0, a} + {1'b0, (sub_mode ? ~b : b)} + {32'd0, sub_mode};

        // signed less-than: if the signs differ, a's sign decides (overflow-safe)
        slt_bit  = (a[31] != b[31]) ? a[31] : addsub[31];
        // unsigned less-than: a borrow means the carry-out is 0
        sltu_bit = ~addsub[32];

        unique case (op)
            ALU_ADD:    y = addsub[31:0];
            ALU_SUB:    y = addsub[31:0];
            ALU_AND:    y = a & b;
            ALU_OR:     y = a | b;
            ALU_XOR:    y = a ^ b;
            ALU_SLT:    y = {31'd0, slt_bit};
            ALU_SLTU:   y = {31'd0, sltu_bit};
            ALU_COPY_B: y = b;
            ALU_COPY_A: y = a;
            default:    y = 32'd0;
        endcase
    end

endmodule : tp_alu
