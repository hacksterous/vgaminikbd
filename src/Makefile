VERILOG = iverilog
PROJECT := vgaminikbd
all: $(PROJECT) run

$(PROJECT): keycharcmdcodes.vh sim/clockGenSim.v sim/charROMSim.v sim/charBufferSim.v ansiescape.v hvsync.v uart.v charbufferinit.v heartbeat.v keysynchronizer.v vga.v fifo.v sim/kbdromSim.v ps2receiver.v kbd.v datamux2in.v vgaminikbd.v tb.v
	$(VERILOG) -o $(PROJECT) -DSIM_ONLY sim/clockGenSim.v sim/charROMSim.v sim/charBufferSim.v ansiescape.v hvsync.v uart.v charbufferinit.v heartbeat.v keysynchronizer.v vga.v fifo.v sim/kbdromSim.v ps2receiver.v kbd.v datamux2in.v vgaminikbd.v tb.v


run: $(PROJECT)
	vvp $(PROJECT)
	vcd2fst vgaminikbd.vcd vgaminikbd.fst
	rm -rf vgaminikbd.vcd

.PHONY: clean build
build: $(PROJECT)
clean:
	rm -rf $(PROJECT) *.fst *.vcd
