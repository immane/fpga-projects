module sdram_user_ctrl #(
    parameter integer BURST_WORDS = 8,
    parameter integer PIXEL_FIFO_ADDR_WIDTH = 6
) (
    input             clk,
    input             rst_n,
    input             init_done,
    input             cmd_ack,

    input             pix_valid,
    input      [15:0] pix_data,
    output wire        pix_ready,

    output wire        out_valid,
    output wire [15:0] out_data,
    input             out_ready,

    output reg [2:0]  user_cmd,
    output reg        user_cmd_en,
    output reg [20:0] user_addr,
    output reg [31:0] user_data,
    output wire [7:0] user_len,
    input      [31:0] read_data
);

    localparam [2:0] CMD_ACTIVATE = 3'b011;
    localparam [2:0] CMD_WRITE    = 3'b100;
    localparam [2:0] CMD_READ     = 3'b101;
    localparam [2:0] CMD_NOP      = 3'b111;
    localparam [20:0] SDRAM_WORDS = 21'd1048576;

    localparam [3:0] M_IDLE      = 4'd0;
    localparam [3:0] M_ACT_W     = 4'd1;
    localparam [3:0] M_ACT_W_ACK = 4'd2;
    localparam [3:0] M_W_CMD     = 4'd3;
    localparam [3:0] M_W_DATA    = 4'd4;
    localparam [3:0] M_W_RECOVER = 4'd5;
    localparam [3:0] M_ACT_R     = 4'd6;
    localparam [3:0] M_ACT_R_ACK = 4'd7;
    localparam [3:0] M_R_CMD     = 4'd8;
    localparam [3:0] M_R_WAIT    = 4'd9;
    localparam [3:0] M_R_DATA    = 4'd10;

    // The IP encodes a burst of N words as N - 1.
    assign user_len = BURST_WORDS - 1;

    reg [31:0] burst_buf0 [0:BURST_WORDS-1];
    reg [31:0] burst_buf1 [0:BURST_WORDS-1];
    reg [1:0]  buf_ready;
    reg [1:0]  buf_busy;
    reg        fill_buf;
    reg        active_buf;
    reg        half_word;
    reg [2:0]  pack_count;
    reg [15:0] pix_low;
    reg [20:0] next_addr;
    reg [20:0] buf_addr0, buf_addr1, active_addr;

    wire fill_available = !buf_ready[fill_buf] && !buf_busy[fill_buf];
    wire other_fill_available = !buf_ready[~fill_buf] && !buf_busy[~fill_buf];
    assign pix_ready = init_done && fill_available;

    localparam integer PIXEL_FIFO_DEPTH = (1 << PIXEL_FIFO_ADDR_WIDTH);
    reg [15:0] pixel_fifo [0:PIXEL_FIFO_DEPTH-1];
    reg [PIXEL_FIFO_ADDR_WIDTH-1:0] pixel_wr_ptr, pixel_rd_ptr;
    reg [PIXEL_FIFO_ADDR_WIDTH:0] pixel_count;

    reg [3:0] state;
    reg [3:0] send_count;
    reg [3:0] read_count;
    reg [2:0] wait_count;

    wire read_word_valid = (state == M_R_DATA);
    wire pixel_pop = (pixel_count != 0) && out_ready;
    wire take_buf0 = (state == M_IDLE) && buf_ready[0] &&
                     (pixel_count <= PIXEL_FIFO_DEPTH - 2 * BURST_WORDS);
    wire take_buf1 = (state == M_IDLE) && !take_buf0 && buf_ready[1] &&
                     (pixel_count <= PIXEL_FIFO_DEPTH - 2 * BURST_WORDS);
    wire release_active_buf = read_word_valid &&
                              (read_count == BURST_WORDS - 1);

    assign out_valid = (pixel_count != 0);
    assign out_data = pixel_fifo[pixel_rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_wr_ptr <= 0;
            pixel_rd_ptr <= 0;
            pixel_count <= 0;
        end else begin
            if (read_word_valid) begin
                pixel_fifo[pixel_wr_ptr] <= read_data[15:0];
                pixel_fifo[pixel_wr_ptr + 1'b1] <= read_data[31:16];
                pixel_wr_ptr <= pixel_wr_ptr + 2'd2;
            end

            if (pixel_pop)
                pixel_rd_ptr <= pixel_rd_ptr + 1'b1;

            case ({read_word_valid, pixel_pop})
                2'b10: pixel_count <= pixel_count + 2'd2;
                2'b01: pixel_count <= pixel_count - 1'b1;
                2'b11: pixel_count <= pixel_count + 1'b1;
                default: pixel_count <= pixel_count;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_ready <= 0;
            buf_busy <= 0;
            fill_buf <= 1'b0;
            half_word <= 1'b0;
            pack_count <= 0;
            pix_low <= 0;
            next_addr <= 0;
            buf_addr0 <= 0;
            buf_addr1 <= 0;
        end else begin
            if (!fill_available && other_fill_available)
                fill_buf <= ~fill_buf;

            if (take_buf0) begin
                buf_ready[0] <= 1'b0;
                buf_busy[0] <= 1'b1;
            end else if (take_buf1) begin
                buf_ready[1] <= 1'b0;
                buf_busy[1] <= 1'b1;
            end

            if (release_active_buf)
                buf_busy[active_buf] <= 1'b0;

            if (pix_valid && pix_ready) begin
                if (!half_word) begin
                    pix_low <= pix_data;
                    half_word <= 1'b1;
                end else begin
                    if (fill_buf)
                        burst_buf1[pack_count] <= {pix_data, pix_low};
                    else
                        burst_buf0[pack_count] <= {pix_data, pix_low};
                    half_word <= 1'b0;

                    if (pack_count == BURST_WORDS - 1) begin
                        pack_count <= 0;
                        buf_ready[fill_buf] <= 1'b1;
                        if (fill_buf)
                            buf_addr1 <= next_addr;
                        else
                            buf_addr0 <= next_addr;

                        if (next_addr >= SDRAM_WORDS - BURST_WORDS)
                            next_addr <= 0;
                        else
                            next_addr <= next_addr + BURST_WORDS;
                        fill_buf <= ~fill_buf;
                    end else begin
                        pack_count <= pack_count + 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= M_IDLE;
            active_buf <= 0;
            active_addr <= 0;
            send_count <= 0;
            read_count <= 0;
            wait_count <= 0;
            user_cmd <= CMD_NOP;
            user_cmd_en <= 1'b0;
            user_addr <= 0;
            user_data <= 0;
        end else begin
            user_cmd_en <= 1'b0;
            user_cmd <= CMD_NOP;

            case (state)
                M_IDLE: begin
                    if (take_buf0) begin
                        active_buf <= 1'b0;
                        active_addr <= buf_addr0;
                        state <= M_ACT_W;
                    end else if (take_buf1) begin
                        active_buf <= 1'b1;
                        active_addr <= buf_addr1;
                        state <= M_ACT_W;
                    end
                end

                M_ACT_W: begin
                    user_cmd <= CMD_ACTIVATE;
                    user_addr <= active_addr;
                    user_cmd_en <= 1'b1;
                    state <= M_ACT_W_ACK;
                end

                M_ACT_W_ACK: begin
                    if (cmd_ack)
                        state <= M_W_CMD;
                end

                M_W_CMD: begin
                    user_cmd <= CMD_WRITE;
                    user_addr <= active_addr;
                    user_data <= active_buf ? burst_buf1[0] : burst_buf0[0];
                    user_cmd_en <= 1'b1;
                    send_count <= 1;
                    state <= M_W_DATA;
                end

                M_W_DATA: begin
                    if (send_count < BURST_WORDS) begin
                        user_data <= active_buf ? burst_buf1[send_count] : burst_buf0[send_count];
                        send_count <= send_count + 1'b1;
                    end else begin
                        wait_count <= 0;
                        state <= M_W_RECOVER;
                    end
                end

                M_W_RECOVER: begin
                    if (wait_count == 3'd4)
                        state <= M_ACT_R;
                    else
                        wait_count <= wait_count + 1'b1;
                end

                M_ACT_R: begin
                    user_cmd <= CMD_ACTIVATE;
                    user_addr <= active_addr;
                    user_cmd_en <= 1'b1;
                    state <= M_ACT_R_ACK;
                end

                M_ACT_R_ACK: begin
                    if (cmd_ack)
                        state <= M_R_CMD;
                end

                M_R_CMD: begin
                    user_cmd <= CMD_READ;
                    user_addr <= active_addr;
                    user_cmd_en <= 1'b1;
                    wait_count <= 0;
                    state <= M_R_WAIT;
                end

                M_R_WAIT: begin
                    if (wait_count == 3'd3) begin
                        read_count <= 0;
                        state <= M_R_DATA;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                M_R_DATA: begin
                    if (read_count == BURST_WORDS - 1) begin
                        read_count <= 0;
                        state <= M_IDLE;
                    end else begin
                        read_count <= read_count + 1'b1;
                    end
                end

                default: state <= M_IDLE;
            endcase
        end
    end

endmodule
