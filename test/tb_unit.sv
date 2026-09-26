// tb_unit.sv — self-checking unit tests for each block on its own.
//
// The program-level tests (tb_isa, tb_soc, tb_xpulse, ...) prove the parts
// work together by running real RISC-V code. This proves each part is right
// in isolation, including cases a program is unlikely to hit: a queue
// overflow, a timebase rate trim, a glitch on the serial line, a register
// written in the same clock it is read.
//
// Run with:  iverilog -g2012 -o tb_unit.vvp -s tb_unit <sources> && vvp tb_unit.vvp
`default_nettype none
`timescale 1ns/1ps

module tb_unit;
    import tp_pkg::*;

    integer errors = 0;
    integer checks = 0;

    task chk(input cond, input string name);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  FAIL  %0s", name);
            end
        end
    endtask

    task section(input string name);
        $display("\n[%0s]", name);
    endtask

    reg clk = 1'b0;
    always #5 clk = ~clk;


    // =================================================================
    // Timebase
    // =================================================================
    reg         tb_rst = 1'b1, tb_rate_we = 1'b0, tb_adj_we = 1'b0;
    reg  [31:0] tb_rate = 32'd0, tb_adj = 32'd0;
    wire [31:0] tb_now;

    sync_timebase #(.FRACW(24)) u_tb (
        .clk(clk), .rst(tb_rst),
        .rate_we(tb_rate_we), .rate_in(tb_rate),
        .adj_we(tb_adj_we), .adj_in(tb_adj), .now(tb_now)
    );

    // =================================================================
    // Event queue
    // =================================================================
    reg         fq_rst = 1'b1, fq_push = 1'b0, fq_pop = 1'b0;
    reg  [31:0] fq_wdata = 32'd0;
    wire [31:0] fq_rdata;
    wire        fq_empty, fq_full, fq_ovf;
    wire [1:0]  fq_count;

    sync_event_fifo #(.DEPTH(2), .PTRW(1)) u_fq (
        .clk(clk), .rst(fq_rst), .push(fq_push), .wdata(fq_wdata),
        .pop(fq_pop), .rdata(fq_rdata), .empty(fq_empty), .full(fq_full),
        .count(fq_count), .overflow(fq_ovf)
    );

    // =================================================================
    // Capture lane
    // =================================================================
    reg        cp_rst = 1'b1;
    reg  [7:0] cp_pin = 8'h00;
    wire [7:0] cp_evt, cp_rise, cp_level;

    sync_capture #(.NCH(8), .FILTW(0)) u_cp (
        .clk(clk), .rst(cp_rst), .pin(cp_pin),
        .en(8'hFF), .fall(8'h00), .both(1'b0),
        .evt(cp_evt), .evt_rise(cp_rise), .level(cp_level)
    );


    // =================================================================
    // Nibble register file. The testbench keeps its own phase counter,
    // exactly as the core does.
    // =================================================================
    reg  [2:0] rf_phase = 3'd0;
    reg  [3:0] rf_ra = 4'd0, rf_rb = 4'd0, rf_wa = 4'd0, rf_wd = 4'd0;
    reg        rf_we = 1'b0;
    wire [3:0] rf_qa, rf_qb;
    always @(posedge clk) rf_phase <= rf_phase + 3'd1;

    tp_nregfile u_nrf (
        .clk(clk), .ra(rf_ra), .rb(rf_rb), .qa(rf_qa), .qb(rf_qb),
        .we(rf_we), .wa(rf_wa), .wd(rf_wd)
    );

    task rf_sync;                         // wait for a negedge at phase 0
        begin
            @(negedge clk);
            while (rf_phase != 3'd0) @(negedge clk);
        end
    endtask

    task rf_write(input [3:0] r, input [31:0] v);
        integer k;
        begin
            rf_sync;
            for (k = 0; k < 8; k = k + 1) begin
                rf_we = 1'b1; rf_wa = r; rf_wd = v[4*k +: 4];
                @(negedge clk);
            end
            rf_we = 1'b0;
        end
    endtask

    task rf_read(input [3:0] ra, input [3:0] rb,
                 output [31:0] va, output [31:0] vb);
        integer k;
        begin
            rf_sync;
            for (k = 0; k < 8; k = k + 1) begin
                rf_ra = ra; rf_rb = rb; #1;
                va[4*k +: 4] = rf_qa;
                vb[4*k +: 4] = rf_qb;
                @(negedge clk);
            end
        end
    endtask

    // =================================================================
    // UART, looped back on itself at a short divider
    // =================================================================
    reg         ua_rst = 1'b1, ua_start = 1'b0, ua_ack = 1'b0;
    reg  [7:0]  ua_txd = 8'h00;
    reg  [11:0] ua_div = 12'd8;
    reg         ua_force_low = 1'b0;          // inject a glitch on the line
    wire        ua_tx, ua_busy, ua_valid, ua_ovr;
    wire [7:0]  ua_rxd;
    wire        ua_line = ua_tx && !ua_force_low;

    tp_uart u_ua (
        .clk(clk), .rst(ua_rst), .div(ua_div),
        .tx_start(ua_start), .tx_data(ua_txd), .tx_busy(ua_busy), .tx(ua_tx),
        .rx(ua_line), .rx_ack(ua_ack),
        .rx_data(ua_rxd), .rx_valid(ua_valid), .rx_overrun(ua_ovr)
    );

    task ua_send(input [7:0] b);
        begin
            @(negedge clk); ua_txd = b; ua_start = 1'b1;
            @(negedge clk); ua_start = 1'b0;
            while (ua_busy) @(negedge clk);
            repeat (2 * 8) @(negedge clk);    // let the receiver finish the stop bit
        end
    endtask

    task ua_take;
        begin
            @(negedge clk); ua_ack = 1'b1;
            @(negedge clk); ua_ack = 1'b0;
        end
    endtask

    // =================================================================
    // GPIO / UART register block
    // =================================================================
    reg         pr_rst = 1'b1, pr_req = 1'b0, pr_we = 1'b0;
    reg  [3:0]  pr_addr = 4'd0;
    reg  [31:0] pr_wdata = 32'd0;
    reg  [7:0]  pr_gin = 8'h00;
    wire [31:0] pr_rdata;
    wire [7:0]  pr_gout, pr_gsel;
    wire        pr_tx;

    tp_periph u_pr (
        .clk(clk), .rst(pr_rst), .req(pr_req), .addr(pr_addr), .we(pr_we),
        .wdata(pr_wdata), .rdata(pr_rdata), .gpio_in(pr_gin),
        .gpio_out(pr_gout), .gpio_sel(pr_gsel),
        .uart_tx(pr_tx), .uart_rx(pr_tx)     // looped back
    );

    task pr_wr(input [3:0] a, input [31:0] d);
        begin
            @(negedge clk); pr_req = 1'b1; pr_we = 1'b1; pr_addr = a; pr_wdata = d;
            @(negedge clk); pr_req = 1'b0; pr_we = 1'b0;
        end
    endtask

    task pr_rd(input [3:0] a, output [31:0] d);
        begin
            @(negedge clk); pr_req = 1'b1; pr_we = 1'b0; pr_addr = a; #1;
            d = pr_rdata;
            @(negedge clk); pr_req = 1'b0;
        end
    endtask

    integer i, latency;
    reg [31:0] t_mark;

    initial begin
        section("sync_timebase");
        @(negedge clk); tb_rst = 1'b0;
        @(negedge clk);
        t_mark = tb_now;
        repeat (100) @(negedge clk);
        chk((tb_now - t_mark) === 32'd100,
            "free running: exactly one tick per clock");

        // a step of +1000 applies in a single clock and loses no tick
        @(negedge clk);
        t_mark = tb_now;
        tb_adj = 32'd1000; tb_adj_we = 1'b1;
        @(negedge clk);
        tb_adj_we = 1'b0;
        chk((tb_now - t_mark) === 32'd1001, "TADJ steps by +1000 plus the tick");

        // rate trim: 2^23 means one extra tick every two clocks
        @(negedge clk);
        tb_rate = 32'h0080_0000; tb_rate_we = 1'b1;
        @(negedge clk);
        tb_rate_we = 1'b0;
        @(negedge clk);
        t_mark = tb_now;
        repeat (100) @(negedge clk);
        chk((tb_now - t_mark) === 32'd150,
            "rate +2^23 adds 50 extra ticks in 100 clocks");

        // -------------------------------------------------------------
        section("sync_event_fifo");
        @(negedge clk); fq_rst = 1'b0;
        chk(fq_empty === 1'b1, "empty after reset");
        @(negedge clk); fq_wdata = 32'hAAAA_0001; fq_push = 1'b1;
        @(negedge clk); fq_wdata = 32'hBBBB_0002;
        @(negedge clk); fq_push = 1'b0;
        #1;
        chk(fq_count === 2'd2, "two entries queued");
        chk(fq_full  === 1'b1, "queue reports full");
        chk(fq_rdata === 32'hAAAA_0001, "head is the oldest entry");
        chk(fq_ovf   === 1'b0, "no overflow yet");

        @(negedge clk); fq_wdata = 32'hCCCC_0003; fq_push = 1'b1;
        @(negedge clk); fq_push = 1'b0;
        #1;
        chk(fq_ovf === 1'b1, "pushing into a full queue sets overflow");

        @(negedge clk); fq_pop = 1'b1;
        @(negedge clk); fq_pop = 1'b0;
        #1;
        chk(fq_rdata === 32'hBBBB_0002, "pop advances to the next entry");
        @(negedge clk); fq_pop = 1'b1;
        @(negedge clk); fq_pop = 1'b0;
        #1;
        chk(fq_empty === 1'b1, "queue drains to empty");

        // -------------------------------------------------------------
        section("sync_capture");
        @(negedge clk); cp_rst = 1'b0;
        repeat (4) @(negedge clk);
        chk(cp_evt === 8'h00, "idle produces no events");

        latency = 0;
        @(negedge clk); cp_pin[3] = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            #1;
            if (cp_evt[3] && latency == 0) latency = i + 1;
        end
        // two flops of synchroniser, so the event appears on the second
        // clock after the pin moves — and always on the second, which is
        // the property that makes the timestamp calibratable.
        chk(latency == 2, "rising edge detected 2 clocks after the pin moves");
        if (latency != 2)
            $display("        latency was %0d clocks, expected 2", latency);

        @(negedge clk);
        chk(cp_level[3] === 1'b1, "filtered level follows the pin");
        chk(cp_evt === 8'h00, "the event is a one-clock pulse");

        // falling edge must not fire while `fall` is low
        @(negedge clk); cp_pin[3] = 1'b0;
        repeat (4) @(negedge clk);
        chk(cp_evt === 8'h00, "falling edge ignored when not selected");


        // -------------------------------------------------------------
        section("tp_nregfile (rotating, nibble-serial)");
        begin : rf_tests
            reg [31:0] vals [1:15];
            reg [31:0] ga, gb;
            integer i, bad;
            for (i = 1; i < 16; i = i + 1) vals[i] = 32'h9E37_79B9 * i ^ (i << 27);
            for (i = 1; i < 16; i = i + 1) rf_write(i[3:0], vals[i]);

            bad = 0;
            for (i = 1; i < 16; i = i + 1) begin
                rf_read(i[3:0], 4'd0, ga, gb);
                if (ga !== vals[i]) bad = bad + 1;
            end
            chk(bad == 0, "all 15 registers read back what was written");
            chk(gb === 32'd0, "x0 reads as zero");

            rf_write(4'd0, 32'hFFFF_FFFF);
            rf_read(4'd0, 4'd0, ga, gb);
            chk(ga === 32'd0, "a write to x0 is discarded");

            rf_read(4'd3, 4'd12, ga, gb);
            chk(ga === vals[3] && gb === vals[12], "both read ports work in the same pass");

            // Registers keep rotating while nobody touches them: wait an odd
            // number of clocks and read again.
            repeat (37) @(negedge clk);
            rf_read(4'd7, 4'd15, ga, gb);
            chk(ga === vals[7] && gb === vals[15],
                "values survive arbitrary idle time (rotation stays in phase)");

            // Read and write the same register in one pass, as ADD x5,x5,x5
            // does: each nibble must be read before it is overwritten.
            rf_sync;
            begin : same_reg
                integer k;
                reg [31:0] seen;
                for (k = 0; k < 8; k = k + 1) begin
                    rf_ra = 4'd5; #1; seen[4*k +: 4] = rf_qa;
                    rf_we = 1'b1; rf_wa = 4'd5; rf_wd = ~rf_qa;
                    @(negedge clk);
                end
                rf_we = 1'b0;
                chk(seen === vals[5], "read-during-write sees the old value");
            end
            rf_read(4'd5, 4'd0, ga, gb);
            chk(ga === ~vals[5], "and the new value is in place afterwards");
        end

        // -------------------------------------------------------------
        section("tp_uart");
        repeat (3) @(negedge clk); ua_rst = 1'b0;
        chk(ua_tx === 1'b1 && !ua_busy, "line idles high after reset");

        begin : ua_timing
            integer n;
            @(negedge clk); ua_txd = 8'hA5; ua_start = 1'b1;
            @(negedge clk); ua_start = 1'b0;
            n = 0;
            while (ua_tx === 1'b0) begin @(negedge clk); n = n + 1; end
            chk(n == 8, "start bit lasts exactly `div` clocks");
            while (ua_busy) @(negedge clk);
            repeat (16) @(negedge clk);
            chk(ua_valid && ua_rxd === 8'hA5, "loopback receives 0xA5");
            ua_take;
            chk(!ua_valid, "reading clears RX_VALID");
        end

        ua_send(8'h00);
        chk(ua_valid && ua_rxd === 8'h00, "all-zero byte (longest low run)");
        ua_take;
        ua_send(8'hFF);
        chk(ua_valid && ua_rxd === 8'hFF, "all-one byte");
        ua_take;

        ua_send(8'h3C);
        ua_send(8'hC3);
        chk(ua_ovr, "second byte before a read sets RX_OVERRUN");
        chk(ua_rxd === 8'hC3, "and the newer byte is kept");
        ua_take;
        chk(!ua_ovr && !ua_valid, "one read clears both flags");

        // A 2-clock dip on the line is not a start bit.
        @(negedge clk); ua_force_low = 1'b1;
        repeat (2) @(negedge clk); ua_force_low = 1'b0;
        repeat (12 * 8) @(negedge clk);
        chk(!ua_valid, "a short glitch is rejected, no phantom byte");

        ua_div = 12'd21;                      // an odd divider
        ua_send(8'h96);
        repeat (21 * 2) @(negedge clk);
        chk(ua_valid && ua_rxd === 8'h96, "works at a different, odd divider");
        ua_take;

        // -------------------------------------------------------------
        section("tp_periph (GPIO + UART registers)");
        begin : pr_tests
            reg [31:0] d;
            repeat (3) @(negedge clk); pr_rst = 1'b0;
            pr_rd(4'd2, d); chk(d === 32'hFF, "GPIO_SEL resets to 0xFF (all pins show functions)");
            pr_rd(4'd5, d); chk(d === 32'd434, "UART_DIV resets to 434 (115,200 baud at 50 MHz)");
            pr_rd(4'd0, d); chk(d === 32'd0,  "GPIO_OUT resets to zero");

            pr_wr(4'd0, 32'h0000_00A5);
            chk(pr_gout === 8'hA5, "GPIO_OUT drives the pins");
            pr_wr(4'd6, 32'h0000_0050);
            chk(pr_gout === 8'hF5, "GPIO_SET sets only the given bits");
            // clear a mask with bits both set (0x05) and already clear (0x0A):
            // a CLR that toggled instead would turn 0x0A back on
            pr_wr(4'd7, 32'h0000_000F);
            chk(pr_gout === 8'hF0, "GPIO_CLR clears only the given bits, never sets");
            pr_wr(4'd8, 32'h0000_0081);
            chk(pr_gout === 8'h71, "GPIO_XOR toggles only the given bits");
            pr_rd(4'd0, d); chk(d === 32'h71, "GPIO_OUT reads back");

            pr_gin = 8'h3C;
            pr_rd(4'd1, d); chk(d === 32'h3C, "GPIO_IN reads the input pins");

            pr_wr(4'd2, 32'h0000_0010);
            chk(pr_gsel === 8'h10, "GPIO_SEL writes");

            pr_wr(4'd5, 32'd9);                   // fast baud for the test
            pr_wr(4'd3, 32'h0000_005A);
            pr_rd(4'd4, d); chk(d[0] === 1'b1, "UART_STAT shows TX_BUSY after a write");
            repeat (12 * 9 + 20) @(negedge clk);
            pr_rd(4'd4, d); chk(d[1:0] === 2'b10, "byte looped back: RX_VALID, not busy");
            pr_rd(4'd3, d); chk(d === 32'h5A, "UART_DATA returns the received byte");
            pr_rd(4'd4, d); chk(d[1] === 1'b0, "and reading it cleared RX_VALID");
        end

        // -------------------------------------------------------------
        $display("\n%0d checks, %0d failures", checks, errors);
        if (errors == 0) $display("UNIT TESTS PASSED\n");
        else             $display("UNIT TESTS FAILED\n");
        $finish;
    end

endmodule
