`timescale 1ns/1ps

module tmds_encoder_golden_tb;

reg clk_hdmi;
reg rst_n;
reg de;
reg [7:0] data_i;
reg [1:0] ctrl_i;
wire [9:0] tmds_o;

integer i;

tmds_encoder dut (
    .clk_hdmi(clk_hdmi),
    .rst_n(rst_n),
    .de(de),
    .data_i(data_i),
    .ctrl_i(ctrl_i),
    .tmds_o(tmds_o)
);

always #5 clk_hdmi = ~clk_hdmi;

reg [8:0] ref_q_m;
reg signed [4:0] ref_disparity;

function [3:0] count_ones8;
    input [7:0] v;
    integer k;
    begin
        count_ones8 = 4'd0;
        for (k = 0; k < 8; k = k + 1)
            count_ones8 = count_ones8 + v[k];
    end
endfunction

function [3:0] count_ones10;
    input [9:0] v;
    integer k;
    begin
        count_ones10 = 4'd0;
        for (k = 0; k < 10; k = k + 1)
            count_ones10 = count_ones10 + v[k];
    end
endfunction

function [8:0] qm_from_data;
    input [7:0] d;
    reg use_xnor;
    reg [8:0] q;
    begin
        use_xnor = (count_ones8(d) > 4) || ((count_ones8(d) == 4) && (d[0] == 1'b0));
        q[0] = d[0];
        q[1] = use_xnor ? ~(q[0] ^ d[1]) : (q[0] ^ d[1]);
        q[2] = use_xnor ? ~(q[1] ^ d[2]) : (q[1] ^ d[2]);
        q[3] = use_xnor ? ~(q[2] ^ d[3]) : (q[2] ^ d[3]);
        q[4] = use_xnor ? ~(q[3] ^ d[4]) : (q[3] ^ d[4]);
        q[5] = use_xnor ? ~(q[4] ^ d[5]) : (q[4] ^ d[5]);
        q[6] = use_xnor ? ~(q[5] ^ d[6]) : (q[5] ^ d[6]);
        q[7] = use_xnor ? ~(q[6] ^ d[7]) : (q[6] ^ d[7]);
        q[8] = ~use_xnor;
        qm_from_data = q;
    end
endfunction

task automatic apply_and_check;
    input step_rst_n;
    input step_de;
    input [7:0] step_data;
    input [1:0] step_ctrl;
    reg [9:0] expected;
    reg [9:0] sym;
    reg dc_invert;
    reg [3:0] dc_ones;
    reg [3:0] dc_n1_final;
    reg [8:0] next_q_m;
    reg signed [4:0] next_disparity;
    begin
        rst_n = step_rst_n;
        de = step_de;
        data_i = step_data;
        ctrl_i = step_ctrl;

        if (!step_rst_n) begin
            expected = 10'b0000000000;
            next_q_m = 9'b000000000;
            next_disparity = 5'sd0;
        end else if (!step_de) begin
            case (step_ctrl)
                2'b00: expected = 10'b1101010100;
                2'b01: expected = 10'b0010101011;
                2'b10: expected = 10'b0101010100;
                default: expected = 10'b1010101011;
            endcase
            next_q_m = 9'b000000000;
            next_disparity = 5'sd0;
        end else begin
            dc_ones = ref_q_m[0] + ref_q_m[1] + ref_q_m[2] + ref_q_m[3] +
                      ref_q_m[4] + ref_q_m[5] + ref_q_m[6] + ref_q_m[7];

            dc_invert = (ref_disparity == 0 || dc_ones == 4) ? ~ref_q_m[8] :
                        ((ref_disparity > 0) ? (dc_ones > 4) : (dc_ones < 4));

            sym[9] = dc_invert;
            sym[8] = ref_q_m[8];
            sym[7:0] = dc_invert ? ~ref_q_m[7:0] : ref_q_m[7:0];

            expected = sym;
            dc_n1_final = count_ones10(sym);
            next_disparity = ref_disparity + (dc_n1_final <<< 1) - 10;
            next_q_m = qm_from_data(step_data);
        end

        @(posedge clk_hdmi);
        #1;

        if (tmds_o !== expected) begin
            $display("ERROR @%0t: rst_n=%b de=%b data=%h ctrl=%b expected=%b got=%b ref_qm=%b ref_disp=%0d",
                $time, step_rst_n, step_de, step_data, step_ctrl, expected, tmds_o, ref_q_m, ref_disparity);
            $finish;
        end

        ref_q_m = next_q_m;
        ref_disparity = next_disparity;
    end
endtask

initial begin
    clk_hdmi = 1'b0;
    rst_n = 1'b0;
    de = 1'b0;
    data_i = 8'h00;
    ctrl_i = 2'b00;
    ref_q_m = 9'b0;
    ref_disparity = 5'sd0;

    $dumpfile("tb/tmds_encoder_golden_tb.vcd");
    $dumpvars(0, tmds_encoder_golden_tb);

    apply_and_check(1'b0, 1'b0, 8'h00, 2'b00);
    apply_and_check(1'b0, 1'b0, 8'h00, 2'b00);

    apply_and_check(1'b1, 1'b0, 8'h00, 2'b00);
    apply_and_check(1'b1, 1'b0, 8'h00, 2'b01);
    apply_and_check(1'b1, 1'b0, 8'h00, 2'b10);
    apply_and_check(1'b1, 1'b0, 8'h00, 2'b11);

    apply_and_check(1'b1, 1'b1, 8'h00, 2'b00);
    apply_and_check(1'b1, 1'b1, 8'hff, 2'b00);
    apply_and_check(1'b1, 1'b1, 8'h55, 2'b00);
    apply_and_check(1'b1, 1'b1, 8'haa, 2'b00);
    apply_and_check(1'b1, 1'b1, 8'h0f, 2'b00);
    apply_and_check(1'b1, 1'b1, 8'hf0, 2'b00);

    for (i = 0; i < 128; i = i + 1)
        apply_and_check(1'b1, 1'b1, $random, 2'b00);

    apply_and_check(1'b0, 1'b1, 8'h00, 2'b00);
    apply_and_check(1'b1, 1'b0, 8'h00, 2'b00);

    $display("PASS: tmds_encoder golden comparison completed.");
    repeat (2) @(posedge clk_hdmi);
    $finish;
end

endmodule