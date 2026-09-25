// tp_decode.sv — instruction word -> ctrl_t control bundle.
// Pure combinational. Covers all 40 RV32I instructions plus the 10-instruction
// Xpulse time extension in the custom-0 opcode space. Illegal encodings set
// d_legal low; the core reports that in the status word rather than
// trapping, because a trap handler costs CSRs and CSRs cost a tile.
`default_nettype none

module tp_decode
(
    input  wire logic [31:0] instr,
    output logic [tp_pkg::CTRL_W-1:0] ctrl
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
        d_wb_sel    = tp_pkg::WB_ALU;
        d_alu_op    = tp_pkg::ALU_ADD;
        d_shift_op  = tp_pkg::SH_NONE;
        d_imm_sel   = tp_pkg::IMM_NONE;
        d_funct3    = funct3;
        d_time_op   = funct3;
        d_time_sub  = funct7;

        unique case (opcode)

            // ---- U-type -------------------------------------------------
            tp_pkg::OPC_LUI: begin
                d_legal     = 1'b1;
                d_rf_we     = 1'b1;
                d_alu_op    = tp_pkg::ALU_COPY_B;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_U;
            end

            tp_pkg::OPC_AUIPC: begin
                d_legal     = 1'b1;
                d_rf_we     = 1'b1;
                d_alu_op    = tp_pkg::ALU_ADD;
                d_alu_a_pc  = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_U;
            end

            // ---- jumps --------------------------------------------------
            // The ALU computes every jump and branch target, so there is no
            // second adder: A = PC (or rs1 for JALR), B = immediate. The link
            // value PC+4 comes from a dedicated incrementer in the core.
            tp_pkg::OPC_JAL: begin
                d_legal     = 1'b1;
                d_rf_we     = 1'b1;
                d_wb_sel    = tp_pkg::WB_PC4;
                d_is_jal    = 1'b1;
                d_alu_op    = tp_pkg::ALU_ADD;
                d_alu_a_pc  = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_J;
            end

            tp_pkg::OPC_JALR: begin
                d_legal     = (funct3 == 3'b000);
                d_rf_we     = 1'b1;
                d_wb_sel    = tp_pkg::WB_PC4;
                d_is_jalr   = 1'b1;
                d_alu_op    = tp_pkg::ALU_ADD;
                d_alu_a_pc  = 1'b0;          // A = rs1
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_I;
            end

            // ---- branches -----------------------------------------------
            tp_pkg::OPC_BRANCH: begin
                d_legal     = (funct3 != 3'b010) && (funct3 != 3'b011);
                d_is_branch = 1'b1;
                d_alu_op    = tp_pkg::ALU_ADD;
                d_alu_a_pc  = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_B;
            end

            // ---- loads --------------------------------------------------
            tp_pkg::OPC_LOAD: begin
                d_legal     = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b010) || (funct3 == 3'b100) ||
                                 (funct3 == 3'b101);
                d_rf_we     = 1'b1;
                d_wb_sel    = tp_pkg::WB_MEM;
                d_mem_read  = 1'b1;
                d_alu_op    = tp_pkg::ALU_ADD;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_I;
            end

            // ---- stores -------------------------------------------------
            tp_pkg::OPC_STORE: begin
                d_legal     = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b010);
                d_mem_write = 1'b1;
                d_alu_op    = tp_pkg::ALU_ADD;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_S;
            end

            // ---- register-immediate -------------------------------------
            tp_pkg::OPC_OPIMM: begin
                d_rf_we     = 1'b1;
                d_alu_b_imm = 1'b1;
                d_imm_sel   = tp_pkg::IMM_I;
                d_legal     = 1'b1;
                unique case (funct3)
                    3'b000: d_alu_op = tp_pkg::ALU_ADD;    // ADDI
                    3'b010: d_alu_op = tp_pkg::ALU_SLT;    // SLTI
                    3'b011: d_alu_op = tp_pkg::ALU_SLTU;   // SLTIU
                    3'b100: d_alu_op = tp_pkg::ALU_XOR;    // XORI
                    3'b110: d_alu_op = tp_pkg::ALU_OR;     // ORI
                    3'b111: d_alu_op = tp_pkg::ALU_AND;    // ANDI
                    3'b001: begin                     // SLLI
                        d_shift_op = tp_pkg::SH_SLL;
                        d_wb_sel   = tp_pkg::WB_SHIFT;
                        d_legal    = (funct7 == 7'b0000000);
                    end
                    3'b101: begin                     // SRLI / SRAI
                        d_shift_op = (funct7[5]) ? tp_pkg::SH_SRA : tp_pkg::SH_SRL;
                        d_wb_sel   = tp_pkg::WB_SHIFT;
                        d_legal    = (funct7 == 7'b0000000) ||
                                        (funct7 == 7'b0100000);
                    end
                    default: d_legal = 1'b0;
                endcase
            end

            // ---- register-register --------------------------------------
            tp_pkg::OPC_OP: begin
                d_rf_we = 1'b1;
                d_legal = (funct7 == 7'b0000000) ||
                             ((funct7 == 7'b0100000) &&
                              ((funct3 == 3'b000) || (funct3 == 3'b101)));
                unique case (funct3)
                    3'b000: d_alu_op = funct7[5] ? tp_pkg::ALU_SUB : tp_pkg::ALU_ADD;
                    3'b010: d_alu_op = tp_pkg::ALU_SLT;
                    3'b011: d_alu_op = tp_pkg::ALU_SLTU;
                    3'b100: d_alu_op = tp_pkg::ALU_XOR;
                    3'b110: d_alu_op = tp_pkg::ALU_OR;
                    3'b111: d_alu_op = tp_pkg::ALU_AND;
                    3'b001: begin
                        d_shift_op = tp_pkg::SH_SLL;
                        d_wb_sel   = tp_pkg::WB_SHIFT;
                    end
                    3'b101: begin
                        d_shift_op = funct7[5] ? tp_pkg::SH_SRA : tp_pkg::SH_SRL;
                        d_wb_sel   = tp_pkg::WB_SHIFT;
                    end
                    default: d_legal = 1'b0;
                endcase
            end

            // ---- FENCE / FENCE.I: architecturally a NOP here -------------
            tp_pkg::OPC_FENCE: begin
                d_legal    = 1'b1;
                d_is_fence = 1'b1;
            end

            // ---- ECALL / EBREAK: halt. No CSRs in this build. ------------
            tp_pkg::OPC_SYSTEM: begin
                d_legal     = (funct3 == 3'b000);
                d_is_system = 1'b1;
            end

            // ---- Xpulse time extension ---------------------------------
            tp_pkg::OPC_CUSTOM0: begin
                d_legal   = 1'b1;
                d_is_time = 1'b1;
                d_wb_sel  = tp_pkg::WB_TIME;
                unique case (funct3)
                    tp_pkg::TF3_TIME, tp_pkg::TF3_POP, tp_pkg::TF3_STAT, tp_pkg::TF3_MARK:
                        d_rf_we = 1'b1;           // these produce a result
                    tp_pkg::TF3_WAIT, tp_pkg::TF3_ARM, tp_pkg::TF3_PULSE:
                        d_rf_we = 1'b0;
                    tp_pkg::TF3_CTL:
                        d_legal = (funct7 == tp_pkg::TCTL_ADJ)  ||
                                     (funct7 == tp_pkg::TCTL_RATE) ||
                                     (funct7 == tp_pkg::TCTL_CFG)  ||
                                     (funct7 == tp_pkg::TCTL_PW);
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
