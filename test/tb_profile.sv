// tb_profile.sv — run the full instruction set test against the 2x2 build
// profile instead of the default 1x2 one.
//
// This matters because BARREL=1 and BIMODAL=1 select generate branches that
// no other test in this repository executes. A parameter you never simulate
// is a parameter that does not work, and finding that out after choosing a
// bigger tile would be an expensive way to learn it.
//
// Instantiates tp_soc directly rather than the Tiny Tapeout wrapper,
// because the wrapper hard-codes the 1x2 parameters.
//
// Run with:  make profile
`default_nettype none
`timescale 1ns/1ps

module tb_profile;

    localparam int TIMEOUT   = 4000000;
    localparam int MAX_SLOTS = 128;

    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;

    integer errors = 0, checks = 0;

    reg  [7:0] cap_pin = 8'h00;
    wire [3:0] trig_pin;
    wire       evt_pending, evt_pulse, ovf_pin, halted, illegal, heartbeat;
    wire       sck, cs_flash_n, cs_ram_n;
    wire [3:0] sd_out, sd_oe;

    wire [3:0] flash_sd, psram_sd;
    wire [3:0] sd_in = sd_oe[0] ? sd_out
                     : (!cs_flash_n ? flash_sd
                        : (!cs_ram_n ? psram_sd : 4'hF));

    // ---- the 2x2 profile ----
    tp_soc #(
        .NREG(16), .AW(4), .RESET_PC(32'h0000_0000),
        .BARREL(1'b1),        // one-cycle log shifter
        .BIMODAL(1'b1),       // 16-entry bimodal predictor
        .HAS_CPU(1'b1),
        .NCH(8), .NCMP(4), .DEPTH(8), .PTRW(3), .FRACW(24), .FILTW(3)
    ) dut (
        .clk(clk), .rst(rst),
        .cap_pin(cap_pin), .trig_pin(trig_pin),
        .evt_pending(evt_pending), .evt_pulse(evt_pulse), .ovf_pin(ovf_pin),
        .halted(halted), .illegal(illegal), .heartbeat(heartbeat),
        .sck(sck), .cs_flash_n(cs_flash_n), .cs_ram_n(cs_ram_n),
        .sd_out(sd_out), .sd_oe(sd_oe), .sd_in(sd_in)
    );

    qspi_flash_model #(.DUMMY(4), .WORDS(512)) u_flash (
        .cs_n(cs_flash_n), .sck(sck), .ctrl_sd(sd_out), .dev_sd(flash_sd));
    qspi_psram_model #(.DUMMY(6), .BYTES(4096)) u_psram (
        .cs_n(cs_ram_n), .sck(sck), .ctrl_sd(sd_out), .dev_sd(psram_sd));

    integer     exp_slot  [0:MAX_SLOTS-1];
    reg [31:0]  exp_value [0:MAX_SLOTS-1];
    reg [8*48:1] exp_label [0:MAX_SLOTS-1];
    integer     n_exp, fd, code, i, cyc, slot_i;
    reg [31:0]  val_i, got;
    reg [8*48:1] lbl_i;

    function [31:0] psram_word(input integer slot);
        psram_word = {u_psram.mem[slot*4+3], u_psram.mem[slot*4+2],
                      u_psram.mem[slot*4+1], u_psram.mem[slot*4+0]};
    endfunction

    initial begin
        $dumpfile("tb_profile.vcd");
        $dumpvars(0, tb_profile);
        #1 $readmemh("isa.hex", u_flash.mem);

        n_exp = 0;
        fd = $fopen("isa_expect.txt", "r");
        if (fd == 0) begin
            $display("run 'python3 ../sw/mkisa.py' first");
            $finish;
        end
        code = 1;
        while (code > 0 && n_exp < MAX_SLOTS) begin
            code = $fscanf(fd, "%d %h %s\n", slot_i, val_i, lbl_i);
            if (code == 3) begin
                exp_slot[n_exp]  = slot_i;
                exp_value[n_exp] = val_i;
                exp_label[n_exp] = lbl_i;
                n_exp = n_exp + 1;
            end
        end
        $fclose(fd);

        $display("\n=== TinyPulse-Skywater130 2x2 profile ===");
        $display("barrel shifter ON, bimodal predictor ON, queue depth 8, filter 3");

        repeat (20) @(posedge clk);
        rst = 1'b0;

        cyc = 0;
        while (!halted && cyc < TIMEOUT) begin
            @(posedge clk);
            cyc = cyc + 1;
        end
        $display("ran %0d clocks", cyc);

        checks = checks + 1;
        if (!halted) begin
            errors = errors + 1;
            $display("  FAIL  program never halted");
        end
        checks = checks + 1;
        if (illegal) begin
            errors = errors + 1;
            $display("  FAIL  illegal instruction decoded");
        end

        for (i = 0; i < n_exp; i = i + 1) begin
            got = psram_word(exp_slot[i]);
            checks = checks + 1;
            if (got !== exp_value[i]) begin
                errors = errors + 1;
                $display("  FAIL  slot %0d got %08x want %08x  %0s",
                         exp_slot[i], got, exp_value[i], exp_label[i]);
            end
        end

        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("2x2 PROFILE PASSED\n");
        else             $display("2x2 PROFILE FAILED\n");
        $finish;
    end

endmodule
