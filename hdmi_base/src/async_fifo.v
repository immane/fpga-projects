module async_fifo #(
    parameter ADDRESS_WIDTH = 11,
    parameter DATA_WIDTH = 16,
    parameter ALMOST_FULL_MARGIN = 4,
    parameter ALMOST_EMPTY_MARGIN = 4,
    parameter ALMOST_FULL_RELEASE_MARGIN = 8
) (
    // Write port
    input wire w_clk,
    input wire w_rst_n,
    input wire w_en,
    input wire [DATA_WIDTH-1:0] w_data,
    output reg full,
    output reg almost_full,

    // Read port
    input wire r_clk,
    input wire r_rst_n,
    input wire r_en,
    output wire [DATA_WIDTH-1:0] r_data,
    output reg empty,
    output reg almost_empty
);
    // FIFO pointers and synchronization logic 
    reg [ADDRESS_WIDTH:0] w_ptr, r_ptr;
    wire [ADDRESS_WIDTH:0] w_ptr_gray_next, r_ptr_gray_next;
    
    // Internal dual-port RAM for FIFO storage
    sdp_bram #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_ram (
        .w_clk(w_clk),
        .w_en(w_en && !full),
        .w_addr(w_ptr[ADDRESS_WIDTH-1:0]),
        .w_data(w_data),
        .r_clk(r_clk),
        .r_en(r_en && !empty), 
        .r_addr(r_ptr[ADDRESS_WIDTH-1:0]),
        .r_data(r_data)
    );

    // FIFO pointer management and full/empty flag generation
    wire [ADDRESS_WIDTH:0] w_ptr_next = w_ptr + (w_en && !full);
    wire [ADDRESS_WIDTH:0] r_ptr_next = r_ptr + (r_en && !empty);
    
    assign w_ptr_gray_next = (w_ptr_next >> 1) ^ w_ptr_next;
    assign r_ptr_gray_next = (r_ptr_next >> 1) ^ r_ptr_next;

    // Synchronize pointers across clock domains using Gray code to prevent metastability
    reg [ADDRESS_WIDTH:0] w_ptr_gray, r_ptr_gray;

    // Synchronize the opposite clock domain's pointer for full/empty detection
    reg [ADDRESS_WIDTH:0] w_ptr_gray_sync_tmp, w_ptr_gray_sync;
    reg [ADDRESS_WIDTH:0] r_ptr_gray_sync_tmp, r_ptr_gray_sync;

    always @(posedge w_clk or negedge w_rst_n) begin
        if(!w_rst_n) {r_ptr_gray_sync_tmp, r_ptr_gray_sync} <= 0;
        else         {r_ptr_gray_sync_tmp, r_ptr_gray_sync} <= {r_ptr_gray, r_ptr_gray_sync_tmp};
    end
    
    always @(posedge r_clk or negedge r_rst_n) begin
        if(!r_rst_n) {w_ptr_gray_sync_tmp, w_ptr_gray_sync} <= 0;
        else         {w_ptr_gray_sync_tmp, w_ptr_gray_sync} <= {w_ptr_gray, w_ptr_gray_sync_tmp};
    end        

    function [ADDRESS_WIDTH:0] gray2bin;
        input [ADDRESS_WIDTH:0] gray;
        integer idx;
        begin
            gray2bin[ADDRESS_WIDTH] = gray[ADDRESS_WIDTH];
            for (idx = ADDRESS_WIDTH - 1; idx >= 0; idx = idx - 1)
                gray2bin[idx] = gray2bin[idx + 1] ^ gray[idx];
        end
    endfunction

    wire [ADDRESS_WIDTH:0] r_ptr_bin_sync_w = gray2bin(r_ptr_gray_sync);
    wire [ADDRESS_WIDTH:0] w_ptr_bin_sync_r = gray2bin(w_ptr_gray_sync);
    wire [ADDRESS_WIDTH:0] fifo_level_w = w_ptr - r_ptr_bin_sync_w;
    wire [ADDRESS_WIDTH:0] fifo_level_r = w_ptr_bin_sync_r - r_ptr;

    // Update binary and Gray pointers in lockstep so synchronized depth information is not delayed by an extra local cycle.
    always @(posedge w_clk or negedge w_rst_n) begin
        if(!w_rst_n) begin
            w_ptr <= 0;
            w_ptr_gray <= 0;
        end else if (w_en && !full) begin
            w_ptr <= w_ptr_next;
            w_ptr_gray <= w_ptr_gray_next;
        end
    end
    
    always @(posedge r_clk or negedge r_rst_n) begin
        if(!r_rst_n) begin
            r_ptr <= 0;
            r_ptr_gray <= 0;
        end else if (r_en && !empty) begin
            r_ptr <= r_ptr_next;
            r_ptr_gray <= r_ptr_gray_next;
        end
    end

    // Full when next write pointer equals read pointer with MSB inverted (Gray code)
    wire full_val = (w_ptr_gray_next == {~r_ptr_gray_sync[ADDRESS_WIDTH:ADDRESS_WIDTH-1], r_ptr_gray_sync[ADDRESS_WIDTH-2:0]});
    always @(posedge w_clk or negedge w_rst_n) begin
        if(!w_rst_n) full <= 1'b0;
        else         full <= full_val;
    end

    always @(posedge w_clk or negedge w_rst_n) begin
        if(!w_rst_n) begin
            almost_full <= 1'b0;
        end else begin
            if (almost_full) begin
                if (fifo_level_w <= ((1 << ADDRESS_WIDTH) - ALMOST_FULL_RELEASE_MARGIN))
                    almost_full <= 1'b0;
            end else begin
                if (fifo_level_w >= ((1 << ADDRESS_WIDTH) - ALMOST_FULL_MARGIN))
                    almost_full <= 1'b1;
            end
        end
    end

    // Empty when next read pointer equals write pointer (Gray code)
    wire empty_val = (r_ptr_gray_next == w_ptr_gray_sync);
    always @(posedge r_clk or negedge r_rst_n) begin
        if(!r_rst_n) empty <= 1'b1;
        else         empty <= empty_val;
    end

    always @(posedge r_clk or negedge r_rst_n) begin
        if(!r_rst_n) almost_empty <= 1'b1;
        else         almost_empty <= (fifo_level_r <= ALMOST_EMPTY_MARGIN);
    end

endmodule