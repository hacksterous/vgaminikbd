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
	//remains high forever after deassertion
	output reg userResetn /* synthesis syn_keep=1 */,
	output wire keyTimeout,
	output wire cursorBlink);

	reg syncReg;
	reg [4:0] heartbeatCounter;
	`ifdef SIM_ONLY
	assign cursorBlink = heartbeatCounter[1];
	assign keyTimeout = heartbeatCounter[1];
	`else
	assign cursorBlink = heartbeatCounter[4];
	assign keyTimeout = heartbeatCounter[3];
	`endif
	always @(posedge clk) begin
		if (~resetn) begin
			heartbeatCounter <= `DELAY 'h0;
			syncReg <= `DELAY 1'b0;
			userResetn <= `DELAY 1'b0;
		end else begin
			heartbeatCounter <= `DELAY (syncReg & ~vsync)? (heartbeatCounter + 1'b1): heartbeatCounter; //increment on a falling edge
			syncReg <= `DELAY vsync;
		`ifdef SIM_ONLY
			userResetn <= `DELAY resetn;
		`else
			userResetn <= `DELAY heartbeatCounter[1]? 1'b1: userResetn;
		`endif
		end
	end


endmodule
