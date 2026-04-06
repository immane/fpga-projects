module debouncer #(
    parameter CLOCK_FREQUENCY = 27_000_000,
    parameter STABLE_TIMES = 20
)(
    input clk,
    input rst_n,
    input key_i,
    output reg key_o
);

// Number of clock cycles for stable time (20ms)
localparam DEBOUNCER_COUNT = CLOCK_FREQUENCY / 1000 * STABLE_TIMES; 

// Initial values for registers
initial begin
    key_tmp = 1'b1;
    key_o = 1'b1;
    cnt = 0;
end

// Debouncing logic: sample the key input every 20ms and update the output if stable
reg key_tmp;
reg [19:0] cnt;
    
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // Reset the counter and output states
        cnt <= 0;
        key_tmp <= 1'b1;
        key_o <= 1'b1;
    end
    else begin
        // Increment the counter until it reaches the debouncer count
        if(cnt < DEBOUNCER_COUNT) begin
            cnt <= cnt + 1;
        end
        else begin
            key_tmp <= key_i;
            key_o <= key_tmp;
            cnt <= 0;
        end
    end
end
    
endmodule