module hdmi_top #(
    parameter integer H_ACTIVE = 1920,
    parameter integer H_FRONT_PORCH = 88,
    parameter integer H_SYNC_PULSE = 44,
    parameter integer H_BACK_PORCH = 148,
    parameter integer V_ACTIVE = 1080,
    parameter integer V_FRONT_PORCH = 4,
    parameter integer V_SYNC_PULSE = 5,
    parameter integer V_BACK_PORCH = 36,
    parameter integer TMDS_ALIGN_LATENCY = 5
)(
    input  wire        clk_hdmi,
    input  wire        clk_hdmi_5x,
    input  wire        rst_n,
    input  wire [15:0] rgb565_i,
    output wire        de_o,
    output wire        vsync_o,
    output wire        frame_end_o,

    output wire tmds_clk_p,
    output wire tmds_clk_n,
    output wire tmds_data0_p,
    output wire tmds_data0_n,
    output wire tmds_data1_p,
    output wire tmds_data1_n,
    output wire tmds_data2_p,
    output wire tmds_data2_n
);

// Internal reset signal synchronized to clk_hdmi domain
wire hsync, vsync;
wire de;
wire [11:0] x, y;
wire frame_end;

reg [TMDS_ALIGN_LATENCY-1:0] de_pipe;
reg [TMDS_ALIGN_LATENCY-1:0] hsync_pipe, vsync_pipe;
integer i;

wire [9:0] tmds_r, tmds_g, tmds_b;
wire serial_clk;
wire serial_r, serial_g, serial_b;

wire de_tmds = de_pipe[TMDS_ALIGN_LATENCY-1];
wire hsync_tmds = hsync_pipe[TMDS_ALIGN_LATENCY-1];
wire vsync_tmds = vsync_pipe[TMDS_ALIGN_LATENCY-1];

 // Upscale RGB565 from line buffer to RGB888 for TMDS encoding
wire [23:0] rgb565_upscale_888 = {
    {rgb565_i[15:11], rgb565_i[15:13]},
    {rgb565_i[10:5],  rgb565_i[10:9]},
    {rgb565_i[4:0],   rgb565_i[4:2]}
};

// TMDS encoding and serialization logic will be here (not shown for brevity, see below for details)
assign de_o = de;
assign vsync_o = vsync;
assign frame_end_o = frame_end;

// Generate video timing signals
vid_timing_gen #(
    .H_ACTIVE(H_ACTIVE),
    .H_FRONT_PORCH(H_FRONT_PORCH),
    .H_SYNC_PULSE(H_SYNC_PULSE),
    .H_BACK_PORCH(H_BACK_PORCH),
    .V_ACTIVE(V_ACTIVE),
    .V_FRONT_PORCH(V_FRONT_PORCH),
    .V_SYNC_PULSE(V_SYNC_PULSE),
    .V_BACK_PORCH(V_BACK_PORCH)
) vid_timing (
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .de(de),
    .x(x),
    .y(y),
    .frame_end(frame_end)
);

// Instantiate TMDS encoders for RGB channels
tmds_encoder tmds_encoder_r(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de_tmds),
    .data_i(rgb565_upscale_888[23:16]),
    .ctrl_i(2'b00),
    .tmds_o(tmds_r)
);
tmds_encoder tmds_encoder_g(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de_tmds),
    .data_i(rgb565_upscale_888[15:8]),
    .ctrl_i(2'b00),
    .tmds_o(tmds_g)
);
tmds_encoder tmds_encoder_b(
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de_tmds),
    .data_i(rgb565_upscale_888[7:0]),
    .ctrl_i({vsync_tmds, hsync_tmds}),
    .tmds_o(tmds_b)
);

// Unified control-signal alignment pipeline for TMDS.
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) begin
        de_pipe <= {TMDS_ALIGN_LATENCY{1'b0}};
        hsync_pipe <= {TMDS_ALIGN_LATENCY{1'b0}};
        vsync_pipe <= {TMDS_ALIGN_LATENCY{1'b0}};
    end else begin
        de_pipe[0] <= de;
        hsync_pipe[0] <= hsync;
        vsync_pipe[0] <= vsync;
        for (i = 1; i < TMDS_ALIGN_LATENCY; i = i + 1) begin
            de_pipe[i] <= de_pipe[i-1];
            hsync_pipe[i] <= hsync_pipe[i-1];
            vsync_pipe[i] <= vsync_pipe[i-1];
        end
    end
end

// Connect TMDS outputs to HDMI output pins (not shown here, depends on board pinout)
serlizer_10to1 u_ser_clk (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n),
    .parallel_i  (10'b0000011111),
    .serial_o    (serial_clk)
);
serlizer_10to1 u_ser_r (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n),
    .parallel_i  (tmds_r),
    .serial_o    (serial_r)
);
serlizer_10to1 u_ser_g (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n),
    .parallel_i  (tmds_g),
    .serial_o    (serial_g)
);
serlizer_10to1 u_ser_b (
    .clk_hdmi    (clk_hdmi),
    .clk_hdmi_5x (clk_hdmi_5x),
    .rst_n       (rst_n),
    .parallel_i  (tmds_b),
    .serial_o    (serial_b)
);

// Connect serialized outputs to HDMI output pins using differential buffers (not shown here, depends on board pinout)
ELVDS_OBUF u_obuf_clk (.I(serial_clk), .O(tmds_clk_p),   .OB(tmds_clk_n));
ELVDS_OBUF u_obuf_r   (.I(serial_r),   .O(tmds_data2_p), .OB(tmds_data2_n));
ELVDS_OBUF u_obuf_g   (.I(serial_g),   .O(tmds_data1_p), .OB(tmds_data1_n));
ELVDS_OBUF u_obuf_b   (.I(serial_b),   .O(tmds_data0_p), .OB(tmds_data0_n));

endmodule
