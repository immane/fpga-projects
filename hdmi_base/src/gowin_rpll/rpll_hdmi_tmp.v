//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.11.03 Education
//Part Number: GW2AR-LV18QN88C8/I7
//Device: GW2AR-18
//Device Version: C
//Created Time: Tue Apr  7 09:15:27 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    rPLL_HDMI your_instance_name(
        .clkout(clkout), //output clkout
        .lock(lock), //output lock
        .clkin(clkin), //input clkin
        .fbdsel(fbdsel), //input [5:0] fbdsel
        .idsel(idsel) //input [5:0] idsel
    );

//--------Copy end-------------------
