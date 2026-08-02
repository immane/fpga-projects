// Streaming bridge for the Gowin SDRAM Controller HS IP.
//
// Pixels are packed and emitted independently of the SDRAM command FSM. Two
// write banks and two read banks allow all three paths to run concurrently:
//
//   pixel source -> write bank -> SDRAM -> read bank -> HDMI async FIFO
//
// The HS IP owns SDRAM initialization and all tRCD/tRP/tRFC/tWR delays. This
// module schedules commands, tracks the one row it leaves open, and guarantees
// periodic AUTO REFRESH commands.
module sdram_user_ctrl #(
    parameter integer BURST_SIZE         = 64,
    parameter integer CLK_FREQ_HZ        = 166_500_000,
    parameter integer FRAME_WORDS        = 1_036_800,
    parameter integer MAX_PENDING_BURSTS = 64,
    parameter integer PREFILL_PIXELS      = 2048
) (
    input              clk,
    input              rst_n,
    input              init_done,
    input              cmd_ack,

    input              pix_valid,
    input      [15:0]  pix_data,
    output             wr_ready,

    output reg [2:0]   user_cmd,
    output reg         user_cmd_en,
    output reg [20:0]  user_addr,
    output reg [31:0]  user_data,
    output      [7:0]  user_len,
    input      [31:0]  read_data,

    output     [15:0]  rd_pix,
    output             rd_pix_valid,
    input              rd_ready,
    output reg          stream_ready
);

    localparam [2:0] CMD_NOP       = 3'b111;
    localparam [2:0] CMD_ACTIVE    = 3'b011;
    localparam [2:0] CMD_WRITE     = 3'b100;
    localparam [2:0] CMD_READ      = 3'b101;
    localparam [2:0] CMD_PRECHARGE = 3'b010;
    localparam [2:0] CMD_REFRESH   = 3'b001;

    localparam integer BURST_AW = $clog2(BURST_SIZE);
    localparam [BURST_AW-1:0] BURST_LAST = BURST_SIZE - 1;
    localparam [7:0] BURST_LEN = BURST_SIZE - 1;
    localparam integer PENDING_W = $clog2(MAX_PENDING_BURSTS + 1);
    localparam integer PREFILL_W = $clog2(PREFILL_PIXELS + 1);
    localparam [PENDING_W-1:0] MAX_PENDING = MAX_PENDING_BURSTS;
    localparam [PREFILL_W-1:0] PREFILL_LAST = PREFILL_PIXELS - 1;
    localparam [20:0] BURST_STEP = BURST_SIZE;
    localparam [20:0] FRAME_LAST_START = FRAME_WORDS - BURST_SIZE;

    // Refresh every 13 us. The SDRAM requires 4096 refreshes per 64 ms
    // (15.625 us), leaving more than 2 us for the current burst to finish.
    localparam integer REFRESH_CYCLES = (CLK_FREQ_HZ / 1_000_000) * 13;
    localparam integer REFRESH_W = $clog2(REFRESH_CYCLES + 1);
    localparam [REFRESH_W-1:0] REFRESH_LAST = REFRESH_CYCLES - 1;

    assign user_len = BURST_LEN;

    // ------------------------------------------------------------------
    // Pixel packer and two ping-pong write banks.
    reg                 pack_bank;
    reg                 pack_half;
    reg [15:0]          pack_lo;
    reg [BURST_AW-1:0]  pack_addr;
    reg                 wr_full0;
    reg                 wr_full1;

    wire selected_write_full = pack_bank ? wr_full1 : wr_full0;
    assign wr_ready = init_done && !selected_write_full;
    wire pix_accept = pix_valid && wr_ready;
    wire pack_word = pix_accept && pack_half;
    wire pack_commit = pack_word && (pack_addr == BURST_LAST);
    wire [31:0] packed_data = {pix_data, pack_lo};

    reg                 wr_send_bank;
    reg                 wr_consume_bank;
    reg [BURST_AW-1:0]  wr_raddr0;
    reg [BURST_AW-1:0]  wr_raddr1;
    wire [31:0]         wr_rdata0;
    wire [31:0]         wr_rdata1;
    wire [31:0]         wr_selected_data = wr_send_bank ? wr_rdata1 : wr_rdata0;

    sdp_bram #(.ADDRESS_WIDTH(BURST_AW), .DATA_WIDTH(32)) write_bank0 (
        .w_clk(clk), .w_en(pack_word && !pack_bank), .w_addr(pack_addr), .w_data(packed_data),
        .r_clk(clk), .r_en(1'b1), .r_addr(wr_raddr0), .r_data(wr_rdata0)
    );
    sdp_bram #(.ADDRESS_WIDTH(BURST_AW), .DATA_WIDTH(32)) write_bank1 (
        .w_clk(clk), .w_en(pack_word && pack_bank), .w_addr(pack_addr), .w_data(packed_data),
        .r_clk(clk), .r_en(1'b1), .r_addr(wr_raddr1), .r_data(wr_rdata1)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pack_bank <= 1'b0;
            pack_half <= 1'b0;
            pack_lo   <= 16'd0;
            pack_addr <= {BURST_AW{1'b0}};
        end else if (!init_done) begin
            pack_bank <= 1'b0;
            pack_half <= 1'b0;
            pack_lo   <= 16'd0;
            pack_addr <= {BURST_AW{1'b0}};
        end else if (pix_accept) begin
            if (!pack_half) begin
                pack_lo   <= pix_data;
                pack_half <= 1'b1;
            end else begin
                pack_half <= 1'b0;
                if (pack_addr == BURST_LAST) begin
                    pack_addr <= {BURST_AW{1'b0}};
                    pack_bank <= ~pack_bank;
                end else begin
                    pack_addr <= pack_addr + 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Two ping-pong read-capture banks. The HS IP has no read-valid signal;
    // cmd_ack is aligned with the final word, so the last BURST_SIZE samples
    // in this circular buffer are the completed read.
    reg                 rd_produce_bank;
    reg                 rd_consume_bank;
    reg                 rd_full0;
    reg                 rd_full1;
    reg [BURST_AW-1:0]  rd_cap_ptr;
    reg [BURST_AW-1:0]  rd_start0;
    reg [BURST_AW-1:0]  rd_start1;
    reg [BURST_AW-1:0]  rd_raddr0;
    reg [BURST_AW-1:0]  rd_raddr1;
    wire [31:0]         rd_rdata0;
    wire [31:0]         rd_rdata1;
    wire [31:0]         rd_selected_data = rd_consume_bank ? rd_rdata1 : rd_rdata0;

    wire read_capture;
    sdp_bram #(.ADDRESS_WIDTH(BURST_AW), .DATA_WIDTH(32)) read_bank0 (
        .w_clk(clk), .w_en(read_capture && !rd_produce_bank), .w_addr(rd_cap_ptr), .w_data(read_data),
        .r_clk(clk), .r_en(1'b1), .r_addr(rd_raddr0), .r_data(rd_rdata0)
    );
    sdp_bram #(.ADDRESS_WIDTH(BURST_AW), .DATA_WIDTH(32)) read_bank1 (
        .w_clk(clk), .w_en(read_capture && rd_produce_bank), .w_addr(rd_cap_ptr), .w_data(read_data),
        .r_clk(clk), .r_en(1'b1), .r_addr(rd_raddr1), .r_data(rd_rdata1)
    );

    // Read-bank output runs independently from SDRAM commands and emits one
    // pixel per clk while the downstream FIFO is ready.
    reg                 out_wait;
    reg                 out_load;
    reg                 out_active;
    reg                 out_half;
    reg [BURST_AW-1:0]  out_word;
    reg [31:0]          out_data;

    assign rd_pix = out_half ? out_data[31:16] : out_data[15:0];
    assign rd_pix_valid = out_active;
    wire out_accept = out_active && rd_ready;
    wire out_release = out_accept && out_half && (out_word == BURST_LAST);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_consume_bank <= 1'b0;
            rd_raddr0       <= {BURST_AW{1'b0}};
            rd_raddr1       <= {BURST_AW{1'b0}};
            out_wait        <= 1'b0;
            out_load        <= 1'b0;
            out_active      <= 1'b0;
            out_half        <= 1'b0;
            out_word        <= {BURST_AW{1'b0}};
            out_data        <= 32'd0;
        end else if (!init_done) begin
            rd_consume_bank <= 1'b0;
            rd_raddr0       <= {BURST_AW{1'b0}};
            rd_raddr1       <= {BURST_AW{1'b0}};
            out_wait        <= 1'b0;
            out_load        <= 1'b0;
            out_active      <= 1'b0;
            out_half        <= 1'b0;
            out_word        <= {BURST_AW{1'b0}};
            out_data        <= 32'd0;
        end else if (!out_active && !out_wait && !out_load) begin
            if (rd_consume_bank ? rd_full1 : rd_full0) begin
                if (rd_consume_bank)
                    rd_raddr1 <= rd_start1;
                else
                    rd_raddr0 <= rd_start0;
                out_word <= {BURST_AW{1'b0}};
                out_half <= 1'b0;
                out_wait <= 1'b1;
            end
        end else if (out_wait) begin
            out_wait <= 1'b0;
            out_load <= 1'b1;
        end else if (out_load) begin
            // Register the synchronous RAM output so backpressure cannot
            // replace the current word with prefetched data.
            out_load   <= 1'b0;
            out_active <= 1'b1;
            out_data   <= rd_selected_data;
            if (BURST_SIZE > 1) begin
                if (rd_consume_bank)
                    rd_raddr1 <= rd_start1 + 1'b1;
                else
                    rd_raddr0 <= rd_start0 + 1'b1;
            end
        end else if (out_accept) begin
            if (!out_half) begin
                out_half <= 1'b1;
            end else begin
                out_half <= 1'b0;
                if (out_word == BURST_LAST) begin
                    out_active      <= 1'b0;
                    rd_consume_bank <= ~rd_consume_bank;
                end else begin
                    out_data <= rd_selected_data;
                    out_word <= out_word + 1'b1;
                    if (out_word != BURST_LAST - 1'b1) begin
                        if (rd_consume_bank)
                            rd_raddr1 <= rd_start1 + out_word + 2'd2;
                        else
                            rd_raddr0 <= rd_start0 + out_word + 2'd2;
                    end
                end
            end
        end
    end

    reg [PREFILL_W-1:0] prefill_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prefill_count <= {PREFILL_W{1'b0}};
            stream_ready  <= 1'b0;
        end else if (!init_done) begin
            prefill_count <= {PREFILL_W{1'b0}};
            stream_ready  <= 1'b0;
        end else if (out_accept && !stream_ready) begin
            if (prefill_count == PREFILL_LAST) begin
                stream_ready <= 1'b1;
            end else begin
                prefill_count <= prefill_count + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // SDRAM command scheduler.
    localparam [3:0] ST_IDLE   = 4'd0;
    localparam [3:0] ST_PRE    = 4'd1;
    localparam [3:0] ST_PRE_W  = 4'd2;
    localparam [3:0] ST_REF    = 4'd3;
    localparam [3:0] ST_REF_W  = 4'd4;
    localparam [3:0] ST_ACT    = 4'd5;
    localparam [3:0] ST_ACT_W  = 4'd6;
    localparam [3:0] ST_WPREP  = 4'd7;
    localparam [3:0] ST_WCMD   = 4'd8;
    localparam [3:0] ST_WDATA  = 4'd9;
    localparam [3:0] ST_WWAIT  = 4'd10;
    localparam [3:0] ST_RCMD   = 4'd11;
    localparam [3:0] ST_RCAP   = 4'd12;

    reg [3:0] state;
    reg       op_read;
    reg       pre_for_refresh;
    reg [20:0] op_addr;
    reg [BURST_AW-1:0] send_word;
    reg [20:0] write_addr;
    reg [20:0] read_addr;
    reg [PENDING_W-1:0] pending_bursts;

    reg        row_open;
    reg [1:0]  open_bank;
    reg [10:0] open_row;
    wire [1:0] op_bank = op_addr[20:19];
    wire [10:0] op_row = op_addr[18:8];

    reg [REFRESH_W-1:0] refresh_count;
    wire refresh_due = (refresh_count >= REFRESH_LAST);
    wire refresh_complete = (state == ST_REF_W) && cmd_ack;
    wire write_release = (state == ST_WWAIT) && cmd_ack;
    wire read_complete = (state == ST_RCAP) && cmd_ack;
    assign read_capture = (state == ST_RCAP);

    wire next_write_full = wr_consume_bank ? wr_full1 : wr_full0;
    wire next_read_free = !(rd_produce_bank ? rd_full1 : rd_full0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_full0 <= 1'b0;
            wr_full1 <= 1'b0;
            rd_full0 <= 1'b0;
            rd_full1 <= 1'b0;
        end else if (!init_done) begin
            wr_full0 <= 1'b0;
            wr_full1 <= 1'b0;
            rd_full0 <= 1'b0;
            rd_full1 <= 1'b0;
        end else begin
            if (pack_commit && !pack_bank) wr_full0 <= 1'b1;
            if (pack_commit &&  pack_bank) wr_full1 <= 1'b1;
            if (write_release && !wr_send_bank) wr_full0 <= 1'b0;
            if (write_release &&  wr_send_bank) wr_full1 <= 1'b0;
            if (read_complete && !rd_produce_bank) rd_full0 <= 1'b1;
            if (read_complete &&  rd_produce_bank) rd_full1 <= 1'b1;
            if (out_release && !rd_consume_bank) rd_full0 <= 1'b0;
            if (out_release &&  rd_consume_bank) rd_full1 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_count <= {REFRESH_W{1'b0}};
        end else if (!init_done || refresh_complete) begin
            refresh_count <= {REFRESH_W{1'b0}};
        end else if (!refresh_due) begin
            refresh_count <= refresh_count + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            user_cmd          <= CMD_NOP;
            user_cmd_en       <= 1'b0;
            user_addr         <= 21'd0;
            user_data         <= 32'd0;
            op_read           <= 1'b0;
            op_addr           <= 21'd0;
            pre_for_refresh   <= 1'b0;
            send_word         <= {BURST_AW{1'b0}};
            write_addr        <= 21'd0;
            read_addr         <= 21'd0;
            pending_bursts    <= {PENDING_W{1'b0}};
            wr_send_bank      <= 1'b0;
            wr_consume_bank   <= 1'b0;
            wr_raddr0         <= {BURST_AW{1'b0}};
            wr_raddr1         <= {BURST_AW{1'b0}};
            rd_produce_bank   <= 1'b0;
            rd_cap_ptr        <= {BURST_AW{1'b0}};
            rd_start0         <= {BURST_AW{1'b0}};
            rd_start1         <= {BURST_AW{1'b0}};
            row_open          <= 1'b0;
            open_bank         <= 2'd0;
            open_row          <= 11'd0;
        end else if (!init_done) begin
            state             <= ST_IDLE;
            user_cmd          <= CMD_NOP;
            user_cmd_en       <= 1'b0;
            user_addr         <= 21'd0;
            user_data         <= 32'd0;
            op_read           <= 1'b0;
            op_addr           <= 21'd0;
            pre_for_refresh   <= 1'b0;
            send_word         <= {BURST_AW{1'b0}};
            write_addr        <= 21'd0;
            read_addr         <= 21'd0;
            pending_bursts    <= {PENDING_W{1'b0}};
            wr_send_bank      <= 1'b0;
            wr_consume_bank   <= 1'b0;
            wr_raddr0         <= {BURST_AW{1'b0}};
            wr_raddr1         <= {BURST_AW{1'b0}};
            rd_produce_bank   <= 1'b0;
            rd_cap_ptr        <= {BURST_AW{1'b0}};
            rd_start0         <= {BURST_AW{1'b0}};
            rd_start1         <= {BURST_AW{1'b0}};
            row_open          <= 1'b0;
            open_bank         <= 2'd0;
            open_row          <= 11'd0;
        end else begin
            user_cmd_en <= 1'b0;
            user_cmd    <= CMD_NOP;

            // A completed pack bank can preload word zero while the command
            // scheduler finishes its current operation.
            if (pack_commit) begin
                if (pack_bank)
                    wr_raddr1 <= {BURST_AW{1'b0}};
                else
                    wr_raddr0 <= {BURST_AW{1'b0}};
            end

            case (state)
                ST_IDLE: begin
                    if (refresh_due) begin
                        pre_for_refresh <= 1'b1;
                        state <= row_open ? ST_PRE : ST_REF;
                    end else if ((pending_bursts != 0) && next_read_free) begin
                        op_read         <= 1'b1;
                        op_addr         <= read_addr;
                        pre_for_refresh <= 1'b0;
                        if (!row_open)
                            state <= ST_ACT;
                        else if ((open_bank == read_addr[20:19]) && (open_row == read_addr[18:8]))
                            state <= ST_RCMD;
                        else
                            state <= ST_PRE;
                    end else if (next_write_full && (pending_bursts != MAX_PENDING)) begin
                        op_read         <= 1'b0;
                        op_addr         <= write_addr;
                        wr_send_bank    <= wr_consume_bank;
                        pre_for_refresh <= 1'b0;
                        if (!row_open)
                            state <= ST_ACT;
                        else if ((open_bank == write_addr[20:19]) && (open_row == write_addr[18:8]))
                            state <= ST_WPREP;
                        else
                            state <= ST_PRE;
                    end
                end

                ST_PRE: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_PRECHARGE;
                    user_addr   <= {open_bank, 19'd0};
                    state       <= ST_PRE_W;
                end

                ST_PRE_W: begin
                    if (cmd_ack) begin
                        row_open <= 1'b0;
                        state <= pre_for_refresh ? ST_REF : ST_ACT;
                    end
                end

                ST_REF: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_REFRESH;
                    state       <= ST_REF_W;
                end

                ST_REF_W: begin
                    if (cmd_ack) begin
                        pre_for_refresh <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                ST_ACT: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_ACTIVE;
                    user_addr   <= {op_bank, op_row, 8'd0};
                    state       <= ST_ACT_W;
                end

                ST_ACT_W: begin
                    if (cmd_ack) begin
                        row_open  <= 1'b1;
                        open_bank <= op_bank;
                        open_row  <= op_row;
                        state <= op_read ? ST_RCMD : ST_WPREP;
                    end
                end

                ST_WPREP: begin
                    user_data <= wr_selected_data;
                    if (wr_send_bank)
                        wr_raddr1 <= {{(BURST_AW-1){1'b0}}, 1'b1};
                    else
                        wr_raddr0 <= {{(BURST_AW-1){1'b0}}, 1'b1};
                    state <= ST_WCMD;
                end

                ST_WCMD: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_WRITE;
                    user_addr   <= op_addr;
                    send_word   <= {{(BURST_AW-1){1'b0}}, 1'b1};
                    if (wr_send_bank)
                        wr_raddr1 <= {{(BURST_AW-2){1'b0}}, 2'd2};
                    else
                        wr_raddr0 <= {{(BURST_AW-2){1'b0}}, 2'd2};
                    state <= ST_WDATA;
                end

                ST_WDATA: begin
                    user_data <= wr_selected_data;
                    if (send_word == BURST_LAST) begin
                        state <= ST_WWAIT;
                    end else begin
                        send_word <= send_word + 1'b1;
                        if (wr_send_bank)
                            wr_raddr1 <= send_word + 2'd2;
                        else
                            wr_raddr0 <= send_word + 2'd2;
                    end
                end

                ST_WWAIT: begin
                    if (cmd_ack) begin
                        wr_consume_bank <= ~wr_consume_bank;
                        pending_bursts  <= pending_bursts + 1'b1;
                        if (write_addr >= FRAME_LAST_START)
                            write_addr <= 21'd0;
                        else
                            write_addr <= write_addr + BURST_STEP;
                        state <= ST_IDLE;
                    end
                end

                ST_RCMD: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_READ;
                    user_addr   <= op_addr;
                    rd_cap_ptr  <= {BURST_AW{1'b0}};
                    state       <= ST_RCAP;
                end

                ST_RCAP: begin
                    rd_cap_ptr <= rd_cap_ptr + 1'b1;
                    if (cmd_ack) begin
                        if (rd_produce_bank)
                            rd_start1 <= rd_cap_ptr + 1'b1;
                        else
                            rd_start0 <= rd_cap_ptr + 1'b1;
                        rd_produce_bank <= ~rd_produce_bank;
                        pending_bursts  <= pending_bursts - 1'b1;
                        if (read_addr >= FRAME_LAST_START)
                            read_addr <= 21'd0;
                        else
                            read_addr <= read_addr + BURST_STEP;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
