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
						charBufferWrEn,
						inputCmdMemWrData,

2						currentCursorRow,
						currentCursorCol,
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
						charBufferRdEn,
						inDisplayArea_r0,
						hsync_r0,
						vsync_r0

2						currentScanCharCol_r0,
						charWidthCounter_r0,
						charHeightCounter_r0,
						charBufferRdData,
						charROMRdAddr,
						charROMRdEn,
						inDisplayArea_r1,
						hsync_r1,
						vsync_r1

3						currentScanCharCol_r1,
						charWidthCounter_r1,
						charHeightCounter_r1,
						inDisplayArea_r2,
						charROMRdData,
						hsync_r2,
						vsync_r2

4						pixel
						hsync,
						vsync,
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
	output wire userResetn,
	output wire debug0,
	output wire debug1,
	output wire debug2,
	output reg pixel,
	output reg hsync,
	output reg vsync);

	localparam MAXCOL_M_1 = 79;
	localparam MAXROW_M_1 = 31;
	localparam MAXCHARWIDTH_M_1 = 7;	//1 blank pixel + 7 pixels
	localparam MAXCHARHEIGHT_M_1 = 14;	//9 lines + 1 blank line + 2 cursor lines + 3 interrow blank lines

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
	wire [6:0] charBufferRdData;
	wire	   charBufferRdDataColor;
	wire charBufferWrEn;
	wire charBufferRdEn;
	wire inDisplayArea;
	wire [10:0] charROMRdAddr;
	wire [7:0] charROMRdData;
	reg charROMRdEn;
	reg [2:0] charWidthCounter_r0;
	reg [2:0] charWidthCounter_r1;
	reg [2:0] charWidthCounter;  //0-7, incl. 3 extra blank pixels
	reg [3:0] charHeightCounter_r1;
	reg [3:0] charHeightCounter_r0;
	reg [3:0] charHeightCounter; //0-14
	reg [4:0] currentScanCharRow;//0-31
	reg [6:0] currentScanCharCol;//0-79
	reg [6:0] currentScanCharCol_r0;
	reg [6:0] currentScanCharCol_r1;

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
	reg inputCmdScrollUp_r0;
	reg [7:0] inputCmdMemWrData;
	reg [4:0] scrollRow;
	wire [4:0] currentScrolledRow;

	wire cursorBlink;

	//The heartbeat module takes in the VSync pulse
	//and generates user reset that remains active low
	//for 1 second and then deasserts to high.
	//cursorBlink is a 0.5 second pulse 
	heartbeat uheartbeat (
		.clk (clk),
		.resetn (resetn),
		.vsync (vsync),
		.userResetn (userResetn),
		.cursorBlink (cursorBlink)
	);

	wire inputCmdDown		= (inputCmdMemWrData[7:4] == 4'h0) & 
								((inputCmdMemWrData[3:0] == 4'd`CMD_DOWN) | (inputCmdMemWrData == 4'd`CMD_CRLF));
	wire screenEnd	= (currentCursorCol == MAXCOL_M_1);
	wire inputCmdCls		= inputCmdValid_r0 & (inputCmdMemWrData == 8'd`CMD_CLS);
	wire inputCmdCursorToggle = inputCmdValid_r0 & (inputCmdMemWrData[7:4] == 4'h0) & (inputCmdMemWrData[3:0] == 4'd`CMD_CURTOG);
	wire inputCmdScrollUp	= inputCmdValid_r0 & (inputCmdDown | screenEnd) & (currentCursorRow == MAXROW_M_1);

	charBufferInit ucharbufinit (
		.clk (clk),
		.resetn (resetn),
		.enable (userResetn & inputKeyA & inputKeyB & ~inputCmdCls & ~inputCmdScrollUp_r0),
		.sequentialInit (~inputKeyB),
		.partLineInit (inputCmdScrollUp_r0),
		.partLineRow (currentScrolledRow),
		.partLineCol (7'h0),
		.initWrEn (charBufferInitInProgress),
		.initAddress (charBufferInitAddr),
		.initData (charBufferInitData)
		);

	wire inputCmdCMD_BKSP = inputCmdValid_r0 & (inputCmdMemWrData[7:4] == 4'h0) & 
							(inputCmdMemWrData[3:0] == 4'd`CMD_BKSP);
	wire inputCmdCMD_DEL = inputCmdValid_r0 & (inputCmdMemWrData[7:4] == 4'h0) & 
							(inputCmdMemWrData[3:0] == 4'd`CMD_DEL);
	
	//command to move to absolute row number specified -- bits [7:5] should be 111
	wire inputCmdAbsRow = inputCmdValid_r0 & (inputCmdMemWrData[7:5] == `CMD_ABS_ROW_7_5);
	wire [4:0] inputValueAbsRow = inputCmdMemWrData[4:0];
	
	//command to move to absolute column number specified bit [7] 
	//should be 1 but bits [6:5] should not be 11
	wire inputCmdAbsCol = inputCmdValid_r0 
							& (inputCmdMemWrData[7] == `CMD_ABS_COL_7_7)
							& (inputCmdMemWrData[6:5] != `CMD_ABS_ROW_6_5);
	//note: col value must not be above 79, or it could mess up the logic
	wire [6:0] inputValueAbsCol = inputCmdMemWrData[6:0]; 

	wire isPrintableChar = inputCmdValid_r0 & (|inputCmdMemWrData[7:5]); //inputCmdMemWrData[7:0] > 31
	//TODO: rowDMA when isPrintableChar = 1
	//TODO: rowDMA when currentCursorColNotZero = 0
	reg [6:0] rowDMARdCol;
	reg [6:0] nextRowDMARdCol;
	//row DMA is to handle backspace and delete
	reg [1:0] nextRowDMAState;
	reg [1:0] rowDMAState;
	wire currentCursorColNotZero = |currentCursorCol[6:0];
	localparam LDMA0 = 0;
	localparam LDMA1 = 1;
	localparam LDMA2 = 3;
	localparam LDMA3 = 2;
	//LDMA0 - idle, on backspace or delete, go to 1
	//LDMA1 - read, go to 2
	//LDMA2 - write, if currentScanCharCol == 79 got to 3, else go to 1
	//LDMA3 - column 79, write space, go to 0
	//note: charBuffer is single-port RAM
	//read happens in states LDMA1
	//write to previous location happens in states LDMA2
	wire rowDMARdEn = (rowDMAState == LDMA1);
	wire rowDMAWrEn =  (rowDMAState == LDMA2);
	wire rowDMAWrEnLast = (rowDMAState == LDMA3);
	wire rowDMARdColMaxxed = (rowDMARdCol == 7'd79);
	wire rowDMAIDLE = (rowDMAState == LDMA0);
	always @(*) begin
		nextRowDMAState = rowDMAState;
		nextRowDMARdCol = rowDMARdCol;
		case (rowDMAState)
			LDMA0: begin
				if (inputCmdCMD_BKSP & currentCursorColNotZero | inputCmdCMD_DEL) begin
					nextRowDMAState = LDMA1;
					//the DMA read address -- this is always 1 more than DMA write address
					nextRowDMARdCol = (inputCmdCMD_DEL)? (currentCursorCol + 1'b1): currentCursorCol;
				end
			end
			LDMA1: begin
				//read from column rowDMARdCol
				nextRowDMAState = LDMA2;
			end
			LDMA2: begin
				//write to column (rowDMARdCol - 1) with the data read in state LDMA1
				nextRowDMAState = rowDMARdColMaxxed? LDMA3: LDMA1;
				//if read to column 79 has happened in state LDMA1, then increment read column to 80
				//but exit to state LDMA3
				nextRowDMARdCol = rowDMARdCol + 1'b1;
			end
			LDMA3: begin
				//write to column (rowDMARdCol - 1), which now equals 79, but write data is space char (value 32)
				nextRowDMAState = LDMA0;
				nextRowDMARdCol = 7'h0;
			end
			default: begin
				nextRowDMAState = LDMA0;
				nextRowDMARdCol = 7'h0;
			end
		endcase
	end

	always @(posedge clk) begin
		if (~resetn) begin
			rowDMAState <= `DELAY 2'h0;
			rowDMARdCol <= `DELAY 7'h0;
		end else begin
			rowDMAState <= `DELAY nextRowDMAState;
			rowDMARdCol <= `DELAY nextRowDMARdCol;
		end
	end

	reg cursorInvisible;
	always @(posedge clk) begin
		if (~resetn) begin
			cursorInvisible <= `DELAY 1'b0; //1 means cursor is invisible
			currentCursorCol <= `DELAY 7'h0;
			currentCursorRow <= `DELAY 5'h0;
			inputCmdValid_r0 <= `DELAY 1'b0;
			inputCmdMemWrEn <= `DELAY 1'b0;
			inputCmdMemWrData <= `DELAY 8'h0;
			scrollRow <= `DELAY 5'h0;
			inputCmdScrollUp_r0 <= `DELAY 1'b0;
		end else begin
			//1 means cursor is invisible
			//during backspace or delete operation, make cursor invisible
			cursorInvisible <= `DELAY (inputCmdCursorToggle)? ~cursorInvisible: cursorInvisible; 
			inputCmdValid_r0 <= `DELAY inputCmdValid;
			inputCmdMemWrEn <= `DELAY inputCmdValid & (inputCmdData >= 8'd32);
			inputCmdMemWrData <= `DELAY inputCmdData;
			inputCmdScrollUp_r0 <= `DELAY inputCmdScrollUp;
			//character at current cursor is stored at (MAXROW_M_1 + 1) * currentCursorCol + currentCursorRow
			if (inputCmdValid_r0) begin
				if (inputCmdMemWrData[7:4] == 4'h0) begin
					case (inputCmdMemWrData[3:0])
						4'd`CMD_CRLF: begin
							//Return is CMD_HOME + CMD_DOWN
							currentCursorCol <= `DELAY 7'h0;
							if (currentCursorRow == MAXROW_M_1) begin
								scrollRow <= `DELAY (scrollRow + 1'b1);
								//erase previous line
							end else begin
								currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
							end
						end
						4'd`CMD_DOWN: begin
							//same as LF
							//remain on row MAXROW_M_1
							if (currentCursorRow == MAXROW_M_1) begin
								scrollRow <= `DELAY (scrollRow + 1'b1);
							end else begin
								currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
							end
						end
						4'd`CMD_PGUP: begin
							currentCursorRow = `DELAY 0;
							currentCursorCol <= `DELAY 0;
						end
						4'd`CMD_PGDN: begin
							currentCursorRow = `DELAY MAXROW_M_1;
							currentCursorCol <= `DELAY MAXCOL_M_1;
						end
						4'd`CMD_UP: begin
							if (currentCursorRow != 5'h0) begin
								currentCursorRow <= `DELAY (currentCursorRow - 1'b1);
							end
						end
						4'd`CMD_LEFT, 8'd`CMD_BKSP: begin
						//4'd`CMD_LEFT: begin //backspace on column 0 doesn't make cursor go back one row
							if (currentCursorCol != 7'h0) begin
								currentCursorCol <= `DELAY (currentCursorCol - 1'b1);
							end else if (currentCursorRow != 5'h0) begin
									currentCursorCol <= `DELAY MAXCOL_M_1;
									currentCursorRow <= `DELAY (currentCursorRow - 1'b1);
							end
						end
						4'd`CMD_RIGHT, 8'd`CMD_TAB: begin
							if (currentCursorCol == MAXCOL_M_1) begin
								if (currentCursorRow == MAXROW_M_1) begin
									scrollRow <= `DELAY (scrollRow + 1'b1);
								end else begin
									currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
								end
								currentCursorCol <= `DELAY 7'h0;
							end else begin
								currentCursorCol <= `DELAY (currentCursorCol + 1'b1);
							end
						end
						4'd`CMD_HOME: begin
							//same as CR
							currentCursorCol <= `DELAY 7'h0;
						end
						4'd`CMD_END: begin
							currentCursorCol <= `DELAY MAXCOL_M_1;
						end
						4'd`CMD_CLS: begin //kbd.v will generate ASCII code 'd14 (Form-Feed or ^L) on seeing Shift+Esc
							currentCursorCol <= `DELAY 7'h0;
							currentCursorRow <= `DELAY 7'h0;
							scrollRow <= `DELAY 5'h0;
						end
					endcase
				end else if (inputCmdAbsRow) begin
					currentCursorRow <= ` DELAY inputValueAbsRow;
				end else if (inputCmdAbsCol) begin
					currentCursorCol <= ` DELAY inputValueAbsCol;
				end else begin
					//printable character > ASCII 31
					if (currentCursorCol == MAXCOL_M_1) begin
						currentCursorCol <= `DELAY 5'h0;
						if (currentCursorRow == MAXROW_M_1) begin
							scrollRow <= `DELAY (scrollRow + 1'b1);
							//previous line gets erased
						end else begin
							currentCursorRow <= `DELAY (currentCursorRow + 1'b1);
						end
					end else begin
						currentCursorCol <= `DELAY (currentCursorCol + 1'b1);
					end
				end
			end else if (~inputKeyB | ~inputKeyA) begin
				//key presses will initialize cursor
				currentCursorCol	<= `DELAY 7'h0;
				currentCursorRow	<= `DELAY 5'h0;
				scrollRow			<= `DELAY 5'h0;
			end
		end
	end

	assign debug0 = 1'b1; //green
	assign debug1 = 1'b1;//userResetn; //red
	assign debug2 = 1'b1; //blue

	wire [4:0] shiftedHeightCounter = ({1'b0, charHeightCounter_r0[3:0]} - 5'd9);
	//bit[4] set means charHeightCounter_r0 is < 9, so use charHeightCounter in ROM address
	wire [3:0] heightCounterAdjusted = (shiftedHeightCounter[4])? charHeightCounter_r0[3:0]:
									shiftedHeightCounter[3:0];

	assign charROMRdAddr = {heightCounterAdjusted[3:0], charBufferRdData[6:0]};

	charROM ucharROM (
		.clk (clk),
		.ce (charROMRdEn),
		.ad (charROMRdAddr),
		.oce (1'b0), //unused in charROM's non-pipeline (aka bypass) mode
		.reset (~resetn),
		.dout (charROMRdData));

	//single port RAM to update/read out character (data = ASCII value)
	//32 rows x 80 columns
	//depth = total characters on screen = 2560
	//data width = 8 --> points to one of the 255 characters of charROM

	wire [6:0] rowDMAWrCol = (rowDMARdCol - 1'b1);
	assign currentScrolledRow = currentCursorRow + scrollRow;
	assign charBufferWrAddr =	(charBufferInitInProgress)?	charBufferInitAddr[11:0]:
								(rowDMAWrEn | rowDMAWrEnLast)? {rowDMAWrCol[6:0], currentScrolledRow[4:0]}:
								{currentCursorCol[6:0], currentScrolledRow[4:0]};

	assign charBufferWrData =	(charBufferInitInProgress)?	charBufferInitData[6:0]:
								(rowDMAWrEn)? {charBufferRdDataColor, charBufferRdData[6:0]}:
								//for the last column, write with space
								(rowDMAWrEnLast)? {charBufferRdDataColor, 7'd32}:
								{charBufferRdDataColor, inputCmdMemWrData[6:0]};

	//backspace writes a space character one clock after the cursor is moved left
	//delete just writes a space character without moving the cursor
	assign charBufferWrEn = charBufferInitInProgress | inputCmdMemWrEn
							| rowDMAWrEn | rowDMAWrEnLast;

	wire [4:0] currentScrolledScanRow = currentScanCharRow + scrollRow;
	wire [6:0] charBufferRdCol = (rowDMARdEn)? rowDMARdCol[6:0]: currentScanCharCol[6:0];
	//wire [4:0] charBufferRdRow = (rowDMARdEn)? currentCursorRow[4:0]: currentScrolledScanRow[4:0];
	wire [4:0] charBufferRdRow = (rowDMARdEn)? currentScrolledRow[4:0]: currentScrolledScanRow[4:0];
	assign charBufferRdAddr = {charBufferRdCol[6:0], charBufferRdRow[4:0]};
	assign charBufferRdEn = ((charWidthCounter == 3'h0) & inDisplayArea_r0) 
								| rowDMARdEn;

	charBuffer ucharBuffer (
		//using single port RAM -- write has higher priority on the address bus
	    .dout ({charBufferRdDataColor, charBufferRdData[6:0]}),
        .clk (clk),
        .oce (1'b0), //unused in ucharBuffer's non-pipeline (aka bypass) mode
        .ce (charBufferRdEn | charBufferWrEn),
        .reset (~resetn),
        .wre (charBufferWrEn),
        .ad (charBufferWrEn? charBufferWrAddr: charBufferRdAddr),
        .din (charBufferWrData[7:0]));

	//https://ktln2.org/2018/01/23/implementing-vga-in-verilog/
	hvsync uhvsync(
		.clk(clk),
		.resetn (resetn),
		.debugPixel(debugPixel),
		.HSync(hsyncGen),
		.VSync(vsyncGen),
		.inDisplayArea(inDisplayArea)
	 );

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
			charWidthCounter			<= `DELAY 3'h0;
			charHeightCounter			<= `DELAY 4'h0;
			charHeightCounter_r0		<= `DELAY 4'h0;
			charHeightCounter_r1		<= `DELAY 4'h0;
			currentScanCharCol			<= `DELAY 7'h0;
			currentScanCharRow			<= `DELAY 5'h0;
			charROMRdEn					<= `DELAY 1'b0;
			inDisplayArea_r0			<= `DELAY 1'b0;
			inDisplayArea_r1			<= `DELAY 1'b0;
			inDisplayArea_r2			<= `DELAY 1'b0;
			charWidthCounter_r0			<= `DELAY 1'b0;
			charWidthCounter_r1			<= `DELAY 1'b0;
		end else begin
			charHeightCounter_r0 <= `DELAY charHeightCounter;
			charHeightCounter_r1 <= `DELAY charHeightCounter_r0;
			//don't read ROM if height counter > 8. Font height = 9 lines, extrapolated height = 12 lines.
			charROMRdEn <= `DELAY charBufferRdEn & (charHeightCounter[3:0] < 4'd13); 
			inDisplayArea_r0 <= `DELAY inDisplayArea;
			inDisplayArea_r1 <= `DELAY inDisplayArea_r0;
			inDisplayArea_r2 <= `DELAY inDisplayArea_r1;
			charWidthCounter_r0 <= `DELAY charWidthCounter;
			charWidthCounter_r1 <= `DELAY charWidthCounter_r0;

			if (inDisplayArea) begin
				if (charWidthCounterMaxxed) begin
					charWidthCounter <= `DELAY 3'h0;
				end else begin
					charWidthCounter <= `DELAY nextCharWidthCounter;
				end

				//line (height) within a character only changes at end of the column currentScanCharCol reaches end
				if (charWidthCounterMaxxed & currentScanCharColMaxxed) begin
					if (charHeightCounterMaxxed) begin
						charHeightCounter <= `DELAY 4'h0;
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
				end else begin
					if (~charROMRdData[7]) begin
						//regular glyph
						case (charHeightCounter_r1)
							4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: begin
								case (charWidthCounter_r1)
									//Make first pixel a blank one -- workaround for 
									//leftmost pixel column shift to rightmost column.
									//The shift still happens, but it is now a blank pixel.
									3'h0: pixel <= `DELAY 1'b0;
									3'h1: pixel <= `DELAY charROMRdData[6];
									3'h2: pixel <= `DELAY charROMRdData[5];
									3'h3: pixel <= `DELAY charROMRdData[4];
									3'h4: pixel <= `DELAY charROMRdData[3];
									3'h5: pixel <= `DELAY charROMRdData[2];
									3'h6: pixel <= `DELAY charROMRdData[1];
									3'h7: pixel <= `DELAY charROMRdData[0];
									default: pixel <= `DELAY 1'b0;
								endcase
							end
							//make cursor invisible during backspace/delete operations
							4'd12, 4'd13: pixel <= `DELAY scanningCurrentCursorCell_r2 & cursorBlink & ~cursorInvisible & rowDMAIDLE;
							default: pixel <= `DELAY 1'b0;
						endcase
					end else begin
						//char with descending glyph
						case (charHeightCounter_r1)
							4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8, 4'd9, 4'd10, 4'd11: begin
								case (charWidthCounter_r1)
									//Make first pixel a blank one -- workaround for 
									//leftmost pixel column shift to rightmost column.
									//The shift still happens, but it is now a blank pixel.
									3'h0: pixel <= `DELAY 1'b0; 
									3'h1: pixel <= `DELAY charROMRdData[6];
									3'h2: pixel <= `DELAY charROMRdData[5];
									3'h3: pixel <= `DELAY charROMRdData[4];
									3'h4: pixel <= `DELAY charROMRdData[3];
									3'h5: pixel <= `DELAY charROMRdData[2];
									3'h6: pixel <= `DELAY charROMRdData[1];
									3'h7: pixel <= `DELAY charROMRdData[0];
									default: pixel <= `DELAY 1'b0;
								endcase
							end
							//make cursor invisible during backspace/delete operations
							4'd12, 4'd13: pixel <= `DELAY scanningCurrentCursorCell_r2 & cursorBlink & ~cursorInvisible & rowDMAIDLE;
							default: pixel <= `DELAY 1'b0;
						endcase
					end
				end
			end else begin
				//outside of visible display area
				pixel <= `DELAY 1'b0;
			end
		end
	 end
	 
endmodule
