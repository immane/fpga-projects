module vid_timing_gen #(
    parameter H_ACTIVE = 1280,
    parameter H_FRONT_PORCH = 110,
    parameter H_SYNC_PULSE = 40,
    parameter H_BACK_PORCH = 220,

    parameter V_ACTIVE = 720,
    parameter V_FRONT_PORCH = 5,
    parameter V_SYNC_PULSE = 5,
    parameter V_BACK_PORCH = 20
)(
    input wire clk_hdmi,
    input wire rst_n,

    output reg hsync,
    output reg vsync,
    output reg de,
    output reg [11:0] x,
    output reg [11:0] y,
    output wire frame_end
);

// Calculate total horizontal and vertical timings
localparam H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
localparam V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;
localparam H_SYNC_START = H_ACTIVE + H_FRONT_PORCH;
localparam H_SYNC_END = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE;
localparam V_SYNC_START = V_ACTIVE + V_FRONT_PORCH;
localparam V_SYNC_END = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE;

// Internal counters for horizontal and vertical timings
reg [11:0] h_cnt;
reg [11:0] v_cnt;


// Generate horizontal and vertical counters
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) begin
        h_cnt <= 12'h0;
        v_cnt <= 12'h0;
    end else begin
        if (h_cnt < H_TOTAL - 12'h1) begin
            h_cnt <= h_cnt + 12'h1;
        end else begin
            h_cnt <= 12'h0;
            if (v_cnt < V_TOTAL - 12'h1) begin
                v_cnt <= v_cnt + 12'h1;
            end else begin
                v_cnt <= 12'h0;
            end
        end
    end
end

// Generate synchronization signals and data enable
function is_in_range;
    input [11:0] val; input [11:0] min; input [11:0] max;
    begin
        is_in_range = (val >= min) && (val <= max);
    end
endfunction
always @(posedge clk_hdmi or negedge rst_n) begin
    if(!rst_n) begin
        vsync <= 1'b0;
        hsync <= 1'b0;
        de <= 1'b0;
        x <= 12'd0;
        y <= 12'd0;
    end
    else begin
        hsync <= is_in_range(h_cnt, H_SYNC_START, H_SYNC_END - 12'h1);
        vsync <= is_in_range(v_cnt, V_SYNC_START, V_SYNC_END - 12'h1);
        de <= (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
        x <= h_cnt;
        y <= v_cnt;
    end
end

// Generate frame end signal when both horizontal and vertical counters reach their maximum values
assign frame_end = (h_cnt == H_TOTAL - 12'h1) && (v_cnt == V_TOTAL - 12'h1);

endmodule