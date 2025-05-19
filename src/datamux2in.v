//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module datamux2in (
	debug0,
	debug1,
	debug2,
	clk,
	resetn,
	d0,
	d0v,
	d1,
	d1v,
	error,
	od,
	odv);

	output debug0;
	output debug1;
	output debug2;
	input clk;
	input resetn;
	input [7:0] d0;
	input d0v;
	input [7:0] d1;
	input d1v;
	output error;
	output [7:0] od;
	output odv;

	assign debug0 = ~nedfifo0;//data in UART FIFO
	assign debug1 = ~nedfifo1;//data in KBD FIFO
	assign debug2 = ~arbFifoNotEmpty;//data in output FIFO

	wire nedfifo0;
	reg popdfifo0;
	wire nfdfifo0;
	wire [7:0] outdfifo0;
	fifo #(.WIDTH(8), .DEPTH(4)) dfifo0 (
		.clk (clk),
		.resetn (resetn),
		.push (d0v),
		.notfull (nfdfifo0),
		.inData (d0),
		.notempty (nedfifo0),
		.pop (popdfifo0),
		.outData (outdfifo0));

	wire nedfifo1;
	reg popdfifo1;
	wire nfdfifo1;
	wire [7:0] outdfifo1;
	fifo #(.WIDTH(8), .DEPTH(4)) dfifo1 (
		.clk (clk),
		.resetn (resetn),
		.push (d1v),
		.notfull (nfdfifo1),
		.inData (d1),
		.notempty (nedfifo1),
		.pop (popdfifo1),
		.outData (outdfifo1));

	wire arbFifoError;
	reg arbFifoPush0;
	reg arbFifoPush1;
	wire push0Error = d0v & ~nfdfifo0;
	wire push1Error = d1v & ~nfdfifo1;
	wire pushError = push0Error | push1Error;
	wire popError = ~nedfifo0 & popdfifo0 | ~nedfifo1 & popdfifo1;
	assign error = pushError | popError | arbFifoError;

	reg [1:0] arbCounter; //Johnson counter
	wire arbCounterEn = nedfifo0 | nedfifo1;
	wire [1:0] nefifo = {nedfifo1, nedfifo0};
	wire [1:0] lastPopFifo;
	always @(posedge clk) begin
		if (~resetn) begin
			arbCounter <= `DELAY 2'b01;
		end else begin
			if (arbCounterEn) 
				arbCounter <= `DELAY {arbCounter[0], arbCounter[1]};
			else
				arbCounter <= `DELAY 2'b01;
		end
	end

	//same as delayed version of popdfifo1/0
	assign lastPopFifo = {arbFifoPush1, arbFifoPush0};

	always @(*) begin
		casez ({nefifo[1:0], lastPopFifo[1:0], arbCounter[1:0]})
			//arbitration required
			{2'b?1, 2'b??, 2'b01}: {popdfifo1, popdfifo0} = 2'b01;
			{2'b1?, 2'b??, 2'b10}: {popdfifo1, popdfifo0} = 2'b10;
			{2'b11, 2'b01, 2'b??}: {popdfifo1, popdfifo0} = 2'b10;
			{2'b11, 2'b10, 2'b??}: {popdfifo1, popdfifo0} = 2'b01;
			//any one pending
			{2'b01, 2'b0?, 2'b??}: {popdfifo1, popdfifo0} = 2'b01;
			{2'b10, 2'b?0, 2'b??}: {popdfifo1, popdfifo0} = 2'b10;
						  default: {popdfifo1, popdfifo0} = 2'b00;
		endcase
	end

	wire arbFifoPush;
	wire arbFifoNotFull;
	reg odv;
	wire arbFifoNotEmpty;
	always @(posedge clk) begin
		if (~resetn) begin
			arbFifoPush0	<= `DELAY 1'b0;
			arbFifoPush1	<= `DELAY 1'b0;
			odv				<= `DELAY 1'b0;
		end else begin
			arbFifoPush0	<= `DELAY popdfifo0;
			arbFifoPush1	<= `DELAY popdfifo1;
			odv				<= `DELAY arbFifoNotEmpty;
		end
	end

	wire [7:0] arbFifoInData = (arbFifoPush1)? outdfifo1:
							(arbFifoPush0)? outdfifo0:
							8'h0;

	assign arbFifoPush = arbFifoPush0 | arbFifoPush1;
	assign arbFifoError = arbFifoPush & ~arbFifoNotFull;

	fifo #(.WIDTH(8), .DEPTH(2)) ArbFifo (
		.clk (clk),
		.resetn (resetn),
		.push (arbFifoPush),
		.notfull (arbFifoNotFull),
		.inData (arbFifoInData),
		.notempty (arbFifoNotEmpty),
		.pop (arbFifoNotEmpty),
		.outData (od));

endmodule
