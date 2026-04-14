module pattern_gen # (
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter PATTERN_MODE = 1 // 0: uniform color grid, 1: HDMI diagnostic pattern
) (
    input wire clk,
    input wire rst_n,
    input wire ready,
    input wire frame_pulse,     // Indicates start of new frame for synchronization (optional)
    output reg [11:0] x,        // Internal self-generated x coordinate (no CDC)
    output reg [11:0] y,        // Internal self-generated y coordinate (no CDC)
    output reg [23:0] rgb_o,
    output reg ve
);
    // Self-generate x, y coordinates with full frame timing (active + blanking).
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end else if (frame_pulse) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end else if (ready) begin
            if (x_cnt == H_ACTIVE - 1) begin
                x_cnt <= 0;
                y_cnt <= (y_cnt == V_ACTIVE - 1) ? 0 : y_cnt + 1;
            end else begin
                x_cnt <= x_cnt + 1;
            end
        end
    end


    localparam integer GRID_COLS = 8;
    localparam integer GRID_ROWS = 4;

    // Region boundaries (compile-time only), used to avoid runtime divide paths.
    localparam integer X_T1 = (H_ACTIVE * 1) / 8;
    localparam integer X_T2 = (H_ACTIVE * 2) / 8;
    localparam integer X_T3 = (H_ACTIVE * 3) / 8;
    localparam integer X_T4 = (H_ACTIVE * 4) / 8;
    localparam integer X_T5 = (H_ACTIVE * 5) / 8;
    localparam integer X_T6 = (H_ACTIVE * 6) / 8;
    localparam integer X_T7 = (H_ACTIVE * 7) / 8;

    localparam integer Y_Q1 = (V_ACTIVE * 1) / 4;
    localparam integer Y_Q2 = (V_ACTIVE * 2) / 4;
    localparam integer Y_Q3 = (V_ACTIVE * 3) / 4;

    localparam integer Y_2_3 = (V_ACTIVE * 2) / 3;
    localparam integer Y_5_6 = (V_ACTIVE * 5) / 6;

    localparam integer PLUGE_1 = H_ACTIVE / 24;
    localparam integer PLUGE_2 = H_ACTIVE / 12;
    localparam integer PLUGE_3 = H_ACTIVE / 8;

    // Grayscale: replace (x*255)/(H_ACTIVE-1) with constant-scale multiply+shift.
    localparam integer GRAY_SHIFT = 12;
    localparam integer GRAY_SCALE = ((255 << GRAY_SHIFT) + ((H_ACTIVE - 1) / 2)) / (H_ACTIVE - 1);

    reg [2:0] bar_idx;
    reg [2:0] grid_idx;
    reg [1:0] grid_row_idx;
    reg [7:0] gray_level;
    reg checker_pix;

    function [2:0] x_bin8;
        input [11:0] xin;
        begin
            if (xin < X_T1) x_bin8 = 3'd0;
            else if (xin < X_T2) x_bin8 = 3'd1;
            else if (xin < X_T3) x_bin8 = 3'd2;
            else if (xin < X_T4) x_bin8 = 3'd3;
            else if (xin < X_T5) x_bin8 = 3'd4;
            else if (xin < X_T6) x_bin8 = 3'd5;
            else if (xin < X_T7) x_bin8 = 3'd6;
            else x_bin8 = 3'd7;
        end
    endfunction

    function [1:0] y_bin4;
        input [11:0] yin;
        begin
            if (yin < Y_Q1) y_bin4 = 2'd0;
            else if (yin < Y_Q2) y_bin4 = 2'd1;
            else if (yin < Y_Q3) y_bin4 = 2'd2;
            else y_bin4 = 2'd3;
        end
    endfunction

    // PATTERN_MODE=0 gives uniform color blocks.
    // PATTERN_MODE=1 gives an HDMI diagnostic pattern: bars + grayscale + checker/pluge.
    always @(posedge clk or negedge rst_n) begin
         if (!rst_n) begin
            x     <= 0;
            y     <= 0;
            rgb_o <= 24'h000000;
            ve    <= 1'b0;
        end else begin
            x <= x_cnt;
            y <= y_cnt;
            ve <= ready; // Only assert VE during active area when ready

            if (ready) begin
                if (x_cnt >= H_ACTIVE || y_cnt >= V_ACTIVE) begin
                    rgb_o <= 24'h000000;
                end else if (PATTERN_MODE == 0) begin
                    grid_idx = x_bin8(x_cnt);
                    grid_row_idx = y_bin4(y_cnt);
                    grid_idx = (x_bin8(x_cnt) + {1'b0, y_bin4(y_cnt)}) & 3'h7;
                    rgb_o <= palette_color(grid_idx);
                end else begin
                    bar_idx = x_bin8(x_cnt);

                    if (y_cnt < Y_2_3) begin
                        // Top: 75% style color bars.
                        rgb_o <= palette_color(bar_idx);
                    end else if (y_cnt < Y_5_6) begin
                        // Middle: full grayscale ramp for banding and gamma checks.
                        gray_level = (x_cnt * GRAY_SCALE) >> GRAY_SHIFT;
                        rgb_o <= {gray_level, gray_level, gray_level};
                    end else begin
                        // Bottom-left: near-black PLUGE bars for black-level validation.
                        if (x_cnt < PLUGE_3) begin
                            if (x_cnt < PLUGE_1)
                                rgb_o <= 24'h101010;
                            else if (x_cnt < PLUGE_2)
                                rgb_o <= 24'h202020;
                            else
                                rgb_o <= 24'h404040;
                        end else begin
                            // Bottom-right: checkerboard for sampling and detail stability checks.
                            checker_pix = x_cnt[5] ^ y_cnt[5];
                            rgb_o <= checker_pix ? 24'hE0E0E0 : 24'h202020;
                        end
                    end
                end
            end
        end
    end

    function [23:0] palette_color;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: palette_color = 24'hFFFFFF; // white
                3'd1: palette_color = 24'hFFFF00; // yellow
                3'd2: palette_color = 24'h00FFFF; // cyan
                3'd3: palette_color = 24'h00FF00; // green
                3'd4: palette_color = 24'hFF00FF; // magenta
                3'd5: palette_color = 24'hFF0000; // red
                3'd6: palette_color = 24'h0000FF; // blue
                default: palette_color = 24'h000000; // black
            endcase
        end
    endfunction
endmodule