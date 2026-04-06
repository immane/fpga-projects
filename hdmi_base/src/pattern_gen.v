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

// Generate a simple color pattern based on the pixel position and frame count
reg [23:0] frame_cnt;
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n)
        frame_cnt <= 24'd0;
    else if (frame_end)
        frame_cnt <= frame_cnt + 24'd1;
end

// Update RGB output based on the current pixel position and frame count
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n)
        rgb_o <= 24'h000000;
    else if (!de)
        rgb_o <= 24'h000000;
    else begin
        // Create a simple color pattern that changes every frame and varies across the screen
        // One example: Use the upper bits of x to create vertical color bands, and frame count to animate
        // Test for 720p: 1280x720, so x[9:7] gives us 8 vertical bands (1280/8 = 160 pixels per band)
        case (x[9:7])
            3'b000: rgb_o <= 24'hFF0000 ^ {frame_cnt[7:0], 16'h0000};
            3'b001: rgb_o <= 24'h00FF00 ^ {8'h00, frame_cnt[7:0], 8'h00};
            3'b010: rgb_o <= 24'h0000FF ^ {16'h0000, frame_cnt[7:0]};
            3'b011: rgb_o <= 24'h00FFFF ^ {frame_cnt[7:0], 8'h00, 8'h00};
            3'b100: rgb_o <= 24'hFF00FF ^ {8'h00, frame_cnt[7:0], 8'h00};
            3'b101: rgb_o <= 24'hFFFF00 ^ {16'h0000, frame_cnt[7:0]};
            default: rgb_o <= {x[7:0], y[7:0], frame_cnt[7:0]};
        endcase
    end
end 
endmodule