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
	reg [2:0] ansiEscSeqState;	
	reg [2:0] nextAnsiEscSeqState;

	reg nextRxANSIDataOutValid;
	reg [7:0] nextRxANSIDataOut;

	wire ansiEscSeqStateANSI_RECD_IDLE = (ansiEscSeqState == ANSI_RECD_IDLE);
	wire ansiEscSeqStateANSI_RECD_ESC = (ansiEscSeqState == ANSI_RECD_ESC);
	wire ansiEscSeqStateANSI_RECD_SEQ = (ansiEscSeqState == ANSI_RECD_SEQ);

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
			rxANSIDataOut <= `DELAY 8'h0;
			ansiEscDebug <= `DELAY 1'b1;
			fifoOutValid <= `DELAY 1'b0;
		end else begin
			ansiEscSeqState <= `DELAY nextAnsiEscSeqState;
			rxANSIDataOutValid <= `DELAY nextRxANSIDataOutValid;
			rxANSIDataOut <= `DELAY nextRxANSIDataOut;
			ansiEscDebug <= `DELAY (^ansiEscSeqStateANSI_RECD_IDLE & fifoOutValid)? ~ansiEscDebug: ansiEscDebug;
			fifoOutValid <= `DELAY fifoRdEn;
		end
	end

	always @(*) begin
		nextAnsiEscSeqState = ansiEscSeqState;
		nextRxANSIDataOutValid = 1'b0;
		nextRxANSIDataOut = rxANSIDataOut;

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
				65: begin //A -- up
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = 2; //CMD_UP
				end
				66: begin //B -- down
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = 10; //CMD_DOWN
				end
				67: begin //C -- right
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = 14; //CMD_RIGHT
				end
				68: begin //D -- left
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = 12; //CMD_LEFT
				end
				default: begin
					nextRxANSIDataOutValid = 1'b1;
					nextRxANSIDataOut = fifoOut;
				end
			endcase
		end
	end

endmodule
