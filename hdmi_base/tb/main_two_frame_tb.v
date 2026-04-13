`timescale 1ns/1ps

module main_two_frame_tb;

reg clk;
reg rst_key_n;
wire [5:0] led;
wire tmds_clk_p;
wire tmds_clk_n;
wire tmds_data0_p;
wire tmds_data0_n;
wire tmds_data1_p;
wire tmds_data1_n;
wire tmds_data2_p;
wire tmds_data2_n;

integer sys_cycles;
integer frame_count;
integer last_frame_cycle;
integer wr_req_cnt;
integer wr_acc_cnt;
integer rd_req_cnt;
integer rd_acc_cnt;
integer full_hi_cnt;
integer ve_hi_cnt;
integer fifo_wen_hi_cnt;

reg [1:0] vsync_hdmi_tb;
wire frame_pulse_hdmi_tb = vsync_hdmi_tb[0] && !vsync_hdmi_tb[1];

main uut (
    .clk(clk),
    .rst_key_n(rst_key_n),
    .led(led),
    .tmds_clk_p(tmds_clk_p),
    .tmds_clk_n(tmds_clk_n),
    .tmds_data0_p(tmds_data0_p),
    .tmds_data0_n(tmds_data0_n),
    .tmds_data1_p(tmds_data1_p),
    .tmds_data1_n(tmds_data1_n),
    .tmds_data2_p(tmds_data2_p),
    .tmds_data2_n(tmds_data2_n)
);

// Speed up simulation only: shrink timing to observe frames quickly.
defparam uut.vid_timing.H_ACTIVE = 64;
defparam uut.vid_timing.H_FRONT_PORCH = 8;
defparam uut.vid_timing.H_SYNC_PULSE = 8;
defparam uut.vid_timing.H_BACK_PORCH = 8;
defparam uut.vid_timing.V_ACTIVE = 48;
defparam uut.vid_timing.V_FRONT_PORCH = 2;
defparam uut.vid_timing.V_SYNC_PULSE = 2;
defparam uut.vid_timing.V_BACK_PORCH = 2;

always #5 clk = ~clk;

always @(posedge uut.clk_hdmi or negedge uut.hdmi_rst_n) begin
    if (!uut.hdmi_rst_n)
        vsync_hdmi_tb <= 2'b00;
    else
        vsync_hdmi_tb <= {vsync_hdmi_tb[0], uut.vsync};
end

always @(posedge uut.clk_sys) begin
    if (uut.frame_pulse) begin
        wr_req_cnt <= 0;
        wr_acc_cnt <= 0;
        full_hi_cnt <= 0;
        ve_hi_cnt <= 0;
        fifo_wen_hi_cnt <= 0;
    end else begin
        if (uut.ptrn_ve)
            wr_req_cnt <= wr_req_cnt + 1;
        if (uut.ptrn_ve && !uut.fifo_full)
            wr_acc_cnt <= wr_acc_cnt + 1;
        if (uut.fifo_full)
            full_hi_cnt <= full_hi_cnt + 1;
        if (uut.ptrn_ve)
            ve_hi_cnt <= ve_hi_cnt + 1;
        if (uut.hdmi_line_buf_fifo.w_en)
            fifo_wen_hi_cnt <= fifo_wen_hi_cnt + 1;
    end
end

always @(posedge uut.clk_hdmi) begin
    if (frame_pulse_hdmi_tb) begin
        rd_req_cnt <= 0;
        rd_acc_cnt <= 0;
    end else begin
        if (uut.de)
            rd_req_cnt <= rd_req_cnt + 1;
        if (uut.de && !uut.fifo_empty)
            rd_acc_cnt <= rd_acc_cnt + 1;
    end
end

always @(posedge uut.clk_sys) begin
    sys_cycles <= sys_cycles + 1;

    if (uut.frame_pulse) begin
        frame_count <= frame_count + 1;
        $display("[frame] t=%0t frame=%0d sys_cycle=%0d delta=%0d rst_n=%b ve=%b full=%b empty=%b w_ptr=%0d r_ptr=%0d w_data=%h r_data=%h",
                 $time,
                 frame_count,
                 sys_cycles,
                 sys_cycles - last_frame_cycle,
                 uut.rst_n,
                 uut.ptrn_ve,
                 uut.fifo_full,
                 uut.fifo_empty,
                 uut.hdmi_line_buf_fifo.w_ptr,
                 uut.hdmi_line_buf_fifo.r_ptr,
                 uut.rgb_pattern_o_565,
                 uut.rgb_from_buf_565);
        $display("[stats] wr_req=%0d wr_acc=%0d rd_req=%0d rd_acc=%0d full_hi=%0d ve_hi=%0d w_en_hi=%0d",
                 wr_req_cnt,
                 wr_acc_cnt,
                 rd_req_cnt,
             rd_acc_cnt,
             full_hi_cnt,
             ve_hi_cnt,
             fifo_wen_hi_cnt);
        last_frame_cycle <= sys_cycles;

        // Stop after observing two full frame intervals (3 pulses: 0,1,2).
        if (frame_count == 2) begin
            $display("INFO: captured two frame intervals successfully.");
            $finish;
        end
    end
end

initial begin
    clk = 1'b0;
    rst_key_n = 1'b1;
    sys_cycles = 0;
    frame_count = 0;
    last_frame_cycle = 0;
    wr_req_cnt = 0;
    wr_acc_cnt = 0;
    rd_req_cnt = 0;
    rd_acc_cnt = 0;
    full_hi_cnt = 0;
    ve_hi_cnt = 0;
    fifo_wen_hi_cnt = 0;
    vsync_hdmi_tb = 2'b00;

    $dumpfile("tb/main_two_frame_tb.vcd");
    $dumpvars(0, main_two_frame_tb);

    repeat (20) @(posedge clk);
    rst_key_n = 1'b0;

    // Timeout guard
    repeat (3000000) @(posedge clk);
    $display("TIMEOUT: did not capture two frame intervals.");
    $finish;
end

endmodule
