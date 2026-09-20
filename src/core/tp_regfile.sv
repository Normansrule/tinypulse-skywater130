// tp_regfile.sv — NREG x 32-bit, 2 read ports, 1 write port, x0 = 0.
//
// NREG=16 is RV32E, which is what the 1x2 tile build uses: 512 flip-flops,
// about 10,000 um^2 in sky130, roughly half the cell area of a 1x2 tile.
// This is the single largest block in the design; shrink it first if the
// harden run runs out of room.
//
// Synchronous write, combinational read, and deliberately NO write-through
// bypass. This is the opposite of what most register files do, and the reason
// is the pipeline shape.
//
// In TinyPulse all register reads and the register write belong to the SAME
// instruction in the SAME cycle. A bypass would therefore feed an
// instruction its own result as its own operand: for `addi x1, x1, 1` the
// read of x1 would return the value being written, which is computed from
// the read of x1. That is a combinational loop in silicon and an unstable
// one in simulation, and it is also simply the wrong answer — the
// instruction must see the OLD x1.
//
// Because no two instructions are ever in the read stage and the write stage
// at the same time, there is no read-after-write hazard to bypass in the
// first place. Verilator flags the bypassed version as UNOPTFLAT; if you are
// ever tempted to add it back, run the lint first.
`default_nettype none

module tp_regfile #(
    parameter int NREG = 16,
    parameter int AW   = 4        // $clog2(NREG)
) (
    input  wire  logic          clk,
    input  wire  logic          we,
    input  wire  logic [AW-1:0] waddr,
    input  wire  logic [31:0]   wdata,
    input  wire  logic [AW-1:0] raddr1,
    input  wire  logic [AW-1:0] raddr2,
    output logic [31:0]         rdata1,
    output logic [31:0]         rdata2
);

    logic [31:0] regs [NREG-1:0];

    always_ff @(posedge clk) begin
        if (we && (waddr != '0))
            regs[waddr] <= wdata;
    end

    always_comb begin
        rdata1 = (raddr1 == '0) ? 32'd0 : regs[raddr1];
        rdata2 = (raddr2 == '0) ? 32'd0 : regs[raddr2];
    end

endmodule : tp_regfile
