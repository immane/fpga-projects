module pwm_gen#(
	parameter DFLT_DUTY = 8'h7F  // Default duty cycle (50%)
)(
	input clk,
	input rst_n,
	input [7:0] duty,  // Duty cycle (0-255)
	output reg pwm_o
);

// Initialize registers
initial begin
	cnt <= 8'b0;
	pwm_o <= DFLT_DUTY;
end

// Counter for generating PWM signal
reg [7:0] cnt;
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)
		cnt <= 1'b0;  // Reset clock counter
	else
		cnt <= cnt + 1'b1;  // Increment clock counter
end

// Update PWM output based on duty cycle and counter
always @(posedge clk or negedge rst_n) begin
	if (!rst_n)
		pwm_o <= DFLT_DUTY;  // Reset to default duty cycle
	else
		pwm_o <= (duty > cnt) ? 1'b1 : 1'b0;  // Simple threshold for PWM output
end
	
endmodule