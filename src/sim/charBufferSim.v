//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Anirban Banerjee
// 
// Create Date:	 20:56:29 04/03/2024 
// Design Name: 
// Module Name:	 charBuffer
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
//Simulation model for charBuffer Xilinx block RAM configured as pseudo-DPRAM
//byte array of length 2560 = 80 * 32
//80 columns x 32 rows
//8 bit data out is a pointer to charROM
module charBuffer (dout, clk, oce, ce, reset, wre, ad, din);

	output [7:0] dout;
	input clk;
	input oce; //unused
	input ce;
	input reset;
	input wre;
	input [11:0] ad;
	input [7:0] din;

	reg [7:0] memory [0:2559];
	reg [7:0] memrddata;

	initial $readmemb("./charBuffer.readmemb", memory);

	always @(posedge clk) begin
		if (reset) memrddata <= #1 8'h0;
		else if (ce & ~wre) memrddata <= #1 memory[ad];
	end

	always @(posedge clk) begin
		if (wre & ce) memory[ad] <= #1 din;
	end

	assign dout = memrddata;
	
endmodule
