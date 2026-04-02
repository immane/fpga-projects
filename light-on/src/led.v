module led #(
    // Parameters for clock frequency and brightness control
    parameter CLOCK_FREQUENCY = 27_000_000,  // 27MHz clock
    parameter A_MINUTE_SEC = 6'd60,  // Maximum value for seconds
    parameter BRIGHTNESS = 8'h01  // Maximum brightness (0-255)
)(
    input clk,
    input rst_n,
    input key_i,
    output [5:0] led
);


// Initial values for registers
initial begin
    led_r = 6'b0;
    brightness = BRIGHTNESS;
end


reg [7:0] brightness;
wire [1:0] key_state;
key_ctrl key_ctrl_inst (
    .clk       (clk),
    .rst_n     (rst_n),
    .key_i     (key_i),
    .key_state (key_state)
);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        brightness <= BRIGHTNESS; // Reset brightness to default
    end
    else begin
        case (key_state)
            2'b00: 
                brightness <= 2'b1;
            default: 
                // Update brightness based on key state (simple mapping for demonstration)
                brightness <= {key_state, key_state, key_state, key_state};
        endcase
    end
end


// Instantiate the second counter to keep track of seconds
wire [5:0] bin_sec;
sec_cnt #(
    .CLOCK_FREQUENCY (CLOCK_FREQUENCY),
    .A_MINUTE_SEC    (A_MINUTE_SEC)
) sec_cnt_inst(
    .clk     (clk),
    .bin_sec (bin_sec)
);

// Use the binary second register to control the LEDs with PWM for brightness control
wire pwm_signal;
pwm_gen pwm(
    .clk    (clk),
    .rst_n  (rst_n),
    .duty   (brightness),
    .pwm_o  (pwm_signal)
);

integer i;
reg[5:0] led_r;
always @(posedge clk) begin
    for(i = 0; i < 6; i = i + 1) begin
        led_r[i] <= bin_sec[i] && pwm_signal;
    end
end

// Output the LED states (active low)
assign led = ~led_r;

endmodule