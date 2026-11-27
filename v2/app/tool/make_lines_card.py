"""Home card of the production-lines section, from the machines' Blender sprites.

    python tool/make_lines_card.py   -> assets/images/cards/lines.webp
Needs the sprites in assets/panel (v2/models/render_machines.py belt gate fan).
"""
import json
import pathlib

from PIL import Image, ImageDraw, ImageFilter

APP = pathlib.Path(__file__).resolve().parent.parent
PANEL = APP / "assets" / "panel"
OUT = APP / "assets" / "images" / "cards"
W, H = 720, 880


# same background and placing as tool/make_cards.py
def bg(c1=(16, 30, 52), c2=(6, 10, 18), glow=(245, 164, 0), gpos=(0.5, 0.42), gstr=70):
    im = Image.new("RGB", (W, H), c2)
    d = ImageDraw.Draw(im)
    for r in range(int(H * 0.9), 0, -6):
        t = r / (H * 0.9)
        col = tuple(int(c1[i] * (1 - t) + c2[i] * t) for i in range(3))
        cx, cy = W * 0.5, H * 0.38
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    g = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(g)
    gx, gy = W * gpos[0], H * gpos[1]
    gd.ellipse([gx - 210, gy - 150, gx + 210, gy + 150], fill=tuple(int(v * gstr / 255) for v in glow))
    g = g.filter(ImageFilter.GaussianBlur(90))
    im = Image.fromarray(__import__("numpy").clip(__import__("numpy").asarray(im, dtype="int16") + __import__("numpy").asarray(g, dtype="int16"), 0, 255).astype("uint8"))
    # subtle dot grid
    d = ImageDraw.Draw(im)
    for y in range(10, H, 22):
        for x in range(10, W, 22):
            d.point((x, y), fill=(40, 58, 82))
    return im.convert("RGBA")


def place(base, im, cx, cy, shadow=True):
    x, y = int(cx - im.width / 2), int(cy - im.height / 2)
    if shadow:
        sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
        a = im.split()[3].point(lambda v: int(v * 0.55))
        blk = Image.new("RGBA", im.size, (0, 0, 0, 255))
        blk.putalpha(a)
        sh.alpha_composite(blk, (x + 10, y + 18))
        base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(16)))
    base.alpha_composite(im, (x, y))


def save(im, name):
    im.convert("RGB").save(OUT / f"{name}.webp", quality=84, method=6)
    print("card", name)




def sprite(kind, layers, width):
    j = json.load(open(PANEL / "machine_sprites.json"))[kind]
    im = Image.new("RGBA", (j["w"], j["h"]), (0, 0, 0, 0))
    for name in layers:
        x, y, _, _ = j["layers"][name]
        part = Image.open(PANEL / f"mach_{kind}_{name}.webp").convert("RGBA")
        im.alpha_composite(part, (int(x), int(y)))
    im = im.crop(im.getchannel("A").getbbox())
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def main():
    im = bg(glow=(60, 200, 255), gpos=(0.5, 0.5), gstr=60)
    place(im, sprite("fan", ["base", "blades1"], 330), W * 0.27, H * 0.3)
    place(im, sprite("gate", ["base", "leaf"], 420), W * 0.66, H * 0.33)
    place(im, sprite("belt", ["base", "box"], 700), W * 0.5, H * 0.68)
    save(im, "lines")


if __name__ == "__main__":
    main()
