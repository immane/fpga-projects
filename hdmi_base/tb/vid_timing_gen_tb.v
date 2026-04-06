`timescale 1ns/1ps

module vid_timing_gen_tb;

localparam FRAME_TARGET = 3;

localparam H_ACTIVE = 8;
localparam H_FRONT_PORCH = 2;
localparam H_SYNC_PULSE = 2;
localparam H_BACK_PORCH = 2;
localparam H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;

localparam V_ACTIVE = 4;
localparam V_FRONT_PORCH = 1;
localparam V_SYNC_PULSE = 1;
localparam V_BACK_PORCH = 1;
localparam V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

reg clk_hdmi;
reg rst_n;

wire hsync;
wire vsync;
wire de;
wire [11:0] x;
wire [11:0] y;
wire frame_end;

integer frame_count;
integer active_pixel_count;
integer total_pixel_count;
integer line_start_count;

vid_timing_gen #(
    .H_ACTIVE(H_ACTIVE),
    .H_FRONT_PORCH(H_FRONT_PORCH),
    .H_SYNC_PULSE(H_SYNC_PULSE),
    .H_BACK_PORCH(H_BACK_PORCH),
    .V_ACTIVE(V_ACTIVE),
    .V_FRONT_PORCH(V_FRONT_PORCH),
    .V_SYNC_PULSE(V_SYNC_PULSE),
    .V_BACK_PORCH(V_BACK_PORCH)
) uut (
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .de(de),
    .x(x),
    .y(y),
    .frame_end(frame_end)
);

always #5 clk_hdmi = ~clk_hdmi;

always @(posedge clk_hdmi) begin
    if (!rst_n) begin
        frame_count <= 0;
        active_pixel_count <= 0;
        total_pixel_count <= 0;
        line_start_count <= 0;
    end else begin
        total_pixel_count <= total_pixel_count + 1;

        if (x == 0)
            line_start_count <= line_start_count + 1;

        if (de)
            active_pixel_count <= active_pixel_count + 1;

        if (frame_end) begin
            frame_count <= frame_count + 1;
            $display("frame %0d end at time=%0t h_cnt=%0d v_cnt=%0d x=%0d y=%0d active_pixels=%0d total_pixels=%0d lines=%0d",
                frame_count + 1,
                $time,
                uut.h_cnt,
                uut.v_cnt,
                x,
                y,
                active_pixel_count,
                total_pixel_count,
                line_start_count
            );
            active_pixel_count <= 0;
            total_pixel_count <= 0;
            line_start_count <= 0;
        end
    end
end

initial begin
    clk_hdmi = 1'b0;
    rst_n = 1'b0;
    frame_count = 0;
    active_pixel_count = 0;

    $dumpfile("tb/vid_timing_gen_tb.vcd");
    $dumpvars(0, vid_timing_gen_tb);

    repeat (4) @(posedge clk_hdmi);
    rst_n = 1'b1;

    wait (frame_count == FRAME_TARGET);
    repeat (4) @(posedge clk_hdmi);
    $finish;
end

always @(posedge clk_hdmi) begin
    if (rst_n && frame_end && (uut.h_cnt != H_TOTAL - 1 || uut.v_cnt != V_TOTAL - 1)) begin
        $display("ERROR: frame_end asserted at wrong position time=%0t h_cnt=%0d v_cnt=%0d x=%0d y=%0d",
            $time,
            uut.h_cnt,
            uut.v_cnt,
            x,
            y
        );
        $finish;
    end

    if (rst_n && de && (x >= H_ACTIVE || y >= V_ACTIVE)) begin
        $display("ERROR: de asserted outside active area at time=%0t x=%0d y=%0d", $time, x, y);
        $finish;
    end

    if (rst_n && hsync && (x < H_ACTIVE + H_FRONT_PORCH || x >= H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE)) begin
        $display("ERROR: hsync outside expected range at time=%0t x=%0d", $time, x);
        $finish;
    end

    if (rst_n && vsync && (y < V_ACTIVE + V_FRONT_PORCH || y >= V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE)) begin
        $display("ERROR: vsync outside expected range at time=%0t y=%0d", $time, y);
        $finish;
    end
end

endmodule