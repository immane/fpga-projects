// Testbench for sdram_user_ctrl ROLLING FRAME BUFFER mode:
// pattern pixels (gated by wr_ready => lossless write) are written into a
// static frame region; after the first full frame is stored (fb_ready), a
// read pointer sweeps the same region and the read-back stream must match
// the (static) written pattern exactly.
//
// NOTE: pix_valid/pix_data are REGISTERED one cycle after wr_ready, exactly
// like the real pattern_gen (its `ve <= ready`), so the backpressure
// handshake (including the "last word fill" early-deassert) is exercised.
`timescale 1ns/1ps
module sdram_user_ctrl_tb;
    reg         clk      = 1'b0;
    reg         rst_n    = 1'b0;
    reg         rd_ready = 1'b1;   // FIFO never full in this TB

    wire        init_done, cmd_ack;
    wire [31:0] read_data;
    wire        fb_ready;

    wire [2:0]  user_cmd;
    wire        user_cmd_en;
    wire [20:0] user_addr;
    wire [31:0] user_data;
    wire [7:0]  user_len;
    wire [15:0] rd_pix;
    wire        rd_pix_valid;
    wire        wr_ready;
    wire        pix_valid;
    wire [15:0] pix_data;

    // Frame region: 1024 words = 2048 pixels (small for fast simulation)
    localparam integer FB_WORDS = 1024;
    localparam integer FB_PIX   = 2 * FB_WORDS;

    // UUT: rolling frame buffer (BURST_SIZE=16 for TB speed)
    sdram_user_ctrl #(
        .BURST_SIZE(16),
        .FB_WORDS  (FB_WORDS)
    ) uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .init_done   (init_done),
        .cmd_ack     (cmd_ack),
        .pix_valid   (pix_valid),
        .pix_data    (pix_data),
        .user_cmd    (user_cmd),
        .user_cmd_en (user_cmd_en),
        .user_addr   (user_addr),
        .user_data   (user_data),
        .user_len    (user_len),
        .read_data   (read_data),
        .rd_pix      (rd_pix),
        .rd_pix_valid(rd_pix_valid),
        .rd_ready    (rd_ready),
        .wr_ready    (wr_ready),
        .fb_ready    (fb_ready),
        .selftest_done   (),
        .selftest_err    (),
        .selftest_err_cnt()
    );

    // SDRAM HS controller behavioral model
    sdram_hs_model #(.CL(2),.WR(2),.RP(2),.RCD(2)) model (
        .clk      (clk),
        .rst_n    (rst_n),
        .cmd_en   (user_cmd_en),
        .cmd      (user_cmd),
        .addr     (user_addr),
        .data     (user_data),
        .data_len (user_len),
        .o_data   (read_data),
        .cmd_ack  (cmd_ack),
        .init_done(init_done)
    );

    always #3 clk = ~clk;

    // Static pattern source modeled like pattern_gen: pix_valid/pix_data are
    // registered one cycle after wr_ready; the value = position (wraps every
    // frame, so the value at any frame address is constant across frames).
    reg [15:0] px = 16'd0;
    reg        pix_valid_q = 1'b0;
    reg [15:0] pix_data_q  = 16'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px          <= 16'd0;
            pix_valid_q <= 1'b0;
            pix_data_q  <= 16'd0;
        end else begin
            pix_valid_q <= wr_ready;
            if (wr_ready) begin
                pix_data_q <= px;                 // static: value = position
                px         <= (px == FB_PIX - 1) ? 16'd0 : px + 16'd1;
            end
        end
    end
    assign pix_valid = pix_valid_q;
    assign pix_data  = pix_data_q;

    // Reference: expected read-back pixel = position (mod frame) since the
    // pattern is static; the read pointer sweeps 0..FB_PIX-1 in order.
    integer rd_count = 0;
    integer err      = 0;
    always @(posedge clk) begin
        if (rd_pix_valid) begin
            if (rd_pix !== (rd_count % FB_PIX)) begin
                err = err + 1;
                if (err < 8)
                    $display("MISMATCH t=%0t out=%h exp=%h r_addr=%h rd_out=%0d rd_wptr=%0d",
                             $time, rd_pix, rd_count % FB_PIX,
                             uut.r_addr, uut.rd_out_ptr, uut.rd_wptr);
            end
            rd_count = rd_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (80000) @(posedge clk);

        $display("RESULT: fb_ready=%0d written=%0d readback=%0d mismatches=%0d",
                 fb_ready, (fb_ready ? FB_WORDS*2 : 0), rd_count, err);
        if (err == 0 && fb_ready && rd_count > (3 * FB_PIX))
            $display("PASS: frame-buffer read-back matches static pattern (%0d px read)", rd_count);
        else
            $display("FAIL");
        $finish;
    end
endmodule
