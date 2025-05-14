//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
// This is the top level design module
// Supports CPU, keyboard but no console UART and outputs VGA
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module vgaminikbd(
	input keyA,
	input keyB,
	`ifdef SIM_ONLY
	input resetn,
	`endif
	input KBD_CLK,
	input KBD_DATA,

	input UART_RX0, //RX from CPU to VGA
	output UART_TX0, //TX to CPU from keyboard
	input clkin, //27MHz clock from FPGA board xtal
	`ifdef SIM_ONLY
	input debug,
	`endif
	output wire debug0,
	output wire debug1,
	output wire debug2,
	output wire pixel,
	output wire hsync,
	output wire vsync);

	wire clk;
	wire [7:0] rxDataOut;
	wire rxDataOutValid;

	`ifndef SIM_ONLY
	//Gowin/Xilinx global reset controls main reset
	wire resetn = 1'b1;
	wire debug = 1'b0;
	`endif

	wire keyAOut, keyBOut;

	keySynchronizer ukdA (
		.clk (clk),
		.resetn (resetn),
		.keyIn (keyA),
		.keyOut (keyAOut));

	keySynchronizer ukdB (
		.clk (clk),
		.resetn (resetn),
		.keyIn (keyB),
		.keyOut (keyBOut));

	wire [7:0] kbdAsciiData;
	wire kbdAsciiDataValid;

	kbd ukbd (
		.clk (clk),
		.resetn (resetn),
		.KBD_CLK (KBD_CLK),
		.KBD_DATA (KBD_DATA),
		.kbdData (kbdAsciiData),
		.kbdDataValid (kbdAsciiDataValid));

/*
The formulas of rPLL output calculation are as follows:
1. fCLKOUT = (fCLKIN*FDIV)/IDIV
2. fCLKOUTD = fCLKOUT/SDIV
3. fVCO = fCLKOUT*ODIV

			fCLKIN	= 27MHz
(Programmed value is 1 less than values below.)
Here:		
			FDIV	= 28
			IDIV	= 3
			fCLKOUT = 252MHz
			SDIV	= 10
			fCLKOUTD= 25.2MHz
			ODIV	= 2
			fVCO	= 504MHz

Also try:	FDIV	= 7
			IDIV	= 8
			fCLKOUT = 24MHz
			SDIV	= 2
			fCLKOUTD= x
			ODIV	= 32
			fVCO	= 768MHz


Note!
 * fCLKIN: The frequency of input clock CLKIN;
 * fCLKOUT: The frequency of output clock CLKOUT;
 * fCLKOUTD: The frequency of output clock CLKOUTD, and CLKOUTD is the clock
"CLKOUT" after division.
 * fVCO: VCO oscillation frequency.
*/

	//25.2MHz bit clock -- closer to standard, but some monitors (Samsung SyncMaster 2009)
	//have a top blank area that can't be adjusted
	//clockGen uclockGen(
	//	.clkin (clkin),	//27MHz on Tang Nano 1k
	//	.clkoutd (clk), //25.2MHz (standard is 25.175MHz)
	//	.clkout (),		//252MHz
	//	.lock ());

	//24MHz bit clock, works OK with Samsung SyncMaster
	clockGenALT uclockGen(
		.clkin (clkin),	//27MHz on Tang Nano 1k
		`ifdef SIM_ONLY
		.clkoutd(),
		`endif
		.clkout (clk),	//24MHz
		.lock ());

	wire dataArbError;
	wire [7:0] dataArbDout;
	wire dataArbDoutValid;
	wire oneSecPulse;

	datamux2in uarb (	
		.clk (clk),
		.resetn (resetn),
		.d0 (rxDataOut),
		.d0v (rxDataOutValid),
		.d1 (kbdAsciiData),
		.d1v (kbdAsciiDataValid),
		.error (dataArbError),
		.od (dataArbDout),
		.odv (dataArbDoutValid));

	assign UART_TX0 = 1'b1; //FIXME
	wire debug_UART_TX0;
	//assign debug2 = debug_UART_TX0;

	uart uuart0 (
		.ECHO (1'b0),
		.clk (clk),
		.rstn (resetn),
		.UART_TX (debug_UART_TX0),//UART_TX0), //from keyboard to CPU FIXME
		.UART_RX (UART_RX0), //from CPU to VGA
		//1667 = 19200 baud w/ 32MHz, 1313 w/ 25.2MHz
		`ifdef SIM_ONLY
		.clockDividerValue(20'd131),
		`else
		.clockDividerValue(20'd1313),
		`endif
		.dataOutRx (rxDataOut), //CPU Rx parallel data to mux
		.dataOutRxAvailable (rxDataOutValid),
		.dataInTx (8'h0), //kbdAsciiData), //keyboard parallel data to Tx
		.dataInTxValid (1'b0),//kbdAsciiDataValid), FIXME
		.dataInTxBusy (debug2), //FIXME
		.rxError (),
		.rxBitTick(),
		.txBitTick());

	vga uvga(
		.resetn (resetn),
		//FIXME
		//.inputCmdData (dataArbDout),
		//.inputCmdValid (dataArbDoutValid),
		.inputCmdData (rxDataOut),
		.inputCmdValid (rxDataOutValid),
		.inputKeyA (keyAOut),
		.inputKeyB (keyBOut),
		.debug (debug),
		.clk (clk),
		.debug0 (debug0), //green
		.debug1 (debug1), //red
		.debug2 (),		  //blue
		.pixel (pixel),
		.hsync (hsync),
		.vsync (vsync));

endmodule
