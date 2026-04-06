`timescale 1ns/1ps

module pattern_gen_tb;

reg clk_hdmi;
reg rst_n;
reg [11:0] x;
reg [11:0] y;
reg de;
reg frame_end;
wire [23:0] rgb_o;

integer frame_index;

pattern_gen #(
    .H_ACTIVE(16),
    .V_ACTIVE(8)
) uut (
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .x(x),
    .y(y),
    .de(de),
    .frame_end(frame_end),
    .rgb_o(rgb_o)
);

always #5 clk_hdmi = ~clk_hdmi;

task automatic drive_pixel;
    input [11:0] pixel_x;
    input [11:0] pixel_y;
    input pixel_de;
    input pixel_frame_end;
begin
    x = pixel_x;
    y = pixel_y;
    de = pixel_de;
    frame_end = pixel_frame_end;
    @(posedge clk_hdmi);
end
endtask

initial begin
    clk_hdmi = 1'b0;
    rst_n = 1'b0;
    x = 12'd0;
    y = 12'd0;
    de = 1'b0;
    frame_end = 1'b0;
    frame_index = 0;

    $dumpfile("tb/pattern_gen_tb.vcd");
    $dumpvars(0, pattern_gen_tb);

    repeat (4) @(posedge clk_hdmi);
    rst_n = 1'b1;

    for (frame_index = 0; frame_index < 3; frame_index = frame_index + 1) begin
        drive_pixel(12'd0, 12'd0, 1'b0, 1'b0);
        drive_pixel(12'd0, 12'd0, 1'b1, 1'b0);
        drive_pixel(12'd160, 12'd0, 1'b1, 1'b0);
        drive_pixel(12'd320, 12'd0, 1'b1, 1'b0);
        drive_pixel(12'd480, 12'd0, 1'b1, 1'b0);
        drive_pixel(12'd640, 12'd0, 1'b1, 1'b0);
        drive_pixel(12'd800, 12'd0, 1'b1, 1'b0);
        drive_pixel(12'd1120, 12'd64, 1'b1, 1'b0);
        drive_pixel(12'd1279, 12'd719, 1'b1, 1'b1);
        drive_pixel(12'd0, 12'd0, 1'b0, 1'b0);
    end

    repeat (4) @(posedge clk_hdmi);
    $finish;
end

always @(posedge clk_hdmi) begin
    if (!rst_n && rgb_o !== 24'h000000) begin
        $display("ERROR: rgb_o not cleared during reset at time=%0t rgb=%h", $time, rgb_o);
        $finish;
    end

    if (rst_n && !de && rgb_o !== 24'h000000) begin
        $display("ERROR: rgb_o not blanked when de=0 at time=%0t rgb=%h", $time, rgb_o);
        $finish;
    end

    if (rst_n && de) begin
        $display("time=%0t frame_cnt=%0d x=%0d y=%0d rgb=%h", $time, uut.frame_cnt, x, y, rgb_o);
    end
end

endmodule