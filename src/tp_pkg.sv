// tp_pkg.sv — shared types and ISA constants for the TinyPulse-Skywater130 core.
// One package, imported everywhere. ISA constants live here only.
`default_nettype none

package tp_pkg;

    // ---------------------------------------------------------------
    // RV32I base opcodes (inst[6:0])
    // ---------------------------------------------------------------
    localparam logic [6:0] OPC_LUI     = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC   = 7'b0010111;
    localparam logic [6:0] OPC_JAL     = 7'b1101111;
    localparam logic [6:0] OPC_JALR    = 7'b1100111;
    localparam logic [6:0] OPC_BRANCH  = 7'b1100011;
    localparam logic [6:0] OPC_LOAD    = 7'b0000011;
    localparam logic [6:0] OPC_STORE   = 7'b0100011;
    localparam logic [6:0] OPC_OPIMM   = 7'b0010011;
    localparam logic [6:0] OPC_OP      = 7'b0110011;
    localparam logic [6:0] OPC_FENCE   = 7'b0001111;
    localparam logic [6:0] OPC_SYSTEM  = 7'b1110011;
    // Xpulse time extension lives in the RISC-V custom-0 encoding space.
    localparam logic [6:0] OPC_CUSTOM0 = 7'b0001011;

    // ---------------------------------------------------------------
    // Xpulse funct3 map (opcode = OPC_CUSTOM0)
    // ---------------------------------------------------------------
    localparam logic [2:0] TF3_TIME  = 3'b000;  // TIME   rd
    localparam logic [2:0] TF3_POP   = 3'b001;  // TPOP   rd
    localparam logic [2:0] TF3_STAT  = 3'b010;  // TSTAT  rd
    localparam logic [2:0] TF3_WAIT  = 3'b011;  // TWAIT  rs1
    localparam logic [2:0] TF3_ARM   = 3'b100;  // TARM   rs1, rs2
    localparam logic [2:0] TF3_PULSE = 3'b101;  // TPULSE rs1
    localparam logic [2:0] TF3_MARK  = 3'b110;  // TMARK  rd, rs1
    localparam logic [2:0] TF3_CTL   = 3'b111;  // TADJ/TRATE/TCFG/TPW by funct7

    // Sub-ops carried in funct7 when funct3 == TF3_CTL
    localparam logic [6:0] TCTL_ADJ  = 7'd0;    // TADJ  rs1 — step the timebase
    localparam logic [6:0] TCTL_RATE = 7'd1;    // TRATE rs1 — fractional rate
    localparam logic [6:0] TCTL_CFG  = 7'd2;    // TCFG  rs1 — capture config
    localparam logic [6:0] TCTL_PW   = 7'd3;    // TPW   rs1 — trigger pulse width

    // ---------------------------------------------------------------
    // No datapath control encodings live here any more. The 32-bit core
    // needed a 37-bit control bundle passed from decode to execute; the
    // nibble core decodes straight from the instruction register as it
    // executes, so there is nothing to pack. Everything below is shared
    // with software: the memory map and the register offsets.
    // ---------------------------------------------------------------

    // ---------------------------------------------------------------
    // Sync unit register offsets (word index within 0x2000_0000)
    // ---------------------------------------------------------------
    localparam logic [3:0] SR_TIME  = 4'h0;  // R   current timebase
    localparam logic [3:0] SR_EVENT = 4'h1;  // R   pop one event (destructive)
    localparam logic [3:0] SR_STAT  = 4'h2;  // R   status
    localparam logic [3:0] SR_CFG   = 4'h3;  // W   capture enable + edge select
    localparam logic [3:0] SR_CMP0  = 4'h4;  // W   compare 0 deadline
    localparam logic [3:0] SR_CMP1  = 4'h5;  // W   compare 1 deadline
    // offset 6 is deliberately unmapped: the third compare channel is
    // reachable through TARM only. Widening the memory-mapped decode was
    // not worth the gates.
    localparam logic [3:0] SR_PW    = 4'h7;  // W   trigger pulse width
    localparam logic [3:0] SR_ADJ   = 4'h8;  // W   step the timebase (signed)
    localparam logic [3:0] SR_RATE  = 4'h9;  // W   fractional rate increment
    localparam logic [3:0] SR_PULSE = 4'hA;  // W   fire triggers now

    // ---------------------------------------------------------------
    // Address map (decoded on addr[31:28] in tp_bus)
    // ---------------------------------------------------------------
    localparam logic [3:0] DEV_FLASH = 4'h0;  // 0x0xxx_xxxx external QSPI flash
    localparam logic [3:0] DEV_PSRAM = 4'h1;  // 0x1xxx_xxxx external QSPI PSRAM
    localparam logic [3:0] DEV_SYNC  = 4'h2;  // 0x2xxx_xxxx sync unit registers
    localparam logic [3:0] DEV_PERIPH= 4'h3;  // 0x3xxx_xxxx GPIO and UART
    localparam logic [3:0] DEV_ROM   = 4'h4;  // 0x4xxx_xxxx boot ROM (UART bootloader)

endpackage : tp_pkg
