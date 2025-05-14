//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Anirban Banerjee
// 
// Create Date:	 May/25/2024 
// Design Name: 
// Module Name:	 vga 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
/*
Pipeline Staging for input command and cursor movement
===========================================
Clock Cycle				Signal
===========================================
0						inputCmdValid,
						inputCmdData

1						inputCmdValid_r0
						inputCmdMemWrEn,
						inputCmdMemWrData,

2						currentCursorRow,
						currentCursorCol,
						screenEndScrollingStarted,
						scrollRow
*/
/*
Pipeline Staging for VGA pixel output
===========================================
Clock Cycle				Signal
===========================================
0						HSync,
						VSync,
						hsyncGen,
						vsyncGen,
						inDisplayArea

1						charWidthCounter,
						charHeightCounter,
						currentScanCharCol,
						currentScanCharRow,
						charBufferRdAddr,
						charBufferRdEn
						inDisplayArea_r0,
						hsync_r0,
						vsync_r0

2						charWidthCounter_r0,
						charHeightCounter_r0,
						charHeightCounterBlank_r0,
						bottomCursor,
						charBufferRdData,
						charROMRdAddr,
						charROMRdEn,
						inDisplayArea_r1,
						hsync_r1,
						vsync_r1

3						charHeightCounterBlank_r1,
						charWidthCounter_r1,
						inDisplayArea_r2,
						charROMRdData,
						bottomCursor_r0,
						hsync_r2,
						vsync_r2

4						pixel
						hsync,
						vsync
*/

`timescale 1ns/1ps
`include "keycharcmdcodes.vh"
`include "vgaminikbd.vh"

module vga(
	input resetn,
	input inputCmdValid,
	input [7:0] inputCmdData,
	input clk,
	input debug,
	input inputKeyA,
	input inputKeyB,
	output wire debug0,
	output wire debug1,
	output wire debug2,
	output reg pixel,
	output reg hsync,
	output reg vsync);

	localparam MAXCOL_M_1 = 79;
	localparam MAXROW_M_1 = 31;
	localparam MAXCHARWIDTH_M_1 = 7;	//5 pixels + 3 blank pixels
	localparam MAXCHARHEIGHT_M_1 = 14;	//7 lines + 1 blank line + 7 interrow blank lines
										//ROM is read only for first 8 values

	localparam MAXCHARS_M_1 = 12'd2559;

	wire hsyncGen;
	wire vsyncGen;
	reg hsync_r0;
	reg vsync_r0;
	reg hsync_r1;
	reg vsync_r1;
	reg hsync_r2;
	reg vsync_r2;

	reg inDisplayArea_r0;
	reg inDisplayArea_r1;
	reg inDisplayArea_r2;

	wire [11:0] charBufferWrAddr;
	wire [11:0] charBufferRdAddr;
	wire [7:0] charBufferWrData;
	wire [7:0] charBufferRdData;
	wire charBufferWrEn;
	wire charBufferRdEn;
	wire inDisplayArea;
	wire [10:0] charROMRdAddr;
	wire [4:0] charROMRdData;
	reg charROMRdEn;
	reg [2:0] charWidthCounter_r0;
	reg [2:0] charWidthCounter_r1;
	reg [2:0] charWidthCounter;  //0-7, incl. 3 extra blank pixels
	reg charHeightCounterBlank_r0;
	reg charHeightCounterBlank_r1;
	reg bottomCursor;
	reg bottomCursor_r0;
	reg [3:0] charHeightCounter_r0;
	reg [3:0] charHeightCounter; //0-10, 7 lines + 1 blank font line, 
								 //plus 7 interrow blank lines
								 //ROM is read only for first 8 values
	reg [4:0] currentScanCharRow;//0-31
	reg [6:0] currentScanCharCol;//0-79

	reg [4:0] currentCursorRow;
	reg [6:0] currentCursorCol;

	wire debugPixel;

	wire charWidthCounterMaxxed;
	wire charHeightCounterMaxxed;
	wire currentScanCharRowMaxxed;
	wire currentScanCharColMaxxed;

	wire charBufferInitInProgress;
	wire [11:0] charBufferInitAddr;
	wire [6:0] charBufferInitData;

	reg inputCmdMemWrEn;
	reg inputCmdValid_r0;
	reg [7:0] inputCmdMemWrData;
	reg [4:0] scrollRow;
	reg screenEndScrollingStarted;
	wire [4:0] currentScrolledRow;

	wire userResetn;
	wire oneSecPulse;

	//The heartbeat module takes in the VSync pulse
	//and generates user reset that remains active (low)
	//for 4 seconds and then deasserts to high.
	//cursorBlink is a 1 second pulse (low+pulse)
	wire slowClkPosEdge;
	heartbeat uheartbeat (
		.clk (clk),
		.resetn (resetn),
		.vsync (vsync),
		.inputKey (inputKeyB),
		.slowClkPosEdge (slowClkPosEdge),
		.userResetn (userResetn),
		.cursorBlink (oneSecPulse)
	);

	wire inputCmdDown		= (inputCmdMemWrData == 8'd`CMD_DOWN) & (currentCursorRow == MAXROW_M_1);
	wire screenEndScroll	= (currentCursorRow == MAXROW_M_1) & (currentCursorCol == MAXCOL_M_1);
	wire inputCmdCMD_CLS	= inputCmdValid & (inputCmdData == 8'd`CMD_CLS);
	wire inputCmdScrollUp	= inputCmdValid_r0 & (inputCmdDown | screenEndScroll);

	charBufferInit ucharbufinit (
		.clk (clk),
		.resetn (resetn),
		.enable (userResetn & inputKeyA & inputKeyB & ~inputCmdCMD_CLS & ~inputCmdScrollUp_r0),
		.zeroize (~inputKeyA | inputCmdCMD_CLS | inputCmdScrollUp_r0),
		.partLineInit (inputCmdScrollUp_r0),
		.partLineRow (currentScrolledRow),
		.partLineCol (7'h0),
		.initWrEn (charBufferInitInProgress),
		.initAddress (charBufferInitAddr),
		.initData (charBufferInitData)
		);

	reg inputCmdScrollUp_r0;
	reg inputCmdCMD_BKSP_r0;
	wire inputCmdCMD_BKSP = inputCmdValid_r0 & (inputCmdMemWrData == 8'd`CMD_BKSP);
	wire inputCmdCMD_DEL = inputCmdValid & (inputCmdValid == 8'd`CMD_DEL);
	always @(posedge clk) begin
		if (~resetn) begin
			currentCursorCol <= `DELAY 7'h0;
			currentCursorRow <= `DELAY 5'h0;
			inputCmdValid_r0 <= `DELAY 1'b0;
			inputCmdMemWrEn <= `DELAY 1'b0;
			inputCmdMemWrData <= `DELAY 8'h0;
			scrollRow <= `DELAY 5'h0;
			screenEndScrollingStarted <= `DELAY 1'b0;
			inputCmdScrollUp_r0 <= `DELAY 1'b0;
			inputCmdCMD_BKSP_r0 <= `DELAY 1'b0;
		end else begin
			inputCmdValid_r0 <= `DELAY inputCmdValid;
			inputCmdMemWrEn <= `DELAY inputCmdValid & (inputCmdData >= 8'd32);
			inputCmdMemWrData <= `DELAY inputCmdData;
			inputCmdScrollUp_r0 <= `DELAY inputCmdScrollUp;
			inputCmdCMD_BKSP_r0 <= `DELAY inputCmdCMD_BKSP;
			//character at current cursor is stored at (MAXROW_M_1 + 1) * currentCursorCol + currentCursorRow
			if (inputCmdValid_r0) begin
				case (inputCmdMemWrData)
					8'd`CMD_CRLF: begin
						//Return is CMD_HOME + CMD_DOWN
						currentCursorCol <= `DELAY 7'h0;
						//if ((currentCursorRow == MAXROW_M_1) | screenEndScrollingStarted) begin
						if (currentCursorRow == MAXROW_M_1) begin
							//screenEndScrollingStarted <= `DELAY 1'b1;
							scrollRow <= `DELAY (scrollRow + 1'b1);
							//erase previous line
						end else begin
							currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
						end
					end
					8'd`CMD_DOWN: begin
						//same as LF
						//remain on row MAXROW_M_1
						//if ((currentCursorRow == MAXROW_M_1) | screenEndScrollingStarted) begin
						if (currentCursorRow == MAXROW_M_1) begin
							//screenEndScrollingStarted <= `DELAY 1'b1;
							scrollRow <= `DELAY (scrollRow + 1'b1);
						end else begin
							currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
						end
					end
					8'd`CMD_UP: begin
						if (currentCursorRow != 5'h0) begin
							currentCursorRow <= `DELAY (currentCursorRow - 1'b1);
						end
					end
					8'd`CMD_LEFT, 8'd`CMD_BKSP: begin
						if (currentCursorCol != 7'h0) begin
							currentCursorCol <= `DELAY (currentCursorCol - 1'b1);
						end else if (currentCursorRow != 5'h0) begin
								currentCursorCol <= `DELAY MAXCOL_M_1;
								currentCursorRow <= `DELAY (currentCursorRow - 1'b1);
						end
					end
					8'd`CMD_RIGHT, 8'd`CMD_TAB: begin
						if (currentCursorCol == MAXCOL_M_1) begin
							//if ((currentCursorRow == MAXROW_M_1) | screenEndScrollingStarted) begin
							if (currentCursorRow == MAXROW_M_1) begin
								screenEndScrollingStarted <= `DELAY 1'b1;
								scrollRow <= `DELAY (scrollRow + 1'b1);
							end else begin
								currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
							end
							currentCursorCol <= `DELAY 7'h0;
						end else begin
							currentCursorCol <= `DELAY (currentCursorCol + 1'b1);
						end
					end
					8'd`CMD_HOME: begin
						//same as CR
						currentCursorCol <= `DELAY 7'h0;
					end
					8'd`CMD_END: begin
						currentCursorCol <= `DELAY MAXCOL_M_1;
					end
					8'd`CMD_CLS: begin //kbd.v will generate ASCII code 'd14 (Form-Feed or ^L) on seeing Shift+Esc
						currentCursorCol <= `DELAY 7'h0;
						currentCursorRow <= `DELAY 7'h0;
						scrollRow <= `DELAY 5'h0;
						screenEndScrollingStarted <= `DELAY 1'b0;
					end
					default: begin
						//printable character > ASCII 31
						if (currentCursorCol == MAXCOL_M_1) begin
							currentCursorCol <= `DELAY 5'h0;
							//if ((currentCursorRow == MAXROW_M_1) | screenEndScrollingStarted) begin
							if (currentCursorRow == MAXROW_M_1) begin
								screenEndScrollingStarted <= `DELAY 1'b1;
								scrollRow <= `DELAY (scrollRow + 1'b1);
								//erase previous line
							end else begin
								currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
							end
						end else begin
							currentCursorCol <= `DELAY (currentCursorCol + 1'b1);
						end
					end
				endcase
			end else if (~inputKeyB | ~inputKeyA) begin
				//key presses will initialize cursor
				currentCursorCol	<= `DELAY 7'h0;
				currentCursorRow	<= `DELAY 5'h0;
				scrollRow			<= `DELAY 5'h0;
				screenEndScrollingStarted	<= `DELAY 1'b0;
			end
		end
	end

	assign debug0 = userResetn; //green
	assign debug1 = 1'b1;//userResetn; //red
	assign debug2 = 1'b1; //blue

	charROM ucharROM (
		.clk (clk),
		.ce (charROMRdEn),
		.ad (charROMRdAddr),
		.oce (1'b0), //unused in charROM's non-pipeline (aka bypass) mode
		.reset (~resetn),
		.dout (charROMRdData));

	//pseudo-dual port RAM to update/read out character (data = ASCII value)
	//32 rows x 80 columns
	//depth = total characters on screen = 2560
	//data width = 8 --> points to one of the 255 characters of charROM

	assign currentScrolledRow = currentCursorRow + scrollRow;
	assign charBufferWrAddr =	(charBufferInitInProgress)?	charBufferInitAddr:
								{currentCursorCol, currentScrolledRow};

	assign charBufferWrData =	(charBufferInitInProgress)?	{1'b0, charBufferInitData[6:0]}:
								inputCmdMemWrData;

	//backspace writes a space character one clock after the cursor is moved left
	//delete just writes a space character without moving the cursor
	wire backspaceOrDelCmd = inputCmdCMD_BKSP_r0 | inputCmdCMD_DEL;
	assign charBufferWrEn = charBufferInitInProgress | inputCmdMemWrEn | backspaceOrDelCmd;

	charBuffer ucharBuffer (
		//using single port RAM -- write has higher priority on the address bus
	    .dout (charBufferRdData),
        .clk (clk),
        .oce (1'b0), //unused in ucharBuffer's non-pipeline (aka bypass) mode
        .ce (charBufferRdEn | charBufferWrEn),
        .reset (~resetn),
        .wre (charBufferWrEn),
        .ad (charBufferWrEn? charBufferWrAddr: charBufferRdAddr),
        .din (backspaceOrDelCmd? 8'd`CMD_SPC: charBufferWrData));

	//https://ktln2.org/2018/01/23/implementing-vga-in-verilog/
	hvsync uhvsync(
		.clk(clk),
		.resetn (resetn),
		.debugPixel(debugPixel),
		.HSync(hsyncGen),
		.VSync(vsyncGen),
		.inDisplayArea(inDisplayArea)
	 );

	assign charROMRdAddr = {charBufferRdData, charHeightCounter_r0[2:0]};

	wire [4:0] currentScrolledScanRow = currentScanCharRow + scrollRow;
	//assign charBufferRdAddr = {currentScanCharCol[6:0], currentScanCharRow[4:0]}; //FIXME
	assign charBufferRdAddr = {currentScanCharCol[6:0], currentScrolledScanRow[4:0]};
	assign charBufferRdEn = (charWidthCounter == 3'h0) & inDisplayArea_r0;

	wire [2:0] nextCharWidthCounter = (charWidthCounter + 1'b1);
	wire [3:0] nextCharHeightCounter = (charHeightCounter + 1'b1);
	wire [6:0] nextCurrentScanCharCol = (currentScanCharCol + 1'b1);
	wire [4:0] nextCurrentScanCharRow = (currentScanCharRow + 1'b1);

	assign charWidthCounterMaxxed = (charWidthCounter == MAXCHARWIDTH_M_1);
	assign charHeightCounterMaxxed = (charHeightCounter == MAXCHARHEIGHT_M_1);
	assign currentScanCharColMaxxed = (currentScanCharCol == MAXCOL_M_1);
	assign currentScanCharRowMaxxed = (currentScanCharRow == (MAXROW_M_1));

	always @(posedge clk) begin
		if (~resetn) begin
			charWidthCounter <= `DELAY 3'h0;
			charHeightCounter <= `DELAY 3'h0;
			charHeightCounter_r0 <= `DELAY 3'h0;
			currentScanCharCol <= `DELAY 7'h0;
			currentScanCharRow <= `DELAY 5'h0;
			charROMRdEn <= `DELAY 1'b0;
			inDisplayArea_r0 <= `DELAY 1'b0;
			inDisplayArea_r1 <= `DELAY 1'b0;
			inDisplayArea_r2 <= `DELAY 1'b0;
			charWidthCounter_r0 <= `DELAY 1'b0;
			charWidthCounter_r1 <= `DELAY 1'b0;
			charHeightCounterBlank_r0 <= `DELAY 1'b0;
			charHeightCounterBlank_r1 <= `DELAY 1'b0;
			bottomCursor <= `DELAY 1'b0;
			bottomCursor_r0 <= `DELAY 1'b0;
		end else begin
			//free running counter for scanning character width from 0-5
			//we need charWidthCounter == 6 to increment currentScanCharCol counter
			if (inDisplayArea) begin
				if (charWidthCounterMaxxed) begin
					charWidthCounter <= `DELAY 3'h0;
				end else begin
					charWidthCounter <= `DELAY nextCharWidthCounter;
				end

				//line (height) within a character only changes at end of the column currentScanCharCol reaches end
				if (charWidthCounterMaxxed & currentScanCharColMaxxed) begin
					if (charHeightCounterMaxxed) begin
						charHeightCounter <= `DELAY 3'h0;
					end else begin
						charHeightCounter <= `DELAY nextCharHeightCounter;
					end
				end

				//currentScanCharCol << 5 + currentScanCharRow = charBuffer memory read address
				//(the data out of charBuffer + charHeightCounter) points to a location in 
				//charROM that gives the 5 values for pixel
				if (charWidthCounterMaxxed) begin
					if (currentScanCharColMaxxed) begin
						currentScanCharCol <= `DELAY 7'h0;
					end else begin
						currentScanCharCol <= `DELAY nextCurrentScanCharCol;
					end
				end

				if (charWidthCounterMaxxed & charHeightCounterMaxxed & currentScanCharColMaxxed) begin
					if (currentScanCharRowMaxxed) begin
						currentScanCharRow <= `DELAY 5'h0;
					end else begin
						currentScanCharRow <= `DELAY nextCurrentScanCharRow;
					end
				end
			end
			charHeightCounter_r0 <= `DELAY charHeightCounter;
			charROMRdEn <= `DELAY charBufferRdEn & ~charHeightCounter[3]; //don't read ROM if height counter > 7
			inDisplayArea_r0 <= `DELAY inDisplayArea;
			inDisplayArea_r1 <= `DELAY inDisplayArea_r0;
			inDisplayArea_r2 <= `DELAY inDisplayArea_r1;
			charWidthCounter_r0 <= `DELAY charWidthCounter;
			charWidthCounter_r1 <= `DELAY charWidthCounter_r0;
			bottomCursor <= `DELAY (charHeightCounter[3:2] == 2'b10) & (^charHeightCounter[1:0]) &
							((~charWidthCounter[2] & |charWidthCounter[1:0]) | (charWidthCounter[2:1] == 2'b10));
			bottomCursor_r0 <= `DELAY bottomCursor;
			charHeightCounterBlank_r0 <= `DELAY charHeightCounter[3];//height counter value is > 7 and < 11
			charHeightCounterBlank_r1 <= `DELAY charHeightCounterBlank_r0;
		end
	end

	reg scanningCurrentCursorCell_r0;
	reg scanningCurrentCursorCell_r1;
	reg scanningCurrentCursorCell_r2;
	wire scanningCurrentCursorCell = (currentScanCharRow[4:0] == currentCursorRow[4:0]) &
										(currentScanCharCol[6:0] == currentCursorCol[6:0]);

	always @(posedge clk) begin
		if (~resetn) begin
			hsync_r0 <= `DELAY 1'b0;
			vsync_r0 <= `DELAY 1'b0;
			hsync_r1 <= `DELAY 1'b0;
			vsync_r1 <= `DELAY 1'b0;
			hsync_r2 <= `DELAY 1'b0;
			vsync_r2 <= `DELAY 1'b0;
			hsync <= `DELAY 1'b0;
			vsync <= `DELAY 1'b0;
			pixel <= `DELAY 1'b0;
			scanningCurrentCursorCell_r0 <= `DELAY 1'b0;
			scanningCurrentCursorCell_r1 <= `DELAY 1'b0;
			scanningCurrentCursorCell_r2 <= `DELAY 1'b0;
		end else begin
			hsync_r0 <= `DELAY hsyncGen;
			vsync_r0 <= `DELAY vsyncGen;
			hsync_r1 <= `DELAY hsync_r0;
			vsync_r1 <= `DELAY vsync_r0;
			hsync_r2 <= `DELAY hsync_r1;
			vsync_r2 <= `DELAY vsync_r1;
			hsync <= `DELAY hsync_r2;
			vsync <= `DELAY vsync_r2;
			scanningCurrentCursorCell_r0 <= `DELAY scanningCurrentCursorCell;
			scanningCurrentCursorCell_r1 <= `DELAY scanningCurrentCursorCell_r0;
			scanningCurrentCursorCell_r2 <= `DELAY scanningCurrentCursorCell_r1;
			if (inDisplayArea_r2) begin
				if (debug) begin
					//send out bands
					pixel <= `DELAY debugPixel;
				end else if (bottomCursor_r0) begin
					//bottom
					pixel <= `DELAY scanningCurrentCursorCell_r2 & oneSecPulse; //0 if current scan cell doesn't have cursor
				end else if (charHeightCounterBlank_r1) begin
					//height counter value > 7 and < 11
					//insert blank line
					pixel <= `DELAY 1'b0;
				end else begin
					case (charWidthCounter_r1)
						//Make first pixel a blank one -- workaround for 
						//leftmost pixel column shift to rightmost column.
						//The shift still happens, but it is now a blank pixel.
						3'h0: pixel <= `DELAY 1'b0; 
						3'h1: pixel <= `DELAY charROMRdData[4];
						3'h2: pixel <= `DELAY charROMRdData[3];
						3'h3: pixel <= `DELAY charROMRdData[2];
						3'h4: pixel <= `DELAY charROMRdData[1];
						3'h5: pixel <= `DELAY charROMRdData[0];
						3'h6: pixel <= `DELAY 1'b0;
						3'h7: pixel <= `DELAY 1'b0;//scanningCurrentCursorCell_r2 & oneSecPulse; //0 if current scan cell doesn't have cursor
						default: pixel <= `DELAY 1'b0;
					endcase
				end
			end else begin
				//outside of visible display area
				pixel <= `DELAY 1'b0;
			end
		end
	 end
	 
endmodule
