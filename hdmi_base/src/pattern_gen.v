module pattern_gen # (
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720
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
    // Define vertical band width for 9 color bands
    localparam integer BAND = H_ACTIVE / 9;

    // Self-generate x, y coordinates with full frame timing (active + blanking).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_pulse) begin
            x <= 12'b0;
            y <= 12'b0;
            ve <= 1'b0;
        end else if (ready) begin
            ve <= 1'b1;
            if (x < H_ACTIVE - 1)
                x <= x + 1'b1;
            else begin
                x <= 12'b0;
                if (y < V_ACTIVE - 1)
                    y <= y + 1'b1;
                else
                    y <= 12'b0;
            end
        end else ve <= 1'b0; // Deassert VE when not ready
    end

    // Update RGB output: 9 vertical bands (left->right):
    // red, orange, yellow, green, cyan, blue, purple, white, black.
    // Only output color during active display area, else black.
    always @(posedge clk) begin
        if (x == H_ACTIVE || y >= V_ACTIVE)
            rgb_o <= 24'h000000; // black
        else if (x < BAND * 1)
            rgb_o <= 24'hFF0000; // red
        else if (x < BAND * 2)
            rgb_o <= 24'hFF8000; // orange
        else if (x < BAND * 3)
            rgb_o <= 24'hFFFF00; // yellow
        else if (x < BAND * 4)
            rgb_o <= 24'h00FF00; // green
        else if (x < BAND * 5)
            rgb_o <= 24'h00FFFF; // cyan
        else if (x < BAND * 6)
            rgb_o <= 24'h0000FF; // blue
        else if (x < BAND * 7)
            rgb_o <= 24'h8000FF; // purple
        else if (x < BAND * 8)
            rgb_o <= 24'hFFFFFF; // white
        else
            rgb_o <= 24'h000000; // black
    end 
endmodule