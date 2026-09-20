// tp_hazard.sv — stall and flush policy for the 2-stage pipeline.
//
// There is no forwarding unit in TinyPulse and that is deliberate, not an
// omission. The pipeline is F | DX: every register read, the ALU, and the
// register write all happen inside DX in the same cycle. Two instructions
// are never in the register-read and register-write stages at the same time,
// so a read-after-write hazard cannot exist. Removing forwarding removes two
// 32-bit muxes from the critical path and about 200 gate-equivalents.
//
// What is left is the control hazard (a taken branch or jump invalidates the
// prefetched instruction) and structural stalls (the shifter, the data bus,
// and TWAIT hold DX for more than one cycle). This module is the single
// place that policy lives.
`default_nettype none

module tp_hazard (
    input  wire logic if_valid,      // fetch buffer holds an instruction
    input  wire logic ex_ready,      // DX is in its accepting state
    input  wire logic shift_busy,
    input  wire logic mem_busy,
    input  wire logic wait_busy,
    input  wire logic halted,
    input  wire logic redirect,      // DX resolved a taken branch/jump
    output logic      if_ready,      // consume the fetch buffer this cycle
    output logic      if_flush,      // discard the prefetched instruction
    output logic      ex_stall       // DX cannot start a new instruction
);

    always_comb begin
        ex_stall = shift_busy || mem_busy || wait_busy || halted;
        if_ready = if_valid && ex_ready && !ex_stall;
        if_flush = redirect;
    end

endmodule : tp_hazard
