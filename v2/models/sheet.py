"""Contact sheet of assembled renders: python sheet.py out_name name1 name2 ..."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
F = ImageFont.truetype(os.path.join(HERE, "fonts", "Cairo-600.ttf"), 22)
out, names = sys.argv[1], sys.argv[2:]
cols = min(4, len(names))
rows = (len(names) + cols - 1) // cols
S = 420
W = Image.new("RGB", (cols * S, rows * (S + 34)), (18, 20, 23))
d = ImageDraw.Draw(W)
for i, n in enumerate(names):
    p = os.path.join(OUT, n + "_assembled.png")
    im = Image.open(p).convert("RGB").resize((S, S))
    x, y = (i % cols) * S, (i // cols) * (S + 34)
    W.paste(im, (x, y))
    d.text((x + S // 2, y + S + 4), n, font=F, fill=(220, 220, 220), anchor="ma")
W.save(os.path.join(OUT, out + ".jpg"), quality=88)
print(os.path.join(OUT, out + ".jpg"))
