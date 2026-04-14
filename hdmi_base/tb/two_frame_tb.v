`timescale 1ns/1ps
module tb;

parameter integer H = 160;
parameter integer V = 120;

reg clk;
reg rst_n;
reg ready;
reg frame_pulse;

wire [11:0] x;
wire [11:0] y;
wire [23:0] rgb_o;
wire ve;
integer i;
integer total_cycles;

pattern_gen #(.H_ACTIVE(H), .V_ACTIVE(V), .PATTERN_MODE(1)) uut (
    .clk(clk),
    .rst_n(rst_n),
    .ready(ready),
    .frame_pulse(frame_pulse),
    .x(x),
    .y(y),
    .rgb_o(rgb_o),
    .ve(ve)
);

initial begin
    $dumpfile("tb/two_frame_tb.vcd");
    $dumpvars(0, tb);

    clk = 0;
    rst_n = 0;
    ready = 0;
    frame_pulse = 1;
    #20;
    rst_n = 1;
    frame_pulse = 0;

    // Run for two frames
    total_cycles = 2 * H * V;
    for (i = 0; i < total_cycles; i = i + 1) begin
        @(posedge clk);
        ready = 1;
        @(posedge clk);
        ready = 0;
    end

    #100;
    $finish;
end

// 100 MHz clock
always #5 clk = ~clk;

endmodule
