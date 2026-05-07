module main(
    input clk,
    input rst_key_n,
    output wire [5:0]led,

    // HDMI output signals
    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire tmds_data0_p, output wire tmds_data0_n,  // Blue
    output wire tmds_data1_p, output wire tmds_data1_n,  // Green
    output wire tmds_data2_p, output wire tmds_data2_n   // Red
);

// Active-low reset from button
wire rst_n = ~rst_key_n; 

localparam integer TMDS_ALIGN_LATENCY = 5; // line-buffer read data is registered once more before TMDS encoding
localparam integer TEST_PATTERN_MODE = 1;  // 0: uniform color grid, 1: HDMI diagnostic pattern
 
// HDMI config
// 1080p
localparam integer 
    H_ACTIVE = 1920, H_FRONT_PORCH = 88, H_SYNC_PULSE = 44, H_BACK_PORCH = 148,
    V_ACTIVE = 1080, V_FRONT_PORCH = 4,  V_SYNC_PULSE = 5,  V_BACK_PORCH = 36;

/*
// 720p
localparam integer 
    H_ACTIVE = 1280, H_FRONT_PORCH = 110, H_SYNC_PULSE = 40, H_BACK_PORCH = 220,
    V_ACTIVE = 720,  V_FRONT_PORCH = 5,   V_SYNC_PULSE = 5,  V_BACK_PORCH = 20;
*/

// Derived timing parameters (kept in timing module when needed)

// Internal signals
wire de_hdmi;
wire vsync_hdmi;
wire frame_end_hdmi;

reg [25:0] led_cnt;

assign hdmi_rst_n = rst_n && lock; // Hold HDMI domain in reset until PLL locks

// LED diagnostic:
// - PLL unlocked: fast blink (input clock domain alive)
// - PLL locked:   slow blink (HDMI domain active)
always @(posedge clk) begin
    led_cnt <= led_cnt + 26'd1;
end
assign led[5] = (!lock) ? led_cnt[22] : led_cnt[24];

// Frame counter for debugging
reg [24:0] rst_cnt = 0;
always @(posedge clk_sys) begin
    if(!frame_pulse) rst_cnt <= rst_cnt + 1;
end
assign led[0] = rst_cnt[24];


// PLL and clock generation
// Generate System clock (~166.5MHz) and CPU clock (~83.25MHz) from 27MHz using rPLL_SYS
// Generate HDMI clock (e.g. 148.5MHz for 1080p60) from the input 27MHz using rPLL_HDMI
// Generate HDMI clock using PLL and clock divider
wire clk_sys;    // ~166.5MHz
wire clk_sys_90; // ~166.5MHz with 90-degree phase shift
wire clk_cpu;    // ~83.25MHz
wire clk_hdmi;
wire clk_hdmi_5x;
wire hdmi_rst_n;
wire lock;
wire lock_sys;

timing #(
    .PLL_PROFILE(2'd3) // 1080p60
) u_timing (
    .clk(clk),
    .rst_n(rst_n),
    .hdmi_rst_n(hdmi_rst_n),
    .clk_sys(clk_sys),
    .clk_sys_90(clk_sys_90),
    .clk_cpu(clk_cpu),
    .clk_hdmi(clk_hdmi),
    .clk_hdmi_5x(clk_hdmi_5x),
    .lock(lock),
    .lock_sys(lock_sys)
);


// Pattern generator output goes through line buffer before TMDS encoding
// now self-generates x,y coordinates in clk_sys domain (no CDC)
wire [23:0] rgb_ptrn_o;
wire [11:0] x, y;  // Pattern generator's internal coordinates
wire ptrn_ve;
pattern_gen #(
    .H_ACTIVE(H_ACTIVE),
    .V_ACTIVE(V_ACTIVE),
    .PATTERN_MODE(TEST_PATTERN_MODE)
) test_pattern (
    .clk(clk_sys),
    .rst_n(rst_n),
    .ready(!fifo_full), // Backpressure from line buffer FIFO
    .frame_pulse(frame_pulse), // Pulse at the start of each frame for synchronization
    .x(x),
    .y(y),
    .rgb_o(rgb_ptrn_o), // Connect to TMDS encoder later
    .ve(ptrn_ve)
);

// Vsync to reset pattern generator at the start of each frame 
reg [2:0] vsync_sys;
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) vsync_sys <= 3'b000;
    else vsync_sys <= {vsync_sys[1:0], vsync_hdmi};
end
wire frame_pulse = vsync_sys[1] && !vsync_sys[2];


// Line buffer to align video data with TMDS encoding timing (1 line buffer depth is sufficient for 720p/1080p)
wire fifo_full, fifo_empty;
wire fifo_almost_full, fifo_almost_empty;
async_fifo #(
    .ADDRESS_WIDTH(12), // 4096 entries, enough for one line of 1080p (1920 pixels)
    .DATA_WIDTH(16)
) hdmi_line_buf_fifo (
    .w_clk(clk_sys),
    .w_rst_n(rst_n),
    .w_en(!fifo_full),
    .w_data(rgb_ptrn_out_565),
    .full(fifo_full),
    .almost_full(fifo_almost_full),

    .r_clk(clk_hdmi),
    .r_rst_n(hdmi_rst_n),
    .r_en(de_hdmi),
    .r_data(rgb_from_buf_565),
    .empty(fifo_empty),
    .almost_empty(fifo_almost_empty)
);


// Dither RGB888 pattern output to RGB565 for HDMI line buffer
// Use pattern generator's self-generated coordinates (no CDC issue)
wire [15:0] rgb_ptrn_out_565;
wire [15:0] rgb_from_buf_565;
dither_rgb888_to_565 #(
    .DITHER_EN(1'b1),
    .PRESERVE_GRAY(1'b0)
) u_dither (
    .rgb888(rgb_ptrn_o),
    .x(x),
    .y(y),
    .rgb565(rgb_ptrn_out_565) 
);

// HDMI output module (video timing generation + TMDS encoding)
hdmi_top #(
    .H_ACTIVE(H_ACTIVE),
    .H_FRONT_PORCH(H_FRONT_PORCH),
    .H_SYNC_PULSE(H_SYNC_PULSE),
    .H_BACK_PORCH(H_BACK_PORCH),
    .V_ACTIVE(V_ACTIVE),
    .V_FRONT_PORCH(V_FRONT_PORCH),
    .V_SYNC_PULSE(V_SYNC_PULSE),
    .V_BACK_PORCH(V_BACK_PORCH),
    .TMDS_ALIGN_LATENCY(TMDS_ALIGN_LATENCY)
) u_hdmi_top (
    .clk_hdmi(clk_hdmi),
    .clk_hdmi_5x(clk_hdmi_5x),
    .rst_n(hdmi_rst_n),
    .rgb565_i(rgb_from_buf_565),
    .de_o(de_hdmi),
    .vsync_o(vsync_hdmi),
    .frame_end_o(frame_end_hdmi),
    .tmds_clk_p(tmds_clk_p),
    .tmds_clk_n(tmds_clk_n),
    .tmds_data0_p(tmds_data0_p),
    .tmds_data0_n(tmds_data0_n),
    .tmds_data1_p(tmds_data1_p),
    .tmds_data1_n(tmds_data1_n),
    .tmds_data2_p(tmds_data2_p),
    .tmds_data2_n(tmds_data2_n)
);

endmodule