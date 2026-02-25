#!/usr/bin/env python3
"""Convert a 5x8 font PNG (16 cols x N rows of glyphs) to a C header."""

import sys
from PIL import Image

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.png> <output.h>")
        sys.exit(1)

    img = Image.open(sys.argv[1]).convert("L")
    w, h = img.size
    glyph_w, glyph_h = 5, 8
    cols, rows = w // glyph_w, h // glyph_h

    if cols < 16 or rows < 8:
        print(f"Error: expected at least 16x8 glyphs, got {cols}x{rows}")
        sys.exit(1)

    num_glyphs = cols * rows
    glyphs = []

    for g in range(num_glyphs):
        gr, gc = divmod(g, 16)
        gx0, gy0 = gc * glyph_w, gr * glyph_h
        row_bytes = []
        for y in range(glyph_h):
            val = 0
            for x in range(glyph_w):
                px = img.getpixel((gx0 + x, gy0 + y))
                if px < 128:  # dark pixel = foreground
                    val |= (0x80 >> x)
            row_bytes.append(val)
        glyphs.append(row_bytes)

    with open(sys.argv[2], "w") as f:
        f.write("// Auto-generated from v06c-font-5x8.png — do not edit\n")
        f.write("#ifndef FONT_5X8_H\n#define FONT_5X8_H\n\n")
        f.write("#include <stdint.h>\n\n")
        f.write(f"#define FONT_NUM_GLYPHS {num_glyphs}\n\n")
        f.write(f"// {num_glyphs} glyphs, {glyph_h} bytes each, 5 MSBits active\n")
        f.write(f"static const uint8_t font_5x8[FONT_NUM_GLYPHS][{glyph_h}] = {{\n")
        for g in range(num_glyphs):
            row_str = ", ".join(f"0x{b:02x}" for b in glyphs[g])
            comment = ""
            if g < 96:
                ch = g + 0x20
                if 0x20 <= ch < 0x7f:
                    c = chr(ch)
                    if c == '\\':
                        c = '\\\\'
                    elif c == "'":
                        c = "\\'"
                    comment = f"  // '{c}'"
            elif g < 128:
                comment = f"  // cyr {g - 96}"
            else:
                comment = f"  // ext {g - 128}"
            f.write(f"    {{{row_str}}},{comment}\n")
        f.write("};\n\n#endif\n")

    print(f"Generated {sys.argv[2]}: {num_glyphs} glyphs")

if __name__ == "__main__":
    main()
