//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
// This is the top level design module
// Supports CPU, keyboard but no console UART and outputs VGA
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "vgaminikbd.vh"
  module charBufferInit (
	input clk,
	input resetn,
	input enable,
	input partLineInit, //only erase one line partially
	input [4:0] partLineRow, //partial line erase: row number
	input [6:0] partLineCol, //partial line erase: column to start at
	input zeroize,
	output wire initWrEn,
	output wire [11:0] initAddress,
	output reg [6:0] initData
	);

	`ifdef SIM_ONLY
	localparam MAXCOL_M_1 = 79;
	localparam MAXCOL = 80;
	`else
	localparam MAXCOL_M_1 = 79;
	localparam MAXCOL = 80;
	`endif

	localparam INIT_STATE_IDLE = 1'b0;
	localparam INIT_STATE_ACTIVE = 1'b1;

	localparam MAXROW_M_1 = 31;

	`ifdef SIM_ONLY
	localparam MAXCHARS_M_1 = 12'd2559;
	`else
	localparam MAXCHARS_M_1 = 12'd2559;
	`endif

  	reg [6:0] initCursorCol;
	reg [4:0] initCursorRow;
	reg enable_r0;

	reg zeroizeStretched;
	reg partLineInitStretched;
	reg initState;
	wire nextInitState;

	wire initCursorColAtMax = (initCursorCol == MAXCOL_M_1);
	wire initAddressAtMax = (partLineInitStretched)? initCursorColAtMax: (initAddress == MAXCHARS_M_1);

	wire initStateIDLE = (initState == INIT_STATE_IDLE);
	wire initStateACTIVE = (initState == INIT_STATE_ACTIVE);
	wire enableFallEdge = enable_r0 & ~enable;

	assign nextInitState =  (enableFallEdge & initStateIDLE)?
								INIT_STATE_ACTIVE:
							(initStateACTIVE & initAddressAtMax)?
								INIT_STATE_IDLE:
								initState;
	
	assign initWrEn = initStateACTIVE;
	assign initAddress = {initCursorCol[6:0], initCursorRow[4:0]};

	always @(posedge clk) begin
		if (~resetn) begin
			initCursorRow <= `DELAY 5'h0;
			initCursorCol <= `DELAY 7'h0;
			initData <= `DELAY 7'h0;
			initState <= `DELAY 1'b0;
			zeroizeStretched <= `DELAY 1'b0;
			partLineInitStretched <= `DELAY 1'b0;
			enable_r0 <= `DELAY 1'b0;
		end else begin
			
			if (initStateIDLE & partLineInit) begin
				initCursorRow <= `DELAY  partLineRow;
				initCursorCol <= `DELAY  partLineCol;
			end else if (initStateACTIVE) begin
				initCursorRow <= `DELAY (initCursorColAtMax & ~partLineInitStretched)? (initCursorRow + 1'b1): initCursorRow;
				initCursorCol <= `DELAY (initCursorColAtMax)? 7'h0: (initCursorCol + 1'b1);
				initData <= `DELAY (zeroizeStretched)? 7'h0: (initData + 1'b1);
			end else begin
				initCursorCol <= `DELAY 7'h0;
				initCursorRow <= `DELAY 5'h0;
				initData <= `DELAY 7'h0;
			end
			initState <= `DELAY nextInitState;
			zeroizeStretched <= `DELAY (initStateACTIVE & initAddressAtMax)? 1'b0: (zeroize & initStateIDLE)? 1'b1: zeroizeStretched;
			partLineInitStretched <= `DELAY (initStateACTIVE & initAddressAtMax)? 1'b0: (partLineInit & initStateIDLE)? 1'b1: partLineInitStretched;
			enable_r0 <= `DELAY enable;
		end
	end

endmodule
