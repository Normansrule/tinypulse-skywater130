// tp_bus.sv — address decode and arbitration between the two masters.
//
// Masters : instruction fetch (read only) and the load/store unit.
// Slaves  : the external QSPI controller (flash + PSRAM) and the sync unit
//           register file.
//
// Policy: the data port wins. Fetch is speculative and restartable, a load
// is not, and the core is already stalled waiting for it. Whoever starts a
// QSPI transaction owns the controller until it answers — `owner` holds the
// mux steady so a redirect changing the fetch PC mid-transaction cannot
// corrupt an address already on the wire.
//
// Sync unit accesses never touch the QSPI controller and complete in a
// single clock.
`default_nettype none

module tp_bus
(
    input  wire  logic        clk,
    input  wire  logic        rst,

    // instruction master
    input  wire  logic        imem_req,
    input  wire  logic [31:0] imem_addr,
    output logic              imem_rvalid,
    output logic [31:0]       imem_rdata,

    // data master
    input  wire  logic        dmem_req,
    input  wire  logic [31:0] dmem_addr,
    input  wire  logic        dmem_we,
    input  wire  logic [31:0] dmem_wdata,
    input  wire  logic [3:0]  dmem_be,
    output logic              dmem_rvalid,
    output logic [31:0]       dmem_rdata,

    // QSPI slave
    output logic              q_req,
    output logic [23:0]       q_addr,
    output logic              q_we,
    output logic [31:0]       q_wdata,
    output logic [3:0]        q_be,
    output logic              q_dev,        // 0 = flash, 1 = PSRAM
    input  wire  logic        q_rvalid,
    input  wire  logic [31:0] q_rdata,

    // sync unit slave
    output logic              reg_req,
    output logic [3:0]        reg_addr,
    output logic              reg_we,
    output logic [31:0]       reg_wdata,
    input  wire  logic [31:0] reg_rdata
);

    logic [3:0] d_dev, i_dev;
    assign d_dev = dmem_addr[31:28];
    assign i_dev = imem_addr[31:28];

    logic d_is_sync, d_is_ext, i_is_ext;
    assign d_is_sync = (d_dev == tp_pkg::DEV_SYNC);
    assign d_is_ext  = (d_dev == tp_pkg::DEV_FLASH) || (d_dev == tp_pkg::DEV_PSRAM);
    assign i_is_ext  = (i_dev == tp_pkg::DEV_FLASH) || (i_dev == tp_pkg::DEV_PSRAM);

    // ---- sync unit path: single cycle ----
    assign reg_req   = dmem_req && d_is_sync;
    assign reg_addr  = dmem_addr[5:2];
    assign reg_we    = dmem_we;
    assign reg_wdata = dmem_wdata;

    // ---- QSPI ownership ----
    logic busy, owner;                 // owner: 0 = fetch, 1 = data

    logic start_d, start_i;
    assign start_d = !busy && dmem_req && d_is_ext;
    assign start_i = !busy && !start_d && imem_req && i_is_ext;

    always_ff @(posedge clk) begin
        if (rst) begin
            busy  <= 1'b0;
            owner <= 1'b0;
        end else if (!busy) begin
            if (start_d) begin busy <= 1'b1; owner <= 1'b1; end
            else if (start_i) begin busy <= 1'b1; owner <= 1'b0; end
        end else if (q_rvalid) begin
            busy <= 1'b0;
        end
    end

    // While busy the mux follows `owner`; on the starting cycle it follows
    // the combinational grant, so the controller sees a stable request.
    logic use_data;
    assign use_data = busy ? owner : start_d;

    // Drop the request in the cycle the controller answers, otherwise it
    // sees req still high while it is back in its idle state and starts the
    // same transaction a second time.
    assign q_req   = (busy && !q_rvalid) || start_d || start_i;
    assign q_addr  = use_data ? dmem_addr[23:0] : imem_addr[23:0];
    assign q_we    = use_data ? dmem_we         : 1'b0;
    assign q_wdata = dmem_wdata;
    assign q_be    = use_data ? dmem_be         : 4'b1111;
    assign q_dev   = use_data ? (d_dev == tp_pkg::DEV_PSRAM) : (i_dev == tp_pkg::DEV_PSRAM);

    // ---- responses ----
    assign imem_rvalid = q_rvalid && !owner;
    assign imem_rdata  = q_rdata;

    assign dmem_rvalid = (dmem_req && d_is_sync) ||     // sync: same cycle
                         (q_rvalid && owner);
    assign dmem_rdata  = d_is_sync ? reg_rdata : q_rdata;

    // Only addr[31:28] (device) and addr[23:0] (offset) are decoded; the
    // gap in the middle is unmapped address space by design.
    wire _unused = &{1'b0, imem_addr[27:24], dmem_addr[27:24], 1'b0};

endmodule : tp_bus
