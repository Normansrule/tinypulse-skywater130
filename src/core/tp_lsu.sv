// tp_lsu.sv — load/store alignment, byte strobes and sign extension.
// Split from the core so the byte-lane muxing is testable on its own and so
// the core FSM only deals with "issue a word request, take a word back".
`default_nettype none

module tp_lsu (
    input  wire logic [2:0]  funct3,
    input  wire logic [1:0]  addr_lo,     // byte offset within the word
    // store path
    input  wire logic [31:0] store_data,  // rs2
    output logic [31:0]      mem_wdata,   // lane-replicated
    output logic [3:0]       mem_be,      // byte enables
    // load path
    input  wire logic [31:0] mem_rdata,   // raw word from the bus
    output logic [31:0]      load_data    // extended result
);

    logic [7:0]  byte_sel;
    logic [15:0] half_sel;

    always_comb begin
        // ---- store: replicate into the right lane ----
        unique case (funct3[1:0])
            2'b00: begin  // SB
                mem_wdata = {4{store_data[7:0]}};
                mem_be    = 4'b0001 << addr_lo;
            end
            2'b01: begin  // SH
                mem_wdata = {2{store_data[15:0]}};
                mem_be    = addr_lo[1] ? 4'b1100 : 4'b0011;
            end
            default: begin // SW
                mem_wdata = store_data;
                mem_be    = 4'b1111;
            end
        endcase

        // ---- load: select then extend ----
        unique case (addr_lo)
            2'b00:   byte_sel = mem_rdata[7:0];
            2'b01:   byte_sel = mem_rdata[15:8];
            2'b10:   byte_sel = mem_rdata[23:16];
            default: byte_sel = mem_rdata[31:24];
        endcase

        half_sel = addr_lo[1] ? mem_rdata[31:16] : mem_rdata[15:0];

        unique case (funct3)
            3'b000:  load_data = {{24{byte_sel[7]}},  byte_sel};   // LB
            3'b001:  load_data = {{16{half_sel[15]}}, half_sel};   // LH
            3'b010:  load_data = mem_rdata;                        // LW
            3'b100:  load_data = {24'd0, byte_sel};                // LBU
            3'b101:  load_data = {16'd0, half_sel};                // LHU
            default: load_data = mem_rdata;
        endcase
    end

endmodule : tp_lsu
