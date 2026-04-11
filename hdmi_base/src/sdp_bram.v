module sdp_bram #(
    parameter ADDRESS_WIDTH = 11,
    parameter DATA_WIDTH = 16
) (
    // Write port
    input wire w_clk,
    input wire w_en,
    input wire [ADDRESS_WIDTH-1:0] w_addr,
    input wire [DATA_WIDTH-1:0] w_data,

    // Read port
    input wire r_clk,
    input wire r_en,
    input wire [ADDRESS_WIDTH-1:0] r_addr,
    output reg [DATA_WIDTH-1:0] r_data
);

  // Simple dual-port RAM with separate read/write clocks and enables
  reg [DATA_WIDTH-1:0] mem[(2**ADDRESS_WIDTH)-1:0];

  always @(posedge w_clk) begin
    if (w_en) begin
      mem[w_addr] <= w_data;
    end
  end

  always @(posedge r_clk) begin
    if (r_en) begin
      r_data <= mem[r_addr];
    end
  end
endmodule
