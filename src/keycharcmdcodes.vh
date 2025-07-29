//Key Raw ASCII Emulation
//UP Arrow:		0x1E ESC[A
//DOWN Arrow:	0x1F ESC[B
//RIGHT Arrow:	0x1D ESC[C
//LEFT Arrow:	0x1C ESC[D
//HOME:			0x01 ESC[H
//END:			0x04 ESC[F

`ifndef __KEYCHARCMDCODES__
`define __KEYCHARCMDCODES__
`define CHAR_NUL 0
`define CMD_NUL 0
`define CMD_CRLF 1
`define CMD_UP 2
`define CMD_SCROLL_DOWN 3
`define CMD_DEL 4
`define CMD_PGUP 5
`define CMD_PGDN 6
//code 7 is available
`define CMD_BKSP 8
`define CMD_TAB 9
`define CMD_LF 10
`define CMD_DOWN 10
`define CMD_CLS 11
`define CMD_LEFT 12
`define CMD_CR 13
`define CMD_HOME 13
`define CMD_RIGHT 14
`define CMD_END 15
`define CMD_ERASE_SOL 16
`define CMD_ERASE_EOL 17
`define CMD_ERASE_LINE 18
//CMD_CURTOG: toggle cursor enable
`define CMD_CURTOG 19
//CMD_CHRTOG: toggle character mode for codes 0-31
`define CMD_CHRTOG 20
`define CMD_SETCOL 21
`define CMD_SETROW 22
`define CMD_INSTOG 23
`define CMD_MOVROWS 24
`define CMD_MOVCOLS 25
`define CHAR_SPC 32
`endif
