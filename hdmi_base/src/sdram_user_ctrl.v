//====================================================================
// sdram_user_ctrl.v
// Burst-mode read/write sequencer for the Gowin SDRAM Controller HS IP.
//
// IMPORTANT (per Gowin "SDRAM Controller HS" User Guide IPUG756):
//   * I_sdrc_cmd[2:0] is the raw SDRAM command bus {RAS#, CAS#, WE#}
//       ACTIVE    = 3'b011
//       WRITE     = 3'b100
//       READ      = 3'b101
//       PRECHARGE = 3'b010
//       REFRESH   = 3'b001
//       NOP       = 3'b111
//   * user_len is 0-based: value N-1 means a burst of N words.
//   * Each command: assert user_cmd_en for exactly 1 cycle together with
//     the command + address. For a WRITE burst, word 0 is presented on the
//     same cycle as the command and words 1..N-1 on the following cycles.
//   * O_sdrc_cmd_ack pulses for 1 cycle when the command's execution is
//     complete; wait for it before issuing the next command.
//   * The IP has NO O_sdrc_data_valid. Read data appears on O_sdrc_data
//     (a registered copy of the SDRAM DQ bus); cmd_ack for a READ aligns
//     with the last read word, so the last N samples before cmd_ack are the
//     read data (captured here into a circular buffer).
//   * Auto-refresh is user controlled: we issue REFRESH periodically
//     (~14.4us @166.5MHz) between bursts.
//
// RD_OUT_EN=1 (default): after every write burst the same address is read
// back and streamed out as 16-bit pixels (rd_pix/rd_pix_valid) to the
// line-buffer async FIFO. NOTE: write+readback of each burst halves the
// effective write bandwidth; set RD_OUT_EN=0 for pure write-only mode.
//====================================================================
// TIMING NOTE (Aug 2026): BURST_SIZE=32 + readback blew up clk_sys
// (166.5MHz) timing (TNS -622ns, 828 endpoints, Fmax ~105MHz) and broke the
// HDMI pattern path. Keep BURST_SIZE small (main uses 4); shift-register
// write output avoids the indexed-mux fanout; readout uses a small circular
// buffer (N deep) so its mux stays small.
module sdram_user_ctrl #(
    parameter integer BURST_SIZE = 16,   // words per burst (power of 2, 1..256)
    parameter integer RD_OUT_EN  = 1,    // 1: write + readback to FIFO, 0: write only
    parameter integer SELFTEST_EN = 0    // 1: write KNOWN data, read back, self-check (board bring-up)
) (
    input             clk,               // I_sdrc_clk (clk_sys)
    input             rst_n,
    input             init_done,         // O_sdrc_init_done
    input             cmd_ack,           // O_sdrc_cmd_ack
    input             pix_valid,         // 16-bit pixel valid (write source)
    input      [15:0] pix_data,
    // To the SDRAM HS controller IP
    output reg [2:0]  user_cmd,
    output reg        user_cmd_en,
    output reg [20:0] user_addr,         // {bank[20:19], row[18:8], col[7:0]}
    output reg [31:0] user_data,
    output     [7:0]  user_len,          // burst length - 1 (0-based)
    // From the SDRAM HS controller IP
    input      [31:0] read_data,         // O_sdrc_data
    // To the line-buffer async FIFO (16-bit pixels, clk_sys write side)
    output reg [15:0] rd_pix,            // read-back pixel
    output reg        rd_pix_valid,      // pixel valid (FIFO write strobe)
    input             rd_ready,          // FIFO not full (backpressure)
    output            wr_ready,          // 1 when a pixel can be accepted (write path)
    // Board bring-up self-test status
    output reg        selftest_done,     // pulses once per self-checked burst (loop running)
    output reg        selftest_err,      // sticky: any read-back mismatch
    output reg [15:0] selftest_err_cnt   // running mismatch count
);

    // ---- SDRAM command encoding (IPUG756 Table 6-1) ----
    localparam CMD_NOP       = 3'b111;
    localparam CMD_ACTIVE    = 3'b011;
    localparam CMD_WRITE     = 3'b100;
    localparam CMD_READ      = 3'b101;
    localparam CMD_PRECHARGE = 3'b010;
    localparam CMD_REFRESH   = 3'b001;

    // ---- geometry / limits ----
    localparam SDRAM_HALF_WORDS = 21'h100000;          // use first half (4MB)
    localparam [7:0] N1         = BURST_SIZE[7:0] - 8'd1; // last index / data_len
    localparam [7:0] RD_MASK    = BURST_SIZE[7:0] - 8'd1; // circular buffer mask (N must be power of 2)
    localparam [23:0] REFRESH_PERIOD = 24'd2400;           // ~14.4us @ 166.5MHz

    assign user_len = N1;

    // write-path pixel-accept strobe: the pattern gen may only advance a
    // pixel while the controller is collecting a burst (lossless write)
    assign wr_ready = (state == ST_PACK);

    // ---- FSM states ----
    // Command states assert user_cmd_en for exactly ONE cycle (IPUG756:
    // cmd_en is a 1-cycle pulse), then a matching _W state waits for cmd_ack.
    localparam ST_IDLE  = 4'd0;
    localparam ST_PACK  = 4'd1;   // collect pixels into burst_buf
    localparam ST_PRE   = 4'd2;   // issue PRECHARGE
    localparam ST_PRE_W = 4'd3;   // wait PRECHARGE ack
    localparam ST_REF   = 4'd4;   // issue AUTO REFRESH
    localparam ST_REF_W = 4'd5;   // wait REFRESH ack
    localparam ST_ACT   = 4'd6;   // issue ACTIVATE (bank,row)
    localparam ST_ACT_W = 4'd7;   // wait ACTIVATE ack
    localparam ST_WCMD  = 4'd8;   // issue WRITE + word 0
    localparam ST_WDAT  = 4'd9;   // stream words 1..N-1
    localparam ST_WWAIT = 4'd10;  // wait write cmd_ack
    localparam ST_RCMD  = 4'd11;  // issue READ
    localparam ST_RCAP  = 4'd12;  // capture read data until cmd_ack
    localparam ST_ROUT  = 4'd13;  // stream read-back pixels to the FIFO
    localparam ST_NEXT  = 4'd14;  // advance address, back to PACK

    reg [3:0]  state;
    reg [7:0]  pack_cnt;
    reg [7:0]  send_cnt;
    reg        half_word;
    reg [15:0] pix_lo;
    reg [20:0] wr_word_addr;              // linear word address of current burst
    reg [31:0] burst_buf [0:BURST_SIZE-1]; // written data (storage for VERIFY)
    reg [31:0] wr_shift [0:BURST_SIZE-1];  // shift register driving user_data out
    reg [31:0] rd_buf    [0:BURST_SIZE-1]; // readback capture (circular)
    reg [7:0]  rd_wptr;
    reg [7:0]  rd_word_idx;                // read-out word counter
    reg        rd_half;                    // low/high 16-bit half of current word
    reg        row_open;
    reg [10:0] cur_row;
    reg [1:0]  cur_bank;
    reg [23:0] ref_cnt;
    reg        ref_pending;
    integer    i;

    // target bank/row/col for the current burst address
    wire [1:0]  tgt_bank = wr_word_addr[20:19];
    wire [10:0] tgt_row  = wr_word_addr[18:8];
    wire [7:0]  tgt_col  = wr_word_addr[7:0];
    wire        row_same = row_open && (cur_bank == tgt_bank) && (cur_row == tgt_row);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            user_cmd     <= CMD_NOP;
            user_cmd_en  <= 1'b0;
            user_addr    <= 21'd0;
            user_data    <= 32'd0;
            pack_cnt     <= 8'd0;
            send_cnt     <= 8'd0;
            half_word    <= 1'b0;
            pix_lo       <= 16'd0;
            wr_word_addr <= 21'd0;
            for (i = 0; i < BURST_SIZE; i = i + 1) begin
                wr_shift[i] <= 32'd0;
            end
            rd_wptr      <= 8'd0;
            rd_word_idx  <= 8'd0;
            rd_half      <= 1'b0;
            rd_pix       <= 16'd0;
            rd_pix_valid <= 1'b0;
            selftest_done <= 1'b0;
            selftest_err  <= 1'b0;
            selftest_err_cnt <= 16'd0;
            row_open     <= 1'b0;
            cur_row      <= 11'd0;
            cur_bank     <= 2'd0;
            ref_cnt      <= 24'd0;
            ref_pending  <= 1'b0;
        end else begin
            // defaults
            user_cmd_en   <= 1'b0;
            user_cmd      <= CMD_NOP;
            rd_pix_valid  <= 1'b0;
            selftest_done <= 1'b0;

            // free-running refresh timer
            if (ref_cnt == REFRESH_PERIOD) begin
                ref_cnt     <= 24'd0;
                ref_pending <= 1'b1;
            end else begin
                ref_cnt <= ref_cnt + 1'b1;
            end

            case (state)
                //------------------------------------------------------
                ST_IDLE: begin
                    if (init_done) state <= ST_PACK;
                end

                //------------------------------------------------------
                // Pack pairs of 16-bit pixels into 32-bit words.
                // SELFTEST: fill the burst with KNOWN data (independent of the
                // pattern generator) so the board LEDs can verify write+read.
                ST_PACK: begin
                    if (SELFTEST_EN) begin
                        burst_buf[pack_cnt] <= {wr_word_addr[7:0], pack_cnt, 16'hA55A};
                        if (pack_cnt == N1) begin
                            pack_cnt <= 8'd0;
                            if (ref_pending) begin
                                state <= row_open ? ST_PRE : ST_REF;
                            end else if (!row_open) begin
                                state <= ST_ACT;
                            end else if (!row_same) begin
                                state <= ST_PRE;
                            end else begin
                                state <= ST_WCMD;
                            end
                        end else begin
                            pack_cnt <= pack_cnt + 1'b1;
                        end
                    end else if (pix_valid) begin
                        if (!half_word) begin
                            pix_lo    <= pix_data;
                            half_word <= 1'b1;
                        end else begin
                            burst_buf[pack_cnt] <= {pix_data, pix_lo};
                            half_word <= 1'b0;
                            if (pack_cnt == N1) begin
                                pack_cnt <= 8'd0;
                                // dispatch: refresh / activate / write now
                                if (ref_pending) begin
                                    state <= row_open ? ST_PRE : ST_REF;
                                end else if (!row_open) begin
                                    state <= ST_ACT;
                                end else if (!row_same) begin
                                    state <= ST_PRE;
                                end else begin
                                    state <= ST_WCMD;
                                end
                            end else begin
                                pack_cnt <= pack_cnt + 1'b1;
                            end
                        end
                    end
                end

                //------------------------------------------------------
                ST_PRE: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_PRECHARGE;
                    user_addr   <= {tgt_bank, 11'd0, 8'd0};  // A10=0: single-bank
                    state       <= ST_PRE_W;
                end

                ST_PRE_W: begin
                    if (cmd_ack) begin
                        row_open <= 1'b0;
                        state    <= ref_pending ? ST_REF : ST_ACT;
                    end
                end

                ST_REF: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_REFRESH;
                    state       <= ST_REF_W;
                end

                ST_REF_W: begin
                    if (cmd_ack) begin
                        ref_pending <= 1'b0;
                        state       <= ST_ACT;
                    end
                end

                ST_ACT: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_ACTIVE;
                    user_addr   <= {tgt_bank, tgt_row, 8'd0};
                    state       <= ST_ACT_W;
                end

                ST_ACT_W: begin
                    if (cmd_ack) begin
                        row_open <= 1'b1;
                        cur_bank <= tgt_bank;
                        cur_row  <= tgt_row;
                        state    <= ST_WCMD;
                    end
                end

                //------------------------------------------------------
                // Write burst: word 0 with the command, then stream words
                // 1..N-1 from the shift register (no indexed-mux fanout).
                ST_WCMD: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_WRITE;
                    user_addr   <= wr_word_addr;
                    user_data   <= burst_buf[0];   // word 0 together with command
                    send_cnt    <= 8'd1;
                    // pre-load shift register with words 1..N-1
                    for (i = 0; i < BURST_SIZE-1; i = i + 1)
                        wr_shift[i] <= burst_buf[i+1];
                    state       <= ST_WDAT;
                end

                ST_WDAT: begin
                    user_data <= wr_shift[0];      // stream words 1..N-1
                    for (i = 0; i < BURST_SIZE-1; i = i + 1)
                        wr_shift[i] <= wr_shift[i+1];
                    if (send_cnt == N1) begin
                        send_cnt <= 8'd0;
                        state    <= ST_WWAIT;
                    end else begin
                        send_cnt <= send_cnt + 1'b1;
                    end
                end

                ST_WWAIT: begin
                    if (cmd_ack) begin
                        // readback needed for FIFO output OR for the self-test
                        state <= (RD_OUT_EN || SELFTEST_EN) ? ST_RCMD : ST_NEXT;
                    end
                end

                //------------------------------------------------------
                // Read back the burst just written and stream it to the FIFO.
                ST_RCMD: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_READ;
                    user_addr   <= wr_word_addr;
                    rd_wptr     <= 8'd0;
                    state       <= ST_RCAP;
                end

                ST_RCAP: begin
                    // circular capture; the i-th read word is stored at
                    // (rd_wptr + i) & RD_MASK when capture ends (cmd_ack)
                    rd_buf[rd_wptr & RD_MASK] <= read_data;
                    rd_wptr <= rd_wptr + 1'b1;
                    if (cmd_ack) begin
                        rd_word_idx <= 8'd0;
                        rd_half     <= 1'b0;
                        state       <= ST_ROUT;
                    end
                end

                ST_ROUT: begin
                    if (SELFTEST_EN) begin
                        // compare each read-back word against what was written
                        if (rd_buf[(rd_wptr + rd_word_idx) & RD_MASK] !== burst_buf[rd_word_idx]) begin
                            selftest_err_cnt <= selftest_err_cnt + 16'd1;
                            selftest_err     <= 1'b1;
                        end
                        if (rd_word_idx == N1) begin
                            rd_word_idx    <= 8'd0;
                            selftest_done  <= 1'b1;   // 1-cycle pulse per checked burst
                            state          <= ST_NEXT;
                        end else begin
                            rd_word_idx <= rd_word_idx + 1'b1;
                        end
                    end else if (rd_ready) begin
                        // output 2N 16-bit pixels: low half then high half of each
                        // 32-bit word, gated by the FIFO backpressure (rd_ready)
                        if (!rd_half) begin
                            rd_pix       <= rd_buf[(rd_wptr + rd_word_idx) & RD_MASK][15:0];
                            rd_pix_valid <= 1'b1;
                            rd_half      <= 1'b1;
                        end else begin
                            rd_pix       <= rd_buf[(rd_wptr + rd_word_idx) & RD_MASK][31:16];
                            rd_pix_valid <= 1'b1;
                            rd_half      <= 1'b0;
                            if (rd_word_idx == N1) begin
                                rd_word_idx <= 8'd0;
                                state       <= ST_NEXT;
                            end else begin
                                rd_word_idx <= rd_word_idx + 1'b1;
                            end
                        end
                    end
                end

                //------------------------------------------------------
                // Advance to the next burst address.
                ST_NEXT: begin
                    if (wr_word_addr >= (SDRAM_HALF_WORDS - BURST_SIZE[20:0]))
                        wr_word_addr <= 21'd0;
                    else
                        wr_word_addr <= wr_word_addr + BURST_SIZE[20:0];
                    state <= ST_PACK;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule