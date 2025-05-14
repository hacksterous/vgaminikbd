module clockGenALT (clkout, clkoutd, lock, clkin);

output clkout;
output clkoutd;
output lock;
input clkin;

	assign clkoutd = clkin;//not functionally correct for VGA
	assign clkout = clkin;
	assign lock = 1'b1;

endmodule
