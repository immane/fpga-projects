module main(
    input clk,              // 27MHz input clock
    input rst_key_n,        // Active-low reset button

    // Diagnostic LEDs (e.g. PLL lock status, frame counter MSB)
    output wire [5:0]led,

    // HDMI output signals
    output wire tmds_clk_p, 
    output wire tmds_clk_n, // TMDS clock pair
    output wire tmds_data0_p, 
    output wire tmds_data0_n,  // Blue
    output wire tmds_data1_p, 
    output wire tmds_data1_n,  // Green
    output wire tmds_data2_p, 
    output wire tmds_data2_n,  // Red

    // SDRAM physical interface
    // "Magic" port names that the gowin compiler connects to the on-chip SDRAM
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [31:0] IO_sdram_dq,       // 32 bit bidirectional data bus
    output [10:0] O_sdram_addr,     // 11 bit multiplexed address bus
    output [1:0] O_sdram_ba,        // two banks
    output [3:0] O_sdram_dqm        // 32/4
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


// LED diagnostic. Tang Nano 20K LEDs are active-low.
reg [25:0] led_cnt;
always @(posedge clk) begin
    led_cnt <= led_cnt + 26'd1;
end
assign led[5] = (!lock) ? led_cnt[22] : led_cnt[24];

// led[1]: SDRAM initialized, led[2]: HDMI FIFO underflow (sticky),
// led[3]: SDRAM stream prefilled, led[4]: system PLL locked.
assign led[1] = ~sdrc_init_done;
assign led[2] = ~fifo_underflow;
assign led[3] = ~stream_ready;
assign led[4] = ~lock_sys;

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
wire hdmi_clk_rst_n;
wire video_rst_n;
wire lock;
wire lock_sys;
wire stream_ready;
wire sdrc_init_done;
reg  fifo_underflow;

assign hdmi_clk_rst_n = rst_n && lock;

timing #(
    .PLL_PROFILE(2'd3) // 1080p60
) u_timing (
    .clk(clk),
    .rst_n(rst_n),
    .hdmi_rst_n(hdmi_clk_rst_n),
    .clk_sys(clk_sys),
    .clk_sys_90(clk_sys_90),
    .clk_cpu(clk_cpu),
    .clk_hdmi(clk_hdmi),
    .clk_hdmi_5x(clk_hdmi_5x),
    .lock(lock),
    .lock_sys(lock_sys)
);

// Use the same PLL-qualified reset for the HS IP, its user scheduler, the
// source-side pipeline, and the FIFO write domain.
reg [1:0] sdrc_rst_sync;
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n)         sdrc_rst_sync <= 2'b00;
    else if (!lock_sys) sdrc_rst_sync <= 2'b00;
    else                sdrc_rst_sync <= {sdrc_rst_sync[0], 1'b1};
end
wire sdrc_rst_n = sdrc_rst_sync[1];

// Keep the pixel timing generator reset until SDRAM has prefilled the async
// FIFO. CLKDIV itself is released as soon as the HDMI PLL locks.
reg [1:0] video_rst_sync;
always @(posedge clk_hdmi or negedge hdmi_clk_rst_n) begin
    if (!hdmi_clk_rst_n) video_rst_sync <= 2'b00;
    else                 video_rst_sync <= {video_rst_sync[0], stream_ready};
end
assign video_rst_n = video_rst_sync[1];


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
    .rst_n(sdrc_rst_n),
    .ready(wr_ready),
    .frame_pulse(1'b0),
    .x(x),
    .y(y),
    .rgb_o(rgb_ptrn_o), // Connect to TMDS encoder later
    .ve(ptrn_ve)
);


// Vsync crossing is retained for frame diagnostics. The source wraps after
// exactly H_ACTIVE*V_ACTIVE accepted pixels and must not be reset while data
// remains buffered in SDRAM.
wire vsync_hdmi;
reg [2:0] vsync_sys;
always @(posedge clk_sys or negedge rst_n) begin
    if (!rst_n) vsync_sys <= 3'b000;
    else vsync_sys <= {vsync_sys[1:0], vsync_hdmi};
end
wire frame_pulse = vsync_sys[1] && !vsync_sys[2];


// Line buffer to align video data with TMDS encoding timing (1 line buffer depth is sufficient for 720p/1080p)
wire de_hdmi;
wire fifo_full, fifo_empty;
wire fifo_almost_full, fifo_almost_empty;
async_fifo #(
    .ADDRESS_WIDTH(12), // 4096 entries, enough for one line of 1080p (1920 pixels)
    .DATA_WIDTH(16)
) hdmi_line_buf_fifo (
    .w_clk(clk_sys),
    .w_rst_n(sdrc_rst_n),
    .w_en(rd_pix_valid && !fifo_full),
    .w_data(rd_pix),
    .full(fifo_full),
    .almost_full(fifo_almost_full),

    .r_clk(clk_hdmi),
    .r_rst_n(video_rst_n),
    .r_en(de_hdmi && !fifo_empty),
    .r_data(rgb_from_buf_565),
    .empty(fifo_empty),
    .almost_empty(fifo_almost_empty)
);

always @(posedge clk_hdmi or negedge video_rst_n) begin
    if (!video_rst_n) fifo_underflow <= 1'b0;
    else if (de_hdmi && fifo_empty) fifo_underflow <= 1'b1;
end


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
wire frame_end_hdmi;
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
    .rst_n(video_rst_n),
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

// SDRAM controller inter-module wires (use sdrc_* naming to match IP signals)
wire        sdrc_cmd_ack;
wire [2:0]  sdrc_cmd;
wire        sdrc_cmd_en;
wire [20:0] sdrc_addr;
wire [31:0] sdrc_wdata;
wire [7:0]  sdrc_data_len;
wire [31:0] sdrc_rdata;
wire [15:0] rd_pix;
wire        rd_pix_valid;
wire        wr_ready;

// 1920*1080 RGB565 pixels occupy 1,036,800 32-bit SDRAM words.
sdram_user_ctrl #(
    .BURST_SIZE(64),
    .CLK_FREQ_HZ(166_500_000),
    .FRAME_WORDS(1_036_800),
    .MAX_PENDING_BURSTS(64),
    .PREFILL_PIXELS(2048)
) u_sdram_user_ctrl (
    .clk        (clk_sys),
    .rst_n      (sdrc_rst_n),
    .init_done  (sdrc_init_done),
    .cmd_ack    (sdrc_cmd_ack),
    .pix_valid  (ptrn_ve),
    .pix_data   (rgb_ptrn_out_565),
    .user_cmd   (sdrc_cmd),
    .user_cmd_en(sdrc_cmd_en),
    .user_addr  (sdrc_addr),
    .user_data  (sdrc_wdata),
    .user_len   (sdrc_data_len),
    .read_data  (sdrc_rdata),
    .rd_pix     (rd_pix),
    .rd_pix_valid(rd_pix_valid),
    .rd_ready   (!fifo_almost_full),
    .wr_ready   (wr_ready),
    .stream_ready(stream_ready)
);

// SDRAM controller IP
SDRAM_Controller_HS_Top u_sdram_ctrl (
    .I_sdrc_rst_n         (sdrc_rst_n),
    .I_sdrc_clk           (clk_sys),
    .I_sdram_clk          (clk_sys_90),
    .I_sdrc_cmd_en        (sdrc_cmd_en),
    .I_sdrc_cmd           (sdrc_cmd),
    .I_sdrc_precharge_ctrl(1'b0),
    .I_sdram_power_down   (1'b0),
    .I_sdram_selfrefresh  (1'b0),
    .I_sdrc_addr          (sdrc_addr),
    .I_sdrc_dqm           (4'b0000),
    .I_sdrc_data          (sdrc_wdata),
    .I_sdrc_data_len      (sdrc_data_len),
    .O_sdram_clk          (O_sdram_clk),
    .O_sdram_cke          (O_sdram_cke),
    .O_sdram_cs_n         (O_sdram_cs_n),
    .O_sdram_cas_n        (O_sdram_cas_n),
    .O_sdram_ras_n        (O_sdram_ras_n),
    .O_sdram_wen_n        (O_sdram_wen_n),
    .O_sdram_dqm          (O_sdram_dqm),
    .O_sdram_addr         (O_sdram_addr),
    .O_sdram_ba           (O_sdram_ba),
    .O_sdrc_data          (sdrc_rdata),
    .O_sdrc_init_done     (sdrc_init_done),
    .O_sdrc_cmd_ack       (sdrc_cmd_ack),
    .IO_sdram_dq          (IO_sdram_dq)
);

endmodule
