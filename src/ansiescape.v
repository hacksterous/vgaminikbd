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

module ansiEscape (
	input resetn,
	input clk,
	input keyTimeout,
	output reg ansiEscDebug,
	input rxDataInValid,
	input [7:0] rxDataIn,
	output reg rxANSIDataOutValid,
	output reg [7:0] rxANSIDataOut);

	//always @(*) rxANSIDataOutValid	= rxDataInValid;
	//always @(*) rxANSIDataOut		= rxDataIn[7:0];
	//assign ansiEscDebug = 1'b1;

	localparam ANSI_RECD_IDLE = 0;
	localparam ANSI_RECD_ESC = 1;
	localparam ANSI_RECD_SEQ = 3;
	localparam ANSI_RECD_SEQNEXT = 2;

	reg [3:0] inputHistory;
	reg [3:0] nextInputHistory;

	reg [1:0] ansiEscSeqState;	
	reg [1:0] nextAnsiEscSeqState;

	reg nextRxANSIDataOutValid;
	reg [7:0] nextRxANSIDataOut;

	wire ansiEscSeqStateANSI_RECD_IDLE = (ansiEscSeqState == ANSI_RECD_IDLE);
	wire ansiEscSeqStateANSI_RECD_ESC = (ansiEscSeqState == ANSI_RECD_ESC);
	wire ansiEscSeqStateANSI_RECD_SEQ = (ansiEscSeqState == ANSI_RECD_SEQ);
	wire ansiEscSeqStateANSI_RECD_SEQNEXT = (ansiEscSeqState == ANSI_RECD_SEQNEXT);

	reg keyTimeout_r0;
	reg keyEscapeTimeoutRunning;

	wire keyTimeoutPosPulse = ~keyTimeout_r0 & keyTimeout;

	//count two pulses of keyTimeout rise edge for the escape key to time out
	wire keyEscapeTimeoutStart = keyTimeoutPosPulse & ansiEscSeqStateANSI_RECD_ESC;

	//timeout
	wire keyEscapeTimedOut = keyTimeoutPosPulse & keyEscapeTimeoutRunning;

	//clear timeout running flag -- either timeout happened or a new character
	//came in and timeout was aborted
	wire keyEscapeTimeoutEnd = keyEscapeTimedOut | fifoOutValid;

	wire fifoEmpty;
	wire [7:0] fifoOut;

	reg fifoOutValid;
	wire fifoRdEn = ~fifoEmpty;

	//In GoWin FIFO SC IP generator, do not select
	//output register option
	regFifo4x8 ufifo(
		.Data(rxDataIn), //input [7:0] Data
		.Clk(clk), //input Clk
		.WrEn(rxDataInValid), //input WrEn
		.RdEn(fifoRdEn), //input RdEn
		.Reset(~resetn), //input Reset
		.Q(fifoOut), //output [7:0] Q
		.Empty(fifoEmpty), //output Empty
		.Full() //output Full
	);

	always @(posedge clk) begin
		if (~resetn) begin
			ansiEscSeqState <= `DELAY 3'h0;
			rxANSIDataOutValid <= `DELAY 1'b0;
			inputHistory <= `DELAY 4'h0;
			rxANSIDataOut <= `DELAY 8'h0;
			ansiEscDebug <= `DELAY 1'b1;
			fifoOutValid <= `DELAY 1'b0;
			keyEscapeTimeoutRunning <= `DELAY 1'b0;
			keyTimeout_r0 <= `DELAY 1'b0;
		end else begin
			ansiEscSeqState <= `DELAY nextAnsiEscSeqState;
			rxANSIDataOutValid <= `DELAY nextRxANSIDataOutValid;
			inputHistory <= `DELAY nextInputHistory;
			rxANSIDataOut <= `DELAY nextRxANSIDataOut;
			ansiEscDebug <= `DELAY (^ansiEscSeqStateANSI_RECD_IDLE & fifoOutValid)? ~ansiEscDebug: ansiEscDebug;
			fifoOutValid <= `DELAY fifoRdEn;
			keyTimeout_r0 <= `DELAY keyTimeout;
			keyEscapeTimeoutRunning <= `DELAY (keyEscapeTimeoutEnd)? 1'b0:
											(keyEscapeTimeoutStart)? 1'b1: 
											keyEscapeTimeoutRunning;
		end
	end

	always @(*) begin
		nextAnsiEscSeqState = ansiEscSeqState;
		nextRxANSIDataOutValid = 1'b0;
		nextRxANSIDataOut = rxANSIDataOut;
		nextInputHistory = inputHistory;

		//MS bit is for color information, and is passed as-is
		//for non-control characters.
		if (ansiEscSeqStateANSI_RECD_IDLE & fifoOutValid) begin
			if (fifoOut[7:0] == 8'd`CHAR_ESC) begin
				nextAnsiEscSeqState = ANSI_RECD_ESC;
			end else begin
				//remain in ANSI_RECD_IDLE state
				nextRxANSIDataOutValid = 1'b1;
				nextRxANSIDataOut = fifoOut;
			end
		end else if (ansiEscSeqStateANSI_RECD_ESC & fifoOutValid) begin
			if (fifoOut[7:0] == 8'd`CHAR_LEFTBRACKET) begin
				nextAnsiEscSeqState = ANSI_RECD_SEQ;
			end else begin
				nextAnsiEscSeqState = ANSI_RECD_IDLE;
				nextRxANSIDataOutValid = 1'b1;
				nextRxANSIDataOut = fifoOut;
			end
		end else if (ansiEscSeqStateANSI_RECD_SEQ & fifoOutValid) begin
			nextAnsiEscSeqState = ANSI_RECD_IDLE;
			case (fifoOut[7:0])
				`CHAR_A: begin //A -- up
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_UP;
				end
				`CHAR_B: begin //B -- down
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_DOWN;
				end
				`CHAR_C: begin //C -- right
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_RIGHT;
				end
				`CHAR_D: begin //D -- left
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_LEFT;
				end
				`CHAR_F: begin //F -- end
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_END;
				end
				`CHAR_H: begin //H -- home
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_HOME;
				end
				`CHAR_J: begin //J -- clear screen -- difference from ANSI
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_CLS;
				end
				`CHAR_K: begin //K -- clear from cursor to end of the line
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = `CMD_ERASE_EOL;
				end

				/*
				https://en.wikipedia.org/wiki/ANSI_escape_code
				<esc>[1~    - Home        <esc>[16~   -             <esc>[31~   - F17
				<esc>[2~    - Insert      <esc>[17~   - F6          <esc>[32~   - F18
				<esc>[3~    - Delete      <esc>[18~   - F7          <esc>[33~   - F19
				<esc>[4~    - End         <esc>[19~   - F8          <esc>[34~   - F20
				<esc>[5~    - PgUp        <esc>[20~   - F9          <esc>[35~   - 
				<esc>[6~    - PgDn        <esc>[21~   - F10         
				<esc>[7~    - Home        <esc>[22~   -             
				<esc>[8~    - End         <esc>[23~   - F11         
				<esc>[9~    -             <esc>[24~   - F12         
				<esc>[10~   - F0          <esc>[25~   - F13         
				<esc>[11~   - F1          <esc>[26~   - F14         
				<esc>[12~   - F2          <esc>[27~   -             
				<esc>[13~   - F3          <esc>[28~   - F15         
				<esc>[14~   - F4          <esc>[29~   - F16         
				<esc>[15~   - F5          <esc>[30~   -
				*/
				`CHAR_ZERO, `CHAR_ONE, `CHAR_TWO, `CHAR_THREE,
				`CHAR_FOUT, `CHAR_FIVE, `CHAR_SIX, `CHAR_SEVEN,
				`CHAR_EIGHT, `CHAR_NINE: begin 
					//1-8 -- generate output in next state SEQNEXT
					nextAnsiEscSeqState = ANSI_RECD_SEQNEXT;
					nextInputHistory = fifoOut[3:0];
					nextRxANSIDataOutValid = 1'b0;
				end
				default: begin
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = fifoOut;
				end
			endcase
		end else if (ansiEscSeqStateANSI_RECD_SEQNEXT & fifoOutValid) begin
			nextAnsiEscSeqState = ANSI_RECD_IDLE;
			case (fifoOut[7:0])
				`CHAR_J: begin
					//clear in display
					//J, if history is 2 or 3, clear display
					//"ESC [ 2 J" is clear screen
					if ((inputHistory == 4'h2) | (inputHistory == 4'h3)) begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_CLS;
					end else begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = fifoOut;
					end
				end
				`CHAR_K: begin 
					//clear in line
					//"ESC [ 0 K" is clear from cursor to end of the line
					//"ESC [ 1 K" is clear from cursor to start of the line
					//"ESC [ 2 K" is clear entire line
					if (inputHistory == 4'h2) begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_ERASE_LINE;
					end else if (inputHistory == 4'h1) begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_ERASE_SOL;
					end else if (inputHistory == 4'h0) begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_ERASE_EOL;
					end else begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = fifoOut;
					end
				end
				`CHAR_TILDE: begin 
					if (inputHistory == 4'h0) begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_CLS;
					end else if ((inputHistory == 4'h1) |
							(inputHistory == 4'h7)) begin //"ESC [ 1 ~" is Home
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_HOME;  //home not generating this
														//"ESC [ H" is generated
					end else if (inputHistory == 4'h2) begin //Insert
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_INSTOG;
					end else if (inputHistory == 4'h3) begin //Delete 
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_DEL;
					end else if ((inputHistory == 4'h4) 
							| (inputHistory == 4'h8)) begin //End 
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_END; //end not generating this
													  //"ESC [ F" is generated
					end else if (inputHistory == 4'h5) begin //PgUp 
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_PGUP;
					end else if (inputHistory == 4'h6) begin //PgDn 
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = `CMD_PGDN;
					end else begin
						nextRxANSIDataOutValid = 1'b1;
						nextRxANSIDataOut = fifoOut;
					end
				end
				default: begin
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = fifoOut;
				end
			endcase
		end else if (ansiEscSeqStateANSI_RECD_ESC & keyEscapeTimedOut) begin
			//escape has timed out due to delay in arrival of the
			//next char in ANSI sequence.
			//This means that the RECD_ESC state has seen two 
			//pulses at the frequency of heartbest[3]
			nextAnsiEscSeqState = ANSI_RECD_IDLE;
			nextRxANSIDataOutValid = 1'b1;
			nextRxANSIDataOut = 8'd`CHAR_ESC;
		end
	end

endmodule
