`timescale 1ns/1ps

module main_fifo_frame_tb;

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
integer pulse_cycle_0;
integer pulse_cycle_1;
integer pulse_cycle_2;
integer wr_req_cnt;
integer wr_acc_cnt;
integer rd_req_cnt;
integer rd_acc_cnt;

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

// Speed up simulation only: shrink HDMI timing so frame_pulse appears quickly.
defparam uut.vid_timing.H_ACTIVE = 64;
defparam uut.vid_timing.H_FRONT_PORCH = 8;
defparam uut.vid_timing.H_SYNC_PULSE = 8;
defparam uut.vid_timing.H_BACK_PORCH = 8;
defparam uut.vid_timing.V_ACTIVE = 48;
defparam uut.vid_timing.V_FRONT_PORCH = 2;
defparam uut.vid_timing.V_SYNC_PULSE = 2;
defparam uut.vid_timing.V_BACK_PORCH = 2;

always #5 clk = ~clk;

// Per-frame FIFO activity counters.
always @(posedge uut.clk_sys) begin
    if (uut.frame_pulse) begin
        wr_req_cnt <= 0;
        wr_acc_cnt <= 0;
    end else begin
        if (uut.fifo_w_en)
            wr_req_cnt <= wr_req_cnt + 1;
        if (uut.fifo_w_en && !uut.fifo_full)
            wr_acc_cnt <= wr_acc_cnt + 1;
    end
end

always @(posedge uut.clk_hdmi) begin
    if (uut.frame_pulse) begin
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

        if (frame_count == 0) begin
            pulse_cycle_0 <= sys_cycles;
        end else if (frame_count == 1) begin
            pulse_cycle_1 <= sys_cycles;
        end else if (frame_count == 2) begin
            pulse_cycle_2 <= sys_cycles;
        end

        $display("[frame_pulse] t=%0t sys_cycle=%0d frame_count=%0d logic_rst_n=%b fifo_w_en=%b ptrn_ve=%b full=%b empty=%b w_ptr=%0d r_ptr=%0d w_data=%h r_data=%h",
                 $time,
                 sys_cycles,
                 frame_count,
                 uut.logic_rst_n,
                 uut.fifo_w_en,
                 uut.ptrn_ve,
                 uut.fifo_full,
                 uut.fifo_empty,
                 uut.hdmi_line_buf_fifo.w_ptr,
                 uut.hdmi_line_buf_fifo.r_ptr,
                 uut.rgb_pattern_o_565,
                 uut.rgb_from_buf_565);

            $display("[frame_stats ] wr_req=%0d wr_acc=%0d rd_req=%0d rd_acc=%0d",
                 wr_req_cnt,
                 wr_acc_cnt,
                 rd_req_cnt,
                 rd_acc_cnt);

        if (frame_count == 3) begin
            $display("INFO: captured 4 frame_pulse events (0,1,2,3). End simulation.");
            $display("INFO: cycles between pulse0 and pulse1 = %0d", pulse_cycle_1 - pulse_cycle_0);
            $display("INFO: cycles between pulse1 and pulse2 = %0d", pulse_cycle_2 - pulse_cycle_1);
            $finish;
        end
    end
end

initial begin
    clk = 1'b0;
    // In current main.v: rst_n = ~rst_key_n. Keep rst_key_n=0 for normal run.
    rst_key_n = 1'b1;
    sys_cycles = 0;
    frame_count = 0;
    pulse_cycle_0 = 0;
    pulse_cycle_1 = 0;
    pulse_cycle_2 = 0;
    wr_req_cnt = 0;
    wr_acc_cnt = 0;
    rd_req_cnt = 0;
    rd_acc_cnt = 0;

    $dumpfile("tb/main_fifo_frame_tb.vcd");
    $dumpvars(0, main_fifo_frame_tb);

    repeat (20) @(posedge clk);
    rst_key_n = 1'b0;

    // Timeout guard
    repeat (5000000) @(posedge clk);
    $display("TIMEOUT: did not observe enough frame pulses.");
    $finish;
end

endmodule
