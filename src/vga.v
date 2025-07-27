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

2						charWidthCounter_r0,
						charHeightCounter_r0,
						charBufferRdData,
						charROMRdAddr,
						charROMRdEn,
						inDisplayArea_r1,
						hsync_r1,
						vsync_r1

3						charWidthCounter_r1,
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
	output wire [7:0] debugUARTTxData,
	output wire debugUARTTxDataValid,
	output wire userResetn,
	output wire debug0,
	output wire debug1,
	output wire debug2,
	output reg pixel,
	output reg hsync,
	output reg vsync);

	
	localparam TABLEN = 4'd4; //tab is 8 space wide
	localparam MAXCOL_M_1 = 79;
	localparam MAXCOL_M_2 = 78;
	localparam MAXCOL_M_TABLEN_1 = 75;
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

	reg [4:0] currentCursorRow;
	reg [6:0] currentCursorCol/*synthesis syn_ preserve =1*/;

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
	reg [7:0] inputCmdMemWrData/*synthesis syn_ preserve =1*/;

	reg [4:0] scrollRow;
	wire [4:0] currentScrolledRow;

	wire cursorBlink;

	reg cursorInvisible;
	reg pendingSetCol;
	reg pendingSetRow;
	reg insertMode;

	//The heartbeat module takes in the VSync pulse
	//and generates user reset that remains active low
	//for 1 second and then deasserts to high.
	//cursorBlink is a 0.5 second pulse 
	heartbeat uheartbeat (
		.clk (clk),
		.resetn (resetn),
		.vsync (vsync),
		.userResetn (userResetn),
		.cursorBlink (cursorBlink));

	wire inputCmdDownCode = (inputCmdMemWrData[3:0] == 4'd`CMD_DOWN) | (inputCmdMemWrData == 4'd`CMD_CRLF);

	wire screenEnd = (currentCursorCol == MAXCOL_M_1);

	//wire inputCmdLow16 = inputCmdValid_r0 & (inputCmdMemWrData[7:4] == 4'h0);
	wire inputCmdLow16 = inputCmdValid_r0 & ~|inputCmdMemWrData[7:4];
	wire inputCmdCls		= inputCmdLow16 & (inputCmdMemWrData == 4'd`CMD_CLS);

	wire inputCmdCMD_BKSP = inputCmdLow16 & (inputCmdMemWrData[3:0] == 4'd`CMD_BKSP);
	wire inputCmdCMD_DEL = inputCmdLow16 & (inputCmdMemWrData[3:0] == 4'd`CMD_DEL);
	
	wire inputCmdLow32 = inputCmdValid_r0 & ~|inputCmdMemWrData[7:5];

	wire isPrintableChar = inputCmdMemWrEn;

	wire inputCmdInsertToggle = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_INSTOG);

	wire inputCmdScrollUp	= (inputCmdLow16 & inputCmdDownCode 
								| inputCmdValid_r0 & screenEnd & isPrintableChar)
								& (currentCursorRow == MAXROW_M_1);

	wire inputCmdCursorToggle = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_CURTOG);
	//erase to start of line (move char at current char to column 0 with the rest of characters following)
	wire inputCmdEraseSOL = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_ERASE_SOL);

	//erase to end of line and erase line -- for these two, make use of charBufferInit logic
	wire inputCmdEraseEOL = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_ERASE_EOL);
	wire inputCmdEraseLine = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_ERASE_LINE);

	wire inputCmdSetCol = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_SETCOL);
	wire inputCmdSetRow = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_SETROW);

	wire inputCmdMoveRows = inputCmdLow32 & (inputCmdMemWrData[4:0] == 5'd`CMD_MOVROWS);

	//reg [6:0] insertModeCol;
	reg eraseToSOLInProgress;
	reg [6:0] rowDMARdCol;
	reg [6:0] nextRowDMARdCol;
	//row DMA is to handle backspace and delete
	reg [2:0] nextRowDMAState;
	reg [2:0] rowDMAState;
	localparam ROWDMA_IDLE = 0;
	localparam ROWDMA_READ = 1;
	localparam ROWDMA_WRITE = 3;
	localparam ROWDMA_LASTWRITE = 2;
	localparam ROWDMA_INSCHAR_READ = 6;
	localparam ROWDMA_INSCHAR_WRITE = 7;
	localparam ROWDMA_INSCHAR_DONE = 5;
	localparam ROWDMA_ROWMOVE = 4;
	//ROWDMA_IDLE - idle, on backspace or delete, go to 1, if 
	//ROWDMA_READ - read, go to 2
	//ROWDMA_WRITE - write, if currentScanCharCol == 79 got to 3, else go to 1
	//ROWDMA_LASTWRITE - column 79, write space, go to 0
	//note: charBuffer is single-port RAM
	//read happens in states ROWDMA_READ
	//write to previous location happens in states ROWDMA_WRITE
	wire rowDMAInsReadWrite;
	wire rowDMAInsDone;

	wire rowDMAIdle = (rowDMAState == ROWDMA_IDLE);
	wire rowDMARdEn = (rowDMAState == ROWDMA_READ);
	wire rowDMAWrEn =  (rowDMAState == ROWDMA_WRITE);
	wire rowDMAWrEnLast = (rowDMAState == ROWDMA_LASTWRITE);
	wire rowDMAInsRdEn = (rowDMAState == ROWDMA_INSCHAR_READ);
	wire rowDMAInsWrEn = (rowDMAState == ROWDMA_INSCHAR_WRITE);
	assign rowDMAInsDone = (rowDMAState == ROWDMA_INSCHAR_DONE);
	wire rowDMARowMove = (rowDMAState == ROWDMA_ROWMOVE);
	wire [6:0] rowDMAWrCol = (rowDMAWrEnLast | rowDMAInsDone)? rowDMARdCol:
							 (rowDMAInsReadWrite)? (rowDMARdCol + 1'b1):
							 (eraseToSOLInProgress)? (rowDMARdCol - currentCursorCol):
							 (rowDMARdCol - 1'b1);
	wire rowDMARdColMaxxed = (rowDMARdCol == MAXCOL_M_1);
	//wire rowDMARdColAtCursor = (rowDMARdCol == insertModeCol); //FIXME
	wire rowDMARdColAtCursor = (rowDMARdCol == currentCursorCol);
	wire rowDMAWrColMaxxed = (rowDMAWrCol == MAXCOL_M_1);
	assign rowDMAInsReadWrite = rowDMAInsRdEn | rowDMAInsWrEn;
	wire bkspNotAtColZero = inputCmdCMD_BKSP & |currentCursorCol[6:0];

	wire cursorColNotAtMax = (currentCursorCol != MAXCOL_M_1);
	
	wire insertModeNotAtMaxCol = insertMode & cursorColNotAtMax;
	wire inputCmdInsertChar = isPrintableChar & insertModeNotAtMaxCol;
	wire rowDMAInsCharStart = rowDMAIdle & inputCmdInsertChar;

	wire nextEraseToSOLInProgress = (rowDMAWrEnLast & rowDMAWrColMaxxed)? 1'b0:
									(rowDMAIdle & inputCmdEraseSOL)? 1'b1:
									eraseToSOLInProgress;

	always @(*) begin
		nextRowDMAState = rowDMAState;
		nextRowDMARdCol = rowDMARdCol;
		case (rowDMAState)
			ROWDMA_IDLE: begin
				if (inputCmdMoveRows) begin
					nextRowDMAState = ROWDMA_ROWMOVE;
					nextRowDMARdCol = 7'h0;
				end else if (inputCmdInsertChar) begin
					nextRowDMAState = ROWDMA_INSCHAR_READ;
					nextRowDMARdCol = MAXCOL_M_2;
				end else if (bkspNotAtColZero | inputCmdCMD_DEL | inputCmdEraseSOL) begin
					nextRowDMAState = ROWDMA_READ;
					//the DMA read address -- this is always 1 more than DMA write address except in erase to SOL case
					nextRowDMARdCol = (inputCmdCMD_DEL)? (currentCursorCol + 1'b1):
										currentCursorCol;
				end
			end
			ROWDMA_ROWMOVE: begin

			end
			ROWDMA_INSCHAR_READ: begin
				nextRowDMAState = ROWDMA_INSCHAR_WRITE;
			end
			ROWDMA_INSCHAR_WRITE: begin
				nextRowDMAState = (rowDMARdColAtCursor)? ROWDMA_INSCHAR_DONE: ROWDMA_INSCHAR_READ;
				//nextRowDMARdCol = (rowDMARdColAtCursor)? insertModeCol: (rowDMARdCol - 1'b1); //FIXME
				nextRowDMARdCol = (rowDMARdColAtCursor)? currentCursorCol: (rowDMARdCol - 1'b1);
			end
			ROWDMA_INSCHAR_DONE: begin
				nextRowDMAState = ROWDMA_IDLE;
			end
			ROWDMA_READ: begin
				//read from column rowDMARdCol
				nextRowDMAState = ROWDMA_WRITE;
			end
			ROWDMA_WRITE: begin
				//write to column (rowDMARdCol - 1) with the data read in state ROWDMA_READ
				nextRowDMAState = (rowDMARdColMaxxed)? ROWDMA_LASTWRITE: ROWDMA_READ;
				//if read to column 79 has happened in state ROWDMA_READ, then increment read column to 80
				//but exit to state ROWDMA_LASTWRITE
				//reuse rowDMARdCol counter for rowDMAWrCol, so capture the current rowDMAWrCol value
				nextRowDMARdCol = (rowDMARdColMaxxed)? (rowDMAWrCol + 1'b1): (rowDMARdCol + 1'b1);
			end
			ROWDMA_LASTWRITE: begin
				//write to column (rowDMARdCol - 1), which now equals 79, but write data is null char
				//for erase to SOL, stay in this state
				nextRowDMAState = (rowDMAWrColMaxxed)? ROWDMA_IDLE: ROWDMA_LASTWRITE;
				//nextRowDMARdCol = (rowDMAWrColMaxxed)? 7'h0: (rowDMARdCol + 1'b1);
				nextRowDMARdCol = (rowDMARdCol + 1'b1);
			end
			default: begin
				nextRowDMAState = ROWDMA_IDLE;
				nextRowDMARdCol = 7'h0;
			end
		endcase
	end

	//wire [6:0] nextInsertModeCol = (rowDMAInsCharStart)? currentCursorCol: insertModeCol;
	always @(posedge clk) begin
		if (~resetn) begin
			rowDMAState <= `DELAY 2'h0;
			rowDMARdCol <= `DELAY 7'h0;
			eraseToSOLInProgress <= `DELAY 1'b0;
			//insertModeCol <= `DELAY 7'h0;
		end else begin
			rowDMAState <= `DELAY nextRowDMAState;
			rowDMARdCol <= `DELAY nextRowDMARdCol;
			eraseToSOLInProgress <= `DELAY nextEraseToSOLInProgress;
			//insertModeCol <= `DELAY nextInsertModeCol;
		end
	end

	//NOTE: only the scrollUp command needs to be delayed
	//because it depends upon a cursor command of data < 16
	//that needs to complete first, otherwise wrong row will
	//be erased
	charBufferInit ucharbufinit (
		.clk (clk),
		.resetn (userResetn),
		.enable (userResetn & inputKeyA & inputKeyB 
					& ~inputCmdCls 
					& ~inputCmdScrollUp_r0 
					& ~inputCmdEraseEOL
					& ~inputCmdEraseLine),
		.sequential (~inputKeyB),
		.initRowOnly (inputCmdScrollUp_r0
						| inputCmdEraseEOL 
						| inputCmdEraseLine),
		.rowInitRow (currentScrolledRow),
		.rowInitCol ((inputCmdEraseEOL)? currentCursorCol: 7'h0),
		.initWrEn (charBufferInitInProgress),
		.initAddress (charBufferInitAddr),
		.initData (charBufferInitData));

	assign debugUARTTxData = {1'b0, inputCmdMemWrData[7:1]};
	assign debugUARTTxDataValid = inputCmdValid_r0;
	always @(posedge clk) begin
		if (~resetn) begin
			inputCmdScrollUp_r0 <= `DELAY 5'h0;
			insertMode <= `DELAY 1'b0;
			pendingSetCol <= `DELAY 1'b0; //1 means next input byte will set the column
			pendingSetRow <= `DELAY 1'b0; //1 means next input byte will set the column
			cursorInvisible <= `DELAY 1'b0; //1 means cursor is invisible
			currentCursorCol <= `DELAY 7'h0;
			currentCursorRow <= `DELAY 5'h0;
			inputCmdValid_r0 <= `DELAY 1'b0;
			inputCmdMemWrEn <= `DELAY 1'b0;
			inputCmdMemWrData <= `DELAY 8'h0;
			scrollRow <= `DELAY 5'h0;
		end else begin
			inputCmdScrollUp_r0 <= `DELAY inputCmdScrollUp;
			pendingSetCol <= `DELAY (inputCmdSetCol)? 1'b1: pendingSetCol; 
			pendingSetRow <= `DELAY (inputCmdSetRow)? 1'b1: pendingSetRow; 
			//1 means cursor is invisible
			//during backspace or delete operation, make cursor invisible
			cursorInvisible <= `DELAY (inputCmdCursorToggle)? ~cursorInvisible: cursorInvisible; 
			insertMode <= `DELAY (inputCmdInsertToggle)? ~insertMode: insertMode;
			inputCmdValid_r0 <= `DELAY inputCmdValid;
			inputCmdMemWrEn <= `DELAY inputCmdValid & |inputCmdData[6:5] & ~pendingSetCol & ~pendingSetRow;
			inputCmdMemWrData <= `DELAY inputCmdData;
			//character at current cursor is stored at (MAXROW_M_1 + 1) * currentCursorCol + currentCursorRow
			if (pendingSetRow & inputCmdValid_r0) begin
				currentCursorRow <= `DELAY inputCmdMemWrData[4:0];
				pendingSetRow <= `DELAY 1'b0;
			end else if (pendingSetCol & inputCmdValid_r0) begin
				currentCursorCol <= `DELAY inputCmdMemWrData[6:0];
				pendingSetCol <= `DELAY 1'b0;
			end else if (eraseToSOLInProgress & rowDMAWrColMaxxed & rowDMAWrEnLast) begin
				currentCursorCol <= `DELAY 7'h0;
			end else if (~inputKeyB | ~inputKeyA) begin
				//events not directly from a typed character
				//key presses will initialize cursor
				currentCursorCol	<= `DELAY 7'h0;
				currentCursorRow	<= `DELAY 5'h0;
				scrollRow			<= `DELAY 5'h0;
			end else if (inputCmdValid_r0 | rowDMAInsDone) begin
				if (inputCmdMemWrData[7:4] == 4'h0) begin
					case (inputCmdMemWrData[3:0])
						4'd`CMD_SCROLL_UP: begin
							scrollRow <= `DELAY (scrollRow - 1'b1);
						end
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
							currentCursorRow <= `DELAY 0;
						end
						4'd`CMD_PGDN: begin
							currentCursorRow <= `DELAY MAXROW_M_1;
						end
						4'd`CMD_TAB: begin
							if (currentCursorCol <= MAXCOL_M_TABLEN_1) begin
								currentCursorCol <= `DELAY currentCursorCol + TABLEN;
							end else begin
								currentCursorCol <= `DELAY MAXCOL_M_1;
							end
						end
						4'd`CMD_UP: begin
							if (currentCursorRow != 5'h0) begin
								currentCursorRow <= `DELAY (currentCursorRow - 1'b1);
							end
						end
						4'd`CMD_LEFT, 8'd`CMD_BKSP: begin
							if (currentCursorCol != 7'h0) begin
								currentCursorCol <= `DELAY (currentCursorCol - 1'b1);
							end
						end
						4'd`CMD_RIGHT: begin
							if (currentCursorCol != MAXCOL_M_1) begin
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
				end else if (isPrintableChar & ~insertModeNotAtMaxCol | rowDMAInsDone) begin
					//printable character > ASCII 31 < 128
					//in insert mode, this code is used only when cursor column is max
					if (currentCursorCol == MAXCOL_M_1) begin
						currentCursorCol <= `DELAY 7'h0;
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
			end //if inputCmdValid_r0
		end //else ~resetn
	end //always

	assign debug0 = ~insertMode; //green
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

	//There is only one counter for rowDMARdCol, once read column has reached MAXCOL_M_1,
	//reuse the counter for write column.
	//currentCursorCol does not change while eraseToSOL operation is in progress
	assign currentScrolledRow = currentCursorRow + scrollRow;
	assign charBufferWrAddr =	(charBufferInitInProgress)?	charBufferInitAddr[11:0]:
								(rowDMAWrEn | rowDMAWrEnLast | rowDMAInsWrEn)? {rowDMAWrCol[6:0], currentScrolledRow[4:0]}:
								{currentCursorCol[6:0], currentScrolledRow[4:0]};

	assign charBufferWrData =	(charBufferInitInProgress)?	charBufferInitData[6:0]:
								(rowDMAWrEn | rowDMAInsWrEn)? {charBufferRdDataColor, charBufferRdData[6:0]}:
								(rowDMAInsDone)? inputCmdMemWrData: //still holding last input char
								//on the last column for bksp/del, write with null
								(rowDMAWrEnLast)? {charBufferRdDataColor, 7'd0}:
								{charBufferRdDataColor, inputCmdMemWrData[6:0]};

	//backspace writes a space character one clock after the cursor is moved left
	//delete just writes a space character without moving the cursor
	assign charBufferWrEn = charBufferInitInProgress | (inputCmdMemWrEn & ~insertMode)
							| rowDMAWrEn | rowDMAWrEnLast | rowDMAInsWrEn 
							| rowDMAInsDone;

	wire [4:0] currentScrolledScanRow = currentScanCharRow + scrollRow;
	wire [6:0] charBufferRdCol = (rowDMARdEn | rowDMAInsRdEn)? rowDMARdCol[6:0]: currentScanCharCol[6:0];
	wire [4:0] charBufferRdRow = (rowDMARdEn | rowDMAInsRdEn)? currentScrolledRow[4:0]: currentScrolledScanRow[4:0];
	assign charBufferRdAddr = {charBufferRdCol[6:0], charBufferRdRow[4:0]};
	assign charBufferRdEn = ((charWidthCounter == 3'h0) & inDisplayArea_r0 & rowDMAIdle) 
								| rowDMARdEn | rowDMAInsRdEn;

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
		.inDisplayArea(inDisplayArea));

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
							4'd12, 4'd13: pixel <= `DELAY scanningCurrentCursorCell_r2 & cursorBlink & ~cursorInvisible & rowDMAIdle;
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
							4'd12, 4'd13: pixel <= `DELAY scanningCurrentCursorCell_r2 & cursorBlink & ~cursorInvisible & rowDMAIdle;
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
