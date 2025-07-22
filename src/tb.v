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
	wire pixel, hsync, vsync;
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
		#10001 keyA = 1'b0;
		#105 keyA = 1'b1;
		#10001 keyB = 1'b0;
		#75 keyB = 1'b1;
	end

	reg [7:0] TXCOUNT;
	//initial TXCOUNT = 14;
	initial TXCOUNT = 2;
	wire [7:0] txString [0:13];
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
	assign txString[0] = "a";
	assign txString[1] = 8;

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

	always @(posedge clk) begin
		//$fwrite(f, "%0d ns: %b %b 000 %b 00\n", $time, hsync, vsync, {3{pixel}});
		if (txStringPtr == TXCOUNT && tbTxState == 2'h0) begin
			#600000
			$finish;
		end
	end

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
		end else if ($time > 40000) begin
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

	reg KBD_CLK;
	reg KBD_DATA;

	initial KBD_CLK = 0;
	initial KBD_DATA = 0;
	always @(KBD_CLK) begin
		#200 KBD_CLK <= ~KBD_CLK;
	end

	vgaminikbd uvgaminikbd(
		.keyA (keyA),
		.keyB (keyB),
		.resetn (resetn),
		.UART_RX0 (tbuartTX),
		.UART_TX0 (),
		.KBD_CLK (KBD_CLK),
		.KBD_DATA (KBD_DATA),
		.debug0 (),
		.debug1 (),
		.debug2 (),
		.clkin (clk),
		.pixel (pixel),
		.hsync (hsync),
		.vsync (vsync));

endmodule
