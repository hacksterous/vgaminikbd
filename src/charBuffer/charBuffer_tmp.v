//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9.02
//Part Number: GW1NZ-LV1QN48C6/I5
//Device: GW1NZ-1
//Created Time: Sun Jun 15 21:02:37 2025

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    charBuffer your_instance_name(
        .dout(dout_o), //output [7:0] dout
        .clk(clk_i), //input clk
        .oce(oce_i), //input oce
        .ce(ce_i), //input ce
        .reset(reset_i), //input reset
        .wre(wre_i), //input wre
        .ad(ad_i), //input [11:0] ad
        .din(din_i) //input [7:0] din
    );

//--------Copy end-------------------
