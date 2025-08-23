//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
// This is the top level design module
// Supports CPU, keyboard but no console UART and outputs VGA
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "keycharcmdcodes.vh"
`include "vgaminikbd.vh"
  module charBufferInit (
	input clk,
	input resetn,
	output wire initStateIsIdle,
	input enable,
	input updateStatusRow,
	input [4:0] scrollRow, 
	input initRowOnly,		 //only erase one line partially
	input [4:0] rowInitRow, //line erase: row number
	input [6:0] rowInitCol, //line erase: column to start at
	input sequential,	 //initialize with sequential values
	output wire initWrEn,
	output wire [11:0] initAddress,
	output reg [6:0] initData
	);

/*
	enable		initRowOnly sequential		Operation
	---------------------------------------------
		1			0		0			Disabled
		0pulse		0		0			Full screen with zeros
		0pulse		0		1			Full screen with character sequence
		0pulse		1		x			Only one row initCursorRow starting 
										at initCursorCol with zeros
*/

	localparam MAXCOL_M_1 = 79;
	localparam MAXCOL = 80;

	localparam INIT_STATE_IDLE = 0;
	localparam INIT_STATE_ACTIVE_SEQ = 1;
	localparam INIT_STATE_ACTIVE_CLS = 3;
	localparam INIT_STATE_ACTIVE_ROW = 2;
	localparam INIT_STATE_ACTIVE_STAT = 6;

	localparam MAXROW_M_1 = 31;

	localparam MAXCHARS_M_1 = 12'd2559;

  	reg [6:0] initCursorCol;
	reg [4:0] initCursorRow;

	reg [2:0] initState;
	wire [2:0] nextInitState;

	wire initAddressAtMax = (initAddress == MAXCHARS_M_1);
	wire initCursorColAtMax = (initCursorCol == MAXCOL_M_1);
	wire initStateIDLE = (initState == INIT_STATE_IDLE);
	wire initStateACTIVE_SEQ = (initState == INIT_STATE_ACTIVE_SEQ);
	wire initStateACTIVE_CLS = (initState == INIT_STATE_ACTIVE_CLS);
	wire initStateACTIVE_ROW = (initState == INIT_STATE_ACTIVE_ROW);
	wire initStateACTIVE_STAT = (initState == INIT_STATE_ACTIVE_STAT);

	assign initStateIsIdle = initStateIDLE;

	wire fullScreenInitDone = (initStateACTIVE_SEQ | initStateACTIVE_CLS) & initAddressAtMax;
	wire rowInitDone = initStateACTIVE_ROW & initCursorColAtMax;
	wire statusUpdateDone = initStateACTIVE_STAT & initCursorColAtMax;
	wire initDone = fullScreenInitDone | rowInitDone;

	//row 31 is the status row
	assign nextInitState =  (initStateIDLE & updateStatusRow)? INIT_STATE_ACTIVE_STAT:
							(~enable & initStateIDLE & sequential & ~initRowOnly)? INIT_STATE_ACTIVE_SEQ:
							(~enable & initStateIDLE & ~sequential & ~initRowOnly)? INIT_STATE_ACTIVE_CLS:
							(~enable & initStateIDLE & initRowOnly)? INIT_STATE_ACTIVE_ROW:
							(initDone & enable | statusUpdateDone)? INIT_STATE_IDLE:
							initState;
	
	assign initWrEn = ~initStateIDLE;
	assign initAddress = {initCursorCol[6:0], initCursorRow[4:0]};

	always @(posedge clk) begin
		if (~resetn) begin
			initCursorRow <= `DELAY 5'h0;
			initCursorCol <= `DELAY 7'h0;
			initData <= `DELAY 7'd`CHAR_NUL;
			initState <= `DELAY 3'h0;
		end else begin
			if (initStateIDLE & updateStatusRow) begin
				initCursorRow <= `DELAY scrollRow - 1'b1; //same as adding 31
				initCursorCol <= `DELAY  7'h0;
				initData <= `DELAY 7'd127;
			end else if (initStateACTIVE_STAT) begin
				initCursorCol <= `DELAY (initCursorCol + 1'b1);
			end else if (initStateIDLE & initRowOnly & ~enable) begin
				initCursorRow <= `DELAY  rowInitRow;
				initCursorCol <= `DELAY  rowInitCol;
			end else if (initStateACTIVE_SEQ | initStateACTIVE_CLS) begin
				initCursorRow <= `DELAY (initCursorColAtMax)? (initCursorRow + 1'b1): initCursorRow;
				initCursorCol <= `DELAY (initCursorColAtMax)? 7'h0: (initCursorCol + 1'b1);
				initData <= `DELAY (fullScreenInitDone | initStateACTIVE_CLS)? 7'd`CHAR_NUL: (initData + 1'b1);
			end else if (initStateACTIVE_ROW) begin
				initCursorCol <= `DELAY (initCursorCol + 1'b1);
				initData <= `DELAY 7'd`CHAR_NUL;
			end else if (initStateIDLE) begin
				initCursorRow <= `DELAY  5'h0;
				initCursorCol <= `DELAY  7'h0;
				initData <= `DELAY 7'd`CHAR_NUL;
			end
			initState <= `DELAY nextInitState;
		end
	end

endmodule
