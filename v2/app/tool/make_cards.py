"""Illustrations for the home/section cards (composited from the Blender renders).

    python tool/make_cards.py   -> assets/images/cards/*.webp
Needs: v2/models/out/ui/*.png (render_ui.py), cairosvg for the diagram card.
"""
import io
import pathlib

from PIL import Image, ImageDraw, ImageFilter

APP = pathlib.Path(__file__).resolve().parent.parent
UI = APP.parent / "models" / "out" / "ui"
OUT = APP / "assets" / "images" / "cards"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 720, 880


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


def comp(name, size):
    im = Image.open(UI / f"{name}.png").convert("RGBA")
    im = im.crop(im.getbbox())
    s = size / max(im.size)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


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


# 1 library: a cluster of components
im = bg()
place(im, comp("motor", 380), W * 0.30, H * 0.56)
place(im, comp("mcb_3p", 250), W * 0.72, H * 0.33)
place(im, comp("contactor", 300), W * 0.58, H * 0.58)
place(im, comp("pb_green_metal", 190), W * 0.22, H * 0.25)
place(im, comp("relay_my4", 200), W * 0.84, H * 0.66)
save(im, "library")

# 2 diagrams: the control + power schematics
im = bg(glow=(63, 213, 232), gstr=60)
try:
    import cairosvg
    for f, cx, sc in (("dol_power.svg", 0.30, 0.95), ("dol_control.svg", 0.70, 0.95)):
        import re
        src = (APP / "assets" / "diagrams" / f).read_text(encoding="utf-8")
        src = re.sub(r"<text[^>]*>[^<]*[\u0600-\u06FF][^<]*</text>", "", src)  # no Arabic shaping in cairosvg
        png = cairosvg.svg2png(bytestring=src.encode("utf-8"), output_width=int(368 * sc), output_height=int(520 * sc))
        sv = Image.open(io.BytesIO(png)).convert("RGBA")
        place(im, sv, W * cx, H * 0.5, shadow=False)
except Exception as e:  # cairosvg missing → plain card
    print("diagram card without svg:", e)
save(im, "diagrams")

# 3 video: exploded contactor + play badge
im = bg(glow=(245, 164, 0), gstr=80)
ex = Image.open(UI / "contactor_exploded.png").convert("RGBA")
ex = ex.crop(ex.getbbox())
s = (W * 0.98) / ex.width
ex = ex.resize((int(ex.width * s), int(ex.height * s)), Image.LANCZOS)
place(im, ex, W * 0.5, H * 0.48)
d = ImageDraw.Draw(im)
cx, cy, r = W * 0.5, H * 0.48, 64
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(245, 164, 0, 235))
d.polygon([(cx - 20, cy - 30), (cx - 20, cy + 30), (cx + 32, cy)], fill=(11, 15, 18, 255))
save(im, "video")

# 4 lesson sheet: a printed page with the exploded view
im = bg(glow=(245, 200, 120), gstr=50)
page = Image.new("RGBA", (440, 600), (250, 250, 248, 255))
pd = ImageDraw.Draw(page)
pd.rectangle([0, 0, 440, 70], fill=(11, 18, 32, 255))
pd.rectangle([0, 70, 440, 76], fill=(217, 149, 0, 255))
pd.rounded_rectangle([300, 18, 420, 34], 6, fill=(230, 236, 240, 255))
pd.rounded_rectangle([340, 42, 420, 52], 5, fill=(140, 160, 175, 255))
thumb = ex.resize((400, int(ex.height * 400 / ex.width)), Image.LANCZOS)
dark = Image.new("RGBA", (420, thumb.height + 20), (15, 21, 25, 255))
dark.alpha_composite(thumb, (10, 10))
page.alpha_composite(dark, (10, 92))
y = 92 + dark.height + 18
for i in range(6):
    pd.rounded_rectangle([392, y, 420, y + 22], 5, fill=(245, 164, 0, 255))
    pd.rounded_rectangle([150 + (i % 3) * 30, y + 3, 380, y + 10], 4, fill=(40, 50, 60, 255))
    pd.rounded_rectangle([60, y + 15, 380, y + 20], 3, fill=(170, 180, 188, 255))
    y += 38
page = page.rotate(-6, resample=Image.BICUBIC, expand=True)
place(im, page, W * 0.5, H * 0.5)
save(im, "sheet")

# 5 lab: the panel
im = bg(glow=(63, 213, 232), gstr=55)
panel = Image.open(APP / "assets" / "images" / "panel.webp").convert("RGBA")
s = (W * 1.05) / panel.width
panel = panel.resize((int(panel.width * s), int(panel.height * s)), Image.LANCZOS)
mask = Image.new("L", panel.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, panel.width, panel.height], 40, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(30))
panel.putalpha(mask)
place(im, panel, W * 0.5, H * 0.52, shadow=False)
save(im, "lab")

# 6 quiz: meter + e-stop
im = bg(glow=(255, 90, 79), gstr=55)
place(im, comp("multimeter", 380), W * 0.38, H * 0.54)
place(im, comp("estop", 240), W * 0.76, H * 0.40)
place(im, comp("lamp_green", 170), W * 0.78, H * 0.75)
save(im, "quiz")
