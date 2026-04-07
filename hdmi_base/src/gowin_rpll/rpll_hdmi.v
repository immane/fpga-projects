//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.11.03 Education
//Part Number: GW2AR-LV18QN88C8/I7
//Device: GW2AR-18
//Device Version: C

module rPLL_HDMI #(
    parameter [1:0] PROFILE = 2'd0 // 0:30Hz, 1:40Hz, 2:50Hz, 3:60Hz
) (
    output clkout,
    output lock,
    input clkin
);

wire clkoutp_o, clkoutd_o, clkoutd3_o, gw_gnd;
assign gw_gnd = 1'b0;

localparam integer IDIV_SEL_CFG =
    (PROFILE == 2'd0) ? 3 : // 30Hz: 74.25MHz pixel -> 371.25MHz 5x
    (PROFILE == 2'd1) ? 2 : // 40Hz: 99.00MHz pixel -> 495.00MHz 5x
    (PROFILE == 2'd2) ? 1 : // 50Hz: 123.75MHz pixel -> 618.75MHz 5x
                        1;  // 60Hz: 148.50MHz pixel -> 742.50MHz 5x
localparam integer FBDIV_SEL_CFG =
    (PROFILE == 2'd0) ? 54 :
    (PROFILE == 2'd1) ? 54 :
    (PROFILE == 2'd2) ? 45 :
                        54;

rPLL rpll_inst (
    .CLKOUT(clkout), .LOCK(lock), .CLKOUTP(clkoutp_o), .CLKOUTD(clkoutd_o), .CLKOUTD3(clkoutd3_o),
    .RESET(gw_gnd), .RESET_P(gw_gnd), .CLKIN(clkin), .CLKFB(gw_gnd),
    .FBDSEL({6{gw_gnd}}), .IDSEL({6{gw_gnd}}), .ODSEL({6{gw_gnd}}),
    .PSDA({4{gw_gnd}}), .DUTYDA({4{gw_gnd}}), .FDLY({4{gw_gnd}})
);
defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.IDIV_SEL = IDIV_SEL_CFG;
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.FBDIV_SEL = FBDIV_SEL_CFG;
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.ODIV_SEL = 2;
defparam rpll_inst.PSDA_SEL = "0000";
defparam rpll_inst.DYN_DA_EN = "true";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

endmodule
