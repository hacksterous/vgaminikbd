//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Anirban Banerjee
// License: GNU GPL v3
// Create Date:	 July/1/2025 
// Design Name: 
// Module Name:	 ansiescape
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: Implements ANSI escape sequences (VT100-like) on UART stream input
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
`include "keycharcmdcodes.vh"

module ansiescape (
	input resetn,
	input clk,
	input rxDataInValid,
	input [7:0] rxDataIn,
	output wire rxANSIDataOutValid,
	output wire [7:0] rxANSIDataOut);

	//TODO
	assign rxANSIDataOutValid	= rxDataInValid;
	assign rxANSIDataOut		= rxDataIn;

endmodule
