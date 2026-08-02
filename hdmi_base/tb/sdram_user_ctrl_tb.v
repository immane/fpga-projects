`timescale 1ns/1ps
module sdram_user_ctrl_tb;
    localparam BURST_SIZE = 64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg rd_ready = 1'b1;
    always #3 clk = ~clk;

    wire init_done;
    wire cmd_ack;
    wire protocol_error;
    wire [31:0] read_data;
    wire [2:0] user_cmd;
    wire user_cmd_en;
    wire [20:0] user_addr;
    wire [31:0] user_data;
    wire [7:0] user_len;
    wire [15:0] rd_pix;
    wire rd_pix_valid;
    wire wr_ready;
    wire stream_ready;

    reg [15:0] source_pixel = 16'd0;
    wire pix_valid = wr_ready;
    wire [15:0] pix_data = source_pixel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            source_pixel <= 16'd0;
        else if (pix_valid && wr_ready)
            source_pixel <= source_pixel + 1'b1;
    end

    sdram_user_ctrl #(
        .BURST_SIZE(BURST_SIZE),
        .CLK_FREQ_HZ(166_500_000),
        .FRAME_WORDS(1_036_800),
        .MAX_PENDING_BURSTS(64),
        .PREFILL_PIXELS(128)
    ) uut (
        .clk(clk), .rst_n(rst_n), .init_done(init_done), .cmd_ack(cmd_ack),
        .pix_valid(pix_valid), .pix_data(pix_data), .wr_ready(wr_ready),
        .user_cmd(user_cmd), .user_cmd_en(user_cmd_en), .user_addr(user_addr),
        .user_data(user_data), .user_len(user_len), .read_data(read_data),
        .rd_pix(rd_pix), .rd_pix_valid(rd_pix_valid), .rd_ready(rd_ready),
        .stream_ready(stream_ready)
    );

    sdram_hs_model #(.CL(3), .WR(2), .RP(3), .RCD(3)) model (
        .clk(clk), .rst_n(rst_n), .cmd_en(user_cmd_en), .cmd(user_cmd),
        .addr(user_addr), .data(user_data), .data_len(user_len),
        .o_data(read_data), .cmd_ack(cmd_ack), .init_done(init_done),
        .protocol_error(protocol_error)
    );

    integer accepted = 0;
    integer emitted = 0;
    integer errors = 0;
    integer writes = 0;
    integer reads = 0;
    integer refreshes = 0;
    integer activates = 0;
    integer precharges = 0;
    reg [15:0] expected = 16'd0;

    always @(posedge clk) begin
        if (pix_valid && wr_ready)
            accepted = accepted + 1;
        if (rd_pix_valid && rd_ready) begin
            if (rd_pix !== expected) begin
                errors = errors + 1;
                if (errors < 8)
                    $display("MISMATCH t=%0t got=%h expected=%h state=%0d", $time, rd_pix, expected, uut.state);
            end
            expected = expected + 1'b1;
            emitted = emitted + 1;
        end
        if (user_cmd_en) begin
            if (user_cmd == 3'b100) writes = writes + 1;
            if (user_cmd == 3'b101) reads = reads + 1;
            if (user_cmd == 3'b001) refreshes = refreshes + 1;
            if (user_cmd == 3'b011) activates = activates + 1;
            if (user_cmd == 3'b010) precharges = precharges + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;

        // Exercise continuous traffic and periodic downstream stalls.
        repeat (1400000) begin
            @(posedge clk);
            if (($time % 997) == 0) rd_ready = 1'b0;
            if (($time % 997) == 60) rd_ready = 1'b1;
        end

        $display("accepted=%0d emitted=%0d errors=%0d writes=%0d reads=%0d refreshes=%0d activates=%0d precharges=%0d protocol_error=%0b ready=%0b",
                 accepted, emitted, errors, writes, reads, refreshes, activates, precharges, protocol_error, stream_ready);
        if (errors == 0 && emitted > 10000 && writes > 100 && reads > 100 &&
            refreshes > 10 && activates > 100 && precharges > 100 &&
            !protocol_error && stream_ready)
            $display("PASS");
        else
            $display("FAIL");
        $finish;
    end
endmodule
