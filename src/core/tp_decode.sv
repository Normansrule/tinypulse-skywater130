// tp_decode.sv — instruction word -> ctrl_t control bundle.
// Pure combinational. Covers all 40 RV32I instructions plus the 10-instruction
// Xpulse time extension in the custom-0 opcode space. Illegal encodings set
// d_legal low; the core reports that in the status word rather than
// trapping, because a trap handler costs CSRs and CSRs cost a tile.
`default_nettype none

import tp_pkg::*;

module tp_decode
(
    input  wire logic [31:0] instr,
    output logic [CTRL_W-1:0] ctrl
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    // Control fields, packed into `ctrl` at the bottom of the file in the
    // order documented in tp_pkg.sv.
    logic       d_legal, d_rf_we;
    logic [2:0] d_wb_sel;
    logic [3:0] d_alu_op;
    logic [1:0] d_shift_op;
    logic       d_alu_a_pc, d_alu_b_imm;
    logic [2:0] d_imm_sel;
    logic       d_is_branch, d_is_jal, d_is_jalr;
    logic       d_mem_read, d_mem_write;
    logic [2:0] d_funct3;
    logic       d_is_time;
    logic [2:0] d_time_op;
    logic [6:0] d_time_sub;
    logic       d_is_fence, d_is_system;

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    always_comb begin
        // defaults: an illegal instruction that changes no state
        d_legal     = 1'b0;
        d_rf_we     = 1'b0;
        d_alu_a_pc  = 1'b0;
        d_alu_b_imm = 1'b0;
        d_is_branch = 1'b0;
        d_is_jal    = 1'b0;
        d_is_jalr   = 1'b0;
        d_mem_read  = 1'b0;
        d_mem_write = 1'b0;
        d_is_time   = 1'b0;
        d_is_fence  = 1'b0;
        d_is_system = 1'b0;
        d_wb_sel    = WB_ALU;
        d_alu_op    = ALU_ADD;
        d_shift_op  = SH_NONE;
        d_imm_sel   = IMM_NONE;
        d_funct3    = funct3;
        d_time_op   = funct3;
        d_time_sub  = funct7;

        unique case (opcode)

            // ---- U-type -------------------------------------------------
            OPC_LUI: begin
                d_legal     = 1'b1;
                d_rf_we     = 1'b1;
                d_alu_op    = ALU_COPY_B;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_U;
            end

            OPC_AUIPC: begin
                d_legal     = 1'b1;
                d_rf_we     = 1'b1;
                d_alu_op    = ALU_ADD;
                d_alu_a_pc  = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_U;
            end

            // ---- jumps --------------------------------------------------
            // The ALU computes every jump and branch target, so there is no
            // second adder: A = PC (or rs1 for JALR), B = immediate. The link
            // value PC+4 comes from a dedicated incrementer in the core.
            OPC_JAL: begin
                d_legal     = 1'b1;
                d_rf_we     = 1'b1;
                d_wb_sel    = WB_PC4;
                d_is_jal    = 1'b1;
                d_alu_op    = ALU_ADD;
                d_alu_a_pc  = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_J;
            end

            OPC_JALR: begin
                d_legal     = (funct3 == 3'b000);
                d_rf_we     = 1'b1;
                d_wb_sel    = WB_PC4;
                d_is_jalr   = 1'b1;
                d_alu_op    = ALU_ADD;
                d_alu_a_pc  = 1'b0;          // A = rs1
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_I;
            end

            // ---- branches -----------------------------------------------
            OPC_BRANCH: begin
                d_legal     = (funct3 != 3'b010) && (funct3 != 3'b011);
                d_is_branch = 1'b1;
                d_alu_op    = ALU_ADD;
                d_alu_a_pc  = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_B;
            end

            // ---- loads --------------------------------------------------
            OPC_LOAD: begin
                d_legal     = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b010) || (funct3 == 3'b100) ||
                                 (funct3 == 3'b101);
                d_rf_we     = 1'b1;
                d_wb_sel    = WB_MEM;
                d_mem_read  = 1'b1;
                d_alu_op    = ALU_ADD;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_I;
            end

            // ---- stores -------------------------------------------------
            OPC_STORE: begin
                d_legal     = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b010);
                d_mem_write = 1'b1;
                d_alu_op    = ALU_ADD;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_S;
            end

            // ---- register-immediate -------------------------------------
            OPC_OPIMM: begin
                d_rf_we     = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = IMM_I;
                d_legal     = 1'b1;
                unique case (funct3)
                    3'b000: d_alu_op = ALU_ADD;    // ADDI
                    3'b010: d_alu_op = ALU_SLT;    // SLTI
                    3'b011: d_alu_op = ALU_SLTU;   // SLTIU
                    3'b100: d_alu_op = ALU_XOR;    // XORI
                    3'b110: d_alu_op = ALU_OR;     // ORI
                    3'b111: d_alu_op = ALU_AND;    // ANDI
                    3'b001: begin                     // SLLI
                        d_shift_op = SH_SLL;
                        d_wb_sel   = WB_SHIFT;
                        d_legal    = (funct7 == 7'b0000000);
                    end
                    3'b101: begin                     // SRLI / SRAI
                        d_shift_op = (funct7[5]) ? SH_SRA : SH_SRL;
                        d_wb_sel   = WB_SHIFT;
                        d_legal    = (funct7 == 7'b0000000) ||
                                        (funct7 == 7'b0100000);
                    end
                    default: d_legal = 1'b0;
                endcase
            end

            // ---- register-register --------------------------------------
            OPC_OP: begin
                d_rf_we = 1'b1;
                d_legal = (funct7 == 7'b0000000) ||
                             ((funct7 == 7'b0100000) &&
                              ((funct3 == 3'b000) || (funct3 == 3'b101)));
                unique case (funct3)
                    3'b000: d_alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b010: d_alu_op = ALU_SLT;
                    3'b011: d_alu_op = ALU_SLTU;
                    3'b100: d_alu_op = ALU_XOR;
                    3'b110: d_alu_op = ALU_OR;
                    3'b111: d_alu_op = ALU_AND;
                    3'b001: begin
                        d_shift_op = SH_SLL;
                        d_wb_sel   = WB_SHIFT;
                    end
                    3'b101: begin
                        d_shift_op = funct7[5] ? SH_SRA : SH_SRL;
                        d_wb_sel   = WB_SHIFT;
                    end
                    default: d_legal = 1'b0;
                endcase
            end

            // ---- FENCE / FENCE.I: architecturally a NOP here -------------
            OPC_FENCE: begin
                d_legal    = 1'b1;
                d_is_fence = 1'b1;
            end

            // ---- ECALL / EBREAK: halt. No CSRs in this build. ------------
            OPC_SYSTEM: begin
                d_legal     = (funct3 == 3'b000);
                d_is_system = 1'b1;
            end

            // ---- Xpulse time extension ---------------------------------
            OPC_CUSTOM0: begin
                d_legal   = 1'b1;
                d_is_time = 1'b1;
                d_wb_sel  = WB_TIME;
                unique case (funct3)
                    TF3_TIME, TF3_POP, TF3_STAT, TF3_MARK:
                        d_rf_we = 1'b1;           // these produce a result
                    TF3_WAIT, TF3_ARM, TF3_PULSE:
                        d_rf_we = 1'b0;
                    TF3_CTL:
                        d_legal = (funct7 == TCTL_ADJ)  ||
                                     (funct7 == TCTL_RATE) ||
                                     (funct7 == TCTL_CFG)  ||
                                     (funct7 == TCTL_PW);
                    default: d_legal = 1'b0;
                endcase
            end

            default: d_legal = 1'b0;
        endcase
    end

    // Pack. The order here is the order tp_core unpacks in, and the
    // order the table in tp_pkg.sv documents.
    assign ctrl = {d_legal, d_rf_we, d_wb_sel, d_alu_op, d_shift_op,
                   d_alu_a_pc, d_alu_b_imm, d_imm_sel, d_is_branch,
                   d_is_jal, d_is_jalr, d_mem_read, d_mem_write, d_funct3,
                   d_is_time, d_time_op, d_time_sub, d_is_fence,
                   d_is_system};

    // Register specifiers and the destination field are read by the core,
    // not by the decoder.
    wire _unused = &{1'b0, instr[24:15], instr[11:7], 1'b0};

endmodule : tp_decode
