`timescale 1ns/1ps

module tmds_encoder_tb;

reg clk_hdmi;
reg rst_n;
reg de;
reg [7:0] data_i;
reg [1:0] ctrl_i;
wire [9:0] tmds_o;

integer test_idx;

tmds_encoder uut (
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de),
    .data_i(data_i),
    .ctrl_i(ctrl_i),
    .tmds_o(tmds_o)
);

always #5 clk_hdmi = ~clk_hdmi;

task automatic apply_step;
    input step_de;
    input [7:0] step_data;
    input [1:0] step_ctrl;
    input [127:0] step_name;
    begin
        de = step_de;
        data_i = step_data;
        ctrl_i = step_ctrl;

        @(posedge clk_hdmi);
        #1;
        $display("time=%0t step=%0s de=%b data=%h ctrl=%b q_m=%b disparity=%0d tmds=%b",
            $time,
            step_name,
            step_de,
            step_data,
            step_ctrl,
            uut.q_m,
            uut.disparity,
            tmds_o
        );
    end
endtask

task automatic check_ctrl_code;
    input [1:0] ctrl;
    input [9:0] expected;
    begin
        if (tmds_o !== expected) begin
            $display("ERROR: control code mismatch at time=%0t ctrl=%b expected=%b got=%b", $time, ctrl, expected, tmds_o);
            $finish;
        end
    end
endtask

task automatic ensure_known_output;
    begin
        if (^tmds_o === 1'bx) begin
            $display("ERROR: tmds_o has X/Z at time=%0t value=%b", $time, tmds_o);
            $finish;
        end
    end
endtask

initial begin
    clk_hdmi = 1'b0;
    rst_n = 1'b0;
    de = 1'b0;
    data_i = 8'h00;
    ctrl_i = 2'b00;

    $dumpfile("tb/tmds_encoder_tb.vcd");
    $dumpvars(0, tmds_encoder_tb);

    repeat (3) @(posedge clk_hdmi);
    #1;
    if (tmds_o !== 10'b0) begin
        $display("ERROR: reset output mismatch at time=%0t expected=0000000000 got=%b", $time, tmds_o);
        $finish;
    end

    rst_n = 1'b1;

    apply_step(1'b0, 8'h00, 2'b00, "ctrl00");
    ensure_known_output();
    check_ctrl_code(2'b00, 10'b1101010100);

    apply_step(1'b0, 8'h00, 2'b01, "ctrl01");
    ensure_known_output();
    check_ctrl_code(2'b01, 10'b0010101011);

    apply_step(1'b0, 8'h00, 2'b10, "ctrl10");
    ensure_known_output();
    check_ctrl_code(2'b10, 10'b0101010100);

    apply_step(1'b0, 8'h00, 2'b11, "ctrl11");
    ensure_known_output();
    check_ctrl_code(2'b11, 10'b1010101011);

    apply_step(1'b1, 8'h00, 2'b00, "data00");
    ensure_known_output();
    apply_step(1'b1, 8'hff, 2'b00, "dataff");
    ensure_known_output();
    apply_step(1'b1, 8'h55, 2'b00, "data55");
    ensure_known_output();
    apply_step(1'b1, 8'haa, 2'b00, "dataaa");
    ensure_known_output();
    apply_step(1'b1, 8'h0f, 2'b00, "data0f");
    ensure_known_output();
    apply_step(1'b1, 8'hf0, 2'b00, "dataf0");
    ensure_known_output();
    apply_step(1'b1, 8'h81, 2'b00, "data81");
    ensure_known_output();
    apply_step(1'b1, 8'h18, 2'b00, "data18");
    ensure_known_output();

    for (test_idx = 0; test_idx < 8; test_idx = test_idx + 1) begin
        apply_step(1'b1, test_idx * 8'h1d, 2'b00, "sweep");
        ensure_known_output();
    end

    rst_n = 1'b0;
    @(posedge clk_hdmi);
    #1;
    if (tmds_o !== 10'b0) begin
        $display("ERROR: mid-run reset output mismatch at time=%0t got=%b", $time, tmds_o);
        $finish;
    end

    rst_n = 1'b1;
    apply_step(1'b0, 8'h00, 2'b00, "ctrl00_after_reset");
    ensure_known_output();
    check_ctrl_code(2'b00, 10'b1101010100);

    repeat (3) @(posedge clk_hdmi);
    $finish;
end

endmodule