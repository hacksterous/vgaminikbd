//For FPGA implementation
`timescale 1ns/1ps
`include "vgaminikbd.vh"
module uart (
	ECHO,
	clk,
	rstn, //synchronous reset
	UART_TX,
	UART_RX,
	clockDividerValue,
	dataOutRx,
	dataOutRxAvailable,
	dataInTx,
	dataInTxValid,
	dataInTxBusy,
	rxError,
	rxBitTick,
	txBitTick
);

	`define DATA_WIDTH 8

	input ECHO; //echos UART_RX to UART_TX
	input clk, rstn;
	output UART_TX;
	input UART_RX;
	output [`DATA_WIDTH-1:0] dataOutRx; //data received from serial
	output dataOutRxAvailable;
	input [`DATA_WIDTH-1:0] dataInTx; //data to be sent out on serial
	input dataInTxValid;
	output dataInTxBusy;
	output rxError; //receive buffer overflow or other error
	input [19:0] clockDividerValue;
	output rxBitTick;
	output txBitTick;

	wire dataInTxBusy;
	reg uartRxR0;
	reg uartRxReg;
	reg rxError;
	reg [`DATA_WIDTH-1:0] rxDataReg;
	reg dataOutRxAvailable;
	reg [19:0] rxClockDividerReg;
	reg [3:0] rxBitCount;
	wire rxFifoEmpty, rxFifoFull;
	
	reg uartTxReg;
	reg [`DATA_WIDTH:0] txDataReg;
	reg [19:0] txClockDividerReg;
	reg [3:0] txBitCount;

	always @(posedge clk) begin
	    if (~rstn) begin
	        uartRxR0 <= `DELAY 1'b1;
	        uartRxReg <= `DELAY 1'b1;
	        rxClockDividerReg <= `DELAY 20'h0;
	        rxBitCount <= `DELAY 4'h0;
			rxDataReg <= `DELAY {`DATA_WIDTH{1'b0}};
	        rxError <= `DELAY 1'b0;
	    end else begin
	        uartRxR0 <= `DELAY UART_RX;
			uartRxReg <= `DELAY uartRxR0;
	        rxError <= `DELAY 1'b0;
	        dataOutRxAvailable <= `DELAY 1'b0;
	        if (rxClockDividerReg > 20'h0) begin
	            rxClockDividerReg <= `DELAY rxClockDividerReg - 1'b1;
	        end else if (rxBitCount > 4'h0) begin
	            if (rxBitCount > `DATA_WIDTH+1) begin
					//start
	                if (~uartRxReg) begin
	                    rxBitCount <= `DELAY rxBitCount - 1'b1;
	                    rxClockDividerReg <= `DELAY clockDividerValue;
	                end else begin
	                    rxBitCount <= `DELAY 1'b0;
	                    rxClockDividerReg <= `DELAY 20'h0;
	                end
	            end else if (rxBitCount > 4'h1) begin
					//data
	                rxBitCount <= `DELAY rxBitCount - 1'b1;
	                rxClockDividerReg <= `DELAY clockDividerValue;
	                rxDataReg <= `DELAY {uartRxReg, rxDataReg[`DATA_WIDTH-1:1]};
	            end else if (rxBitCount == 4'h1) begin
					//stop
	                rxBitCount <= `DELAY rxBitCount - 1'b1;
	                if (~uartRxReg) begin
						//missing stop bit
	                    rxError <= `DELAY 1'b1;
	                end
					dataOutRxAvailable <= `DELAY 1'b1;
	            end
	        end else begin
	            if (~uartRxReg) begin
					//pre-start
					//delay half bit-time for first Rx bit
	                rxClockDividerReg <= `DELAY {1'b0, clockDividerValue[19:1]}; 
	                rxBitCount <= `DELAY `DATA_WIDTH+2;
	                rxDataReg <= `DELAY {`DATA_WIDTH{1'b0}};
	            end
	        end
	    end
	end

	assign dataOutRx = rxDataReg;

	wire txClockDividerRegGTZ = (txClockDividerReg > 20'h0);
	assign dataInTxBusy = (txClockDividerRegGTZ | (txBitCount > 4'h0));

	always @(posedge clk) begin
	    if (~rstn) begin
	        uartTxReg <= `DELAY 1'b1;
	        txClockDividerReg <= `DELAY 20'h0;
	        txBitCount <= `DELAY 4'h0;
	    end else begin
	        if (txClockDividerRegGTZ) begin
	            txClockDividerReg <= `DELAY txClockDividerReg - 1'b1;
	        end else if (txBitCount == 4'h0) begin
				//start
				if (dataInTxValid & ~ECHO | dataOutRxAvailable & ECHO) begin
					txClockDividerReg <= `DELAY clockDividerValue;
					txBitCount <= `DELAY `DATA_WIDTH + 1'b1;
					txDataReg <= `DELAY {1'b1, (ECHO)? dataOutRx: dataInTx};
					uartTxReg <= `DELAY 1'b0;
				end
	        end else begin
	            if (txBitCount > 4'h1) begin
					//data
	                txBitCount <= `DELAY txBitCount - 1'b1;
	                txClockDividerReg <= `DELAY clockDividerValue;
	                {txDataReg, uartTxReg} <= `DELAY {1'b0, txDataReg};
	            end else if (txBitCount == 1'b1) begin
					//stop
	                txBitCount <= `DELAY txBitCount - 1'b1;
	                txClockDividerReg <= `DELAY clockDividerValue;
	                uartTxReg <= `DELAY 1'b1;
	            end
	        end
	    end
	end
	assign UART_TX = uartTxReg;
	assign rxBitTick = (rxClockDividerReg == clockDividerValue);
	assign txBitTick = (txClockDividerReg == clockDividerValue);
endmodule
