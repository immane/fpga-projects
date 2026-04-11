module async_fifo #(
    parameter ADDRESS_WIDTH = 11,
    parameter DATA_WIDTH = 16
) (
    // Write port
    input wire w_clk,
    input wire w_rst_n,
    input wire w_en,
    input wire [DATA_WIDTH-1:0] w_data,
    output reg full,

    // Read port
    input wire r_clk,
    input wire r_rst_n,
    input wire r_en,
    output wire [DATA_WIDTH-1:0] r_data,
    output reg empty
);
    reg [ADDRESS_WIDTH:0] w_ptr, r_ptr;
    wire [ADDRESS_WIDTH:0] w_ptr_gray, r_ptr_gray;

    // Simple asynchronous FIFO using dual-port RAM
    sdp_bram #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_ram (
        .w_clk(w_clk),
        .w_en(w_en && !full),
        .w_addr(w_ptr[ADDRESS_WIDTH-1:0]),
        .w_data(w_data),

        .r_clk(r_clk),
        .r_en(r_en),
        .r_addr(r_ptr[ADDRESS_WIDTH-1:0]),
        .r_data(r_data)
    );

    assign w_ptr_gray = (w_ptr >> 1) ^ w_ptr; // Binary to Gray code
    assign r_ptr_gray = (r_ptr >> 1) ^ r_ptr; // Binary to Gray code

    reg [ADDRESS_WIDTH:0] w_ptr_gray_sync_tmp, w_ptr_gray_sync;
    reg [ADDRESS_WIDTH:0] r_ptr_gray_sync_tmp, r_ptr_gray_sync;

    // Synchronize pointers across clock domains
    always @(posedge w_clk or negedge w_rst_n) begin
        if(!w_rst_n) {r_ptr_gray_sync_tmp, r_ptr_gray_sync} <= 0;
        else         {r_ptr_gray_sync_tmp, r_ptr_gray_sync} <= {r_ptr_gray, r_ptr_gray_sync_tmp};
    end
    
    always @(posedge r_clk or negedge r_rst_n) begin
        if(!r_rst_n) {w_ptr_gray_sync_tmp, w_ptr_gray_sync} <= 0;
        else         {w_ptr_gray_sync_tmp, w_ptr_gray_sync} <= {w_ptr_gray, w_ptr_gray_sync_tmp};
    end        

    // Full when next write pointer equals read pointer (in Gray code)
    always @(posedge w_clk or negedge w_rst_n) begin
        if(!w_rst_n) w_ptr <= 0;
        else if (w_en && !full) w_ptr <= w_ptr + 1;
    end
    
    always @(posedge r_clk or negedge r_rst_n) begin
        if(!r_rst_n) r_ptr <= 0;
        else if (r_en && !empty) r_ptr <= r_ptr + 1;
    end

    // Determine full and empty conditions based on synchronized pointers
    always @(*) begin
        full = (w_ptr_gray == {~r_ptr_gray_sync[ADDRESS_WIDTH:ADDRESS_WIDTH-1], r_ptr_gray_sync[ADDRESS_WIDTH-2:0]});
        empty = (r_ptr_gray == w_ptr_gray_sync);
    end
endmodule
