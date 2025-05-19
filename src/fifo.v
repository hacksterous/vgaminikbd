//////////////////////////////////////////////////////////////////////////////////
// (C) Anirban Banerjee 2024
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module fifo (
	clk,
	resetn,
	push,
	notfull,
	inData,
	notempty,
	pop,
	outData);

	parameter WIDTH = 8;
	parameter DEPTH = 8;
	localparam WIDTH_M_1 = WIDTH - 1;
	localparam LOG2DEPTH = 3;
	localparam LOG2DEPTH_M_1 = LOG2DEPTH - 1;
	localparam LOG2DEPTH_P_1 = LOG2DEPTH + 1;
	localparam DEPTH_M_1 = DEPTH - 1;
	 
	input			clk;		// Clock
	input			resetn;		// Reset
	input			push;		// Input Source Ready
	output			notfull;	// Input Destination Ready
	input [WIDTH_M_1:0]	inData;	// Input Data
	
	output			notempty;	// Output Source Ready
	input			pop;		// Output Destination Ready
	output [WIDTH_M_1:0]	outData;	// Output Data

	wire		fifo_wen; // Write Enable
	wire		fifo_ren; // Read Enable
	wire		fifo_notempty;
	wire		fifo_full;
	reg [LOG2DEPTH:0]	cnt_c;
	reg [LOG2DEPTH:0]	cnt;
	
	reg [LOG2DEPTH_M_1:0]	fifo_wptr;
	reg [LOG2DEPTH_M_1:0]	fifo_rptr;
	wire [LOG2DEPTH_M_1:0]	fifo_wptr_c;
	wire [LOG2DEPTH_M_1:0]	nxt_fifo_rptr;
	wire [LOG2DEPTH_M_1:0]	fifo_rptr_inc;
	
	reg [WIDTH_M_1:0]outData;
	wire [WIDTH_M_1:0]sramRdata;
	reg	notfull;
	reg	notempty;

	assign	fifo_wen = push & notfull;
	assign	fifo_ren = notempty & pop;
	
	always @(posedge clk) begin
		outData <= `DELAY sramRdata;
	end

	assign fifo_notempty	= (cnt_c != 4'h0);//(cnt_c != {LOG2DEPTH_P_1{1'b0}});
	assign fifo_full		= (cnt_c == 4'b1000);//(cnt_c == {1'b1, {LOG2DEPTH{1'b0}}});

	assign fifo_wptr_c	 = (fifo_wptr + fifo_wen);
	assign fifo_rptr_inc = (fifo_rptr + 1'b1);

	assign nxt_fifo_rptr = fifo_ren? fifo_rptr_inc : fifo_rptr;

	always @(*) begin
	    case({fifo_wen, fifo_ren}) 
	   	 2'b10	 : cnt_c = cnt + {{LOG2DEPTH{1'b0}}, 1'b1};
	   	 2'b01	 : cnt_c = cnt - {{LOG2DEPTH{1'b0}}, 1'b1};
	   	 default : cnt_c = cnt;
	    endcase
	end

	always @(posedge clk) begin
		if (~resetn) begin
			fifo_wptr	<= `DELAY {LOG2DEPTH{1'b0}};
			fifo_rptr	<= `DELAY {LOG2DEPTH{1'b0}};
			cnt			<= `DELAY {LOG2DEPTH_P_1{1'b0}};
			notfull		<= `DELAY 1'b0;
			notempty	<= `DELAY 1'b0;
	    end else begin
			fifo_wptr	<= `DELAY fifo_wptr_c;
			fifo_rptr	<= `DELAY nxt_fifo_rptr;
			cnt			<= `DELAY cnt_c;
			notfull		<= `DELAY ~fifo_full;
			notempty	<= `DELAY fifo_notempty;
	    end
	end

	//flopram
	reg [WIDTH_M_1:0] array [0:DEPTH_M_1];
	wire [WIDTH_M_1:0] rdata;

	always @(posedge clk) begin
		if (fifo_wen) array[fifo_wptr] <= `DELAY inData;
	end

	assign sramRdata = (fifo_ren)? array[fifo_rptr]: {WIDTH{1'b0}};

endmodule
