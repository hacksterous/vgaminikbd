/*****************************************************************************
 *																		   *
 * Module:	   ps2receiver									   *
 * Description:															  *
 *	  This module accepts incoming data from a PS2 core.				   *
 *https://www.eecg.utoronto.ca/~jayar/ece241_08F/AudioVideoCores/ps2/ps2.html*
 *																		   *
 *****************************************************************************/
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module ps2receiver (
	clk,
	reset,
	PS2_CLK,
 	PS2_DAT,
	kbdcode,
	kbdcodeValid);

	input	clk;
	input	reset;
	input	PS2_CLK;
	input	PS2_DAT;

	output reg	[7:0]	kbdcode;
	
	output reg	kbdcodeValid;
	
	localparam	PS2_STATE_0_IDLE		= 3'h0,
				PS2_STATE_1_DATA_IN		= 3'h1,
				PS2_STATE_2_PARITY_IN	= 3'h2,
				PS2_STATE_3_STOP_IN		= 3'h3;
	
	reg		[3:0]	data_count;
	reg		[7:0]	data_shift_reg;
	reg		[2:0]	ns_ps2_receiver;
	reg		[2:0]	s_ps2_receiver;
	wire	ps2_clk_posedge;
	wire	ps2_clk_negedge;
	reg		start_receiving_data;
	reg		ps2_clk_reg;
	reg		ps2_data_reg;
	reg		last_ps2_clk;

	always @(posedge clk) begin
		if (reset == 1'b1)
			s_ps2_receiver <= `DELAY PS2_STATE_0_IDLE;
		else
			s_ps2_receiver <= `DELAY ns_ps2_receiver;
	end
	
	always @(*) begin
		ns_ps2_receiver = PS2_STATE_0_IDLE;
	
		case (s_ps2_receiver)
			PS2_STATE_0_IDLE: begin
				if (start_receiving_data & ~kbdcodeValid)
					ns_ps2_receiver = PS2_STATE_1_DATA_IN;
				else
					ns_ps2_receiver = PS2_STATE_0_IDLE;
			end
			PS2_STATE_1_DATA_IN: begin
				if ((data_count == 3'h7) & ps2_clk_posedge)
					ns_ps2_receiver = PS2_STATE_2_PARITY_IN;
				else
					ns_ps2_receiver = PS2_STATE_1_DATA_IN;
			end
			PS2_STATE_2_PARITY_IN: begin
				if (ps2_clk_posedge)
					ns_ps2_receiver = PS2_STATE_3_STOP_IN;
				else
					ns_ps2_receiver = PS2_STATE_2_PARITY_IN;
			end
			PS2_STATE_3_STOP_IN: begin
				if (ps2_clk_posedge)
					ns_ps2_receiver = PS2_STATE_0_IDLE;
				else
					ns_ps2_receiver = PS2_STATE_3_STOP_IN;
			end
			default: begin
				ns_ps2_receiver = PS2_STATE_0_IDLE;
			end
		endcase
	end
	
	always @(posedge clk) begin
		if (reset) 
			data_count	<= `DELAY 3'h0;
		else if ((s_ps2_receiver == PS2_STATE_1_DATA_IN) & ps2_clk_posedge)
			data_count	<= `DELAY data_count + 3'h1;
		else if (s_ps2_receiver != PS2_STATE_1_DATA_IN)
			data_count	<= `DELAY 3'h0;
	end
	
	always @(posedge clk) begin
		if (reset)
			data_shift_reg	<= `DELAY 8'h00;
		else if ((s_ps2_receiver == PS2_STATE_1_DATA_IN) & ps2_clk_posedge)
			data_shift_reg	<= `DELAY {ps2_data_reg, data_shift_reg[7:1]};
	end
	
	always @(posedge clk) begin
		if (reset)
			kbdcode <= `DELAY 8'h00;
		else if (s_ps2_receiver == PS2_STATE_3_STOP_IN)
			kbdcode <= `DELAY data_shift_reg;
	end
	
	always @(posedge clk) begin
		if (reset)
			kbdcodeValid	<= `DELAY 1'b0;
		else if ((s_ps2_receiver == PS2_STATE_3_STOP_IN) & ps2_clk_posedge)
			kbdcodeValid	<= `DELAY 1'b1;
		else
			kbdcodeValid	<= `DELAY 1'b0;
	end

	always @(posedge clk) begin
		if (reset)
			start_receiving_data <= `DELAY 1'b0;
		else
			start_receiving_data <= `DELAY (kbdcodeValid)? 1'b0: (~ps2_data_reg & ps2_clk_posedge)? 1'b1: start_receiving_data;
	end
	
	always @(posedge clk) begin
		if (reset) begin
			last_ps2_clk	<= `DELAY 1'b1;
			ps2_clk_reg		<= `DELAY 1'b1;
			ps2_data_reg	<= `DELAY 1'b1;
		end else begin
			last_ps2_clk	<= `DELAY ps2_clk_reg;
			ps2_clk_reg		<= `DELAY PS2_CLK;
			ps2_data_reg	<= `DELAY PS2_DAT;
		end
	end
	
	assign ps2_clk_posedge = ps2_clk_reg & ~last_ps2_clk;
	assign ps2_clk_negedge = ~ps2_clk_reg & last_ps2_clk;

endmodule

