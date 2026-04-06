`timescale 1ns/1ps

module led_tb;

reg clk;
reg rst_n;
reg key_i;
wire [5:0] led;

led #(
    .CLOCK_FREQUENCY(8),
    .A_MINUTE_SEC(6'd4),
    .BRIGHTNESS(8'h40)
) uut (
    .clk   (clk),
    .rst_n (rst_n),
    .key_i (key_i),
    .led   (led)
);

defparam uut.key_ctrl_inst.debouncer_inst.CLOCK_FREQUENCY = 1000;
defparam uut.key_ctrl_inst.debouncer_inst.STABLE_TIMES = 1;

always #5 clk = ~clk;

task automatic press_key;
begin
    key_i = 1'b0;
    repeat (6) @(posedge clk);
    key_i = 1'b1;
    repeat (6) @(posedge clk);
end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b1;
    key_i = 1'b1;

    $dumpfile("tb/led_tb.vcd");
    $dumpvars(0, led_tb);

    repeat (4) @(posedge clk);
    rst_n = 1'b0;

    repeat (12) @(posedge clk);
    press_key();
    press_key();
    press_key();

    repeat (24) @(posedge clk);
    $finish;
end

initial begin
    $display("time\trst_n\trst_n_key\tkey_i\tkey_state\tbin_sec\tbrightness\tpwm\tled");
    $monitor("%0t\t%b\t%b\t%b\t%02b\t%02d\t0x%0h\t%b\t%06b",
        $time,
        rst_n,
        uut.rst_n_key,
        key_i,
        uut.key_state,
        uut.bin_sec,
        uut.brightness,
        uut.pwm_signal,
        led
    );
end

endmodule