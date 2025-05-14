//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Anirban Banerjee
// 
// Create Date:	 20:56:29 04/03/2024 
// Design Name: 
// Module Name:	 charROM
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

//Simulation model for charROM Xilinx block RAM configured as pseudo-DPRAM
//byte array of length 1785 = 255 * 7
//255 characters x 7 bytes per character
//5 bits data out is a scan line for character
module charROM (dout, clk, oce, ce, reset, ad);

	output [4:0] dout;
	input clk;
	input oce; //unused
	input ce;
	input reset;
	input [10:0] ad;

	reg [4:0] memory [0:2039];
	reg [4:0] memrddata;

	initial $readmemb("./charROM.readmemb", memory);

	always @(posedge clk) begin
		if (reset) memrddata <= #1 5'h0;		
		else if (ce) memrddata <= #1 memory[ad];
	end

	assign dout = memrddata;
	
endmodule
