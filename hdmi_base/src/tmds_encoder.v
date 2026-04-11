module tmds_encoder (
    input clk_hdmi,
    input rst_n,

    input de,            // Data Enable signal indicating active video data
    input wire [7:0] data_i,  // 8-bit input data for encoding
    input [1:0] ctrl_i,  // Control signals for blanking intervals

    output reg [9:0] tmds_o
);

// Stage-0 input pipeline to shorten the critical path into disparity update.
(* syn_preserve = 1 *) reg       de_q;
(* syn_preserve = 1 *) reg [7:0] data_q;
(* syn_preserve = 1 *) reg [1:0] ctrl_q;
(* syn_preserve = 1 *) reg       de_qq;
(* syn_preserve = 1 *) reg [1:0] ctrl_qq;
(* syn_preserve = 1 *) reg [8:0] q_m_q;
(* syn_preserve = 1 *) reg [3:0] dc_ones_cnt_q;

always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) begin
        de_q   <= 1'b0;
        data_q <= 8'd0;
        ctrl_q <= 2'b00;
    end else begin
        de_q   <= de;
        data_q <= data_i;
        ctrl_q <= ctrl_i;
    end
end

// TMDS encoding: 10-bit output based on input data and control signals
wire [3:0] ones_count =
    data_q[0] + data_q[1] + data_q[2] + data_q[3] + 
    data_q[4] + data_q[5] + data_q[6] + data_q[7];

wire use_xnor;
assign use_xnor = (ones_count > 4) || ((ones_count == 4) && (data_q[0] == 1'b0));

wire [8:0] q_m_next;
assign q_m_next[0] = data_q[0];
assign q_m_next[1] = use_xnor ? ~(q_m_next[0] ^ data_q[1]) : (q_m_next[0] ^ data_q[1]);
assign q_m_next[2] = use_xnor ? ~(q_m_next[1] ^ data_q[2]) : (q_m_next[1] ^ data_q[2]);
assign q_m_next[3] = use_xnor ? ~(q_m_next[2] ^ data_q[3]) : (q_m_next[2] ^ data_q[3]);
assign q_m_next[4] = use_xnor ? ~(q_m_next[3] ^ data_q[4]) : (q_m_next[3] ^ data_q[4]);
assign q_m_next[5] = use_xnor ? ~(q_m_next[4] ^ data_q[5]) : (q_m_next[4] ^ data_q[5]);
assign q_m_next[6] = use_xnor ? ~(q_m_next[5] ^ data_q[6]) : (q_m_next[5] ^ data_q[6]);
assign q_m_next[7] = use_xnor ? ~(q_m_next[6] ^ data_q[7]) : (q_m_next[6] ^ data_q[7]);
assign q_m_next[8] = ~use_xnor;

// Stage-1 pipeline registers for TMDS encoding and disparity calculation
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) begin
        de_qq        <= 1'b0;
        ctrl_qq      <= 2'b00;
        q_m_q        <= 9'd0;
        dc_ones_cnt_q <= 4'd0;
    end else begin
        de_qq   <= de_q;
        ctrl_qq <= ctrl_q;
        q_m_q   <= q_m_next;
        dc_ones_cnt_q <=
            q_m_next[0] + q_m_next[1] + q_m_next[2] + q_m_next[3] +
            q_m_next[4] + q_m_next[5] + q_m_next[6] + q_m_next[7];
    end
end


// Control signal encoding for blanking intervals
reg signed [4:0] disparity;
reg dc_invert;
reg [9:0] tmds_next;
reg signed [5:0] disparity_delta;

always @(posedge clk_hdmi or negedge rst_n) begin
    if(!rst_n) begin
        tmds_o <= 10'b0;
        disparity <= 5'sd0;
    end
    else begin
        if (!de_qq) begin
            // Output control codes during blanking intervals based on pipelined control signals.
            case (ctrl_qq)
                2'b00: tmds_o <= 10'b1101010100; // Control code for blanking
                2'b01: tmds_o <= 10'b0010101011; // Control code for blanking
                2'b10: tmds_o <= 10'b0101010100; // Control code for blanking
                2'b11: tmds_o <= 10'b1010101011; // Control code for blanking
                default: tmds_o <= 10'b0;
            endcase
            disparity <= 5'sd0;

        end else begin
            // Determine whether to invert the data based on the current disparity and the number of ones
            dc_invert = 
                (disparity == 0 || dc_ones_cnt_q == 4) ? ~q_m_q[8] : 
                    (disparity > 0) ? (dc_ones_cnt_q > 4) : (dc_ones_cnt_q < 4);

            // Build next TMDS symbol first so disparity uses same-cycle value.
            tmds_next[9] = dc_invert;
            tmds_next[8] = q_m_q[8];
            tmds_next[7:0] = dc_invert ? ~q_m_q[7:0] : q_m_q[7:0];

            tmds_o <= tmds_next;

            // Equivalent running-disparity update with less logic depth.
            // delta = 2*ones(tmds_next)-10
            // if invert:  ones = 1 + q_m_q[8] + (8-dc_ones_cnt_q)
            // else:       ones = q_m_q[8] + dc_ones_cnt_q
            if (dc_invert)
                disparity_delta = $signed({1'b0, q_m_q[8], 1'b0}) + 6'sd8 - $signed({1'b0, dc_ones_cnt_q, 1'b0});
            else
                disparity_delta = $signed({1'b0, q_m_q[8], 1'b0}) + $signed({1'b0, dc_ones_cnt_q, 1'b0}) - 6'sd10;

            disparity <= disparity + disparity_delta[4:0];
        end
    end
end
    
endmodule