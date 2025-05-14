//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module keySynchronizer (
	input clk,
	input resetn,
	input keyIn,
	output reg keyOut);

	reg sync0, sync1;

	always @(posedge clk) begin
		if (~resetn) begin
			sync0 <= `DELAY 1'b1;
			keyOut <= `DELAY 1'b1;
		end else begin
			sync0 <= `DELAY keyIn;
			keyOut <= `DELAY sync0;
		end
	end

endmodule

