// tp_branch_comp.sv — branch comparator: eq / signed-lt / unsigned-lt.
// Kept separate from the ALU so a branch never has to wait on the ALU result
// mux. tp_branch_unit turns this bundle into taken/not-taken per funct3.
`default_nettype none

module tp_branch_comp
(
    input  wire logic [31:0] rs1,
    input  wire logic [31:0] rs2,
    output logic             ctp_eq,
    output logic             ctp_lt,    // signed
    output logic             ctp_ltu    // unsigned
);

    always_comb begin
        ctp_eq  = (rs1 == rs2);
        ctp_lt  = ($signed(rs1) < $signed(rs2));
        ctp_ltu = (rs1 < rs2);
    end

endmodule : tp_branch_comp
