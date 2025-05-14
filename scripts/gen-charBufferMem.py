mem = []
c = 0
for col in range (80):
	for row in range(32):
		mem.insert(c, format((col + row * 80) % 255, '03d'))
		#mem.insert(c, format((col + row * 80) % 255, '08b'))
		c += 1

for i in range(len(mem)):
	print(mem[i])
