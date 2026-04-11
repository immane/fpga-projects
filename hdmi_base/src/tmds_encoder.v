module tmds_encoder (
    input wire clk_hdmi,
    input wire rst_n,

    input wire de,                  // Data Enable (active video region)
    input wire [7:0] data_i,        // 8-bit pixel data
    input wire [1:0] ctrl_i,        // Control signals for blanking period

    output reg [9:0] tmds_o         // 10-bit TMDS encoded output
);

// Stage 0: Input pipeline registers
(* syn_preserve = 1 *) reg       de_q;
(* syn_preserve = 1 *) reg [7:0] data_q;
(* syn_preserve = 1 *) reg [1:0] ctrl_q;

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

// Stage 1: 8b/10b TMDS first stage encoding
wire [3:0] ones_count = 
    data_q[0] + data_q[1] + data_q[2] + data_q[3] + 
    data_q[4] + data_q[5] + data_q[6] + data_q[7];

wire use_xnor = (ones_count > 4) || ((ones_count == 4) && (data_q[0] == 1'b0));

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

(* syn_preserve = 1 *) reg       de_qq;
(* syn_preserve = 1 *) reg [1:0] ctrl_qq;
(* syn_preserve = 1 *) reg [8:0] q_m_q;
(* syn_preserve = 1 *) reg [3:0] dc_ones_cnt_q;

always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) begin
        de_qq        <= 1'b0;
        ctrl_qq      <= 2'b00;
        q_m_q        <= 9'd0;
        dc_ones_cnt_q <= 4'd0;
    end else begin
        de_qq        <= de_q;
        ctrl_qq      <= ctrl_q;
        q_m_q        <= q_m_next;
        dc_ones_cnt_q <= q_m_next[0] + q_m_next[1] + q_m_next[2] + q_m_next[3] +
                         q_m_next[4] + q_m_next[5] + q_m_next[6] + q_m_next[7];
    end
end

// Stage 2: DC balance decision (pure combinational)
wire dc_invert_comb;
assign dc_invert_comb = 
    (!de_qq) ? 1'b0 :
    (disparity == 0 || dc_ones_cnt_q == 4) ? ~q_m_q[8] :
    (disparity > 0) ? (dc_ones_cnt_q > 4) : (dc_ones_cnt_q < 4);

// Stage 3: Disparity pipeline + final output
reg signed [4:0] disparity;        // Current running disparity
reg signed [4:0] disparity_next;   // Next disparity value (pipelined)

reg [9:0] tmds_next;

always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n) begin
        tmds_o         <= 10'b0;
        disparity      <= 5'sd0;
        disparity_next <= 5'sd0;
    end else begin
        if (!de_qq) begin
            // Blanking period: output control codes
            case (ctrl_qq)
                2'b00: tmds_o <= 10'b1101010100;
                2'b01: tmds_o <= 10'b0010101011;
                2'b10: tmds_o <= 10'b0101010100;
                2'b11: tmds_o <= 10'b1010101011;
                default: tmds_o <= 10'b0;
            endcase
            disparity <= 5'sd0;
        end else begin
            // Data period: apply DC balance
            tmds_next[9]   = dc_invert_comb;
            tmds_next[8]   = q_m_q[8];
            tmds_next[7:0] = dc_invert_comb ? ~q_m_q[7:0] : q_m_q[7:0];

            tmds_o <= tmds_next;

            // Pipelined disparity calculation
            if (dc_invert_comb)
                disparity_next <= disparity + 
                    $signed({1'b0, q_m_q[8], 1'b0}) + 6'sd8 - $signed({1'b0, dc_ones_cnt_q, 1'b0});
            else
                disparity_next <= disparity + 
                    $signed({1'b0, q_m_q[8], 1'b0}) + $signed({1'b0, dc_ones_cnt_q, 1'b0}) - 6'sd10;

            disparity <= disparity_next;
        end
    end
end

endmodule