module main(
    input clk,
    input rst_n,
    output reg led
);

localparam CLOCK_FREQUENCY = 27_000_000; // 27 MHz input
localparam HDMI_FREQ = 74_250_000; // 74.25 MHz for HDMI
localparam HDMI_FREQ_5X = 371_250_000; // 5x HDMI frequency for PLL

wire lock;
wire clk_o_5x;
Gowin_rPLL pll_hdmi(
    .clkout(clk_o_5x), //output clkout
    .lock(lock), //output lock
    .clkin(clk) //input clkin
);

wire clk_o;
Gowin_CLKDIV clkdiv_hdmi(
    .clkout(clk_o), //output clkout
    .hclkin(clk_o_5x), //input hclkin
    .resetn(rst_n) //input resetn
);

reg [31:0] cnt;
always @(posedge clk_o or negedge rst_n) begin
    if (!rst_n)
        cnt <= 32'd0;
    else begin
        if(cnt == HDMI_FREQ) 
            cnt <= 32'd0; // Reset counter after reaching HDMI frequency
        else
            cnt <= cnt + 1;
    end
end

always @(posedge clk_o or negedge rst_n) begin
    if (!rst_n)
        led <= 1'b0;
    else if(cnt == HDMI_FREQ) begin
        led <= ~led; // Toggle LED every second
    end
    else begin
        led <= led; // Keep LED state unchanged
    end
end

endmodule