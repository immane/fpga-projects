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

    // The existing asynchronous line buffer accepts one RGB565 pixel per clk.
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

    // IPUG279 legacy SDRAM Controller HS command encodings.
    localparam [2:0] CMD_NOP   = 3'b000;
    localparam [2:0] CMD_WRITE = 3'b100;
    localparam [2:0] CMD_READ  = 3'b101;
    localparam [20:0] SDRAM_WORDS = 21'd1048576;

    localparam [3:0] M_IDLE    = 4'd0;
    localparam [3:0] M_W_CMD   = 4'd1;
    localparam [3:0] M_W_DATA  = 4'd2;
    localparam [3:0] M_W_ACK   = 4'd3;
    localparam [3:0] M_R_CMD   = 4'd4;
    localparam [3:0] M_R_ACK   = 4'd5;
    localparam [3:0] M_R_FIRST = 4'd6;
    localparam [3:0] M_R_DATA  = 4'd7;

    // I_sdrc_data_len encodes the number of words minus one.
    assign user_len = BURST_WORDS - 1;

    // Two fill buffers let pattern generation continue while the other burst
    // is being written and read by the SDRAM controller.
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

    // A 32-bit SDRAM read yields two RGB565 pixels per cycle. This local queue
    // absorbs that burst rate and emits one pixel per clk to the unchanged
    // 16-bit asynchronous line buffer.
    localparam integer PIXEL_FIFO_DEPTH = (1 << PIXEL_FIFO_ADDR_WIDTH);
    reg [15:0] pixel_fifo [0:PIXEL_FIFO_DEPTH-1];
    reg [PIXEL_FIFO_ADDR_WIDTH-1:0] pixel_wr_ptr, pixel_rd_ptr;
    reg [PIXEL_FIFO_ADDR_WIDTH:0] pixel_count;

    reg [3:0] state;
    reg [3:0] send_count;
    reg [3:0] read_count;
    reg       cmd_ack_seen;

    // The guide specifies the first read word one controller clock after ACK.
    wire read_word_valid = (state == M_R_FIRST) ||
                           ((state == M_R_DATA) && (read_count < BURST_WORDS));
    wire pixel_pop = (pixel_count != 0) && out_ready;
    wire take_buf0 = (state == M_IDLE) && buf_ready[0] &&
                     (pixel_count <= PIXEL_FIFO_DEPTH - 16);
    wire take_buf1 = (state == M_IDLE) && !take_buf0 && buf_ready[1] &&
                     (pixel_count <= PIXEL_FIFO_DEPTH - 16);
    wire release_active_buf = (state == M_R_DATA) &&
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
            // Select a newly freed buffer before accepting another source pixel.
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
            cmd_ack_seen <= 1'b0;
            user_cmd <= CMD_NOP;
            user_cmd_en <= 1'b0;
            user_addr <= 0;
            user_data <= 0;
        end else begin
            user_cmd_en <= 1'b0;

            if (((state == M_W_DATA) || (state == M_W_ACK)) && cmd_ack)
                cmd_ack_seen <= 1'b1;

            case (state)
                M_IDLE: begin
                    // Reserve room for all sixteen RGB565 pixels before a read.
                    if (take_buf0) begin
                        active_buf <= 1'b0;
                        active_addr <= buf_addr0;
                        state <= M_W_CMD;
                    end else if (take_buf1) begin
                        active_buf <= 1'b1;
                        active_addr <= buf_addr1;
                        state <= M_W_CMD;
                    end
                end

                M_W_CMD: begin
                    // Word zero is valid with the write command, per IPUG279.
                    user_cmd <= CMD_WRITE;
                    user_addr <= active_addr;
                    user_data <= active_buf ? burst_buf1[0] : burst_buf0[0];
                    user_cmd_en <= 1'b1;
                    send_count <= 4'd1;
                    cmd_ack_seen <= 1'b0;
                    state <= M_W_DATA;
                end

                M_W_DATA: begin
                    if (send_count < BURST_WORDS) begin
                        user_data <= active_buf ? burst_buf1[send_count] : burst_buf0[send_count];
                        send_count <= send_count + 1'b1;
                    end else begin
                        state <= M_W_ACK;
                    end
                end

                M_W_ACK: begin
                    if (cmd_ack_seen) begin
                        state <= M_R_CMD;
                    end
                end

                M_R_CMD: begin
                    user_cmd <= CMD_READ;
                    user_addr <= active_addr;
                    user_cmd_en <= 1'b1;
                    cmd_ack_seen <= 1'b0;
                    state <= M_R_ACK;
                end

                M_R_ACK: begin
                    if (cmd_ack) begin
                        read_count <= 0;
                        state <= M_R_FIRST;
                    end
                end

                M_R_FIRST: begin
                    // O_sdrc_data[0] is sampled one clock after O_sdrc_cmd_ack.
                    read_count <= 1;
                    state <= M_R_DATA;
                end

                M_R_DATA: begin
                    if (read_count == BURST_WORDS - 1) begin
                        read_count <= BURST_WORDS;
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
