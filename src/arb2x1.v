//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module arb2x1 (
	clk,
	resetn,
	d0,
	d0v,
	d1,
	d1v,
	od,
	odv);

	input clk;
	input resetn;
	input [7:0] d0;
	input d0v;
	input [7:0] d1;
	input d1v;
	output [7:0] od;
	output odv;

	assign odv = d0v | d1v;
	assign od = (d1v)? d1: d0;

endmodule
