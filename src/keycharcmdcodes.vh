//Key Raw ASCII Emulation
//UP Arrow:		0x1E ESC[A
//DOWN Arrow:	0x1F ESC[B
//RIGHT Arrow:	0x1D ESC[C
//LEFT Arrow:	0x1C ESC[D
//HOME:			0x01 ESC[H
//END:			0x04 ESC[F

`ifndef __KEYCHARCMDCODES__
`define __KEYCHARCMDCODES__
`define CMD_NUL 0
`define CMD_CRLF 1
`define CMD_UP 2
`define CMD_DEL 4
`define CMD_BKSP 8
`define CMD_TAB 9
`define CMD_LF 10
`define CMD_DOWN 10
`define CMD_CR 13
`define CMD_HOME 13
`define CMD_CLS 12
`define CMD_LEFT 13
`define CMD_RIGHT 14
`define CMD_END 15
`define CMD_SPC 32
`endif
