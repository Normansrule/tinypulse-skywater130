// tp_nregfile.sv — RV32E register file, read and written four bits at a time.
//
// This is the reason TinyPulse fits in a 2x2 tile. Measured against the
// real sky130_fd_sc_hd library:
//
//     two 32-bit read ports, conventional       21,837 um^2
//     one 32-bit read port                      18,155 um^2
//     this: two 4-bit read ports, rotating      11,322 um^2
//
// The flip-flops are the same 480 in every case (15 registers x 32 bits;
// x0 is not stored). What changes is the read multiplexers: a conventional
// port picks one of 16 registers for all 32 bits at once, which is 32 wide
// 16-to-1 multiplexers per port. Here each port only ever picks 4 bits.
//
// How: every register rotates right by one nibble on EVERY clock, all in
// lockstep, forever. A free-running 3-bit counter `phase` tracks where the
// rotation is. The invariant is
//
//     when phase == k, bits [3:0] of every register hold that register's
//     logical nibble k   (bits 4k+3 .. 4k)
//
// so the core reads nibble k of any register at phase k from the same four
// wires, and an operation that starts at phase 0 sees nibbles 0,1,...,7 —
// least significant first, which is exactly the order a carry chain wants.
//
// A write at phase k replaces the nibble that is leaving the bottom, so it
// lands in logical position k. Nothing is ever out of order, and there is
// no enable on the flip-flops at all: plain D flip-flops are the smallest
// storage cell in the library.
//
// No reset. RISC-V leaves registers undefined at reset and the compiler's
// start-up code initializes what it uses; resetting 480 flops would cost
// area for nothing.
`default_nettype none

module tp_nregfile (
    input  wire  logic       clk,
    input  wire  logic [3:0] ra,      // read port A: register number
    input  wire  logic [3:0] rb,      // read port B
    output logic       [3:0] qa,      // nibble `phase` of register ra
    output logic       [3:0] qb,
    input  wire  logic       we,      // write nibble `phase` of register wa
    input  wire  logic [3:0] wa,
    input  wire  logic [3:0] wd
);
    logic [31:0] r [1:15];

    always_ff @(posedge clk) begin
        for (int i = 1; i < 16; i++)
            r[i] <= {(we && wa == i[3:0]) ? wd : r[i][3:0], r[i][31:4]};
    end

    always_comb begin
        qa = 4'd0;
        qb = 4'd0;
        for (int i = 1; i < 16; i++) begin
            if (ra == i[3:0]) qa = r[i][3:0];
            if (rb == i[3:0]) qb = r[i][3:0];
        end
    end
endmodule : tp_nregfile
