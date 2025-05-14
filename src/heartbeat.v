//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module heartbeat (
	input clk,
	input resetn,
	input vsync,
	input inputKey,
	output wire slowClkPosEdge,
	output reg userResetn /* synthesis syn_keep=1 */, //remains high forever
	output wire cursorBlink);

	reg syncReg;
	reg slowClk_r0;
	reg [5:0] heartbeatCounter;
	`ifdef SIM_ONLY
	assign cursorBlink = heartbeatCounter[1];
	assign slowClkPosEdge = heartbeatCounter[1];
	`else
	assign cursorBlink = heartbeatCounter[3];
	assign slowClkPosEdge = heartbeatCounter[5] & ~slowClk_r0;
	`endif
	always @(posedge clk) begin
		if (~resetn) begin
			heartbeatCounter <= `DELAY 'h0;
			syncReg <= `DELAY 1'b0;
			userResetn <= `DELAY 1'b0;
			slowClk_r0 <= `DELAY 1'b0;
		end else begin
			heartbeatCounter <= `DELAY (syncReg & ~vsync)? (heartbeatCounter + 1'b1): heartbeatCounter; //increment on a falling edge
			syncReg <= `DELAY vsync;
		`ifdef SIM_ONLY
			userResetn <= `DELAY resetn;
		`else
			userResetn <= `DELAY (~inputKey)? 1'b0: heartbeatCounter[5]? 1'b1: userResetn;
		`endif
			slowClk_r0 <= `DELAY heartbeatCounter[5];
		end
	end


endmodule
