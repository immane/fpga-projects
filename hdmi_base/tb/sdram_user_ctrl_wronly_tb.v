// Write-only test (VERIFY_EN=0): verifies the controller writes bursts without
// doing readbacks, never hangs, and no READ commands are issued.
`timescale 1ns/1ps
module sdram_user_ctrl_wronly_tb;
    reg         clk      = 1'b0;
    reg         rst_n    = 1'b0;
    reg         pix_valid= 1'b0;
    reg  [15:0] pix_data = 16'd0;

    wire        init_done, cmd_ack;
    wire [31:0] read_data;

    wire [2:0]  user_cmd;
    wire        user_cmd_en;
    wire [20:0] user_addr;
    wire [31:0] user_data;
    wire [7:0]  user_len;
    wire        rdbk_err, rdbk_done;

    sdram_user_ctrl #(
        .BURST_SIZE(32),
        .VERIFY_EN (0)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .init_done(init_done), .cmd_ack(cmd_ack),
        .pix_valid(pix_valid), .pix_data(pix_data),
        .user_cmd(user_cmd), .user_cmd_en(user_cmd_en),
        .user_addr(user_addr), .user_data(user_data), .user_len(user_len),
        .read_data(read_data), .rdbk_err(rdbk_err), .rdbk_done(rdbk_done)
    );

    sdram_hs_model #(.CL(2),.WR(2),.RP(2),.RCD(2)) model (
        .clk(clk), .rst_n(rst_n),
        .cmd_en(user_cmd_en), .cmd(user_cmd), .addr(user_addr),
        .data(user_data), .data_len(user_len),
        .o_data(read_data), .cmd_ack(cmd_ack), .init_done(init_done)
    );

    always #3 clk = ~clk;

    reg [15:0] px = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin px <= 0; pix_valid <= 0; end
        else begin pix_valid <= 1; pix_data <= px; px <= px + 1; end
    end

    integer wr_c=0, rd_c=0, act_c=0, pre_c=0, ref_c=0, state_ok=0;
    always @(posedge clk) begin
        if (user_cmd_en)
            case (user_cmd)
                3'b100: wr_c  = wr_c + 1;
                3'b101: rd_c  = rd_c + 1;
                3'b011: act_c = act_c + 1;
                3'b010: pre_c = pre_c + 1;
                3'b001: ref_c = ref_c + 1;
                default: ;
            endcase
        if (uut.state == 4'd14) state_ok = state_ok + 1;  // passed through ST_NEXT
    end

    initial begin
        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1;
        repeat (200000) @(posedge clk);
        $display("RESULT wronly: wr=%0d rd=%0d act=%0d pre=%0d ref=%0d next=%0d rdbk_err=%0b",
                 wr_c, rd_c, act_c, pre_c, ref_c, state_ok, rdbk_err);
        if (wr_c > 100 && rd_c == 0 && state_ok > 0)
            $display("PASS (write-only)");
        else
            $display("FAIL (write-only)");
        $finish;
    end
endmodule
