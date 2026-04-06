module serlizer_10to1(
    input wire clk_hdmi,
    input wire clk_hdmi_5x,
    input wire rst_n,

    input wire [9:0] parallel_i,
    output wire serial_o
);
    
// Shift register to hold the 10-bit parallel input
reg [9:0] shift_reg;
always @(posedge clk_hdmi) begin
    shift_reg <= parallel_i;
end

OSER10 uut(
    .Q     (serial_o),      // Serial output 
    .D0    (shift_reg[0]),
    .D1    (shift_reg[1]),
    .D2    (shift_reg[2]),
    .D3    (shift_reg[3]),
    .D4    (shift_reg[4]),
    .D5    (shift_reg[5]),
    .D6    (shift_reg[6]),
    .D7    (shift_reg[7]),
    .D8    (shift_reg[8]),
    .D9    (shift_reg[9]),
    .PCLK  (clk_hdmi),      // Parallel clock 
    .FCLK  (clk_hdmi_5x),   // 5x faster clock for serialization
    .RESET (!rst_n)         // Active low reset
);
defparam uut.GSREN = "false";
defparam uut.LSREN = "true";

endmodule