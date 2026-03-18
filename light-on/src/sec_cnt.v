module sec_cnt #(
    parameter CLOCK_FREQUENCY = 27_000_000,
    parameter A_MINUTE_SEC = 6'd60
)(
    input clk,
    output reg [5:0] bin_sec
);

// Generate a tick every 1 second and count seconds from 0 to 59.
wire t1s;
reg [24:0] cnt_1s;

assign t1s = (cnt_1s == CLOCK_FREQUENCY - 1) ? 1'b1 : 1'b0;

initial begin
    cnt_1s = 25'b0;
    bin_sec = 6'b0;
end

// Counter for generating 1-second tick
always @(posedge clk) begin
    if (cnt_1s < CLOCK_FREQUENCY - 1)
        cnt_1s <= cnt_1s + 1'b1;
    else
        cnt_1s <= 25'b0;
end

// Counter for seconds, resets after reaching A_MINUTE_SEC
always @(posedge clk) begin
    if (t1s) begin
        if (bin_sec < A_MINUTE_SEC - 6'd1)
            bin_sec <= bin_sec + 6'd1;
        else
            bin_sec <= 6'd0;
    end
    else
        bin_sec <= bin_sec;
end

endmodule