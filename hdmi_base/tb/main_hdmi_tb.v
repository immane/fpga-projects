`timescale 1ns/1ps

module main_hdmi_tb;

reg clk;
reg rst_n;
wire led;
wire tmds_clk_p;
wire tmds_clk_n;
wire tmds_data0_p;
wire tmds_data0_n;
wire tmds_data1_p;
wire tmds_data1_n;
wire tmds_data2_p;
wire tmds_data2_n;

integer cycle_count;

main uut (
    .clk(clk),
    .rst_n(rst_n),
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

always #5 clk = ~clk;

task automatic assert_known_and_complement;
begin
    if (^tmds_clk_p === 1'bx || ^tmds_clk_n === 1'bx ||
        ^tmds_data0_p === 1'bx || ^tmds_data0_n === 1'bx ||
        ^tmds_data1_p === 1'bx || ^tmds_data1_n === 1'bx ||
        ^tmds_data2_p === 1'bx || ^tmds_data2_n === 1'bx) begin
        $display("ERROR: unknown value on TMDS outputs at time=%0t", $time);
        $finish;
    end

    if (tmds_clk_n !== ~tmds_clk_p) begin
        $display("ERROR: TMDS clock pair not complementary at time=%0t", $time);
        $finish;
    end

    if (tmds_data0_n !== ~tmds_data0_p ||
        tmds_data1_n !== ~tmds_data1_p ||
        tmds_data2_n !== ~tmds_data2_p) begin
        $display("ERROR: TMDS data pair not complementary at time=%0t", $time);
        $finish;
    end
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cycle_count = 0;

    $dumpfile("tb/main_hdmi_tb.vcd");
    $dumpvars(0, main_hdmi_tb);

    repeat (8) @(posedge clk);
    rst_n = 1'b1;

    repeat (500) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
        assert_known_and_complement();
    end

    $display("PASS: main_hdmi_tb completed %0d cycles.", cycle_count);
    $finish;
end

endmodule