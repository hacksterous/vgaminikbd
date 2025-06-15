# First update the glyph file (typically 7x9-font.glyph).
# Run the font data generator (glyph-7x9-to-array.py)
# with this glyph file.
python3 glyph-7x9-to-array.py 7x9-font.glyph

# The output of this will be the font data file (Python code
# fragment) font7x9Array.py.
# Run the font generator (gen-7x9-font.py).
# This generates Gowin memory initialization file *.mi
python3 gen-7x9-font.py > ../src/mem/charROM.mi

# One can run the font generator with the 'show' option to
# generate the glyph file (can be used to compare with  7x9-font.glyph).
python3 gen-7x9-font.py show > OUTPUT.glyph 

# Regenerate ROM with updated .mi file. 
