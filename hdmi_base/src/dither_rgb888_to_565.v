module dither_rgb888_to_565 #(
    parameter DITHER_EN = 1'b1,
    parameter PRESERVE_GRAY = 1'b1
) (
    input  [23:0] rgb888,   // 8 bits per channel: R[23:16], G[15:8], B[7:0] 
    input  [11:0] x, y,     // Pixel coordinates for dithering pattern
    output [15:0] rgb565    // 5 bits R, 6 bits G, 5 bits B
);

    wire [7:0] r8 = rgb888[23:16];
    wire [7:0] g8 = rgb888[15:8];
    wire [7:0] b8 = rgb888[7:0];

    wire is_gray = (r8 == g8) && (g8 == b8);

    // 2x2 Bayer pattern: [0,2; 3,1]
    wire [1:0] dither_idx = {y[0], x[0]};
    wire [1:0] dither_val = (dither_idx == 2'b00) ? 2'd0 :
                            (dither_idx == 2'b01) ? 2'd2 :
                            (dither_idx == 2'b10) ? 2'd3 :
                                                    2'd1;

    // Add dither value to each channel before truncation
    wire [8:0] r_res = r8 + {dither_val, 1'b0};
    wire [8:0] g_res = g8 + dither_val;
    wire [8:0] b_res = b8 + {dither_val, 1'b0};

    // Rounded quantization path (used when dithering is disabled and for grayscale protection)
    wire [5:0] r_round = ({1'b0, r8} + 6'd4) >> 3;
    wire [6:0] g_round = ({1'b0, g8} + 7'd2) >> 2;
    wire [5:0] b_round = ({1'b0, b8} + 6'd4) >> 3;

    wire [4:0] r_round_sat = r_round[5] ? 5'h1F : r_round[4:0];
    wire [5:0] g_round_sat = g_round[6] ? 6'h3F : g_round[5:0];
    wire [4:0] b_round_sat = b_round[5] ? 5'h1F : b_round[4:0];

    wire [5:0] y5_round = ({1'b0, r8} + 6'd4) >> 3;
    wire [6:0] y6_round = ({1'b0, r8} + 7'd2) >> 2;
    wire [4:0] y5_round_sat = y5_round[5] ? 5'h1F : y5_round[4:0];
    wire [5:0] y6_round_sat = y6_round[6] ? 6'h3F : y6_round[5:0];

    wire [15:0] rgb565_dither = {
        r_res[8] ? 5'h1F : r_res[7:3],
        g_res[8] ? 6'h3F : g_res[7:2],
        b_res[8] ? 5'h1F : b_res[7:3]
    };

    wire [15:0] rgb565_round = {r_round_sat, g_round_sat, b_round_sat};
    wire [15:0] rgb565_gray  = {y5_round_sat, y6_round_sat, y5_round_sat};

    assign rgb565 = (PRESERVE_GRAY && is_gray) ? rgb565_gray :
                    (DITHER_EN ? rgb565_dither : rgb565_round);

endmodule