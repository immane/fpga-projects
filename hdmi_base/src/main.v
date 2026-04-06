module main(
    input clk,
    input rst_n,
    output reg led,

    // HDMI output signals
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire tmds_data0_p, output wire tmds_data0_n,  // Blue
    output wire tmds_data1_p, output wire tmds_data1_n,  // Green
    output wire tmds_data2_p, output wire tmds_data2_n   // Red
);

localparam CLOCK_FREQUENCY = 27_000_000; // 27 MHz input
localparam HDMI_FREQ = 74_250_000; // 74.25 MHz for HDMI
localparam HDMI_FREQ_5X = 371_250_000; // 5x HDMI frequency for PLL


// Initial values for registers

// Generate HDMI clock using PLL and clock divider
wire lock;
wire clk_hdmi;
wire clk_hdmi_5x;

reg [31:0] htmi_cnt;

// Video timing generator signals
wire hsync, vsync, de;
wire [11:0] x, y;
wire frame_end;

// RGB output from pattern generator
wire [23:0] rgb;
wire [9:0] tmds_r;
wire [9:0] tmds_g;
wire [9:0] tmds_b;
wire serial_clk;
wire serial_r;
wire serial_g;
wire serial_b;

// Counter to generate a 1-second tick based on HDMI frequency
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) htmi_cnt <= 32'd0;
    else begin
        if(htmi_cnt == HDMI_FREQ) htmi_cnt <= 32'd0; // Reset counter after reaching HDMI frequency
        else htmi_cnt <= htmi_cnt + 1;
    end
end

// Toggle LED every second based on HDMI frequency
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) led <= 1'b0;
    else if(htmi_cnt == HDMI_FREQ) led <= ~led; // Toggle LED every second
    else led <= led; // Keep LED state unchanged 
end


// 1: PLL and clock generation for HDMI
Gowin_rPLL pll_hdmi(
    .clkout(clk_hdmi_5x), //output clkout
    .lock(lock), //output lock
    .clkin(clk) //input clkin
);
Gowin_CLKDIV clkdiv_hdmi(
    .clkout(clk_hdmi), //output clkout
    .hclkin(clk_hdmi_5x), //input hclkin
    .resetn(rst_n) //input resetn
);

// 2: Instantiate video timing generator
vid_timing_gen vid_timing(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .de(de),
    .x(x),
    .y(y),
    .frame_end(frame_end)
);

// 3: Instantiate pattern generator and TMDS encoders
pattern_gen test_pattern(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de),
    .x(x),
    .y(y),
    .frame_end(frame_end),
    .rgb_o(rgb) // Connect to TMDS encoder later
);

// 4: Instantiate TMDS encoders for RGB channels
tmds_encoder tmds_encoder_r(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de),
    .data_i(rgb[23:16]),
    .ctrl_i(2'b00),
    .tmds_o(tmds_r)
);
tmds_encoder tmds_encoder_g(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de),
    .data_i(rgb[15:8]),
    .ctrl_i(2'b00),
    .tmds_o(tmds_g)
);
tmds_encoder tmds_encoder_b(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de),
    .data_i(rgb[7:0]),
    .ctrl_i({vsync, hsync}),
    .tmds_o(tmds_b)
);

// 5: Connect TMDS outputs to HDMI output pins (not shown here, depends on board pinout)
serlizer_10to1 u_ser_clk (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n & lock),
    .parallel_i  (10'b0000011111),   // Control code for clock channel
    .serial_o    (serial_clk)
);
serlizer_10to1 u_ser_r (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n & lock),
    .parallel_i  (tmds_r),
    .serial_o    (serial_r)
);
serlizer_10to1 u_ser_g (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n & lock),
    .parallel_i  (tmds_g),
    .serial_o    (serial_g)
);
serlizer_10to1 u_ser_b (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n & lock),
    .parallel_i  (tmds_b),
    .serial_o    (serial_b)
);

// 6: Connect serialized outputs to HDMI output pins using differential buffers (not shown here, depends on board pinout)
ELVDS_OBUF u_obuf_clk (.I (serial_clk), .O (tmds_clk_p), .OB (tmds_clk_n));
ELVDS_OBUF u_obuf_r (.I (serial_r), .O (tmds_data2_p), .OB (tmds_data2_n));
ELVDS_OBUF u_obuf_g (.I (serial_g), .O (tmds_data1_p), .OB (tmds_data1_n));
ELVDS_OBUF u_obuf_b (.I (serial_b), .O (tmds_data0_p), .OB (tmds_data0_n));

endmodule