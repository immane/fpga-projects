module pattern_gen # (
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720
) (
    input wire clk,
    input wire [11:0] x,
    input wire [11:0] y,
    output reg [23:0] rgb_o
);
    // Define vertical band width for 9 color bands
    localparam integer BAND_H = H_ACTIVE / 9;

    // Update RGB output: 9 vertical bands (left->right):
    // red, orange, yellow, green, cyan, blue, purple, black, white.
    always @(posedge clk) begin
        if (x < BAND_H * 1)
            rgb_o <= 24'hFF0000; // red
        else if (x < BAND_H * 2)
            rgb_o <= 24'hFF8000; // orange
        else if (x < BAND_H * 3)
            rgb_o <= 24'hFFFF00; // yellow
        else if (x < BAND_H * 4)
            rgb_o <= 24'h00FF00; // green
        else if (x < BAND_H * 5)
            rgb_o <= 24'h00FFFF; // cyan
        else if (x < BAND_H * 6)
            rgb_o <= 24'h0000FF; // blue
        else if (x < BAND_H * 7)
            rgb_o <= 24'h8000FF; // purple
        else if (x < BAND_H * 8)
            rgb_o <= 24'hFFFFFF; // white
        else
            rgb_o <= 24'h000000; // black
    end 
endmodule