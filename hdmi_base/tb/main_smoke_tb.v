`timescale 1ns/1ps

module main_smoke_tb;

reg clk;
reg rst_n;
wire led;

main uut (
    .clk(clk),
    .rst_n(rst_n),
    .led(led)
);

always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    rst_n = 1'b0;

    $dumpfile("tb/main_smoke_tb.vcd");
    $dumpvars(0, main_smoke_tb);

    repeat (6) @(posedge clk);
    rst_n = 1'b1;

    repeat (200) @(posedge clk);
    $display("SMOKE PASS: main ran for 200 cycles after reset release.");
    $finish;
end

endmodule