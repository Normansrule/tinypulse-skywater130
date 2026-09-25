// tp_imm_gen.sv — sign-extended immediate for each RV32I format.
// Bit positions follow the RISC-V base spec exactly; the scrambled B and J
// layouts exist so every immediate bit comes from a fixed instruction bit.
`default_nettype none

module tp_imm_gen
(
    input  wire logic [31:0] instr,
    input  wire logic [2:0]  sel,
    output logic [31:0]      imm
);

    always_comb begin
        unique case (sel)
            // I-type: inst[31:20]
            tp_pkg::IMM_I: imm = {{20{instr[31]}}, instr[31:20]};
            // S-type: inst[31:25] | inst[11:7]
            tp_pkg::IMM_S: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            // B-type: inst[31] | inst[7] | inst[30:25] | inst[11:8] | 0
            tp_pkg::IMM_B: imm = {{19{instr[31]}}, instr[31], instr[7],
                          instr[30:25], instr[11:8], 1'b0};
            // U-type: inst[31:12] << 12
            tp_pkg::IMM_U: imm = {instr[31:12], 12'd0};
            // J-type: inst[31] | inst[19:12] | inst[20] | inst[30:21] | 0
            tp_pkg::IMM_J: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                          instr[20], instr[30:21], 1'b0};
            default: imm = 32'd0;
        endcase
    end

    // The opcode selects the format upstream; this module is told which.
    wire _unused = &{1'b0, instr[6:0], 1'b0};

endmodule : tp_imm_gen
