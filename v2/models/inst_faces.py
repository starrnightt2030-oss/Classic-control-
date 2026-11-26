"""Printed faces of the measuring instruments (scale cards and front panels), drawn with PIL.

The numbers here are the same ones the app's simulation uses (lib/meters/instruments.dart):
  * every needle sweeps SWEEP degrees each side of vertical, from its pivot,
  * the analog multimeter ohm scale is f = Rc / (Rc + R) with Rc = 20 x range,
  * the megger scale is f = log10(1 + R/0.05) / log10(1 + 1000/0.05)  (R in MOhm),
  * the knob angles (clockwise from the top) are the KNOB_* lists below.
Run by instruments.py; writes out/faces/*.png
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "faces")
os.makedirs(OUT, exist_ok=True)

SWEEP = 45.0
DEJAVU = "/usr/share/fonts/truetype/dejavu/"


def font(size, bold=False, cond=False):
    names = []
    if cond:
        names.append("DejaVuSansCondensed-Bold.ttf" if bold else "DejaVuSansCondensed.ttf")
    names.append("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf")
    for n in names:
        p = os.path.join(DEJAVU, n)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.truetype(os.path.join(HERE, "fonts", "Cairo-700.ttf" if bold else "Cairo-400.ttf"), size)


# knob positions: (label, angle in degrees clockwise from the top)
KNOB_AVO = [("OFF", 0), ("2.5", 20), ("10", 40), ("50", 60), ("250", 80), ("1000", 100),
            ("10", 120), ("50", 140), ("250", 160), ("750", 180),
            ("250", 200), ("25", 220),
            ("x10k", 240), ("x1k", 260), ("x10", 280), ("x1", 300), ("BUZZ", 320)]
KNOB_DMM = [("OFF", -75), ("V~", -45), ("V=", -15), ("Ω", 15), ("•)))", 45), ("mA", 75), ("A", 105)]
KNOB_CLAMP = [("OFF", -60), ("40A~", -30), ("400A~", 0), ("V~", 30), ("V=", 60), ("Ω", 90)]
KNOB_MEGGER = [("OFF", -60), ("BATT", -30), ("ACV", 0), ("250V", 30), ("500V", 60), ("1000V", 90)]


def ohm_f(r, rc=20.0):
    return rc / (rc + r)


def meg_f(r):
    return min(1.0, math.log10(1 + r / 0.05) / math.log10(1 + 1000 / 0.05))


class Face:
    """an image of w x h millimetres at px pixels per millimetre"""

    def __init__(self, w_mm, h_mm, px=14, bg=(244, 241, 230)):
        self.px = px
        self.w, self.h = w_mm, h_mm
        self.im = Image.new("RGB", (int(w_mm * px), int(h_mm * px)), bg)
        self.d = ImageDraw.Draw(self.im)

    # millimetres from the bottom-left corner -> pixels
    def P(self, x, y):
        return (x * self.px, (self.h - y) * self.px)

    def polar(self, cx, cy, r, deg):
        a = math.radians(deg)
        return self.P(cx + r * math.sin(a), cy + r * math.cos(a))

    def arc(self, cx, cy, r, a0, a1, color, width_mm=0.35, steps=200):
        pts = [self.polar(cx, cy, r, a0 + (a1 - a0) * i / steps) for i in range(steps + 1)]
        self.d.line(pts, fill=color, width=max(1, int(width_mm * self.px)), joint="curve")

    def tick(self, cx, cy, r0, r1, deg, color, width_mm=0.3):
        self.d.line([self.polar(cx, cy, r0, deg), self.polar(cx, cy, r1, deg)], fill=color, width=max(1, int(width_mm * self.px)))

    def text(self, s, x, y, size_mm, color, bold=False, anchor="mm", cond=False, rot=0):
        f = font(int(size_mm * self.px), bold, cond)
        if not rot:
            self.d.text(self.P(x, y), s, fill=color, font=f, anchor=anchor)
            return
        # rotated label (along an arc)
        tw = int(f.getlength(s)) + 8
        th = int(size_mm * self.px * 1.5)
        t = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        ImageDraw.Draw(t).text((tw / 2, th / 2), s, fill=color, font=f, anchor="mm")
        t = t.rotate(-rot, resample=Image.BICUBIC, expand=True)
        px, py = self.P(x, y)
        self.im.paste(t, (int(px - t.width / 2), int(py - t.height / 2)), t)

    def ptext(self, s, cx, cy, r, deg, size_mm, color, bold=False, follow=True):
        x = cx + r * math.sin(math.radians(deg))
        y = cy + r * math.cos(math.radians(deg))
        self.text(s, x, y, size_mm, color, bold, rot=deg if follow else 0)

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, w_mm=0.3, radius_mm=0):
        a, b = self.P(x0, y1), self.P(x1, y0)
        self.d.rounded_rectangle([a, b], radius=int(radius_mm * self.px), fill=fill, outline=outline,
                                 width=max(1, int(w_mm * self.px)))

    def circle(self, x, y, r, fill=None, outline=None, w_mm=0.3):
        a, b = self.P(x - r, y + r), self.P(x + r, y - r)
        self.d.ellipse([a, b], fill=fill, outline=outline, width=max(1, int(w_mm * self.px)))

    def save(self, name):
        p = os.path.join(OUT, name + ".png")
        self.im.save(p, optimize=True)
        return p


INK = (18, 18, 20)
RED = (200, 24, 20)
GREEN = (20, 120, 50)
BLUE = (20, 60, 160)
WHITE = (240, 240, 236)
GREY = (120, 122, 126)


# ------------------------------------------------------------ analog multimeter
AVO_CARD = (96.0, 66.0)          # mm
AVO_PIVOT = (48.0, -4.0)         # mm, in card coordinates (4 mm below its bottom edge)


def avo_card():
    F = Face(*AVO_CARD, px=16)
    cx, cy = AVO_PIVOT
    S = SWEEP
    # ohm scale (top, green), right = 0, left = infinity
    F.arc(cx, cy, 57, -S, S, GREEN, 0.4)
    for r in [0, 0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 70, 100, 150, 200, 300, 500, 1000, 2000]:
        a = -S + 2 * S * ohm_f(r)
        major = r in (0, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000)
        F.tick(cx, cy, 57, 60.0 if major else 58.6, a, GREEN, 0.3)
        if major and r not in (500, 2000):
            lab = {1000: "1k", 2000: "2k"}.get(r, "%g" % r)
            F.ptext(lab, cx, cy, 62.3, a, 2.5, GREEN, True)
    F.tick(cx, cy, 57, 60, -S, GREEN, 0.35)
    F.ptext("∞", cx, cy, 62.4, -S - 3.2, 3.4, GREEN, True)
    F.text("Ω", 7, 60, 4.4, GREEN, True)
    # mirror band
    for r in range(0, 30):
        rr = 51.5 + r * 0.1
        c = int(150 + 80 * math.sin(r / 29 * math.pi))
        F.arc(cx, cy, rr, -S - 1, S + 1, (c, c, c + 6), 0.12)
    # DCV / ACV / mA scale (black): 0..10 / 0..50 / 0..250
    F.arc(cx, cy, 48.5, -S, S, INK, 0.35)
    for i in range(51):
        a = -S + 2 * S * i / 50
        L = 3.0 if i % 10 == 0 else (2.0 if i % 5 == 0 else 1.2)
        F.tick(cx, cy, 48.5, 48.5 - L, a, INK, 0.28 if i % 5 else 0.36)
    for i in range(6):
        a = -S + 2 * S * i / 5
        F.ptext("%d" % (i * 50), cx, cy, 43.4, a, 2.2, INK, True)
        F.ptext("%d" % (i * 10), cx, cy, 40.2, a, 2.2, INK, True)
        F.ptext("%d" % (i * 2), cx, cy, 37.0, a, 2.2, INK, True)
    F.text("DCV.A", 86, 5, 2.6, INK, True)
    F.text("ACV", 10, 5, 2.6, RED, True)
    # AC 10 V (red, slightly crowded at the bottom end)
    F.arc(cx, cy, 33.6, -S, S, RED, 0.3)
    for i in range(0, 11):
        f = (i / 10) ** 1.08
        a = -S + 2 * S * f
        F.tick(cx, cy, 33.6, 32.0, a, RED, 0.3)
        if i % 2 == 0:
            F.ptext("%d" % i, cx, cy, 30.4, a, 2.0, RED, True)
    F.text("AC10V", cx, 22.5, 2.2, RED, True)
    F.text("ELDAWLY", cx, 14.5, 3.4, INK, True)
    F.text("AVO-360  ANALOG MULTIMETER", cx, 10.4, 1.9, INK)
    F.text("20kΩ/V DC   9kΩ/V AC", cx, 7.4, 1.7, GREY)
    return F.save("avo_card")


AVO_PANEL = (104.0, 90.0)        # mm; bottom = body z 4 mm
AVO_KNOB = (52.0, 46.0)          # knob centre on the panel (body z = 50 mm)


def avo_panel():
    F = Face(*AVO_PANEL, px=12, bg=(20, 20, 22))
    cx, cy = AVO_KNOB
    groups = {
        "OFF": WHITE,
    }
    for i, (lab, a) in enumerate(KNOB_AVO):
        col = WHITE
        if 1 <= i <= 5:
            col = WHITE
        elif 6 <= i <= 9:
            col = (255, 90, 80)
        elif 10 <= i <= 11:
            col = (120, 200, 255)
        elif 12 <= i <= 15:
            col = (110, 230, 140)
        elif i == 16:
            col = (255, 210, 80)
        F.tick(cx, cy, 21.5, 24.0, a, col, 0.5)
        F.ptext(lab, cx, cy, 28.0, a, 2.9 if len(lab) < 4 else 2.5, col, True, follow=False)
    # group arcs
    F.arc(cx, cy, 33.5, 14, 106, WHITE, 0.4)
    F.ptext("DCV", cx, cy, 36.4, 60, 2.6, WHITE, True)
    F.arc(cx, cy, 33.5, 114, 186, (255, 90, 80), 0.4)
    F.ptext("ACV", cx, cy, 36.4, 150, 2.6, (255, 90, 80), True, follow=False)
    F.arc(cx, cy, 33.5, 194, 226, (120, 200, 255), 0.4)
    F.ptext("DCmA", cx, cy, 36.4, 210, 2.6, (120, 200, 255), True, follow=False)
    F.arc(cx, cy, 33.5, 234, 306, (110, 230, 140), 0.4)
    F.ptext("Ω", cx, cy, 36.4, 270, 3.4, (110, 230, 140), True, follow=False)
    # jacks and the side controls
    F.text("−COM", 12, 14.5, 2.8, WHITE, True)
    F.text("+ VΩmA", 92, 14.5, 2.8, (255, 90, 80), True)
    F.text("DC 10A", 12, 85.0, 2.6, (255, 90, 80), True)
    F.text("0Ω ADJ", 92, 85.0, 2.6, (110, 230, 140), True)
    F.text("CAT III 600V", 52, 7.0, 2.2, (180, 180, 180), True)
    F.rect(36, 4.2, 68, 9.6, outline=(255, 210, 80), w_mm=0.3, radius_mm=1)
    return F.save("avo_panel")


# ------------------------------------------------------------ digital multimeter
DMM_PANEL = (76.0, 96.0)
DMM_KNOB = (38.0, 50.0)


def dmm_panel():
    F = Face(*DMM_PANEL, px=12, bg=(22, 22, 25))
    cx, cy = DMM_KNOB
    for lab, a in KNOB_DMM:
        col = WHITE if lab not in ("mA", "A") else (255, 90, 80)
        F.tick(cx, cy, 17.5, 20.0, a, col, 0.5)
        F.ptext(lab, cx, cy, 24.5, a, 3.4, col, True, follow=False)
    F.text("DIGITAL MULTIMETER", 38, 88, 2.6, (200, 200, 200), True)
    F.text("ELDAWLY DM-600", 38, 83.5, 2.4, (255, 200, 40), True)
    for x, lab, col in ((10, "10A", (255, 90, 80)), (29, "mA", (255, 90, 80)), (48, "COM", WHITE), (66, "VΩ", (255, 90, 80))):
        F.text(lab, x, 14.0, 2.8, col, True)
    F.text("FUSED 10A MAX", 19, 9.4, 1.7, (255, 90, 80))
    F.text("CAT III 1000V  CAT IV 600V", 52, 9.4, 1.7, (190, 190, 190))
    return F.save("dmm_panel")


# ------------------------------------------------------------ clamp meter
CLAMP_PANEL = (58.0, 92.0)
CLAMP_KNOB = (29.0, 44.0)


def clamp_panel():
    F = Face(*CLAMP_PANEL, px=12, bg=(26, 27, 30))
    cx, cy = CLAMP_KNOB
    for lab, a in KNOB_CLAMP:
        col = (255, 200, 40) if "A" in lab else WHITE
        F.tick(cx, cy, 13.5, 15.5, a, col, 0.5)
        F.ptext(lab, cx, cy, 20.0, a, 2.7, col, True, follow=False)
    F.text("HOLD", 47, 82, 2.4, WHITE, True)
    F.text("CLAMP METER", 29, 88.4, 2.6, (230, 230, 230), True)
    F.text("ELDAWLY CM-400", 20, 82, 2.2, (255, 200, 40), True)
    F.text("VΩ", 15, 12.5, 2.6, (255, 90, 80), True)
    F.text("COM", 43, 12.5, 2.6, WHITE, True)
    F.text("CAT III 600V", 29, 6.0, 2.0, (180, 180, 180), True)
    return F.save("clamp_panel")


# ------------------------------------------------------------ insulation tester (megger)
MEG_CARD = (100.0, 58.0)
MEG_PIVOT = (50.0, -6.0)


def megger_card():
    F = Face(*MEG_CARD, px=16)
    cx, cy = MEG_PIVOT
    S = SWEEP
    F.arc(cx, cy, 56, -S, S, INK, 0.4)
    marks = [0, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 3, 5, 10, 20, 30, 50, 100, 200, 300, 500]
    for r in marks:
        a = -S + 2 * S * meg_f(r)
        major = r in (0, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500)
        F.tick(cx, cy, 56, 59.4 if major else 57.8, a, INK, 0.32)
        if major:
            F.ptext("%g" % r, cx, cy, 61.8, a, 2.5, INK, True)
    for r in [0.02, 0.03, 0.04, 0.07, 0.15, 0.4, 0.7, 1.5, 4, 7, 15, 40, 70, 150, 400, 700]:
        F.tick(cx, cy, 56, 57.4, -S + 2 * S * meg_f(r), INK, 0.25)
    F.tick(cx, cy, 56, 59.6, S, INK, 0.4)
    F.ptext("∞", cx, cy, 62.0, S + 1.5, 3.6, INK, True)
    # the green "good insulation" band and the red "bad" band
    F.arc(cx, cy, 54.5, -S, -S + 2 * S * meg_f(1.0), RED, 0.9)
    F.arc(cx, cy, 54.5, -S + 2 * S * meg_f(1.0), S, GREEN, 0.9)
    # mirror
    for r in range(0, 26):
        c = int(150 + 80 * math.sin(r / 25 * math.pi))
        F.arc(cx, cy, 49.0 + r * 0.1, -S - 1, S + 1, (c, c, c + 6), 0.12)
    # AC V scale 0..600
    F.arc(cx, cy, 46.0, -S, S, RED, 0.32)
    for i in range(0, 61):
        a = -S + 2 * S * i / 60
        F.tick(cx, cy, 46.0, 46.0 - (2.4 if i % 10 == 0 else 1.2), a, RED, 0.25)
        if i % 10 == 0:
            F.ptext("%d" % (i * 10), cx, cy, 41.4, a, 2.1, RED, True)
    F.text("MΩ", cx, 33.5, 4.2, INK, True)
    F.text("ACV", cx + 30, 29.5, 2.4, RED, True)
    F.text("ELDAWLY  IR-1000", cx, 21.8, 3.0, INK, True)
    F.text("INSULATION RESISTANCE TESTER", cx, 18.0, 1.9, INK)
    F.text("250V · 500V · 1000V DC", cx, 15.0, 1.8, GREY)
    return F.save("megger_card")


MEG_PANEL = (150.0, 50.0)
MEG_KNOB = (102.0, 24.0)


def megger_panel():
    F = Face(*MEG_PANEL, px=10, bg=(232, 196, 30))
    cx, cy = MEG_KNOB
    for lab, a in KNOB_MEGGER:
        col = RED if lab.endswith("V") and lab != "ACV" else INK
        F.tick(cx, cy, 12.5, 14.5, a, col, 0.6)
        F.ptext(lab, cx, cy, 19.0, a, 2.9, col, True, follow=False)
    F.text("TEST", 30, 40.0, 3.4, INK, True)
    F.text("PRESS · TURN TO LOCK", 30, 35.5, 2.0, INK)
    F.text("LINE", 135, 42.5, 3.0, RED, True)
    F.text("EARTH", 135, 9.0, 3.0, INK, True)
    F.text("LIVE", 64, 42.5, 2.4, RED, True)
    F.text("⚠ DANGER  1000V", 30, 7.0, 2.4, RED, True)
    return F.save("megger_panel")


# ------------------------------------------------------------ wattmeter
WATT_CARD = (124.0, 62.0)
WATT_PIVOT = (62.0, -8.0)


def watt_card():
    F = Face(*WATT_CARD, px=14)
    cx, cy = WATT_PIVOT
    S = SWEEP
    F.arc(cx, cy, 63, -S, S, INK, 0.4)
    for i in range(0, 121):
        a = -S + 2 * S * i / 120
        L = 3.4 if i % 10 == 0 else (2.2 if i % 5 == 0 else 1.3)
        F.tick(cx, cy, 63, 63 + L, a, INK, 0.36 if i % 10 == 0 else 0.25)
        if i % 20 == 0:
            F.ptext("%d" % i, cx, cy, 69.4, a, 2.8, INK, True)
    for r in range(0, 28):
        c = int(150 + 80 * math.sin(r / 27 * math.pi))
        F.arc(cx, cy, 58.0 + r * 0.1, -S - 1, S + 1, (c, c, c + 6), 0.12)
    F.text("W", cx, 41, 6.0, INK, True)
    F.text("ELDAWLY  WT-5", cx, 32.5, 3.0, INK, True)
    F.text("PORTABLE WATTMETER  cosφ = 1", cx, 28.5, 2.0, INK)
    F.text("5A × 300V = 1500W  (1 div = 12.5 W)", cx, 25.0, 2.0, RED, True)
    F.text("CLASS 0.5", cx - 42, 20, 2.0, GREY)
    F.text("45-65Hz", cx + 42, 20, 2.0, GREY)
    return F.save("watt_card")


WATT_PANEL = (180.0, 34.0)


def watt_panel():
    F = Face(*WATT_PANEL, px=10, bg=(30, 31, 34))
    F.text("CURRENT", 45, 29.5, 2.8, (255, 200, 40), True)
    F.text("VOLTAGE", 135, 29.5, 2.8, (120, 200, 255), True)
    for x, lab in ((25, "± A"), (65, "5 A"), (115, "± V"), (155, "300 V")):
        F.text(lab, x, 22.5, 3.0, WHITE, True)
    F.rect(5, 3, 85, 33, outline=(255, 200, 40), w_mm=0.4, radius_mm=2)
    F.rect(95, 3, 175, 33, outline=(120, 200, 255), w_mm=0.4, radius_mm=2)
    return F.save("watt_panel")


def all_faces():
    return dict(avo_card=avo_card(), avo_panel=avo_panel(), dmm_panel=dmm_panel(), clamp_panel=clamp_panel(),
                megger_card=megger_card(), megger_panel=megger_panel(), watt_card=watt_card(), watt_panel=watt_panel())


if __name__ == "__main__":
    for k, v in all_faces().items():
        print(k, v)
