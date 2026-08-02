// Testbench for sdram_user_ctrl.v against the SDRAM HS protocol model.
// Feeds a known 16-bit pixel stream, runs the controller, and checks that
// every write burst reads back without error (rdbk_err stays 0) and that
// rdbk_done pulses.
`timescale 1ns/1ps
module sdram_user_ctrl_tb;
    reg         clk      = 1'b0;
    reg         rst_n    = 1'b0;
    reg         pix_valid= 1'b0;
    reg  [15:0] pix_data = 16'd0;

    wire        init_done;
    wire        cmd_ack;
    wire [31:0] read_data;

    wire [2:0]  user_cmd;
    wire        user_cmd_en;
    wire [20:0] user_addr;
    wire [31:0] user_data;
    wire [7:0]  user_len;
    wire        rdbk_err;
    wire        rdbk_done;

    // UUT: bigger burst (32 words) + readback verify
    sdram_user_ctrl #(
        .BURST_SIZE(32),
        .VERIFY_EN (1)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .init_done (init_done),
        .cmd_ack   (cmd_ack),
        .pix_valid (pix_valid),
        .pix_data  (pix_data),
        .user_cmd  (user_cmd),
        .user_cmd_en(user_cmd_en),
        .user_addr (user_addr),
        .user_data (user_data),
        .user_len  (user_len),
        .read_data (read_data),
        .rdbk_err  (rdbk_err),
        .rdbk_done (rdbk_done)
    );

    // SDRAM HS controller behavioral model
    sdram_hs_model #(
        .CL  (2),
        .WR  (2),
        .RP  (2),
        .RCD (2)
    ) model (
        .clk      (clk),
        .rst_n    (rst_n),
        .cmd_en   (user_cmd_en),
        .cmd      (user_cmd),
        .addr     (user_addr),
        .data     (user_data),
        .data_len (user_len),
        .o_data   (read_data),
        .cmd_ack  (cmd_ack),
        .init_done(init_done)
    );

    // ~166 MHz clock
    always #3 clk = ~clk;

    // pixel source: continuous known pattern
    reg [15:0] px = 16'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px <= 16'd0;
            pix_valid <= 1'b0;
        end else begin
            pix_valid <= 1'b1;
            pix_data  <= px;
            px <= px + 16'd1;
        end
    end

    // counts readback completions / errors / commands
    integer done_count = 0;
    integer cmd_pulses = 0;
    integer cmd_wr = 0, cmd_rd = 0, cmd_act = 0, cmd_pre = 0, cmd_ref = 0;
    always @(posedge clk) begin
        if (rdbk_done) done_count = done_count + 1;
        if (user_cmd_en) begin
            cmd_pulses = cmd_pulses + 1;
            case (user_cmd)
                3'b100: cmd_wr  = cmd_wr  + 1;
                3'b101: cmd_rd  = cmd_rd  + 1;
                3'b011: cmd_act = cmd_act + 1;
                3'b010: cmd_pre = cmd_pre + 1;
                3'b001: cmd_ref = cmd_ref + 1;
                default: ;
            endcase
        end
    end

    initial begin
        $dumpfile("d:/Development/FPGA/hdmi_base/tb/sdram_user_ctrl_tb.vcd");
        $dumpvars(0, sdram_user_ctrl_tb);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        // run enough time for several write+verify bursts
        repeat (200000) @(posedge clk);

        $display("RESULT: done=%0d err=%0b cmds=%0d (act=%0d pre=%0d ref=%0d wr=%0d rd=%0d)",
                 done_count, rdbk_err, cmd_pulses, cmd_act, cmd_pre, cmd_ref, cmd_wr, cmd_rd);

        if (rdbk_err)                  $display("FAIL: readback mismatch");
        else if (done_count == 0)      $display("INCOMPLETE: no verify completed");
        else                           $display("PASS: %0d write+verify bursts, no errors", done_count);

        $finish;
    end
endmodule
