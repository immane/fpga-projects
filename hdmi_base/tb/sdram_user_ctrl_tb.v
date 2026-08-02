// Testbench for sdram_user_ctrl read-back-output mode (RD_OUT_EN=1):
// pattern pixels (gated by wr_ready => lossless write) are written to SDRAM,
// read back, and streamed out on rd_pix. Checks the output pixel sequence
// exactly matches the written pixel sequence.
`timescale 1ns/1ps
module sdram_user_ctrl_tb;
    reg         clk      = 1'b0;
    reg         rst_n    = 1'b0;
    reg         rd_ready = 1'b1;   // FIFO never full in this TB

    wire        init_done, cmd_ack;
    wire [31:0] read_data;

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

    // UUT: burst write + readback to FIFO
    sdram_user_ctrl #(
        .BURST_SIZE(16),
        .RD_OUT_EN (1)
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
        .wr_ready    (wr_ready)
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

    // pattern source: only advance a pixel when the write path accepts it
    reg [15:0] px = 16'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) px <= 16'd0;
        else if (wr_ready) px <= px + 16'd1;
    end
    assign pix_valid = wr_ready;
    assign pix_data  = px;

    // reference queue of written pixels, checked against rd_pix
    reg [15:0] refq [0:8191];
    reg [31:0] ref_wr = 0, ref_rd = 0;
    integer    err = 0;
    integer    rd_count = 0;
    always @(posedge clk) begin
        if (wr_ready) begin
            refq[ref_wr[12:0]] <= pix_data;
            ref_wr <= ref_wr + 1;
        end
        if (rd_pix_valid) begin
            rd_count = rd_count + 1;
            if (rd_pix !== refq[ref_rd[12:0]]) begin
                err = err + 1;
                if (err < 5)
                    $display("MISMATCH t=%0t out=%h expected=%h", $time, rd_pix, refq[ref_rd[12:0]]);
            end
            ref_rd <= ref_rd + 1;
        end
    end

    // FSM entry counters for debugging
    reg [3:0] prev_state = 0;
    integer  pack_entries = 0, rout_entries = 0;
    always @(posedge clk) begin
        prev_state <= uut.state;
        if (uut.state == 4'd1 && prev_state != 4'd1)  pack_entries = pack_entries + 1;
        if (uut.state == 4'd13 && prev_state != 4'd13) rout_entries = rout_entries + 1;
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (300000) @(posedge clk);

        $display("RESULT: written=%0d output=%0d mismatches=%0d pack_entries=%0d rout_entries=%0d",
                 ref_wr, rd_count, err, pack_entries, rout_entries);
        // one final burst may still be in the write->readback pipeline
        if (err == 0 && (ref_wr - ref_rd) <= 2*16 && rd_count > 100)
            $display("PASS: read-back pixels match written pixels (%0d px)", rd_count);
        else
            $display("FAIL");
        $finish;
    end
endmodule
