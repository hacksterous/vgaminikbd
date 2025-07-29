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
	`ifdef DEBUG_FPGA_BUILD
	input rowIncrement,
	`endif
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

	wire initAddressAtMax = (initAddress == MAXCHARS_M_1);
	wire initCursorColAtMax = (initCursorCol == MAXCOL_M_1);
	wire initStateIDLE = (initState == INIT_STATE_IDLE);
	wire initStateACTIVE_SEQ = (initState == INIT_STATE_ACTIVE_SEQ);
	wire initStateACTIVE_ZERO = (initState == INIT_STATE_ACTIVE_ZERO);
	wire initStateACTIVE_ROW = (initState == INIT_STATE_ACTIVE_ROW);

	wire fullScreenInitDone = (initStateACTIVE_SEQ | initStateACTIVE_ZERO) & initAddressAtMax;
	wire rowInitDone = initStateACTIVE_ROW & initCursorColAtMax;
	wire initDone = fullScreenInitDone | rowInitDone;

	assign nextInitState =  (~enable & initStateIDLE & sequential & ~initRowOnly)? INIT_STATE_ACTIVE_SEQ:
							(~enable & initStateIDLE & ~sequential & ~initRowOnly)? INIT_STATE_ACTIVE_ZERO:
							(~enable & initStateIDLE & initRowOnly)? INIT_STATE_ACTIVE_ROW:
							(initDone & enable)? INIT_STATE_IDLE:
								initState;
	
	assign initWrEn = ~initStateIDLE;
	assign initAddress = {initCursorCol[6:0], initCursorRow[4:0]};

	always @(posedge clk) begin
		if (~resetn) begin
			initCursorRow <= `DELAY 5'h0;
			initCursorCol <= `DELAY 7'h0;
			`ifdef DEBUG_FPGA_BUILD
			initData <= `DELAY 7'd48;
			`else
			initData <= `DELAY 7'd`CHAR_NUL;
			`endif
			initState <= `DELAY 1'b0;
		end else begin
			if (initStateIDLE & initRowOnly & ~enable) begin
				initCursorRow <= `DELAY  rowInitRow;
				initCursorCol <= `DELAY  rowInitCol;
			`ifdef DEBUG_FPGA_BUILD
			end else if (initStateIDLE & rowIncrement & ~enable) begin
				initData <= `DELAY 7'd48;//number 0
			`endif
			end else if (initStateACTIVE_SEQ | initStateACTIVE_ZERO) begin
				initCursorRow <= `DELAY (initCursorColAtMax)? (initCursorRow + 1'b1): initCursorRow;
				initCursorCol <= `DELAY (initCursorColAtMax)? 7'h0: (initCursorCol + 1'b1);
				initData <= `DELAY 
									`ifdef DEBUG_FPGA_BUILD
									(rowIncrement & initCursorColAtMax & initStateACTIVE_SEQ)? (initData + 1'b1):
									(rowIncrement & initStateACTIVE_SEQ)? initData:
									`endif
									(fullScreenInitDone | initStateACTIVE_ZERO)? 
									7'd`CHAR_NUL: (initData + 1'b1);
			end else if (initStateACTIVE_ROW) begin
				initCursorCol <= `DELAY (initCursorColAtMax)? 7'h0: (initCursorCol + 1'b1);
				initData <= `DELAY 7'd`CHAR_NUL;
			end
			initState <= `DELAY nextInitState;
		end
	end

endmodule
