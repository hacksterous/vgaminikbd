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
	wire asciiCodeValid;
	wire shiftKeycodes;
	wire specialCodeValidFPulse;

	assign romAsciiDout = (shiftState)? romAsciiDoutNormalAndShift[13:7]: romAsciiDoutNormalAndShift[6:0];
	assign asciiCode = (readKbdRom_r0)? romAsciiDout: specialAsciiCode;
	assign specialCodeValidFPulse = ~nextSpecialCodeValid & specialCodeValid & ~nextSkipNextCode;
	//specialCodeValid and readKbdRom_r0 can't occur simultaneously
	assign asciiCodeValid = readKbdRom_r0 | specialCodeValidFPulse;
	assign shiftKeycodes = (kbdOutCode == 8'h12) | (kbdOutCode == 8'h59);

	wire [6:0] nextKbdData;
	wire nextKbdDataValid;
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

	`define MKSS_IDLE 3'h0
	`define MKSS_CRLF0 3'h1
	`define MKSS_TAB0 3'h2
	`define MKSS_TAB1 3'h3
	`define MKSS_TAB2 3'h4
	`define MKSS_DEL0 3'h5
	`define MKSS_BKSP0 3'h6
	`define MKSS_BKSP1 3'h7
	
	wire multiOutputCmdCode = ((romAsciiDout == `CMD_CRLF) |
								(romAsciiDout == `CMD_TAB) |
								(romAsciiDout == `CMD_DEL) |
								(romAsciiDout == `CMD_BKSP)) & readKbdRom_r0;
	reg [6:0] multiAsciiCode;
	wire multiKeyWIP = (multiKeySeqState != `MKSS_IDLE);
	wire multiAsciiCodeValid = multiOutputCmdCode | multiKeyWIP;

	//some keys like ENTER, DEL, BKSP and TAB add more
	//than one ASCII code
	always @(posedge clk) begin
		if (~resetn) begin
			multiKeySeqState <= `DELAY 4'h0;
		end else begin
			if (readKbdRom_r0 | multiKeyWIP) begin
				casez ({multiKeySeqState, romAsciiDout})
					{`MKSS_IDLE, 7'd`CMD_CRLF}: multiKeySeqState <= `DELAY `MKSS_CRLF0;
					{`MKSS_CRLF0, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_IDLE;
					{`MKSS_IDLE, 7'd`CMD_TAB}: multiKeySeqState <= `DELAY `MKSS_TAB0;
					{`MKSS_TAB0, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_TAB1;
					{`MKSS_TAB1, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_TAB2;
					{`MKSS_TAB2, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_IDLE;
					{`MKSS_IDLE, 7'd`CMD_DEL}: multiKeySeqState <= `DELAY `MKSS_DEL0;
					{`MKSS_DEL0, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_IDLE;
					{`MKSS_IDLE, 7'd`CMD_BKSP}: multiKeySeqState <= `DELAY `MKSS_BKSP0;
					{`MKSS_BKSP0, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_BKSP1;
					{`MKSS_BKSP1, 7'b???_????}: multiKeySeqState <= `DELAY `MKSS_IDLE;
					default: multiKeySeqState <= `DELAY `MKSS_IDLE;
				endcase
			end
		end
	end

	always @(*) begin
		multiAsciiCode = 7'd`CMD_NUL;
		if (readKbdRom_r0 | multiKeyWIP) begin
			casez ({multiKeySeqState, romAsciiDout})
				{`MKSS_IDLE, 7'd`CMD_CRLF}: multiAsciiCode = 7'd`CMD_HOME;
				{`MKSS_CRLF0, 7'b???_????}: multiAsciiCode = 7'd`CMD_DOWN;
				{`MKSS_IDLE, 7'd`CMD_TAB}: multiAsciiCode = 7'd`CMD_SPC;
				{`MKSS_TAB0, 7'b???_????}: multiAsciiCode = 7'd`CMD_SPC;
				{`MKSS_TAB1, 7'b???_????}: multiAsciiCode = 7'd`CMD_SPC;
				{`MKSS_TAB2, 7'b???_????}: multiAsciiCode = 7'd`CMD_SPC;
				{`MKSS_IDLE, 7'd`CMD_DEL}: multiAsciiCode = 7'd`CMD_SPC;
				{`MKSS_DEL0, 7'b???_????}: multiAsciiCode = 7'd`CMD_LEFT;
				{`MKSS_IDLE, 7'd`CMD_BKSP}: multiAsciiCode = 7'd`CMD_LEFT;
				{`MKSS_BKSP0, 7'b???_????}: multiAsciiCode = 7'd`CMD_SPC;
				{`MKSS_BKSP1, 7'b???_????}: multiAsciiCode = 7'd`CMD_LEFT;
				default: multiAsciiCode = 7'd`CMD_NUL;
			endcase
		end
	end

	assign nextKbdDataValid = multiAsciiCodeValid | (~multiAsciiCodeValid & asciiCodeValid);
	assign nextKbdData = (multiAsciiCodeValid)? multiAsciiCode:
							(asciiCodeValid)? asciiCode:
							7'h0;

	always @(*) begin
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
					8'h7D: specialAsciiCode = 7'd`CMD_HOME;//pgup = home
					8'h71: specialAsciiCode = 7'd`CMD_DEL;
					8'h69: specialAsciiCode = 7'd`CMD_END;
					8'h7A: specialAsciiCode = 7'd`CMD_END; //pgdn = end
					8'h75: specialAsciiCode = 7'd`CMD_HOME;//up = home
					8'h6B: specialAsciiCode = 7'd`CMD_LEFT;
					8'h72: specialAsciiCode = 7'd`CMD_END; //down = end
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
