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

wire rst_n = ~rst_key_n; // Active-low reset from button;

// Timing parameters
localparam CLOCK_FREQUENCY = 27_000_000; // 27 MHz input
localparam [1:0] PLL_PROFILE = 2'd3; // 0:30Hz, 1:40Hz, 2:50Hz, 3:60Hz
function integer get_hdmi_freq;
    input [1:0] p;
    begin
        case (p)
            2'd0: get_hdmi_freq = 74_250_000;   // 1080p30 / 720p60 pixel clock
            2'd1: get_hdmi_freq = 99_000_000;   // 1080p40 pixel clock
            2'd2: get_hdmi_freq = 123_750_000;  // 1080p50 pixel clock
            2'd3: get_hdmi_freq = 148_500_000;  // 1080p60 / 2k30 pixel clock
            default: get_hdmi_freq = 74_250_000;
        endcase
    end
endfunction
localparam HDMI_FREQ = get_hdmi_freq(PLL_PROFILE);
localparam HDMI_FREQ_5X = HDMI_FREQ * 5;
localparam integer TMDS_ALIGN_LATENCY = 2; // line-buffer read data is registered once more before TMDS encoding

// HDMI config
// 1080p
localparam integer 
    H_ACTIVE = 1920,
    H_FRONT_PORCH = 88,
    H_SYNC_PULSE = 44,
    H_BACK_PORCH = 148,
    V_ACTIVE = 1080,
    V_FRONT_PORCH = 4,
    V_SYNC_PULSE = 5,
    V_BACK_PORCH = 36;

// 720p
/*
localparam integer 
    H_ACTIVE = 1280,
    H_FRONT_PORCH = 110,
    H_SYNC_PULSE = 40,
    H_BACK_PORCH = 220,
    V_ACTIVE = 720,
    V_FRONT_PORCH = 5,
    V_SYNC_PULSE = 5,
    V_BACK_PORCH = 20;
*/

// Derived timing parameters
localparam integer
    H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH,
    V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;


// Initial values for registers

// Generate HDMI clock using PLL and clock divider
wire lock;
wire clk_hdmi;
wire clk_hdmi_5x;
wire hdmi_rst_n;

reg [31:0] htmi_cnt;
reg [25:0] led_cnt;

// Video timing generator signals
wire hsync, vsync, de;
wire [11:0] x, y;
wire frame_end;
reg [TMDS_ALIGN_LATENCY-1:0] de_pipe, hsync_pipe, vsync_pipe;
integer i;

wire de_tmds, hsync_tmds, vsync_tmds;

// RGB output from pattern generator / line buffer
reg [23:0] rgb;
wire [23:0] rgb_from_buf;
wire [9:0] tmds_r, tmds_g, tmds_b;
wire serial_clk, serial_r, serial_g, serial_b;

// assign hdmi_rst_n = lock;
assign hdmi_rst_n = rst_n && lock; // Hold HDMI domain in reset until PLL locks

assign de_tmds = de_pipe[TMDS_ALIGN_LATENCY-1];
assign hsync_tmds = hsync_pipe[TMDS_ALIGN_LATENCY-1];
assign vsync_tmds = vsync_pipe[TMDS_ALIGN_LATENCY-1];

// Counter to generate a 1-second tick based on HDMI frequency
always @(posedge clk_hdmi or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n) htmi_cnt <= 32'd0;
    else begin
        if(htmi_cnt == HDMI_FREQ) htmi_cnt <= 32'd0; // Reset counter after reaching HDMI frequency
        else htmi_cnt <= htmi_cnt + 1;
    end
end

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


// 1: PLL and clock generation
// Generate System clock (~166.5MHz) and CPU clock (~83.25MHz) from 27MHz using rPLL_SYS
wire clk_sys;    // ~166.5MHz
wire clk_sys_90; // ~166.5MHz with 90-degree phase shift
wire clk_cpu;    // ~83.25MHz
wire lock_sys;
rPLL_SYS rpll_sys(
    .clkin(clk),
    .clkout(clk_sys),
    .clkoutp(clk_sys_90),
    .clkoutd(clk_cpu),
    .lock(lock_sys)
);

// Generate HDMI clock (e.g. 148.5MHz for 1080p60) from the input 27MHz using rPLL_HDMI
rPLL_HDMI #(
    .PROFILE(PLL_PROFILE)
) pll_hdmi(
    .clkout(clk_hdmi_5x),
    .lock(lock),
    .clkin(clk)
);
Gowin_CLKDIV clkdiv_hdmi(
    .clkout(clk_hdmi), //output clkout
    .hclkin(clk_hdmi_5x), //input hclkin
    .resetn(hdmi_rst_n) //input resetn
);

// 2: Instantiate video timing generator (1920x1080 timing)
vid_timing_gen #(
    .H_ACTIVE(H_ACTIVE),
    .H_FRONT_PORCH(H_FRONT_PORCH),
    .H_SYNC_PULSE(H_SYNC_PULSE),
    .H_BACK_PORCH(H_BACK_PORCH),
    .V_ACTIVE(V_ACTIVE),
    .V_FRONT_PORCH(V_FRONT_PORCH),
    .V_SYNC_PULSE(V_SYNC_PULSE),
    .V_BACK_PORCH(V_BACK_PORCH)
) vid_timing(
    .clk_hdmi(clk_hdmi),
    .rst_n(hdmi_rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .de(de),
    .x(x),
    .y(y),
    .frame_end(frame_end)
);

///////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// PATTERN GENERATOR ////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// 3: Pattern generator output goes through line buffer before TMDS encoding
// Pattern generator now self-generates x,y coordinates in clk_sys domain (no CDC)
wire [23:0] rgb_pattern_o;
wire [11:0] pg_x, pg_y;  // Pattern generator's internal coordinates
wire ptrn_ve;
wire fifo_w_en;
pattern_gen #(
    .H_ACTIVE(H_ACTIVE),
    .V_ACTIVE(V_ACTIVE)
) test_pattern (
    .clk(clk_sys),
    .rst_n(rst_n),
    .ready(!fifo_almost_full), // Backpressure from line buffer FIFO
    .frame_pulse(frame_pulse), // Pulse at the start of each frame for synchronization
    .x(pg_x),
    .y(pg_y),
    .rgb_o(rgb_pattern_o), // Connect to TMDS encoder later
    .ve(ptrn_ve)
);

// Vsync to reset pattern generator at the start of each frame 
reg [2:0] vsync_sync_sys;
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) vsync_sync_sys <= 3'b000;
    else vsync_sync_sys <= {vsync_sync_sys[1:0], vsync};
end
wire frame_pulse = vsync_sync_sys[1] && !vsync_sync_sys[2];


// Line buffer to align video data with TMDS encoding timing (1 line buffer depth is sufficient for 720p/1080p)
wire fifo_full, fifo_empty;
wire fifo_almost_full, fifo_almost_empty;
wire fifo_rd_valid;
assign fifo_rd_valid = de && !fifo_empty;
async_fifo #(
    .ADDRESS_WIDTH(12), // 4096 entries, enough for one line of 1080p (1920 pixels)
    .DATA_WIDTH(16)
) hdmi_line_buf_fifo (
    .w_clk(clk_sys),
    .w_rst_n(rst_n),
    .w_en(!fifo_almost_full),
    .w_data(rgb_pattern_o_565),
    .full(fifo_full),
    .almost_full(fifo_almost_full),

    .r_clk(clk_hdmi),
    .r_rst_n(hdmi_rst_n),
    .r_en(fifo_rd_valid),
    .r_data(rgb_from_buf_565),
    .empty(fifo_empty),
    .almost_empty(fifo_almost_empty)
);


// Dither RGB888 pattern output to RGB565 for HDMI line buffer
// Use pattern generator's self-generated coordinates (no CDC issue)
wire [15:0] rgb_pattern_o_565;
wire [15:0] rgb_from_buf_565;
dither_rgb888_to_565 u_dither (
    .rgb888(rgb_pattern_o),
    .x(pg_x),
    .y(pg_y),
    .rgb565(rgb_pattern_o_565) 
);

///////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////// TMDS AND OUTPUT //////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

// Upscale RGB565 from line buffer to RGB888 for TMDS encoding
wire [23:0] rgb565_upscale_888 = {
	{rgb_from_buf_565[15:11], rgb_from_buf_565[15:13]},
	{rgb_from_buf_565[10:5], rgb_from_buf_565[10:9]},
	{rgb_from_buf_565[4:0], rgb_from_buf_565[4:2]}
};

// 4: Instantiate TMDS encoders for RGB channels
tmds_encoder tmds_encoder_r(
    .clk_hdmi(clk_hdmi),
    .rst_n(hdmi_rst_n),
    .de(de_tmds),
    .data_i(rgb565_upscale_888[23:16]),
    .ctrl_i(2'b00),
    .tmds_o(tmds_r)
);
tmds_encoder tmds_encoder_g(
    .clk_hdmi(clk_hdmi),
    .rst_n(hdmi_rst_n),
    .de(de_tmds),
    .data_i(rgb565_upscale_888[15:8]),
    .ctrl_i(2'b00),
    .tmds_o(tmds_g)
);
tmds_encoder tmds_encoder_b(
    .clk_hdmi(clk_hdmi),
    .rst_n(hdmi_rst_n),
    .de(de_tmds),
    .data_i(rgb565_upscale_888[7:0]),
    .ctrl_i({vsync_tmds, hsync_tmds}),
    .tmds_o(tmds_b)
);

// Unified control-signal alignment pipeline for TMDS.
always @(posedge clk_hdmi or negedge hdmi_rst_n) begin
    if (!hdmi_rst_n) begin
        de_pipe <= {TMDS_ALIGN_LATENCY{1'b0}};
        hsync_pipe <= {TMDS_ALIGN_LATENCY{1'b0}};
        vsync_pipe <= {TMDS_ALIGN_LATENCY{1'b0}};
    end else begin
        de_pipe[0] <= fifo_rd_valid;
        hsync_pipe[0] <= hsync;
        vsync_pipe[0] <= vsync;
        for (i = 1; i < TMDS_ALIGN_LATENCY; i = i + 1) begin
            de_pipe[i] <= de_pipe[i-1];
            hsync_pipe[i] <= hsync_pipe[i-1];
            vsync_pipe[i] <= vsync_pipe[i-1];
        end
    end
end

// 5: Connect TMDS outputs to HDMI output pins (not shown here, depends on board pinout)
serlizer_10to1 u_ser_clk (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (hdmi_rst_n),
    .parallel_i  (10'b0000011111),   // Control code for clock channel
    .serial_o    (serial_clk)
);
serlizer_10to1 u_ser_r (.clk_hdmi (clk_hdmi), .clk_hdmi_5x (clk_hdmi_5x), .rst_n (hdmi_rst_n), .parallel_i (tmds_r), .serial_o (serial_r));
serlizer_10to1 u_ser_g (.clk_hdmi (clk_hdmi), .clk_hdmi_5x (clk_hdmi_5x), .rst_n (hdmi_rst_n), .parallel_i (tmds_g), .serial_o (serial_g));
serlizer_10to1 u_ser_b (.clk_hdmi (clk_hdmi), .clk_hdmi_5x (clk_hdmi_5x), .rst_n (hdmi_rst_n), .parallel_i (tmds_b), .serial_o (serial_b));

// 6: Connect serialized outputs to HDMI output pins using differential buffers (not shown here, depends on board pinout)
ELVDS_OBUF u_obuf_clk (.I (serial_clk), .O (tmds_clk_p), .OB (tmds_clk_n));
ELVDS_OBUF u_obuf_r (.I (serial_r), .O (tmds_data2_p), .OB (tmds_data2_n));
ELVDS_OBUF u_obuf_g (.I (serial_g), .O (tmds_data1_p), .OB (tmds_data1_n));
ELVDS_OBUF u_obuf_b (.I (serial_b), .O (tmds_data0_p), .OB (tmds_data0_n));

endmodule