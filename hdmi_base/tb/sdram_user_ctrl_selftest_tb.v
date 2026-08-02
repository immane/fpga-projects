// Testbench for sdram_user_ctrl SELFTEST mode (SELFTEST_EN=1):
// the controller generates KNOWN data (independent of the pattern), writes it
// to SDRAM, reads it back and compares. selftest_err must stay 0 and
// selftest_done must pulse (loop running) -> proves write+readback work.
`timescale 1ns/1ps
module sdram_user_ctrl_selftest_tb;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         rd_ready = 1'b1;

    wire        init_done, cmd_ack;
    wire [31:0] read_data;

    wire [2:0]  user_cmd;
    wire        user_cmd_en;
    wire [20:0] user_addr;
    wire [31:0] user_data;
    wire [7:0]  user_len;
    wire [15:0] rd_pix;
    wire        rd_pix_valid, wr_ready;
    wire        selftest_done, selftest_err;
    wire [15:0] selftest_err_cnt;

    sdram_user_ctrl #(
        .BURST_SIZE(16),
        .RD_OUT_EN (0),
        .SELFTEST_EN(1)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .init_done(init_done), .cmd_ack(cmd_ack),
        .pix_valid(1'b0), .pix_data(16'd0),
        .user_cmd(user_cmd), .user_cmd_en(user_cmd_en),
        .user_addr(user_addr), .user_data(user_data), .user_len(user_len),
        .read_data(read_data),
        .rd_pix(rd_pix), .rd_pix_valid(rd_pix_valid), .rd_ready(rd_ready),
        .wr_ready(wr_ready),
        .selftest_done(selftest_done), .selftest_err(selftest_err),
        .selftest_err_cnt(selftest_err_cnt)
    );

    sdram_hs_model #(.CL(2),.WR(2),.RP(2),.RCD(2)) model (
        .clk(clk), .rst_n(rst_n),
        .cmd_en(user_cmd_en), .cmd(user_cmd), .addr(user_addr),
        .data(user_data), .data_len(user_len),
        .o_data(read_data), .cmd_ack(cmd_ack), .init_done(init_done)
    );

    always #3 clk = ~clk;

    integer done_c = 0;
    integer err_cycles = 0;
    integer cmd_c = 0;
    reg [3:0] prev_state = 0;
    integer state_seen [0:15];
    integer s;
    initial for (s = 0; s < 16; s = s + 1) state_seen[s] = 0;
    always @(posedge clk) begin
        if (selftest_done) done_c = done_c + 1;
        if (selftest_err)  err_cycles = err_cycles + 1;
        if (user_cmd_en)   cmd_c = cmd_c + 1;
        if (uut.state != prev_state) begin
            if (cmd_c < 40 || $time < 20000) begin
                $display("t=%0t state=%0d", $time, uut.state);
            end
            state_seen[uut.state] = state_seen[uut.state] + 1;
            prev_state = uut.state;
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (300000) @(posedge clk);

        $display("RESULT selftest: done=%0d err_cycles=%0d err_cnt=%0d init=%0b rd_valid=%0d",
                 done_c, err_cycles, selftest_err_cnt, init_done, rd_pix_valid);
        if (done_c > 100 && err_cycles == 0 && selftest_err_cnt == 0)
            $display("PASS (selftest): SDRAM write+readback self-check clean");
        else
            $display("FAIL (selftest)");
        $finish;
    end
endmodule
