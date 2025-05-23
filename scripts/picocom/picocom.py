#!/usr/bin/env python
# Picocom is based on pySerial example miniterm.py.
# It is very easy to send any ASCII code: surround the
# code by single-quotes.
# E.g., :13 <return> sends chr(13) (ASCII code 13 decimal).
#		:0x10 sends ASCII code 16 decimal
#		:10*10 sends 10 chr(10) characters
# (C) 2025 Anirban Banerjee
#-------------------------------------------------------------------
# Very simple serial terminal
#
# This file is part of pySerial. https://github.com/pyserial/pyserial
# (C)2002-2020 Chris Liechti <cliechti@gmx.net>
#
# SPDX-License-Identifier:	BSD-3-Clause

from __future__ import absolute_import

import codecs
import os
import sys
import time
import threading

import serial
from serial.tools.list_ports import comports
from serial.tools import hexlify_codec

# pylint: disable=wrong-import-order,wrong-import-position

codecs.register(lambda c: hexlify_codec.getregentry() if c == 'hexlify' else None)

try:
	raw_input
except NameError:
	# pylint: disable=redefined-builtin,invalid-name
	raw_input = input   # in python3 it's "raw"
	unichr = chr


def key_description(character):
	"""generate a readable description for a key"""
	if len(character) > 1:
		return "0"
	ascii_code = ord(character)
	if ascii_code < 32:
		return 'Ctrl+{:c}'.format(ord('@') + ascii_code)
	else:
		return repr(character)


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
class ConsoleBase(object):
	"""OS abstraction for console (input/output codec, no echo)"""

	def __init__(self, picocom):
		self.picocom = picocom
		if sys.version_info >= (3, 0):
			self.byte_output = sys.stdout.buffer
		else:
			self.byte_output = sys.stdout
		self.output = sys.stdout

	def setup(self):
		"""Set console to read single characters, no echo"""

	def cleanup(self):
		"""Restore default console settings"""

	def getkey(self):
		"""Read a single key from the console"""
		return None

	def writekey(self, c):
		sys.stderr.write(c)
		sys.stderr.flush()

	def write_bytes(self, byte_string):
		"""Write bytes (already encoded)"""
		self.byte_output.write(byte_string)
		self.byte_output.flush()

	def write(self, text):
		"""Write string"""
		self.output.write(text)
		self.output.flush()

	def cancel(self):
		"""Cancel getkey operation"""

	#  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -
	# context manager:
	# switch terminal temporary to normal mode (e.g. to get user input)

	def __enter__(self):
		self.cleanup()
		return self

	def __exit__(self, *args, **kwargs):
		self.setup()


if os.name == 'nt':  # noqa
	import msvcrt
	import ctypes
	import platform

	class Out(object):
		"""file-like wrapper that uses os.write"""

		def __init__(self, fd):
			self.fd = fd

		def flush(self):
			pass

		def write(self, s):
			os.write(self.fd, s)

	class Console(ConsoleBase):
		fncodes = {
			';': '\x1bOP',  # F1
			'<': '\x1bOQ',  # F2
			'=': '\x1bOR',  # F3
			'>': '\x1bOS',  # F4
			'?': '\x1b[15~',  # F5
			'@': '\x1b[17~',  # F6
			'A': '\x1b[18~',  # F7
			'B': '\x1b[19~',  # F8
			'C': '\x1b[20~',  # F9
			'D': '\x1b[21~',  # F10
		}
		navcodes = {
			'H': '\x1b[A',  # UP
			'P': '\x1b[B',  # DOWN
			'K': '\x1b[D',  # LEFT
			'M': '\x1b[C',  # RIGHT
			'G': '\x1b[H',  # HOME
			'O': '\x1b[F',  # END
			'R': '\x1b[2~',  # INSERT
			'S': '\x1b[3~',  # DELETE
			'I': '\x1b[5~',  # PAGE UP
			'Q': '\x1b[6~',  # PAGE DOWN
		}

		def __init__(self, picocom):
			super(Console, self).__init__(picocom)
			self._saved_ocp = ctypes.windll.kernel32.GetConsoleOutputCP()
			self._saved_icp = ctypes.windll.kernel32.GetConsoleCP()
			ctypes.windll.kernel32.SetConsoleOutputCP(65001)
			ctypes.windll.kernel32.SetConsoleCP(65001)
			# ANSI handling available through SetConsoleMode since Windows 10 v1511 
			# https://en.wikipedia.org/wiki/ANSI_escape_code#cite_note-win10th2-1
			if platform.release() == '10' and int(platform.version().split('.')[2]) > 10586:
				ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
				import ctypes.wintypes as wintypes
				if not hasattr(wintypes, 'LPDWORD'):  # PY2
					wintypes.LPDWORD = ctypes.POINTER(wintypes.DWORD)
				SetConsoleMode = ctypes.windll.kernel32.SetConsoleMode
				GetConsoleMode = ctypes.windll.kernel32.GetConsoleMode
				GetStdHandle = ctypes.windll.kernel32.GetStdHandle
				mode = wintypes.DWORD()
				GetConsoleMode(GetStdHandle(-11), ctypes.byref(mode))
				if (mode.value & ENABLE_VIRTUAL_TERMINAL_PROCESSING) == 0:
					SetConsoleMode(GetStdHandle(-11), mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING)
					self._saved_cm = mode
			self.output = codecs.getwriter('UTF-8')(Out(sys.stdout.fileno()), 'replace')
			# the change of the code page is not propagated to Python, manually fix it
			sys.stderr = codecs.getwriter('UTF-8')(Out(sys.stderr.fileno()), 'replace')
			sys.stdout = self.output
			self.output.encoding = 'UTF-8'  # needed for input

		def __del__(self):
			ctypes.windll.kernel32.SetConsoleOutputCP(self._saved_ocp)
			ctypes.windll.kernel32.SetConsoleCP(self._saved_icp)
			try:
				ctypes.windll.kernel32.SetConsoleMode(ctypes.windll.kernel32.GetStdHandle(-11), self._saved_cm)
			except AttributeError:  # in case no _saved_cm
				pass

		def getkey(self):
			while True:
				z = msvcrt.getwch()
				if z == unichr(13):
					return unichr(10)
				elif z is unichr(0) or z is unichr(0xe0):
					try:
						code = msvcrt.getwch()
						if z is unichr(0):
							return self.fncodes[code]
						else:
							return self.navcodes[code]
					except KeyError:
						pass
				else:
					return z

		def cancel(self):
			# CancelIo, CancelSynchronousIo do not seem to work when using
			# getwch, so instead, send a key to the window with the console
			hwnd = ctypes.windll.kernel32.GetConsoleWindow()
			ctypes.windll.user32.PostMessageA(hwnd, 0x100, 0x0d, 0)

elif os.name == 'posix':
	import atexit
	import termios
	import fcntl
	import signal

	class Console(ConsoleBase):
		def __init__(self, picocom):
			super(Console, self).__init__(picocom)
			self.fd = sys.stdin.fileno()
			self.old = termios.tcgetattr(self.fd)
			atexit.register(self.cleanup)
			signal.signal(signal.SIGINT, self.sigint)
			if sys.version_info < (3, 0):
				self.enc_stdin = codecs.getreader(sys.stdin.encoding)(sys.stdin)
			else:
				self.enc_stdin = sys.stdin

		def setup(self):
			new = termios.tcgetattr(self.fd)
			new[3] = new[3] & ~termios.ICANON & ~termios.ECHO & ~termios.ISIG
			new[6][termios.VMIN] = 1
			new[6][termios.VTIME] = 0
			termios.tcsetattr(self.fd, termios.TCSANOW, new)

		def getkey(self):
			c = self.enc_stdin.read(1)
			if c == unichr(0x7f):
				c = unichr(8)	# map the BS key (which yields DEL) to backspace
			return c

		def cancel(self):
			fcntl.ioctl(self.fd, termios.TIOCSTI, b'\0')

		def cleanup(self):
			termios.tcsetattr(self.fd, termios.TCSAFLUSH, self.old)

		def sigint(self, sig, frame):
			"""signal handler for a clean exit on SIGINT"""
			self.picocom.stop()
			self.cancel()

else:
	raise NotImplementedError(
		'Sorry no implementation for your platform ({}) available.'.format(sys.platform))


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

class Transform(object):
	"""do-nothing: forward all data unchanged"""
	def rx(self, text):
		"""text received from serial port"""
		return text

	def tx(self, text):
		"""text to be sent to serial port"""
		return text

	def echo(self, text):
		"""text to be sent but displayed on console"""
		return text


class CRLF(Transform):
	"""ENTER sends CR+LF"""

	def tx(self, text):
		return text.replace('\n', '\r\n')


class CR(Transform):
	"""ENTER sends CR"""

	def rx(self, text):
		return text.replace('\r', '\n')

	def tx(self, text):
		return text.replace('\n', '\r')


class LF(Transform):
	"""ENTER sends LF"""


class NoTerminal(Transform):
	"""remove typical terminal control codes from input"""

	REPLACEMENT_MAP = dict((x, 0x2400 + x) for x in range(32) if unichr(x) not in '\r\n\b\t')
	REPLACEMENT_MAP.update(
		{
			0x7F: 0x2421,  # DEL
			0x9B: 0x2425,  # CSI
		})

	def rx(self, text):
		return text.translate(self.REPLACEMENT_MAP)

	echo = rx


class NoControls(NoTerminal):
	"""Remove all control codes, incl. CR+LF"""

	REPLACEMENT_MAP = dict((x, 0x2400 + x) for x in range(32))
	REPLACEMENT_MAP.update(
		{
			0x20: 0x2423,  # visual space
			0x7F: 0x2421,  # DEL
			0x9B: 0x2425,  # CSI
		})


class Printable(Transform):
	"""Show decimal code for all non-ASCII characters and replace most control codes"""

	def rx(self, text):
		r = []
		for c in text:
			if ' ' <= c < '\x7f' or c in '\r\n\b\t':
				r.append(c)
			elif c < ' ':
				r.append(unichr(0x2400 + ord(c)))
			else:
				r.extend(unichr(0x2080 + ord(d) - 48) for d in '{:d}'.format(ord(c)))
				r.append(' ')
		return ''.join(r)

	echo = rx


class Colorize(Transform):
	"""Apply different colors for received and echo"""

	def __init__(self):
		# XXX make it configurable, use colorama?
		self.input_color = '\x1b[37m'
		self.echo_color = '\x1b[31m'

	def rx(self, text):
		return self.input_color + text

	def echo(self, text):
		return self.echo_color + text


class DebugIO(Transform):
	"""Print what is sent and received"""

	def rx(self, text):
		sys.stderr.write(' [RX:{!r}] '.format(text))
		sys.stderr.flush()
		return text

	def tx(self, text):
		sys.stderr.write(' [TX:{!r}] '.format(text))
		sys.stderr.flush()
		return text


# other ideas:
# - add date/time for each newline
# - insert newline after: a) timeout b) packet end character

EOL_TRANSFORMATIONS = {
	'crlf': CRLF,
	'cr': CR,
	'lf': LF,
}

TRANSFORMATIONS = {
	'direct': Transform,	# no transformation
	'default': NoTerminal,
	'nocontrol': NoControls,
	'printable': Printable,
	'colorize': Colorize,
	'debug': DebugIO,
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
def ask_for_port():
	"""\
	Show a list of ports and ask the user for a choice. To make selection
	easier on systems with long device names, also allow the input of an
	index.
	"""
	sys.stderr.write('\nAvailable ports:\n')
	ports = []
	for n, (port, desc, hwid) in enumerate(sorted(comports()), 1):
		sys.stderr.write('{:2}: {:20} {!r}\n'.format(n, port, desc))
		ports.append(port)
	while True:
		sys.stderr.write('Enter port index or full name: ')
		port = raw_input('')
		try:
			index = int(port) - 1
			if not 0 <= index < len(ports):
				sys.stderr.write('Invalid index!\n')
				continue
		except ValueError:
			pass
		else:
			port = ports[index]
		return port


class Picocom(object):
	"""\
	Terminal application. Copy data from serial port to console and vice versa.
	Handle special keys from the console to show menu etc.
	"""

	def __init__(self, serial_instance, echo=False, eol='crlf', filters=()):
		self.console = Console(self)
		self.serial = serial_instance
		self.echo = echo
		self.raw = False
		self.input_encoding = 'UTF-8'
		self.output_encoding = 'UTF-8'
		self.eol = eol
		self.filters = filters
		self.update_transformations()
		self.alive = None
		self._reader_alive = None
		self.receiver_thread = None
		self.rx_decoder = None
		self.tx_decoder = None
		self.tx_encoder = None

	def _start_reader(self):
		"""Start reader thread"""
		self._reader_alive = True
		# start serial->console thread
		self.receiver_thread = threading.Thread(target=self.reader, name='rx')
		self.receiver_thread.daemon = True
		self.receiver_thread.start()

	def _stop_reader(self):
		"""Stop reader thread only, wait for clean exit of thread"""
		self._reader_alive = False
		if hasattr(self.serial, 'cancel_read'):
			self.serial.cancel_read()
		self.receiver_thread.join()

	def start(self):
		"""start worker threads"""
		self.alive = True
		self._start_reader()
		# enter console->serial loop
		self.transmitter_thread = threading.Thread(target=self.writer, name='tx')
		self.transmitter_thread.daemon = True
		self.transmitter_thread.start()
		self.console.setup()

	def stop(self):
		"""set flag to stop worker threads"""
		self.alive = False

	def join(self, transmit_only=False):
		"""wait for worker threads to terminate"""
		self.transmitter_thread.join()
		if not transmit_only:
			if hasattr(self.serial, 'cancel_read'):
				self.serial.cancel_read()
			self.receiver_thread.join()

	def close(self):
		self.serial.close()

	def update_transformations(self):
		"""take list of transformation classes and instantiate them for rx and tx"""
		transformations = [EOL_TRANSFORMATIONS[self.eol]] + [TRANSFORMATIONS[f]
															 for f in self.filters]
		self.tx_transformations = [t() for t in transformations]
		self.rx_transformations = list(reversed(self.tx_transformations))

	def set_rx_encoding(self, encoding, errors='replace'):
		"""set encoding for received data"""
		self.input_encoding = encoding
		self.rx_decoder = codecs.getincrementaldecoder(encoding)(errors)

	def set_tx_encoding(self, encoding, errors='replace'):
		"""set encoding for transmitted data"""
		self.output_encoding = encoding
		self.tx_encoder = codecs.getincrementalencoder(encoding)(errors)

	def dump_port_settings(self):
		"""Write current settings to sys.stderr"""
		sys.stderr.write("\nSettings: {p.name}  {p.baudrate},{p.bytesize},{p.parity},{p.stopbits}\n".format(
			p=self.serial))
		sys.stderr.write('RTS: {:8}  DTR: {:8}  BREAK: {:8}\n'.format(
			('active' if self.serial.rts else 'inactive'),
			('active' if self.serial.dtr else 'inactive'),
			('active' if self.serial.break_condition else 'inactive')))
		try:
			sys.stderr.write('CTS: {:8}  DSR: {:8}  RI: {:8}  CD: {:8}\n'.format(
				('active' if self.serial.cts else 'inactive'),
				('active' if self.serial.dsr else 'inactive'),
				('active' if self.serial.ri else 'inactive'),
				('active' if self.serial.cd else 'inactive')))
		except serial.SerialException:
			# on RFC 2217 ports, it can happen if no modem state notification was
			# yet received. ignore this error.
			pass
		sys.stderr.write('software flow control: {}\n'.format('active' if self.serial.xonxoff else 'inactive'))
		sys.stderr.write('hardware flow control: {}\n'.format('active' if self.serial.rtscts else 'inactive'))
		sys.stderr.write('serial input encoding: {}\n'.format(self.input_encoding))
		sys.stderr.write('serial output encoding: {}\n'.format(self.output_encoding))
		sys.stderr.write('EOL: {}\n'.format(self.eol.upper()))
		sys.stderr.write('filters: {}\n'.format(' '.join(self.filters)))

	def reader(self):
		"""loop and copy serial->console"""
		try:
			while self.alive and self._reader_alive:
				# read all that is there or wait for one byte
				data = self.serial.read(self.serial.in_waiting or 1)
				if data:
					if self.raw:
						self.console.write_bytes(data)
					else:
						text = self.rx_decoder.decode(data)
						for transformation in self.rx_transformations:
							text = transformation.rx(text)
						self.console.write(text)
		except serial.SerialException:
			self.alive = False
			self.console.cancel()
			raise	   # XXX handle instead of re-raise?

	#anirb
	def writer(self):
		try:
			while True:
				c = self.console.getkey()
				self.console.writekey(c)
				if c == ':': #: is start of command sequence
					c = ''
					text = ':'
					while True:
						c = self.console.getkey()
						if c == chr(13) or c == chr(10):
							break
						self.console.writekey(c)
						text += c
				elif c != None:
					text = c

				if text == ":q":
					self.alive = False
					termios.tcsetattr(self.console.fd, termios.TCSADRAIN, self.console.old)  # Restore the terminal settings
					self.stop() # exit app
					break
				else:
					noError = True
					count = 1
					if text == "::":
						text = ':'
					elif text[0] == ':':
						#extract characters between single quotes
						# :number
						# :number-number
						# :command
						try:
							embeddedcode = int(text[1:], 0)
							if (embeddedcode < 0x100): #8 bit integer
								text = chr(embeddedcode)
						except ValueError:
							if '*' in text:
								lst = text[1:].split('*')
								try:
									count = int(lst[0], 0)
								except ValueError:
									count = 1

								if len(lst) > 1 and lst[1] != '':
									try:
										embeddedcode = int(lst[1], 0)
										if (embeddedcode < 0x100): #8 bit integer
											text = chr(embeddedcode)
									except ValueError:
										embeddedcode = 0
										text = lst[1] #string literal
								else:
									noError = False
							else:
								noError = False
								self.handle_command(text[1:])
								if text[1:] == "q":
									self.alive = False
									break

					if noError:
						for i in range(count):
							for transformation in self.tx_transformations:
								text = transformation.tx(text)
							self.serial.write(self.tx_encoder.encode(text))
							if self.echo:
								echo_text = c
								for transformation in self.tx_transformations:
									echo_text = transformation.echo(echo_text)
								self.console.write(echo_text)
							if count > 1:
								time.sleep(0.1)

		except:
			self.alive = False
			print("Error encountered!")
			termios.tcsetattr(self.console.fd, termios.TCSADRAIN, self.console.old)  # Restore the terminal settings
			raise

	def handle_command(self, c):
		if c == "q":
			termios.tcsetattr(self.console.fd, termios.TCSADRAIN, self.console.old)  # Restore the terminal settings
			self.stop() # exit app
		elif c == 'u':						# upload file
			self.upload_file()
		elif c in 'h':						# Show help
			sys.stderr.write(self.get_help_text())
		elif c == 'r':						# Toggle RTS
			self.serial.rts = not self.serial.rts
			sys.stderr.write('RTS {}:\n'.format('active' if self.serial.rts else 'inactive'))
		elif c == 'd':						# Toggle DTR
			self.serial.dtr = not self.serial.dtr
			sys.stderr.write('DTR {}:\n'.format('active' if self.serial.dtr else 'inactive'))
		elif c == 'B':						# toggle BREAK condition
			self.serial.break_condition = not self.serial.break_condition
			sys.stderr.write('BREAK {}:\n'.format('active' if self.serial.break_condition else 'inactive'))
		elif c == 'e':						# toggle local echo
			self.echo = not self.echo
			sys.stderr.write('local echo {}:\n'.format('active' if self.echo else 'inactive'))
		elif c == 'f':						# edit filters
			self.change_filter()
		elif c == 'm':						# EOL mode
			modes = list(EOL_TRANSFORMATIONS)
			eol = modes.index(self.eol) + 1
			if eol >= len(modes):
				eol = 0
			self.eol = modes[eol]
			sys.stderr.write('EOL: {}:\n'.format(self.eol.upper()))
			self.update_transformations()
		elif c == 'a':						# set encoding
			self.change_encoding()
		elif c == 'i':						# info
			self.dump_port_settings()
		elif c in 'pP':						# P -> change port
			self.change_port()
		elif c in 'zZ':						# S -> suspend / open port temporarily
			self.suspend_port()
		elif c == 'b':						# B -> change baudrate
			self.change_baudrate()
		elif c == 'b8':						# 8 -> change to 8 bits
			self.serial.bytesize = serial.EIGHTBITS
			self.dump_port_settings()
		elif c == 'b7':						# 7 -> change to 8 bits
			self.serial.bytesize = serial.SEVENBITS
			self.dump_port_settings()
		elif c in 'eE':						# E -> change to even parity
			self.serial.parity = serial.PARITY_EVEN
			self.dump_port_settings()
		elif c in 'oO':						# O -> change to odd parity
			self.serial.parity = serial.PARITY_ODD
			self.dump_port_settings()
		elif c in 'mM':						# M -> change to mark parity
			self.serial.parity = serial.PARITY_MARK
			self.dump_port_settings()
		elif c in 'sS':						# S -> change to space parity
			self.serial.parity = serial.PARITY_SPACE
			self.dump_port_settings()
		elif c in 'nN':						# N -> change to no parity
			self.serial.parity = serial.PARITY_NONE
			self.dump_port_settings()
		elif c == 's1':						# 1 -> change to 1 stop bits
			self.serial.stopbits = serial.STOPBITS_ONE
			self.dump_port_settings()
		elif c == 's2':						# 2 -> change to 2 stop bits
			self.serial.stopbits = serial.STOPBITS_TWO
			self.dump_port_settings()
		elif c == 's3':						# 3 -> change to 1.5 stop bits
			self.serial.stopbits = serial.STOPBITS_ONE_POINT_FIVE
			self.dump_port_settings()
		elif c in 'xX':						# X -> change software flow control
			self.serial.xonxoff = (c == 'X')
			self.dump_port_settings()
		elif c in 'rR':						# R -> change hardware flow control
			self.serial.rtscts = (c == 'R')
			self.dump_port_settings()
		elif c in 'qQ':
			termios.tcsetattr(self.console.fd, termios.TCSADRAIN, self.console.old)  # Restore the terminal settings
			self.stop()						# Q -> exit app
		else:
			sys.stderr.write('Unknown command {} --\n'.format(key_description(c)))

	def upload_file(self):
		"""Ask user for filename and send its contents"""
		sys.stderr.write('\nFile to upload: ')
		sys.stderr.flush()
		with self.console:
			filename = sys.stdin.readline().rstrip('\r\n')
			if filename:
				try:
					with open(filename, 'rb') as f:
						sys.stderr.write('Sending file {}:\n'.format(filename))
						while True:
							block = f.read(1024)
							if not block:
								break
							self.serial.write(block)
							# Wait for output buffer to drain.
							self.serial.flush()
							sys.stderr.write('.')   # Progress indicator.
					sys.stderr.write('\nFile {} sent:\n'.format(filename))
				except IOError as e:
					sys.stderr.write('ERROR opening file {}: {}:\n'.format(filename, e))

	def change_filter(self):
		"""change the i/o transformations"""
		sys.stderr.write('\nAvailable Filters:\n')
		sys.stderr.write('\n'.join(
			'  {:<10} = {.__doc__}'.format(k, v)
			for k, v in sorted(TRANSFORMATIONS.items())))
		sys.stderr.write('\nEnter new filter name(s) [{}]: '.format(' '.join(self.filters)))
		with self.console:
			new_filters = sys.stdin.readline().lower().split()
		if new_filters:
			for f in new_filters:
				if f not in TRANSFORMATIONS:
					sys.stderr.write('unknown filter: {!r}\n'.format(f))
					break
			else:
				self.filters = new_filters
				self.update_transformations()
		sys.stderr.write('filters: {}\n'.format(' '.join(self.filters)))

	def change_encoding(self):
		"""change encoding on the serial port"""
		sys.stderr.write('\nEnter new encoding name [{}]: '.format(self.input_encoding))
		with self.console:
			new_encoding = sys.stdin.readline().strip()
		if new_encoding:
			try:
				codecs.lookup(new_encoding)
			except LookupError:
				sys.stderr.write('invalid encoding name: {}\n'.format(new_encoding))
			else:
				self.set_rx_encoding(new_encoding)
				self.set_tx_encoding(new_encoding)
		sys.stderr.write('serial input encoding: {}\n'.format(self.input_encoding))
		sys.stderr.write('serial output encoding: {}\n'.format(self.output_encoding))

	def change_baudrate(self):
		"""change the baudrate"""
		sys.stderr.write('\nBaudrate: ')
		sys.stderr.flush()
		with self.console:
			backup = self.serial.baudrate
			try:
				self.serial.baudrate = int(sys.stdin.readline().strip())
			except ValueError as e:
				sys.stderr.write('ERROR setting baudrate: {}:\n'.format(e))
				self.serial.baudrate = backup
			else:
				self.dump_port_settings()

	def change_port(self):
		"""Have a conversation with the user to change the serial port"""
		with self.console:
			try:
				port = ask_for_port()
			except KeyboardInterrupt:
				port = None
		if port and port != self.serial.port:
			# reader thread needs to be shut down
			self._stop_reader()
			# save settings
			settings = self.serial.getSettingsDict()
			try:
				new_serial = serial.serial_for_url(port, do_not_open=True)
				# restore settings and open
				new_serial.applySettingsDict(settings)
				new_serial.rts = self.serial.rts
				new_serial.dtr = self.serial.dtr
				new_serial.open()
				new_serial.break_condition = self.serial.break_condition
			except Exception as e:
				sys.stderr.write('ERROR opening new port: {}:\n'.format(e))
				new_serial.close()
			else:
				self.serial.close()
				self.serial = new_serial
				sys.stderr.write('Port changed to: {}:\n'.format(self.serial.port))
			# and restart the reader thread
			self._start_reader()

	def suspend_port(self):
		"""\
		open port temporarily, allow reconnect, exit and port change to get
		out of the loop
		"""
		# reader thread needs to be shut down
		self._stop_reader()
		self.serial.close()
		sys.stderr.write('\nPort closed: {}:\n'.format(self.serial.port))
		do_change_port = False
		while not self.serial.is_open:
			k = self.console.getkey()
			if k in 'pP':
				do_change_port = True
				break
			try:
				self.serial.open()
			except Exception as e:
				sys.stderr.write('ERROR opening port: {}:\n'.format(e))
		if do_change_port:
			self.change_port()
		else:
			# and restart the reader thread
			self._start_reader()
			sys.stderr.write('Port opened: {}:\n'.format(self.serial.port))

	def get_help_text(self):
		# return the help text
		# help text, starts with blank line!
		return """
pySerial ({version}) - picocom - help
---
Toggles:
   {rts:7}	RTS  
   {dtr:7}	DTR   
   {brk:7}	BREAK
   {echo:7} echo  
   {info:7} info  
   {upload:7} upload  
   {filter:7} filter  
   {eol:7}	EOL
---
Port settings:
   p			change port
   7 8			set data bits
   N E O S M	change parity (None, Even, Odd, Space, Mark)
   1 2 3		set stop bits (1, 2, 1.5)
   b			change baud rate
   x X			disable/enable software flow control
   r R			disable/enable hardware flow control
""".format(version=getattr(serial, 'VERSION', 'unknown version'),
		   rts=key_description('r'),
		   dtr=key_description('d'),
		   brk=key_description('b'),
		   echo=key_description('e'),
		   info=key_description('i'),
		   upload=key_description('u'),
		   filter=key_description('f'),
		   eol=key_description('m'))


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# default args can be used to override when calling main() from an other script
# e.g to create a miniterm-my-device.py
def main(default_port=None, default_baudrate=19200, default_rts=None, default_dtr=None, serial_instance=None, default_eol='LF'):
	import argparse

	parser = argparse.ArgumentParser(
		description='Picocom - A pico terminal program for the serial port.')

	parser.add_argument(
		'port',
		nargs='?',
		help='serial port name ("-" to show port list)',
		default=default_port)

	parser.add_argument(
		'baudrate',
		nargs='?',
		type=int,
		help='set baud rate, default: %(default)s',
		default=default_baudrate)

	group = parser.add_argument_group('port settings')

	group.add_argument(
		'--parity',
		choices=['N', 'E', 'O', 'S', 'M'],
		type=lambda c: c.upper(),
		help='set parity, one of {N E O S M}, default: N',
		default='N')

	group.add_argument(
		'--data',
		choices=[5, 6, 7, 8],
		type=int,
		help='set data bits, default: %(default)s',
		default=8)

	group.add_argument(
		'--stop',
		choices=[1, 2, 3],
		type=int,
		help='set stop bits (1, 2, 1.5), default: %(default)s',
		default=1)

	group.add_argument(
		'--rtscts',
		action='store_true',
		help='enable RTS/CTS flow control (default off)',
		default=False)

	group.add_argument(
		'--xonxoff',
		action='store_true',
		help='enable software flow control (default off)',
		default=False)

	group.add_argument(
		'--rts',
		type=int,
		help='set initial RTS line state (possible values: 0, 1)',
		default=default_rts)

	group.add_argument(
		'--dtr',
		type=int,
		help='set initial DTR line state (possible values: 0, 1)',
		default=default_dtr)

	group.add_argument(
		'--non-exclusive',
		dest='exclusive',
		action='store_false',
		help='disable locking for native ports',
		default=True)

	group.add_argument(
		'--ask',
		action='store_true',
		help='ask again for port when open fails',
		default=False)

	group = parser.add_argument_group('data handling')

	group.add_argument(
		'-e', '--echo',
		action='store_true',
		help='enable local echo (default off)',
		default=False)

	group.add_argument(
		'--encoding',
		dest='serial_port_encoding',
		metavar='CODEC',
		help='set the encoding for the serial port (e.g. hexlify, Latin1, UTF-8), default: %(default)s',
		default='UTF-8')

	group.add_argument(
		'-f', '--filter',
		action='append',
		metavar='NAME',
		help='add text transformation',
		default=[])

	group.add_argument(
		'--eol',
		choices=['CR', 'LF', 'CRLF'],
		type=lambda c: c.upper(),
		help='end of line mode',
		default=default_eol)

	group.add_argument(
		'--raw',
		action='store_true',
		help='Do no apply any encodings/transformations',
		default=True)

	group = parser.add_argument_group('diagnostics')

	group.add_argument(
		'-q', '--quiet',
		action='store_true',
		help='suppress non-error messages',
		default=False)

	group.add_argument(
		'--develop',
		action='store_true',
		help='show Python traceback on error',
		default=False)

	args = parser.parse_args()

	if args.filter:
		if 'help' in args.filter:
			sys.stderr.write('Available filters:\n')
			sys.stderr.write('\n'.join(
				'{:<10} = {.__doc__}'.format(k, v)
				for k, v in sorted(TRANSFORMATIONS.items())))
			sys.stderr.write('\n')
			sys.exit(1)
		filters = args.filter
	else:
		filters = ['default']

	while serial_instance is None:
		# no port given on command line -> ask user now
		if args.port is None or args.port == '-':
			try:
				args.port = ask_for_port()
			except KeyboardInterrupt:
				sys.stderr.write('\n')
				parser.error('user aborted and port is not given')
			else:
				if not args.port:
					parser.error('port is not given')

		stopbits = serial.STOPBITS_ONE_POINT_FIVE if args.stop == 3 else args.stop
		try:
			serial_instance = serial.serial_for_url(
				args.port,
				args.baudrate,
				bytesize=args.data,
				parity=args.parity,
				stopbits=stopbits,
				rtscts=args.rtscts,
				xonxoff=args.xonxoff,
				do_not_open=True)

			if not hasattr(serial_instance, 'cancel_read'):
				# enable timeout for alive flag polling if cancel_read is not available
				serial_instance.timeout = 1

			if args.dtr is not None:
				if not args.quiet:
					sys.stderr.write('forcing DTR {}\n'.format('active' if args.dtr else 'inactive'))
				serial_instance.dtr = args.dtr
			if args.rts is not None:
				if not args.quiet:
					sys.stderr.write('forcing RTS {}\n'.format('active' if args.rts else 'inactive'))
				serial_instance.rts = args.rts

			if isinstance(serial_instance, serial.Serial):
				serial_instance.exclusive = args.exclusive

			serial_instance.open()
		except serial.SerialException as e:
			sys.stderr.write('could not open port {!r}: {}\n'.format(args.port, e))
			if args.develop:
				raise
			if not args.ask:
				sys.exit(1)
			else:
				args.port = '-'
		else:
			break

	picocom = Picocom(
		serial_instance,
		echo=args.echo,
		eol=args.eol.lower(),
		filters=filters)
	picocom.raw = args.raw
	picocom.set_rx_encoding(args.serial_port_encoding)
	picocom.set_tx_encoding(args.serial_port_encoding)

	if not args.quiet:
		sys.stderr.write('Picocom on {p.name} {p.baudrate},{p.bytesize},{p.parity},{p.stopbits}:\n'.format(
			p=picocom.serial))
		sys.stderr.write('Quit: {:q} | Help: {:h}\n')

	picocom.start()
	try:
		picocom.join(True)
	except KeyboardInterrupt:
		sys.exit(1)
	if not args.quiet:
		sys.stderr.write('\nExit\n')
	picocom.join()
	picocom.close()


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
if __name__ == '__main__':
	main()
