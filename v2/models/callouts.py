"""Draw bilingual (Arabic/English) callouts on a render using projected 3D anchors."""
import json, sys, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")
FD = os.path.join(HERE, "fonts") + os.sep
AR_B = ImageFont.truetype(os.path.join(HERE, "fonts", "Cairo-700.ttf"), 30)
EN = ImageFont.truetype(FD + "Cairo-400.ttf", 21)
T_AR = ImageFont.truetype(os.path.join(HERE, "fonts", "Cairo-700.ttf"), 44)
T_EN = ImageFont.truetype(FD + "Cairo-600.ttf", 26)
ACC = (249, 176, 0)
_meas = ImageDraw.Draw(Image.new("RGB", (10, 10)))


def draw(img_path, anchors, labels, out, title_ar, title_en):
    im = Image.open(img_path).convert("RGB")
    W, H = im.size
    canvas = Image.new("RGB", (W, H + 110), (18, 20, 23))
    canvas.paste(im, (0, 110))
    d = ImageDraw.Draw(canvas)
    d.text((W - 40, 28), title_ar, font=T_AR, fill=(240, 240, 240), anchor="ra", direction="rtl")
    d.text((40, 42), title_en, font=T_EN, fill=(170, 175, 180), anchor="la")
    d.rectangle((0, 106, W, 110), fill=ACC)
    for key, (ar, en, lx, ly) in labels.items():
        ax, ay = anchors[key]
        ay += 110
        ly += 110
        wa = d.textlength(ar, font=AR_B, direction="rtl")
        we = d.textlength(en, font=EN)
        bw = max(wa, we) + 34
        bh = 78
        bx0 = lx - bw / 2
        by0 = ly - bh / 2
        # leader: elbow from anchor to box edge
        ex = lx
        ey = by0 + bh if ay > ly else by0
        d.line([(ax, ay), (ex, ey)], fill=ACC, width=3)
        d.ellipse((ax - 7, ay - 7, ax + 7, ay + 7), fill=ACC, outline=(18, 20, 23), width=2)
        d.rounded_rectangle((bx0, by0, bx0 + bw, by0 + bh), radius=12, fill=(30, 33, 38), outline=ACC, width=2)
        d.text((lx, by0 + 6), ar, font=AR_B, fill=(250, 250, 250), anchor="ma", direction="rtl")
        d.text((lx, by0 + 46), en, font=EN, fill=(175, 180, 188), anchor="ma")
    canvas.save(out, quality=92)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    A = json.load(open(OUT_DIR + "/contactor_exploded_anchors.json"))
    A["return_springs"] = [1048, 540]
    from contactor import PARTS
    pos = {
        "terminal_screw": (240, 330), "front_housing": (300, 1020), "fixed_top": (560, 150),
        "silver_tip": (840, 300), "moving_contacts": (640, 1030), "fixed_bottom": (960, 1030),
        "carrier": (1000, 800), "armature": (1040, 200), "return_springs": (1340, 1030),
        "coil": (1330, 120), "fixed_core": (1620, 250), "base": (1600, 760),
    }
    extra = {"terminal_screw": ("مسمار الترمينال", "Terminal screw"), "silver_tip": ("نقط الفضة", "Silver contact tips")}
    labels = {}
    for k, (x, y) in pos.items():
        ar, en = (PARTS[k][0], PARTS[k][1]) if k in PARTS else extra[k]
        
        labels[k] = (ar, en, x, y)
    draw(OUT_DIR + "/contactor_exploded.png", A, labels, OUT_DIR + "/contactor_exploded_labeled.jpg",
         "تفكيك أجزاء الكونتاكتور", "AC Contactor — Exploded view")


def auto(name, PARTS, title_ar, title_en, W=1800, H=1100, extra=None, fixes=None):
    """Auto-place labels in top/bottom rows ordered by anchor x."""
    A = json.load(open(OUT_DIR + f"/{name}_anchors.json"))
    if fixes:
        A.update(fixes)
    names = {k: (v[0], v[1]) for k, v in PARTS.items()}
    if extra:
        names.update(extra)
    keys = [k for k in A if k in names]
    top = sorted([k for k in keys if A[k][1] < H * 0.5], key=lambda k: A[k][0])
    bot = sorted([k for k in keys if A[k][1] >= H * 0.5], key=lambda k: A[k][0])
    # balance rows
    while len(top) > len(bot) + 2:
        k = max(top, key=lambda k: A[k][1]); top.remove(k); bot.append(k); bot.sort(key=lambda k: A[k][0])
    while len(bot) > len(top) + 2:
        k = min(bot, key=lambda k: A[k][1]); bot.remove(k); top.append(k); top.sort(key=lambda k: A[k][0])
    labels = {}
    for row, ys in ((top, (70, 185)), (bot, (H - 50, H - 165))):
        n = len(row)
        for i, k in enumerate(row):
            x = (i + 0.5) * W / max(n, 1)
            x = min(max(x, 200), W - 200)
            ar, en = names[k]
            tw = sum(max(_meas.textlength(names[q][0], font=AR_B, direction="rtl"), _meas.textlength(names[q][1], font=EN)) + 60 for q in row)
            y = ys[i % 2] if tw > W - 20 else ys[0]
            
            labels[k] = (ar, en, x, y)
    draw(OUT_DIR + f"/{name}_exploded.png", A, labels, OUT_DIR + f"/{name}_exploded_labeled.jpg",
         title_ar, title_en)
