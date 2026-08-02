module rPLL (
    output CLKOUT,
    output LOCK,
    output CLKOUTP,
    output CLKOUTD,
    output CLKOUTD3,
    input RESET,
    input RESET_P,
    input CLKIN,
    input CLKFB,
    input [5:0] FBDSEL,
    input [5:0] IDSEL,
    input [5:0] ODSEL,
    input [3:0] PSDA,
    input [3:0] DUTYDA,
    input [3:0] FDLY
);

parameter FCLKIN = "27";
parameter DYN_IDIV_SEL = "false";
parameter IDIV_SEL = 3;
parameter DYN_FBDIV_SEL = "false";
parameter FBDIV_SEL = 54;
parameter DYN_ODIV_SEL = "false";
parameter ODIV_SEL = 2;
parameter PSDA_SEL = "0000";
parameter DYN_DA_EN = "true";
parameter DUTYDA_SEL = "1000";
parameter CLKOUT_FT_DIR = 1'b1;
parameter CLKOUTP_FT_DIR = 1'b1;
parameter CLKOUT_DLY_STEP = 0;
parameter CLKOUTP_DLY_STEP = 0;
parameter CLKFB_SEL = "internal";
parameter CLKOUT_BYPASS = "false";
parameter CLKOUTP_BYPASS = "false";
parameter CLKOUTD_BYPASS = "false";
parameter DYN_SDIV_SEL = 2;
parameter CLKOUTD_SRC = "CLKOUT";
parameter CLKOUTD3_SRC = "CLKOUT";
parameter DEVICE = "GW2AR-18C";

assign CLKOUT = CLKIN;
assign LOCK = 1'b1;
assign CLKOUTP = 1'b0;
assign CLKOUTD = 1'b0;
assign CLKOUTD3 = 1'b0;

endmodule

module CLKDIV (
    output CLKOUT,
    input HCLKIN,
    input RESETN,
    input CALIB
);

parameter DIV_MODE = "5";
parameter GSREN = "false";

assign CLKOUT = HCLKIN;

endmodule

module OSER10 (
    output Q,
    input D0,
    input D1,
    input D2,
    input D3,
    input D4,
    input D5,
    input D6,
    input D7,
    input D8,
    input D9,
    input PCLK,
    input FCLK,
    input RESET
);

parameter GSREN = "false";
parameter LSREN = "true";

assign Q = D0;

endmodule

module ELVDS_OBUF (
    input I,
    output O,
    output OB
);

assign O = I;
assign OB = ~I;

endmodule

// Minimal behavioral stub of the encrypted SDRAM Controller HS IP, so main.v
// can be compiled / smoke-tested without the IP netlist.
module SDRAM_Controller_HS_Top (
    output        O_sdram_clk,
    output        O_sdram_cke,
    output        O_sdram_cs_n,
    output        O_sdram_cas_n,
    output        O_sdram_ras_n,
    output        O_sdram_wen_n,
    output [3:0]  O_sdram_dqm,
    output [10:0] O_sdram_addr,
    output [1:0]  O_sdram_ba,
    inout  [31:0] IO_sdram_dq,
    input         I_sdrc_rst_n,
    input         I_sdrc_clk,
    input         I_sdram_clk,
    input         I_sdrc_cmd_en,
    input  [2:0]  I_sdrc_cmd,
    input         I_sdrc_precharge_ctrl,
    input         I_sdram_power_down,
    input         I_sdram_selfrefresh,
    input  [20:0] I_sdrc_addr,
    input  [3:0]  I_sdrc_dqm,
    input  [31:0] I_sdrc_data,
    input  [7:0]  I_sdrc_data_len,
    output [31:0] O_sdrc_data,
    output        O_sdrc_init_done,
    output        O_sdrc_cmd_ack
);

    reg [7:0]  init_cnt = 0;
    reg        init_done_r = 0;
    reg [3:0]  ack_cnt = 0;
    reg        ack_r = 0;
    reg [31:0] dq_r;

    assign O_sdram_clk = I_sdram_clk;
    assign O_sdram_cke = 1'b1;
    assign O_sdram_cs_n = 1'b0;
    assign O_sdram_cas_n = 1'b1;
    assign O_sdram_ras_n = 1'b1;
    assign O_sdram_wen_n = 1'b1;
    assign O_sdram_dqm  = 4'b0000;
    assign O_sdram_addr = 11'd0;
    assign O_sdram_ba   = 2'd0;
    assign IO_sdram_dq  = 32'bz;
    assign O_sdrc_data  = dq_r;
    assign O_sdrc_init_done = init_done_r;
    assign O_sdrc_cmd_ack  = ack_r;

    always @(posedge I_sdrc_clk or negedge I_sdrc_rst_n) begin
        if (!I_sdrc_rst_n) begin
            init_cnt <= 0; init_done_r <= 0; ack_cnt <= 0; ack_r <= 0; dq_r <= 0;
        end else begin
            if (init_cnt < 8'd200) init_cnt <= init_cnt + 1;
            else init_done_r <= 1'b1;

            // crude ack strobe after each accepted command
            if (I_sdrc_cmd_en) ack_cnt <= 4'd4;
            else if (ack_cnt != 0) ack_cnt <= ack_cnt - 1;
            ack_r <= (ack_cnt == 4'd1);
        end
    end

endmodule