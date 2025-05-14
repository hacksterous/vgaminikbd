//Copyright (C)2014-2024 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.9.02
//Part Number: GW1NZ-LV1QN48A3
//Device: GW1NZ-1
//Device Version: C
//Created Time: Wed Jul 17 19:05:49 2024

module kbdrom (dout, clk, oce, ce, reset, ad);

output [13:0] dout;
input clk;
input oce;
input ce;
input reset;
input [6:0] ad;

wire [17:0] prom_inst_0_dout_w;
wire gw_gnd;

assign gw_gnd = 1'b0;

pROM prom_inst_0 (
    .DO({prom_inst_0_dout_w[17:0],dout[13:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(ce),
    .RESET(reset),
    .AD({gw_gnd,gw_gnd,gw_gnd,ad[6:0],gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

defparam prom_inst_0.READ_MODE = 1'b0;
defparam prom_inst_0.BIT_WIDTH = 16;
defparam prom_inst_0.RESET_MODE = "SYNC";
defparam prom_inst_0.INIT_RAM_00 = 256'h0000307E04890000000000000000000000000000000000000000000000000000;
defparam prom_inst_0.INIT_RAM_01 = 256'h000019402BF720E129F32D7A00000000000018A128F100000000000000000000;
defparam prom_inst_0.INIT_RAM_02 = 256'h00001AA529722A7423662B7610200000000019A31A2422E522642C7821E30000;
defparam prom_inst_0.INIT_RAM_03 = 256'h00001C2A1BA62AF5256A26ED0000000000001B5E2CF923E724682162276E0000;
defparam prom_inst_0.INIT_RAM_04 = 256'h000016DF28701DBA266C17BF173E000000001CA8182927EF24E925EB163C0000;
defparam prom_inst_0.INIT_RAM_05 = 256'h000000002E7C00002EFD008100000000000000001EAB2DFB000013A200000000;
defparam prom_inst_0.INIT_RAM_06 = 256'h0000000000001BB71A34000018B1000000000408000000000000000000000000;
defparam prom_inst_0.INIT_RAM_07 = 256'h000000001CB9152A16AD19B315AB00000000071B1C381B361AB51932172E1830;

endmodule //kbdrom
