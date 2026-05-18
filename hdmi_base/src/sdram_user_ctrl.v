module sdram_user_ctrl (
    input             clk,
    input             rst_n,
    input             init_done,
    input             cmd_ack,
    input             pix_valid,
    input      [15:0] pix_data,
    
    // Connected to the IP core
    output reg [2:0]  user_cmd,
    output reg        user_cmd_en,
    output reg [20:0] user_addr,
    output reg [31:0] user_data,   // Write data bus
    output     [7:0]  user_len,    // Burst length

    input             data_valid,  // Important: corresponds to IP's O_sdrc_data_valid
    input      [31:0] read_data    // Corresponds to IP's O_sdrc_data
);

    localparam BURST_SIZE = 8'd8;         // SDRAM burst length (32-bit words)
    localparam SDRAM_HALF_WORDS = 21'h100000; // Use only first half: 0 .. (2^20-1)
    assign user_len = BURST_SIZE;

    localparam IDLE      = 3'd0;
    localparam PACK_DATA = 3'd1;
    localparam W_REQ     = 3'd2;
    localparam W_DATA    = 3'd3;

    reg [2:0] state;
    reg [3:0] pack_cnt;
    reg [3:0] send_cnt;
    reg       half_word;
    reg [15:0] pix_lo;
    reg [20:0] wr_base_addr;
    reg [31:0] burst_buf [0:7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            user_cmd <= 3'b001;
            user_cmd_en <= 1'b0;
            user_addr <= 21'd0;
            user_data <= 32'd0;
            pack_cnt <= 4'd0;
            send_cnt <= 4'd0;
            half_word <= 1'b0;
            pix_lo <= 16'd0;
            wr_base_addr <= 21'd0;
        end else begin
            case (state)
                IDLE: begin
                    user_cmd_en <= 1'b0;
                    if (init_done) begin
                        state <= PACK_DATA;
                    end
                end

                PACK_DATA: begin
                    if (pix_valid) begin
                        if (!half_word) begin
                            pix_lo <= pix_data;
                            half_word <= 1'b1;
                        end else begin
                            burst_buf[pack_cnt] <= {pix_data, pix_lo};
                            half_word <= 1'b0;

                            if (pack_cnt == BURST_SIZE - 1) begin
                                pack_cnt <= 4'd0;
                                user_addr <= wr_base_addr;
                                state <= W_REQ;
                            end else begin
                                pack_cnt <= pack_cnt + 1'b1;
                            end
                        end
                    end
                end

                W_REQ: begin
                    user_cmd    <= 3'b001;      // Write command
                    user_cmd_en <= 1'b1;
                    if (cmd_ack) begin
                        user_cmd_en <= 1'b0;
                        send_cnt <= 4'd0;
                        user_data <= burst_buf[0];
                        state <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (send_cnt < BURST_SIZE - 1) begin
                        send_cnt <= send_cnt + 1'b1;
                        user_data <= burst_buf[send_cnt + 1'b1];
                    end else begin
                        if (wr_base_addr >= (SDRAM_HALF_WORDS - BURST_SIZE))
                            wr_base_addr <= 21'd0;
                        else
                            wr_base_addr <= wr_base_addr + BURST_SIZE;

                        state <= PACK_DATA;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule