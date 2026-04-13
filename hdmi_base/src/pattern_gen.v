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
    // Generate test patterns based on self-generated x,y coordinates.
    // This avoids any CDC complexity by keeping pattern generation in the clk_sys domain.
    wire active_area = (x_cnt < H_ACTIVE) && (y_cnt < V_ACTIVE);

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

    reg [2:0] bar_idx;
    reg [2:0] grid_idx;
    reg [7:0] gray_level;
    reg checker_pix;
    integer grid_col;
    integer grid_row;

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
            ve <= ready && active_area;  // Only assert VE during active area when ready

            if (ready && active_area) begin
                if (x >= H_ACTIVE || y >= V_ACTIVE) begin
                    rgb_o <= 24'h000000;
                end else if (PATTERN_MODE == 0) begin
                    grid_col = (x * GRID_COLS) / H_ACTIVE;
                    grid_row = (y * GRID_ROWS) / V_ACTIVE;
                    grid_idx = (grid_col + grid_row) & 3'h7;
                    rgb_o <= palette_color(grid_idx);
                end else begin
                    bar_idx = (x * 8) / H_ACTIVE;

                    if (y < (V_ACTIVE * 2) / 3) begin
                        // Top: 75% style color bars.
                        rgb_o <= palette_color(bar_idx);
                    end else if (y < (V_ACTIVE * 5) / 6) begin
                        // Middle: full grayscale ramp for banding and gamma checks.
                        gray_level = (x * 255) / (H_ACTIVE - 1);
                        rgb_o <= {gray_level, gray_level, gray_level};
                    end else begin
                        // Bottom-left: near-black PLUGE bars for black-level validation.
                        if (x < (H_ACTIVE / 8)) begin
                            if (x < (H_ACTIVE / 24))
                                rgb_o <= 24'h101010;
                            else if (x < (H_ACTIVE / 12))
                                rgb_o <= 24'h202020;
                            else
                                rgb_o <= 24'h404040;
                        end else begin
                            // Bottom-right: checkerboard for sampling and detail stability checks.
                            checker_pix = x[5] ^ y[5];
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