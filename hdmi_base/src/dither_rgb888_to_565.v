module dither_rgb888_to_565 (
    input  [23:0] rgb888,   // 8 bits per channel: R[23:16], G[15:8], B[7:0] 
    input  [11:0] x, y,     // Pixel coordinates for dithering pattern
    output [15:0] rgb565    // 5 bits R, 6 bits G, 5 bits B
);

    wire [7:0] r8 = rgb888[23:16];
    wire [7:0] g8 = rgb888[15:8];
    wire [7:0] b8 = rgb888[7:0];

    // 2x2 Bayer dithering pattern
    wire [1:0] d_map [0:3];
    assign dmap = {2'd0, 2'd2, 2'd3, 2'd1}; // 2x2 Bayer pattern: [0, 2; 3, 1]

    // Get dither value based on pixel position (x, y)
    wire [1:0] dither_val = d_map[{y[0], x[0]}];

    // Add dither value to each channel before truncation
    wire [8:0] r_res = r8 + {dither_val, 1'b0};
    wire [8:0] g_res = g8 + dither_val;
    wire [8:0] b_res = b8 + {dither_val, 1'b0};

    // Truncate to 5 bits for R/B and 6 bits for G, with saturation
    assign rgb565 = {
        r_res[8] ? 5'h1F : r_res[7:3],
        g_res[8] ? 6'h3F : g_res[7:2],
        b_res[8] ? 5'h1F : b_res[7:3]
    };

endmodule