module key_ctrl (
    input clk,
    input rst_n,
    input key_i,
    output reg [1:0] key_state
);

wire key_o;
debouncer debouncer_inst(
    .clk    (clk),
    .rst_n  (rst_n),
    .key_i  (key_i),
    .key_o  (key_o)
);

reg key_tmp;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        key_state <= 2'b00; // Reset state
    end
    else begin
        key_tmp <= key_o;
        if(key_o != key_tmp && !key_o)  // Detect rising edge of key press
            key_state <= key_state + 1'b1; // Increment state on key press
        else
            key_state <= key_state; // Hold state when key is not pressed
    end
end

endmodule