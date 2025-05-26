//(C) Anirban Banerjee 2024
//License: GNU GPL v3
//TODO: Control, Alt
`timescale 1ns/1ps
`include "keycharcmdcodes.vh"
`include "vgaminikbd.vh"
module kbd (
	clk,
	resetn,
	KBD_CLK,
 	KBD_DATA,
	kbdData,
	kbdDataValid);

	input			clk;
	input			resetn;
	input			KBD_CLK;
	input		 	KBD_DATA;
	output reg [7:0]	kbdData;
	output reg			kbdDataValid;

	reg [2:0] multiKeySeqState;
	wire [7:0] kbdcode;
	wire kbdcodeValid;
	reg fifoReadDataValid;
	wire kbdfifoNotEmpty;
	reg skipNextCode; //this is the second code of a key break/release code pair
	reg nextSkipNextCode;
	reg shiftState;
	reg nextShiftState;
	wire [7:0] kbdOutCode;
	reg readKbdRom_r0;
	reg readKbdRom;
	reg specialCodeValid;
	reg nextSpecialCodeValid;
	reg [6:0] kbdromAddr;
	wire [13:0] romAsciiDoutNormalAndShift;
	reg [6:0] specialAsciiCode;
	wire [6:0] romAsciiDout;
	wire [6:0] asciiCode;
	wire nextKbdDataValid;
	wire [6:0] nextKbdData;
	wire shiftKeycodes;
	wire specialCodeValidFPulse;

	assign romAsciiDout = (shiftState)? romAsciiDoutNormalAndShift[13:7]: romAsciiDoutNormalAndShift[6:0];
	assign asciiCode = (readKbdRom_r0)? romAsciiDout: specialAsciiCode;
	assign specialCodeValidFPulse = ~nextSpecialCodeValid & specialCodeValid & ~nextSkipNextCode;
	//specialCodeValid and readKbdRom_r0 can't occur simultaneously
	assign shiftKeycodes = (kbdOutCode == 8'h12) | (kbdOutCode == 8'h59);
	assign nextKbdDataValid = readKbdRom_r0 | specialCodeValidFPulse;
	assign nextKbdData = (nextKbdDataValid)? asciiCode: 7'h0;

	always @(posedge clk) begin
		if (~resetn) begin
			fifoReadDataValid <= `DELAY 1'b0;
			shiftState <= `DELAY 1'b0;
			readKbdRom_r0 <= `DELAY 1'b0;
			specialCodeValid <= `DELAY 1'b0;
			skipNextCode <= `DELAY 1'b0;
			kbdData <= `DELAY 8'h0;
			kbdDataValid <= `DELAY 1'b0;
		end else begin
			fifoReadDataValid <= `DELAY kbdfifoNotEmpty;
			shiftState <= `DELAY nextShiftState;
			readKbdRom_r0 <= `DELAY readKbdRom;
			specialCodeValid <= `DELAY nextSpecialCodeValid;
			skipNextCode <= `DELAY nextSkipNextCode; //key release code
			kbdData <= `DELAY {1'b0, nextKbdData[6:0]};
			kbdDataValid <= `DELAY nextKbdDataValid;
		end
	end

	always @(*) begin
		//break/release key codes start with F0
		//special key codes start with E0
		//break/release code for special keys start with E0 F0
		nextShiftState = shiftState;
		readKbdRom = 1'b0;
		kbdromAddr = 7'h0;
		nextSpecialCodeValid = specialCodeValid;
		nextSkipNextCode = skipNextCode;
		specialAsciiCode = 7'h0;
		if (fifoReadDataValid & ~skipNextCode) begin
			if (specialCodeValid) begin
				casez (kbdOutCode)
					8'h6C: specialAsciiCode = 7'd`CMD_HOME;
					8'h7D: specialAsciiCode = 7'd`CMD_PGUP;//pgup - first char of page
					8'h71: specialAsciiCode = 7'd`CMD_DEL;
					8'h69: specialAsciiCode = 7'd`CMD_END;
					8'h7A: specialAsciiCode = 7'd`CMD_PGDN; //pgdn - last char of page
					8'h75: specialAsciiCode = 7'd`CMD_UP;//up
					8'h6B: specialAsciiCode = 7'd`CMD_LEFT;
					8'h72: specialAsciiCode = 7'd`CMD_DOWN; //down
					8'h74: specialAsciiCode = 7'd`CMD_RIGHT;
					8'h4A: specialAsciiCode = 7'd47;//Keypad '/'
					8'hF0: nextSkipNextCode = 1'b1; //skip E0, F0, <*>
					default: begin
						specialAsciiCode = 7'd0;
						nextSkipNextCode = 1'b0;
					end
				endcase
				nextSpecialCodeValid = 1'b0; 
			end else if (kbdOutCode == 8'hF0) begin 
				nextSkipNextCode = 1'b1;
				nextSpecialCodeValid = 1'b0; 
			end else if (shiftKeycodes) begin 
				nextShiftState = 1'b1;
				nextSkipNextCode = 1'b0;
				nextSpecialCodeValid = 1'b0; 
			end else if (kbdOutCode == 8'hE0) begin 
				//nextSpecialCodeValid and readKbdRom can't occur simultaneously
				nextSkipNextCode = 1'b0;
				nextSpecialCodeValid = 1'b1; 
			end else begin
				nextSkipNextCode = 1'b0;
				nextSpecialCodeValid = 1'b0; 
				readKbdRom = 1'b1;
				kbdromAddr = kbdOutCode[6:0];
			end
		end else if (fifoReadDataValid) begin
			if (skipNextCode & shiftState) nextShiftState = 1'b0;
			//skipNextCode is 1, clear code flags
			nextSkipNextCode = 1'b0;
			nextSpecialCodeValid = 1'b0; 
		end
	end

	kbdrom ukbdrom (
		.clk (clk),
		.ce (readKbdRom),
		.ad (kbdromAddr),
		.oce (1'b0), //unused in kbdrom's non-pipeline (aka bypass) mode
		.reset (~resetn),
		.dout (romAsciiDoutNormalAndShift[13:0]));

	//keyboard data goes into this FIFO
	fifo #(.WIDTH(8), .DEPTH(4)) kbdfifo (
		.clk (clk),
		.resetn (resetn),
		.push (kbdcodeValid),
		.notfull (),
		.inData (kbdcode),
		.notempty (kbdfifoNotEmpty),
		.pop (kbdfifoNotEmpty),
		.outData (kbdOutCode));

	ps2receiver ps2kbd (
		.clk (clk),
		.reset (~resetn),
		.PS2_CLK (KBD_CLK),
		.PS2_DAT (KBD_DATA),
		.kbdcode (kbdcode),
		.kbdcodeValid (kbdcodeValid));

endmodule
