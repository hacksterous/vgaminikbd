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
	output wire debug0, //green
	output wire debug1, //red
	output wire debug2, //blue
	output wire pixel,
	output wire hsync,
	output wire vsync);

	wire clk;
	wire [7:0] uartRxDataOut;
	wire uartRxDataOutValid;

	`ifndef SIM_ONLY
	//Gowin/Xilinx global reset controls main reset
	wire resetn = 1'b1;
	`endif

	wire userResetn;
	wire keyAOut, keyBOut;

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

	assign keyAOut = keyA; //static very low freq signal
	assign keyBOut = keyB; //static very low freq signal

	wire [7:0] kbdAsciiData;
	wire kbdAsciiDataValid;

	kbd ukbd (
		.clk (clk),
		.resetn (userResetn),
		.KBD_CLK (KBD_CLK),
		.KBD_DATA (KBD_DATA),
		.kbdData (kbdAsciiData),
		.kbdDataValid (kbdAsciiDataValid));

	wire dataArbError;
	wire [7:0] dataArbDout;
	wire dataArbDoutValid;
	wire oneSecPulse;

	wire ansiOutDataValid;
	wire [7:0] ansiOutData;

	wire dataInTxBusy;

	wire keyTimeout;

	wire [7:0] arbDataOut;
	wire arbDataOutValid;

	uart uuart0 (
		.ECHO (1'b0),
		.clk (clk),
		.rstn (userResetn),
		.UART_TX (UART_TX0), //from keyboard to CPU
		.UART_RX (UART_RX0), //from CPU to VGA
		//1667 = 19200 baud w/ 32MHz, 1313 w/ 25.2MHz
		`ifdef SIM_ONLY
		.clockDividerValue(20'd131),
		`else
		.clockDividerValue(20'd1313),
		`endif
		.dataOutRx (uartRxDataOut),	//CPU Rx parallel data to ANSI decode module
		.dataOutRxAvailable (uartRxDataOutValid),
		.dataInTx (ansiOutData),	
		.dataInTxValid (ansiOutDataValid),
		.dataInTxBusy (dataInTxBusy),
		.rxError (),
		.rxBitTick(),
		.txBitTick());

	ansiEscape uansiesc (
		.clk (clk),
		.resetn (userResetn),
		.keyTimeout (keyTimeout),
		.ansiEscDebug(debug0),
		.rxDataIn (arbDataOut),
		.rxDataInValid (arbDataOutValid),
		.rxANSIDataOut (ansiOutData),
		.rxANSIDataOutValid (ansiOutDataValid));

	arb2x1 uarb(
		.clk (clk),
		.resetn (userResetn),
		.d0 (kbdAsciiData),
		.d0v (kbdAsciiDataValid),
		.d1 (uartRxDataOut),
		.d1v (uartRxDataOutValid),
		.od (arbDataOut),
		.odv (arbDataOutValid));

	vga uvga(
		.resetn (resetn),
		.inputCmdData (ansiOutData),
		.inputCmdValid (ansiOutDataValid),
		.inputKeyA (keyAOut),
		.inputKeyB (keyBOut),
		.debugUARTTxData (),
		.debugUARTTxDataValid (),
		.debug (1'b0),
		.clk (clk),
		.keyTimeout (keyTimeout),
		.userResetn (userResetn),
		.debug0 (), //green
		.debug1 (debug1), //red
		.debug2 (debug2), //blue
		.pixel (pixel),
		.hsync (hsync),
		.vsync (vsync));

endmodule
