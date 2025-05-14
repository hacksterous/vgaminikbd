//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Anirban Banerjee
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
// Create Date:	 20:56:29 04/03/2024 
// Design Name: 
// Module Name:	 tb 
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

`timescale 1ns/1ps
module tb ();

	reg clk, resetn;
	reg debug;
	integer f;
	wire tbuartTX;
	wire pixel, hsync, vsync, heartbeat;
	reg keyA, keyB;
	initial resetn = 1'b0;
	initial #7 resetn = 1'b1;
	initial clk = 1'b0;
	initial debug = 1'b0;
	
	always @(clk) begin
		#2 clk <= ~clk;
	end

	initial keyA = 1'b1;
	initial keyB = 1'b1;
	
	initial	begin
		#10000001 keyA = 1'b0;
		#105 keyA = 1'b1;
		#10001 keyB = 1'b0;
		#75 keyB = 1'b1;
	end

	reg [7:0] TXCOUNT;
	initial TXCOUNT = 33;
	wire [7:0] txString [0:33];
	//assign txString[0]  = "h";
	//assign txString[1]  = "e";
	//assign txString[2]  = "l";
	//assign txString[3]  = "l";
	//assign txString[4]  = "o";
	//assign txString[5]  = ",";
	//assign txString[6]  = " ";
	//assign txString[7]  = "w";
	//assign txString[8]  = "o";
	//assign txString[9]  = "r";
	//assign txString[10]  = "l";
	//assign txString[11] = "d";
	//assign txString[12] = "!";
	//assign txString[13] = " ";

	assign txString[0]		= 10;
	assign txString[1]		= 10;
	assign txString[2]		= 10;
	assign txString[3]		= 10;
	assign txString[4]		= 10;
	assign txString[5]		= 10;
	assign txString[6]		= 10;
	assign txString[7]		= 10;
	assign txString[8]		= 10;
	assign txString[9]		= 10;
	assign txString[10]		= 10;
	assign txString[11]		= 10;
	assign txString[12]		= 10;
	assign txString[13]		= 10;
	assign txString[14]		= 10;
	assign txString[15]		= 10;
	assign txString[16]		= 10;
	assign txString[17]		= 10;
	assign txString[18]		= 10;
	assign txString[19]		= 10;
	assign txString[20]		= 10;
	assign txString[21]		= 10;
	assign txString[22]		= 10;
	assign txString[23]		= 10;
	assign txString[24]		= 10;
	assign txString[25]		= 10;
	assign txString[26]		= 10;
	assign txString[27]		= 10;
	assign txString[28]		= 10;
	assign txString[29]		= 10;
	assign txString[30]		= 10;
	assign txString[31]		= 10;
	assign txString[32]		= 10;
	assign txString[33]		= 10;
	reg [1:0] tbTxState;

	initial begin
		//f = $fopen ("vgasim.txt", "w");
		#6000000
		$finish;
		//$fclose(f);
	end

	initial begin
		$dumpfile ("vgaminikbd.vcd");
		$dumpvars;
	end

	//always @(posedge clk) begin
	//	$fwrite(f, "%0d ns: %b %b 000 %b 00\n", $time, hsync, vsync, {3{pixel}});
	//	//if (txStringPtr == TXCOUNT && tbTxState == 2'h0) begin
	//	//	$finish;
	//	//end
	//end

	wire txBusy;
	wire [7:0] txData;
	wire txValid;
	reg [7:0] txStringPtr;
	wire [7:0] nextTxStringPtr;
	initial txStringPtr = 8'h0;

	always @(posedge clk) begin
		//$monitor ("Time: %d -- txData: %h", $time, txData);
		if (~resetn) begin
			tbTxState <= #1 2'h0;
		end else if ($time > 400000) begin
			if (tbTxState == 2'h0) begin
				if (~txBusy & (txStringPtr <= TXCOUNT)) tbTxState <= #1 2'h1;
			end else if (tbTxState == 2'h1) begin
				if (~txBusy) tbTxState <= #1 2'h2;
			end else if (tbTxState == 2'h2) begin
				if (~txBusy) tbTxState <= #1 2'h0;
			end
			txStringPtr <= #1 nextTxStringPtr;
		end
	end

	assign txValid = (tbTxState == 2'h1) & ~txBusy;

	assign nextTxStringPtr = (txValid)? (txStringPtr + 1'b1): txStringPtr;

	assign txData = txString[txStringPtr];

	//this generates serial input data for vgamini's RX0
	uart tbuart (
		.ECHO (1'b0),
		.clk (clk),
		.rstn (resetn),
		.UART_TX (tbuartTX),
		.UART_RX (1'b1),
		.clockDividerValue(20'd131), //166 for 32MHz, 131 at 25MHz
		.dataOutRx (),
		.dataOutRxAvailable (),
		.dataInTx (txData),
		.dataInTxValid (txValid),
		.dataInTxBusy (txBusy),
		.rxError (),
		.rxBitTick(),
		.txBitTick());

	vgaminikbd uvgaminikbd(
		.keyA (keyA),
		.keyB (keyB),
		.resetn (resetn),
		.UART_RX0 (tbuartTX),
		.UART_TX0 (),
		.debug (debug),
		.debug0 (heartbeat),
		.debug1 (),
		.debug2 (),
		.clkin (clk),
		.pixel (pixel),
		.hsync (hsync),
		.vsync (vsync));

endmodule
