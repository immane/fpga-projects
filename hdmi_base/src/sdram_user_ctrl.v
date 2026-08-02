//====================================================================
// sdram_user_ctrl.v
// ROLLING FRAME-BUFFER controller for the Gowin SDRAM Controller HS IP.
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
// ARCHITECTURE (why this is different from the old write+readback streamer):
//   The old per-burst "write then read back the same burst" design could
//   never sustain 1080p30: BURST_SIZE=4 => 8 pixels per burst, but the
//   display needs 62M px/s, so the line-buffer FIFO permanently underran and
//   the screen showed the frozen/green streaming data. The fix is a FRAME
//   BUFFER: write a whole frame's worth of pixels into SDRAM and read it back
//   with independent pointers. Because the test pattern is STATIC (identical
//   every frame), the value at any frame address is always the same, so the
//   write and read pointers can free-run independently - no frame sync, no
//   lag bookkeeping. Reads are gated by fb_ready until the first full frame
//   is stored (SDRAM is uninitialized at power-up).
//
//   * Write path: 16-bit pixels are packed 2-per-32-bit-word into wbuf, then
//     burst-written at w_addr. wr_ready backpressures the pattern gen so no
//     pixel is ever dropped.
//   * Read path: r_addr sweeps the same frame region; burst-reads refill
//     rd_pix/rd_pix_valid into the line-buffer async FIFO (rd_ready gates).
//   * One SDRAM command bus: a single FSM round-robins WRITE/READ bursts
//     ('turn' bit), inserts periodic REFRESH, and PRECHARGEs after every data
//     burst (the HS controller enforces tRP/tRFC via cmd_ack timing).
//   * Bandwidth: 1080p30 needs 31 Mwords/s write + 31 Mwords/s read = 62
//     Mwords/s; SDRAM 32-bit @166.5MHz peaks at 166 Mwords/s so there is
//     ample headroom even with per-burst ACT+PRE overhead.
//====================================================================
// TIMING NOTE (Aug 2026): BURST_SIZE=32 + readback blew up clk_sys
// (166.5MHz) timing (TNS -622ns, 828 endpoints, Fmax ~105MHz) and broke the
// HDMI pattern path. Keep BURST_SIZE small (main uses 4); shift-register
// write output avoids the indexed-mux fanout; readout uses a small circular
// buffer (N deep) so its mux stays small.
// FRAME-BUFFER controller for the Gowin SDRAM Controller HS IP.
//
// ROLLING FRAME BUFFER on a STATIC test pattern (the correct architecture to
// actually drive 1080p from SDRAM - per-burst write+readback streaming could
// never fill a frame: 8px/burst vs 62Mpx/s needed, hence the green/flicker).
//
//   * Write side: pattern pixels (pix_valid/pix_data, 16-bit) are packed
//     2-per-32-bit-word into wbuf, then burst-written to SDRAM at w_addr.
//     The pattern gen is backpressured via wr_ready, so nothing is dropped.
//   * Read side: r_addr sweeps the same frame region; burst-reads refill
//     rd_pix/rd_pix_valid into the line-buffer async FIFO (rd_ready gates).
//   * Because the pattern is STATIC (identical every frame), the value at any
//     frame address is the same regardless of when it was written, so w_addr
//     and r_addr can free-run independently - no frame sync / lag needed.
//     Reads are gated by fb_ready until the first full frame is stored
//     (SDRAM starts uninitialized).
//   * One command bus: a single FSM alternates WRITE/READ bursts with a
//     'turn' round-robin, inserts periodic REFRESH, and PRECHARGEs after
//     every burst (HS controller enforces tRP/tRFC via cmd_ack timing).
//
// Bandwidth: 1080p30 needs 31 Mwords/s write + 31 Mwords/s read = 62 Mwords/s.
// SDRAM 32-bit @166.5MHz peaks at 166 Mwords/s; even with ACT+PRE overhead and
// 50% efficiency this has ~2x headroom. BURST_SIZE=64 amortises the overhead.
module sdram_user_ctrl #(
    parameter integer BURST_SIZE = 64,   // words per burst (power of 2, <= 256)
    parameter integer FB_WORDS   = 1048576 // frame region in 32-bit words (2^20 = 1080p30 RGB565)
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
    // Status
    output reg        fb_ready,          // first full frame stored (display valid)
    output reg        selftest_done,     // retained port (unused)
    output reg        selftest_err,      // retained port (unused)
    output reg [15:0] selftest_err_cnt   // retained port (unused)
);

    // ---- SDRAM command encoding (IPUG756 Table 6-1) ----
    localparam CMD_NOP       = 3'b111;
    localparam CMD_ACTIVE    = 3'b011;
    localparam CMD_WRITE     = 3'b100;
    localparam CMD_READ      = 3'b101;
    localparam CMD_PRECHARGE = 3'b010;
    localparam CMD_REFRESH   = 3'b001;

    // ---- geometry / limits ----
    localparam [7:0]  N1         = BURST_SIZE[7:0] - 8'd1;   // last index / data_len
    localparam [7:0]  RD_MASK    = BURST_SIZE[7:0] - 8'd1;   // circular buffer mask (N power of 2)
    localparam [20:0] FB_WORDS_C = FB_WORDS[20:0];           // frame words (1,036,800 = 1080p30)
    localparam [23:0] REFRESH_PERIOD = 24'd2400;             // ~14.4us @ 166.5MHz

    // wrap a linear address to the frame region (FB_WORDS is not a power of 2)
    function [20:0] wrap_fb;
        input [20:0] a;
        input [20:0] inc;
        begin
            wrap_fb = (a >= (FB_WORDS_C - inc)) ? 21'd0 : (a + inc);
        end
    endfunction

    assign user_len = N1;

    // write-path pixel-accept strobe (lossless write backpressure).
    // NOTE: pattern_gen presents a pixel ONE cycle after `ready` (its ve is
    // registered), so wr_ready must go low a cycle BEFORE the controller
    // stops accepting:
    //   * last_word_fill : the pixel arriving this cycle fills the last word
    //     (half_word && wcnt==N1) -> stop NOW so no un-acceptable pixel comes.
    //   * dispatch_here  : this cycle the FSM also leaves ST_PACK for a
    //     READ/REFRESH/WRITE burst -> stop NOW so the pixel that would be
    //     presented next cycle is not dropped (the pixel accepted this cycle
    //     is still consumed correctly).
    // A round-robin 'turn' bit alternates write/read bursts so neither path
    // starves (read_pending is high almost always -> without 'turn' writes
    // would be blocked by the dispatch gating forever).
    wire        last_word_fill = pix_valid && half_word && (wcnt == N1);
    wire        dispatch_here  = ref_pending || wb_full || (read_pending && turn);
    assign wr_ready = (state == ST_PACK) && !wb_writing && !wb_full
                      && !last_word_fill && !dispatch_here;

    // ---- FSM states ----
    // Command states assert user_cmd_en for exactly ONE cycle (IPUG756:
    // cmd_en is a 1-cycle pulse), then a matching _W state waits for cmd_ack.
    // We service write bursts and read bursts with a round-robin 'turn' flag.
    localparam ST_IDLE  = 4'd0;
    localparam ST_PACK  = 4'd1;   // collect pixels into wbuf / decide next op
    localparam ST_PRE   = 4'd2;   // issue PRECHARGE (close row)
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
    localparam ST_NEXT  = 4'd14;  // advance write/read pointer, precharge, back to PACK

    reg [3:0]  state;
    reg [7:0]  wcnt;                // words packed in wbuf (0..BURST_SIZE)
    reg [7:0]  send_cnt;
    reg        half_word;
    reg [15:0] pix_lo;
    reg        wb_full;             // wbuf has a full burst ready to write
    reg        wb_writing;          // a write burst is in flight (wbuf busy)
    reg [20:0] w_addr;              // linear word address of write pointer
    reg [20:0] r_addr;              // linear word address of read pointer
    reg        is_read;             // current burst is a read (else write)
    reg        turn;                // round-robin: 1 = prefer a READ next
    reg        row_open;
    reg [10:0] cur_row;
    reg [1:0]  cur_bank;
    reg [31:0] wbuf     [0:BURST_SIZE-1]; // write pack SHIFT REGISTER (wbuf[0]=first word)
                                          // indexed write was a timing killer (wcnt==i
                                          // decode on 2048 CE pins) - replaced by a
                                          // shared-enable shift register
    reg [31:0] wr_shift [0:BURST_SIZE-1]; // shift register driving user_data out
    reg [31:0] rd_buf   [0:BURST_SIZE-1]; // readback capture (circular)
    reg [7:0]  rd_wptr;
    reg [7:0]  rd_word_idx;         // read-out word counter
    reg [7:0]  rd_out_ptr;          // read-out index (no add: loaded at capture end)
    reg        rd_half;             // low/high 16-bit half of current word
    reg [23:0] ref_cnt;
    reg        ref_pending;
    integer    i;

    // target bank/row/col for a linear address (single-bank row open tracking)
    wire [1:0]  tgt_bank = is_read ? r_addr[20:19] : w_addr[20:19];
    wire [10:0] tgt_row  = is_read ? r_addr[18:8]  : w_addr[18:8];
    // read is only legal once the first full frame is in SDRAM
    wire        read_pending = fb_ready && rd_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            user_cmd     <= CMD_NOP;
            user_cmd_en  <= 1'b0;
            user_addr    <= 21'd0;
            user_data    <= 32'd0;
            wcnt         <= 8'd0;
            send_cnt     <= 8'd0;
            half_word    <= 1'b0;
            pix_lo       <= 16'd0;
            wb_full      <= 1'b0;
            wb_writing   <= 1'b0;
            w_addr       <= 21'd0;
            r_addr       <= 21'd0;
            is_read      <= 1'b0;
            turn         <= 1'b1;   // prefer a read after the first frame
            row_open     <= 1'b0;
            cur_row      <= 11'd0;
            cur_bank     <= 2'd0;
            for (i = 0; i < BURST_SIZE; i = i + 1) begin
                wbuf[i]     <= 32'd0;
                wr_shift[i] <= 32'd0;
                rd_buf[i]   <= 32'd0;
            end
            rd_wptr      <= 8'd0;
            rd_word_idx  <= 8'd0;
            rd_out_ptr   <= 8'd0;
            rd_half      <= 1'b0;
            rd_pix       <= 16'd0;
            rd_pix_valid <= 1'b0;
            fb_ready     <= 1'b0;
            selftest_done <= 1'b0;
            selftest_err  <= 1'b0;
            selftest_err_cnt <= 16'd0;
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
                // Pack pairs of 16-bit pixels into 32-bit words. When a full
                // burst is ready, dispatch a WRITE (priority); otherwise, if
                // the FIFO needs data and reads are allowed, dispatch a READ.
                // Every data burst is followed by a PRECHARGE (ST_NEXT ->
                // ST_PRE), so at this point row_open is always 0 -> start
                // each burst with an ACTIVATE.
                ST_PACK: begin
                    // 1) accept write pixels (lossless, backpressured)
                    if (!wb_writing && !wb_full && pix_valid) begin
                        if (!half_word) begin
                            pix_lo    <= pix_data;
                            half_word <= 1'b1;
                        end else begin
                            // completed 32-bit word {pix_data, pix_lo}: shift it
                            // into the pack shift register. wbuf[0] holds the
                            // FIRST word (written first), wbuf[N-1] the last.
                            for (i = 0; i < BURST_SIZE-1; i = i + 1)
                                wbuf[i] <= wbuf[i+1];
                            wbuf[BURST_SIZE-1] <= {pix_data, pix_lo};
                            half_word <= 1'b0;
                            if (wcnt == N1) begin
                                wcnt     <= 8'd0;
                                wb_full  <= 1'b1;
                            end else begin
                                wcnt <= wcnt + 1'b1;
                            end
                        end
                    end

                    // 2) dispatch (round-robin: refresh > write > read)
                    if (ref_pending) begin
                        state <= ST_REF;      // refresh first (all banks closed)
                    end else if (wb_full) begin
                        is_read <= 1'b0;
                        turn    <= 1'b1;      // prefer a read after this write
                        state   <= ST_ACT;    // write burst
                    end else if (read_pending && turn) begin
                        is_read <= 1'b1;
                        turn    <= 1'b0;      // prefer a write after this read
                        state   <= ST_ACT;    // read burst
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
                        state    <= ST_PACK;
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
                        state       <= ST_PACK;
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
                        state    <= is_read ? ST_RCMD : ST_WCMD;
                    end
                end

                //------------------------------------------------------
                // Write burst: word 0 with the command, then stream words
                // 1..N-1 from the shift register (no indexed-mux fanout).
                ST_WCMD: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_WRITE;
                    user_addr   <= w_addr;
                    user_data   <= wbuf[0];   // word 0 together with command
                    send_cnt    <= 8'd1;
                    wb_writing  <= 1'b1;
                    for (i = 0; i < BURST_SIZE-1; i = i + 1)
                        wr_shift[i] <= wbuf[i+1];
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
                        wb_writing <= 1'b0;
                        wb_full    <= 1'b0;
                        if (w_addr >= (FB_WORDS_C - BURST_SIZE[20:0])) begin
                            w_addr   <= 21'd0;
                            fb_ready <= 1'b1;   // frame wrapped: fully written
                        end else begin
                            w_addr <= w_addr + BURST_SIZE[20:0];
                        end
                        state      <= ST_NEXT;
                    end
                end

                //------------------------------------------------------
                // Read burst: capture read data until cmd_ack, then stream.
                ST_RCMD: begin
                    user_cmd_en <= 1'b1;
                    user_cmd    <= CMD_READ;
                    user_addr   <= r_addr;
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
                        // rotation offset = final rd_wptr (post-increment, K)
                        rd_out_ptr  <= (rd_wptr + 1'b1) & RD_MASK;
                        rd_half     <= 1'b0;
                        state       <= ST_ROUT;
                    end
                end

                ST_ROUT: begin
                    // output 2N 16-bit pixels: low half then high half of each
                    // 32-bit word, gated by the FIFO backpressure (rd_ready)
                    if (rd_ready) begin
                        if (!rd_half) begin
                            rd_pix       <= rd_buf[rd_out_ptr][15:0];
                            rd_pix_valid <= 1'b1;
                            rd_half      <= 1'b1;
                        end else begin
                            rd_pix       <= rd_buf[rd_out_ptr][31:16];
                            rd_pix_valid <= 1'b1;
                            rd_half      <= 1'b0;
                            if (rd_word_idx == N1) begin
                                rd_word_idx <= 8'd0;
                                r_addr      <= wrap_fb(r_addr, BURST_SIZE[20:0]);
                                state       <= ST_NEXT;
                            end else begin
                                rd_word_idx <= rd_word_idx + 1'b1;
                                rd_out_ptr  <= (rd_out_ptr + 1'b1) & RD_MASK;
                            end
                        end
                    end
                end

                //------------------------------------------------------
                // Close the row after every data burst, back to PACK.
                ST_NEXT: begin
                    state <= row_open ? ST_PRE : ST_PACK;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule