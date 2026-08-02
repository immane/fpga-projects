`timescale 1ns/1ps
// Two-phase async_fifo check after the registered-pointer full change:
// Phase 1: fill to capacity (r_en=0) -> verify full asserts and writes stop
// at exactly the capacity (no overflow).
// Phase 2: drain, sampling r_data one cycle after r_en (registered BRAM read),
// and verify the popped sequence matches what was written.
module async_fifo_tb;

    localparam AW = 4;          // 16 entries
    localparam CAP = 16;

    reg w_clk;
    reg w_rst_n;
    reg w_en;
    reg [15:0] w_data;
    wire full;
    reg r_clk;
    reg r_rst_n;
    reg r_en;
    wire [15:0] r_data;
    wire empty;

    reg [9:0] pushed;
    reg [9:0] popped;
    reg [15:0] exp_val;
    reg [1:0] phase;
    integer err;

    async_fifo #(.ADDRESS_WIDTH(AW), .DATA_WIDTH(16)) uut (
        .w_clk(w_clk), .w_rst_n(w_rst_n), .w_en(w_en), .w_data(w_data),
        .full(full), .almost_full(),
        .r_clk(r_clk), .r_rst_n(r_rst_n), .r_en(r_en), .r_data(r_data),
        .empty(empty), .almost_empty()
    );

    initial begin
        w_clk = 0;
        forever #5 w_clk = ~w_clk;
    end
    initial begin
        r_clk = 0;
        forever #7 r_clk = ~r_clk;
    end

    // write side
    always @(posedge w_clk) begin
        if (!w_rst_n) begin
            w_en <= 0;
            w_data <= 0;
        end else if (phase == 1 && pushed < CAP) begin
            w_en <= 1'b1;
            w_data <= pushed;
            pushed <= pushed + 1'b1;
        end else begin
            w_en <= 1'b0;
        end
    end

    // read side: r_data is the registered BRAM output (valid 1 cycle after r_en)
    reg r_en_q;
    always @(posedge r_clk) begin
        if (!r_rst_n) r_en_q <= 0;
        else r_en_q <= r_en && !empty;
    end
    always @(posedge r_clk) begin
        if (phase == 2) begin
            r_en <= !empty;
            if (r_en_q) begin
                if (r_data !== exp_val) begin
                    err = err + 1;
                    if (err < 5) $display("MISMATCH popped=%0d got=%h exp=%h", popped, r_data, exp_val);
                end
                exp_val <= exp_val + 1'b1;
                popped <= popped + 1'b1;
            end
        end else begin
            r_en <= 0;
        end
    end

    initial begin
        w_rst_n = 0; r_rst_n = 0;
        w_en = 0; w_data = 0; r_en = 0;
        pushed = 0; popped = 0; exp_val = 0; err = 0; phase = 0;
        repeat (4) @(posedge w_clk);
        w_rst_n = 1; r_rst_n = 1;
        phase = 1;
        repeat (400) @(posedge w_clk);   // fill phase
        if (pushed != CAP || !full)
            $display("FILL FAIL: pushed=%0d full=%0b (expect %0d, full=1)", pushed, full, CAP);
        phase = 2;
        repeat (400) @(posedge w_clk);   // drain phase
        repeat (200) @(posedge r_clk);
        $display("async_fifo: pushed=%0d popped=%0d mismatches=%0d full=%0b",
                 pushed, popped, err, full);
        if (pushed == CAP && popped == CAP && err == 0)
            $display("PASS (async_fifo): fills to capacity, full asserts, order OK");
        else
            $display("FAIL (async_fifo)");
        $finish;
    end
endmodule
