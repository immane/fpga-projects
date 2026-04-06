module tmds_encoder (
    input clk_hdmi,
    input rst_n,

    input de,            // Data Enable signal indicating active video data
    input wire [7:0] data_i,  // 8-bit input data for encoding
    input [1:0] ctrl_i,  // Control signals for blanking intervals

    output reg [9:0] tmds_o
);

// TMDS encoding: 10-bit output based on input data and control signals
wire [3:0] ones_count =
    data_i[0] + data_i[1] + data_i[2] + data_i[3] + 
    data_i[4] + data_i[5] + data_i[6] + data_i[7];

wire use_xnor;
assign use_xnor = (ones_count > 4) || ((ones_count == 4) && (data_i[0] == 1'b0));

wire [8:0] q_m_next;
assign q_m_next[0] = data_i[0];
assign q_m_next[1] = use_xnor ? ~(q_m_next[0] ^ data_i[1]) : (q_m_next[0] ^ data_i[1]);
assign q_m_next[2] = use_xnor ? ~(q_m_next[1] ^ data_i[2]) : (q_m_next[1] ^ data_i[2]);
assign q_m_next[3] = use_xnor ? ~(q_m_next[2] ^ data_i[3]) : (q_m_next[2] ^ data_i[3]);
assign q_m_next[4] = use_xnor ? ~(q_m_next[3] ^ data_i[4]) : (q_m_next[3] ^ data_i[4]);
assign q_m_next[5] = use_xnor ? ~(q_m_next[4] ^ data_i[5]) : (q_m_next[4] ^ data_i[5]);
assign q_m_next[6] = use_xnor ? ~(q_m_next[5] ^ data_i[6]) : (q_m_next[5] ^ data_i[6]);
assign q_m_next[7] = use_xnor ? ~(q_m_next[6] ^ data_i[7]) : (q_m_next[6] ^ data_i[7]);
assign q_m_next[8] = ~use_xnor;

reg [8:0] q_m;
always @(posedge clk_hdmi or negedge rst_n) begin
    if (!rst_n)
        q_m <= 9'b0;
    else if (!de)
        q_m <= 9'b0;
    else
        q_m <= q_m_next;
end


// Control signal encoding for blanking intervals
reg signed [4:0] disparity;
reg [3:0] dc_ones_cnt;
reg dc_invert;
reg [3:0] dc_n1_final;
reg [9:0] tmds_next;

always @(posedge clk_hdmi or negedge rst_n) begin
    if(!rst_n) begin
        tmds_o <= 10'b0;
        disparity <= 5'sd0;
    end
    else begin
        if (!de) begin
            // Output control codes during blanking intervals based on ctrl_i
            case (ctrl_i)
                2'b00: tmds_o <= 10'b1101010100; // Control code for blanking
                2'b01: tmds_o <= 10'b0010101011; // Control code for blanking
                2'b10: tmds_o <= 10'b0101010100; // Control code for blanking
                2'b11: tmds_o <= 10'b1010101011; // Control code for blanking
                default: tmds_o <= 10'b0;
            endcase
            disparity <= 5'sd0;

        end else begin
            // Update disparity based on the number of ones in the encoded data
            dc_ones_cnt = 
                q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                q_m[4] + q_m[5] + q_m[6] + q_m[7];

            // Determine whether to invert the data based on the current disparity and the number of ones
            dc_invert = 
                (disparity == 0 || dc_ones_cnt == 4) ? ~q_m[8] : 
                    (disparity > 0) ? (dc_ones_cnt > 4) : (dc_ones_cnt < 4);

            // Build next TMDS symbol first so disparity uses same-cycle value.
            tmds_next[9] = dc_invert;
            tmds_next[8] = q_m[8];
            tmds_next[7:0] = dc_invert ? ~q_m[7:0] : q_m[7:0];

            tmds_o <= tmds_next;

            // Update disparity counter based on the number of ones in the output
            dc_n1_final = 
                tmds_next[9] + tmds_next[8] + tmds_next[7] + tmds_next[6] +
                tmds_next[5] + tmds_next[4] + tmds_next[3] + tmds_next[2] +
                tmds_next[1] + tmds_next[0];

            disparity <= disparity + 2*dc_n1_final - 10;
        end
    end
end
    
endmodule