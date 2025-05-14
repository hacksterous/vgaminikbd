//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:	21:05:41 04/03/2024 
// Design Name: 
// Module Name:	hvsync 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: https://ktln2.org/2018/01/23/implementing-vga-in-verilog/
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
//https://madlittlemods.github.io/vga-simulator
//https://github.com/ARC-Lab-UF/vga-simulator
`timescale 1ns/1ps
`include "vgaminikbd.vh"

module hvsync(
	input clk,
	input resetn,
	output debugPixel,
	output HSync,
	output VSync,
	output wire inDisplayArea
  );

	wire vgaHS, vgaVS;
	reg [9:0] counterX;//0-800
	reg [9:0] counterY;//0-525

/*
https://martin.hinner.info/vga/640x480_60.html

http://tinyvga.com/vga-timing/640x480@60Hz
General timing
Screen refresh rate	60 Hz
Vertical refresh	31.46875 kHz
Pixel freq.	25.175 MHz

Horizontal timing (line)
Polarity of horizontal sync pulse is negative.
Scanline part	Pixels	Time [µs]
Visible area	640	25.422045680238
Front porch	16	0.63555114200596
Sync pulse	96	3.8133068520357
Back porch	48	1.9066534260179
Whole line	800	31.777557100298

Vertical timing (frame)
Polarity of vertical sync pulse is negative.
Frame part	Lines	Time [ms]
Visible area	480	15.253227408143
Front porch	10	0.31777557100298
Sync pulse	2	0.063555114200596
Back porch	33	1.0486593843098
Whole frame	525	16.683217477656
*/

	`define H_VISIBLE 640
	`define H_FRONT_PORCH 16
	`define H_SYNC_PULSE 96
	`define H_BACK_PORCH 48
	`define H_WHOLE_LINE 800

	`define V_VISIBLE 480
	`define V_FRONT_PORCH 10
	`define V_SYNC_PULSE 2
	`define V_BACK_PORCH 33
	`define V_WHOLE_FRAME 525

	wire counterXMaxxed = (counterX == `H_WHOLE_LINE); // H_FRONT_PORCH + H_BACK_PORCH + H_SYNC_PULSE + H_VISIBLE
	wire counterYMaxxed = (counterY == `V_WHOLE_FRAME); // V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH + V_VISIBLE

	always @(posedge clk) begin
		if (~resetn) begin
			counterX <= `DELAY 10'h0;
		end else if (counterXMaxxed)
			counterX <= `DELAY 10'h0;
		else
			counterX <= `DELAY counterX + 1'b1;
	end

	always @(posedge clk) begin
		if (~resetn) begin
			counterY <= `DELAY 10'h0;
		end else if (counterXMaxxed) begin
			if(counterYMaxxed)
				counterY <= `DELAY 10'h0;
			else
				counterY <= `DELAY counterY + 1'b1;
		end
	end

	// active for H_SYNC_PULSE clocks
	assign vgaHS =	(counterX >= (`H_VISIBLE + `H_FRONT_PORCH) && (counterX < (`H_VISIBLE + `H_FRONT_PORCH + `H_SYNC_PULSE)));

	// active for V_SYNC_PULSE clocks
	assign vgaVS =	(counterY >= (`V_VISIBLE + `V_FRONT_PORCH) && (counterY < (`V_VISIBLE + `V_FRONT_PORCH + `V_SYNC_PULSE)));

    assign inDisplayArea = (counterX < `H_VISIBLE) && (counterY < `V_VISIBLE);

	assign HSync = ~vgaHS;
	assign VSync = ~vgaVS;

	assign debugPixel = counterX[6];

endmodule
