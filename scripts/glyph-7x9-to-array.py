import sys

if len(sys.argv) == 2:
	infile = sys.argv[1]
else:
	print("Need input glyph file name")
	sys.exit(1)

fout = open("font7x9Array.py", 'w')
fout.write("font7x9Array = [\n")
charNum = 0
rowCount = 0
with open(infile, 'r') as fin:
	while True:
		line = fin.readline().rstrip('\n')
		if line.find("#Character #") == 0:
			charNum = int(line[12:])
			rowCount = 0
			fout.write('\t')
		else:
			value = 0
			if len(line) < 8:
				print("Incorrect spec. for glyph number: ", end = '')
				print(charNum)
				sys.exit(2)
			for pixel in range(8):
				value = value * 2
				try:
					if line[pixel] == '*':
						value += 1
				except IndexError:
					print("Error for glyph number: ", end = '')
					print(charNum)
					sys.exit(2)
			fout.write('0x')
			fout.write(format(value, '02X'))
			rowCount += 1
			if rowCount != 9 or charNum != 127:
				fout.write(', ')
			else:
				fout.write('] ')

		if rowCount == 9:
			fout.write('#')
			fout.write(str(charNum))
			fout.write('\n')
			charNum += 1
			
			if charNum == 128:
				break


fin.close()
fout.close()
