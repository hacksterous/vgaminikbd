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
	input enable,
	input initRowOnly,		 //only erase one line partially
	input [4:0] rowInitRow, //partial line erase: row number
	input [6:0] rowInitCol, //partial line erase: column to start at
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

	`ifdef SIM_ONLY
	localparam MAXCOL_M_1 = 79;
	localparam MAXCOL = 80;
	`else
	localparam MAXCOL_M_1 = 79;
	localparam MAXCOL = 80;
	`endif

	localparam INIT_STATE_IDLE = 2'h0;
	localparam INIT_STATE_ACTIVE_SEQ = 2'h1;
	localparam INIT_STATE_ACTIVE_ZERO = 2'h3;
	localparam INIT_STATE_ACTIVE_ROW = 2'h2;

	localparam MAXROW_M_1 = 31;

	`ifdef SIM_ONLY
	localparam MAXCHARS_M_1 = 12'd2559;
	`else
	localparam MAXCHARS_M_1 = 12'd2559;
	`endif

  	reg [6:0] initCursorCol;
	reg [4:0] initCursorRow;

	reg [1:0] initState;
	wire [1:0] nextInitState;

	//initRowOnly and enable have to be delayed so that the
	//update in currentScrolledRow is captured.
	reg enable_r0;
	reg initRowOnly_r0;

	wire initAddressAtMax = (initAddress == MAXCHARS_M_1);
	wire initCursorColAtMax = (initCursorCol == MAXCOL_M_1);
	wire initStateIDLE = (initState == INIT_STATE_IDLE);
	wire initStateACTIVE_SEQ = (initState == INIT_STATE_ACTIVE_SEQ);
	wire initStateACTIVE_ZERO = (initState == INIT_STATE_ACTIVE_ZERO);
	wire initStateACTIVE_ROW = (initState == INIT_STATE_ACTIVE_ROW);

	wire fullScreenInitDone = (initStateACTIVE_SEQ | initStateACTIVE_ZERO) & initAddressAtMax;
	wire rowInitDone = initStateACTIVE_ROW & initCursorColAtMax;
	wire initDone = fullScreenInitDone | rowInitDone;

	assign nextInitState =  (~enable_r0 & initStateIDLE & sequential & ~initRowOnly_r0)?
								INIT_STATE_ACTIVE_SEQ:
							(~enable_r0 & initStateIDLE & ~sequential & ~initRowOnly_r0)?
								INIT_STATE_ACTIVE_ZERO:
							(~enable_r0 & initStateIDLE & initRowOnly_r0)?
								INIT_STATE_ACTIVE_ROW:
							(initDone & enable_r0)?
								INIT_STATE_IDLE:
								initState;
	
	assign initWrEn = ~initStateIDLE;
	assign initAddress = {initCursorCol[6:0], initCursorRow[4:0]};

	always @(posedge clk) begin
		initRowOnly_r0 <= `DELAY initRowOnly;
		enable_r0 <= `DELAY enable;
	end

	always @(posedge clk) begin
		if (~resetn) begin
			initCursorRow <= `DELAY 5'h0;
			initCursorCol <= `DELAY 7'h0;
			initData <= `DELAY 7'd`CHAR_NUL;
			initState <= `DELAY 1'b0;
		end else begin
			if (initStateIDLE & initRowOnly_r0 & ~enable_r0) begin
				initCursorRow <= `DELAY  rowInitRow;
				initCursorCol <= `DELAY  rowInitCol;
			end if (initStateACTIVE_SEQ | initStateACTIVE_ZERO) begin
				initCursorRow <= `DELAY (initCursorColAtMax)? (initCursorRow + 1'b1): initCursorRow;
				initCursorCol <= `DELAY (initCursorColAtMax)? 7'h0: (initCursorCol + 1'b1);
				//initData <= `DELAY (fullScreenInitDone)? 7'd`CHAR_NUL: (initStateACTIVE_SEQ)? (initData + 1'b1): 7'd`CHAR_NUL;
				initData <= `DELAY (fullScreenInitDone | ~initStateACTIVE_SEQ)? 7'd`CHAR_NUL: (initData + 1'b1);
			end else if (initStateACTIVE_ROW) begin
				initCursorCol <= `DELAY (initCursorColAtMax)? 7'h0: (initCursorCol + 1'b1);
				initData <= `DELAY 7'd`CHAR_NUL;
			end
			initState <= `DELAY nextInitState;
		end
	end

endmodule
