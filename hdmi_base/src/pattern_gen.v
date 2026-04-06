module pattern_gen # (
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720
) (
    input wire clk_hdmi,
    input wire rst_n,

    input wire [11:0] x,
    input wire [11:0] y,
    input wire de,
    input wire frame_end,

    output reg [23:0] rgb_o
);

localparam integer BAND_H = V_ACTIVE / 9;

// Generate a simple color pattern based on the pixel position and frame count
reg [23:0] frame_cnt;
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n)
        frame_cnt <= 24'd0;
    else if (frame_end)
        frame_cnt <= frame_cnt + 24'd1;
end

// Update RGB output: 9 horizontal bands (top->bottom):
// red, orange, yellow, green, cyan, blue, purple, black, white.
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n)
        rgb_o <= 24'h000000;
    else if (!de)
        rgb_o <= 24'h000000;
    else begin
        if (y < BAND_H * 1)
            rgb_o <= 24'hFF0000; // red
        else if (y < BAND_H * 2)
            rgb_o <= 24'hFF8000; // orange
        else if (y < BAND_H * 3)
            rgb_o <= 24'hFFFF00; // yellow
        else if (y < BAND_H * 4)
            rgb_o <= 24'h00FF00; // green
        else if (y < BAND_H * 5)
            rgb_o <= 24'h00FFFF; // cyan
        else if (y < BAND_H * 6)
            rgb_o <= 24'h0000FF; // blue
        else if (y < BAND_H * 7)
            rgb_o <= 24'h8000FF; // purple
        else if (y < BAND_H * 8)
            rgb_o <= 24'h000000; // black
        else
            rgb_o <= 24'hFFFFFF; // white
    end
end 
endmodule