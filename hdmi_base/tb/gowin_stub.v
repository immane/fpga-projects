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