// tp_branch_unit.sv — funct3 + comparator bundle -> taken.
// Pure combinational decode of BEQ/BNE/BLT/BGE/BLTU/BGEU. Split from the
// comparator so the comparison itself starts the moment the operands are
// read, without waiting on instruction decode.
`default_nettype none

import tp_pkg::*;

module tp_branch_unit
(
    input  wire logic [2:0] funct3,
    input  wire logic       ctp_eq,
    input  wire logic       ctp_lt,
    input  wire logic       ctp_ltu,
    output logic            taken
);

    always_comb begin
        unique case (funct3)
            3'b000:  taken =  ctp_eq;    // BEQ
            3'b001:  taken = ~ctp_eq;    // BNE
            3'b100:  taken =  ctp_lt;    // BLT
            3'b101:  taken = ~ctp_lt;    // BGE
            3'b110:  taken =  ctp_ltu;   // BLTU
            3'b111:  taken = ~ctp_ltu;   // BGEU
            default: taken = 1'b0;       // 010/011 are reserved
        endcase
    end

endmodule : tp_branch_unit
