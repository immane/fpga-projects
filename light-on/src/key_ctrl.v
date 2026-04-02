module key_ctrl (
    input clk,
    input rst_n,
    input key_i,
    output reg [1:0] key_state
);

localparam S1 = 2'b00;
localparam S2 = 2'b01;
localparam S3 = 2'b10;
localparam S4 = 2'b11;

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
        key_tmp <= 1'b0; // Reset key_tmp on reset
    end
    else begin
        key_tmp <= key_o;
    end
end

reg [1:0] current_state;
reg [1:0] next_state;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= S1; // Reset state
    else
        current_state <= next_state; // Update state on clock edge
end

always @(*) begin
    next_state = current_state; // Default to current state

    if(key_tmp && !key_o) begin // Detect falling edge of key_o
        case (current_state)
            S1: next_state = S2;
            S2: next_state = S3;
            S3: next_state = S4;
            S4: next_state = S1;
            default: next_state = S1; // Default to initial state
        endcase
    end
end

always @(*) begin
    key_state = current_state;
end

endmodule