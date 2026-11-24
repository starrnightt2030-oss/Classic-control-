"""22 mm door devices, XB2 style (metal & plastic series), AD16 pilot lamps, push-button stations.
Axis: Z = device axis (head up / toward operator), door plane at z=0, inside of panel z<0. mm.
Run: python door.py <variant|all> [assembled,exploded]"""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

PB_PARTS = {
    "cap":        ("الزرار (الراس)", "Push-button cap", (0, 0, 34)),
    "bezel":      ("الإطار والجسم الأمامي", "Bezel & head body", (0, 0, 20)),
    "head_spring": ("سوستة الإرجاع والذراع", "Return spring & plunger", (0, 0, 6)),
    "ring_nut":   ("صامولة التثبيت", "Fixing ring nut", (0, 0, -6)),
    "base":       ("قاعدة التثبيت (الحامل)", "Mounting base (adapter)", (0, 0, -20)),
    "block":      ("بلوك النقط", "Contact block housing", (0, -30, -38)),
    "block_contacts": ("النقط الداخلية للبلوك", "Contact block internals", (0, -62, -40)),
}
ESTOP_PARTS = dict(PB_PARTS)
ESTOP_PARTS["cap"] = ("راس المشروم", "Mushroom head", (0, 0, 40))
ESTOP_PARTS["head_spring"] = ("آلية الإمساك واللف", "Latching (twist-release) mechanism", (0, 0, 8))
SEL_PARTS = dict(PB_PARTS)
SEL_PARTS["cap"] = ("ذراع السليكتور", "Selector knob", (0, 0, 34))
SEL_PARTS["head_spring"] = ("الكامة وسوستة الطقة", "Cam & detent spring", (0, 0, 6))
LAMP_PARTS = {
    "lens":     ("العدسة الملوّنة", "Coloured lens", (0, 0, 30)),
    "led":      ("كارت الليد", "LED board", (0, 0, 14)),
    "bezel":    ("الإطار", "Bezel", (0, 0, 22)),
    "nut":      ("صامولة التثبيت", "Fixing nut", (0, 0, -4)),
    "body":     ("الجسم والترامل", "Body & terminals", (0, 0, -22)),
    "driver":   ("دايرة التغذية (مقاومة ومكثف)", "Driver (resistor / capacitor)", (0, -34, -24)),
}
STATION_PARTS = {
    "cover":  ("الغطاء", "Cover", (0, 0, 40)),
    "gasket": ("جوان العزل", "Sealing gasket", (0, 0, 22)),
    "screws": ("مسامير الغطاء", "Cover screws", (0, 0, 60)),
    "body":   ("العلبة", "Enclosure body", (0, 0, 0)),
    "gland":  ("جلاند الكابل", "Cable gland", (0, -40, -6)),
}


def mats(M, series):
    return dict(
        black=lib.mat("d_black", (0.02, 0.02, 0.022), rough=0.45, bump=0.25),
        zinc=lib.mat("d_zinc", (0.72, 0.73, 0.75), metal=1.0, rough=0.35),
        chrome=M["chrome"], satin=M["satin"],
        white=lib.mat("d_white", (0.82, 0.82, 0.8), rough=0.45, bump=0.2),
        ink=lib.mat("d_ink", (0.85, 0.85, 0.85), rough=0.6),
        dark_ink=lib.mat("d_dink", (0.03, 0.03, 0.04), rough=0.6),
        copper=lib.mat("d_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        silver=lib.mat("d_ag", (0.93, 0.93, 0.95), metal=1.0, rough=0.18),
        steel=lib.mat("d_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        grey=lib.mat("d_grey", (0.42, 0.43, 0.45), rough=0.45, bump=0.2),
        yellow=lib.mat("d_yellow", (0.85, 0.55, 0.0), rough=0.4, bump=0.2),
        green=lib.mat("d_green", (0.0, 0.20, 0.04), rough=0.25, coat=0.6),
        red=lib.mat("d_red", (0.5, 0.008, 0.008), rough=0.25, coat=0.6),
        pcb=lib.mat("d_pcb", (0.02, 0.18, 0.06), rough=0.4),
    )


def rear(C, M, blocks, metal=True):
    """thread tube, ring nut, XB2 base (zinc U-bracket or plastic), contact blocks with side screws."""
    CYL(11.0, -10, -0.2, 0, 0, C["zinc"] if metal else C["black"], "bezel", axis="Z", bw=0.2)
    for i in range(6):
        o = lib.torus(0.0110, 0.00028, -0.0025 - i * 0.0012, C["zinc"] if metal else C["black"])
        kit.G["bezel"].append(o)
    ring, teeth = lib.knurl_ring(0.0111, 0.0145, 0.003, -0.0050, C["zinc"] if metal else C["black"])
    kit.G["ring_nut"] += [ring, teeth]
    bm = C["zinc"] if metal else C["black"]
    B(-15, 15, -15, 15, -12, -10, bm, "base", bw=0.5)                 # front plate of base
    for s in (-1, 1):
        B(s * 15 - (1.6 if s > 0 else 0) + (0 if s > 0 else 0), s * 15 + (0 if s > 0 else 1.6), -15, 15, -24, -10, bm, "base", bw=0.4) if False else None
        B(min(s * 13.4, s * 15), max(s * 13.4, s * 15), -15, 15, -22, -10, bm, "base", bw=0.4)   # side cheeks
    CYL(1.8, -21, -9.5, -9, 15.8, C["steel"], "base", axis="Z", bw=0.2, verts=24)  # clamp screw
    CYL(2.6, -10, -8.5, -9, 15.8, C["steel"], "base", axis="Z", bw=0.3, verts=24)
    xs = [0.0] if len(blocks) == 1 else [-5.3, 5.3]
    for x, (kind, n1, n2) in zip(xs, blocks):
        b = B(x - 5.1, x + 5.1, -15, 15, -54, -22, C["black"], "block", bw=0.6)
        for z, n in ((-27.5, n1), (-48.5, n2)):
            cut(b, cbox(x - 4, x + 4, -16.5, -12.5, z - 4, z + 4))
            screw(x, -13.6, z, "-Y", M, n, "block", scale=0.8)
            T(n, x, -15.06, z + (6.0 if z > -38 else -6.0), 2.4, C["ink"], "block")
        mark = C["green"] if kind == "NO" else C["red"]
        B(x - 3.5, x + 3.5, -15.3, -14.9, -40, -36, mark, "block", bw=0.1)
        T(kind, x, -15.36, -38.0, 2.0, C["ink"], "block")
        txt = T(("EB-BE101" if kind == "NO" else "EB-BE102"), x + 5.16, 0, -38, 2.1, C["ink"], "block", rot=(90, 0, 90))
        # internals: plunger, bridge, fixed contacts, spring
        B(x - 2.0, x + 2.0, -2, 2, -40, -20, C["white"], "block_contacts", bw=0.3)
        zb = -34 if kind == "NO" else -30
        B(x - 1.6, x + 1.6, -9, 9, zb - 0.6, zb + 0.6, C["copper"], "block_contacts", bw=0.2)
        for y in (-7, 7):
            CYL(1.1, zb + 0.6, zb + 1.3, x, y, C["silver"], "block_contacts", axis="Z", bw=0.1)
            B(x - 1.5, x + 1.5, y - 2, y + 2, zb + 1.3 + (2 if kind == "NO" else 0), zb + 2.4 + (2 if kind == "NO" else 0), C["copper"], "block_contacts", bw=0.2)
        helix("block_contacts", (x, 0, -46), 9, 1.8, 6, 0.3, C["steel"], axis="Z")


# ------------------------------------------------------------------ variants
def build_pb(M, color="green", metal=True, extended=False):
    C = mats(M, metal)
    cap_m = C["green"] if color == "green" else C["red"]
    if metal:
        o = CYL(14.9, 0, 6.0, 0, 0, C["chrome"], "bezel", axis="Z", bw=1.8, verts=96)
        cut(o, ccyl(12.4, -2, 10, 0, 0, axis="Z", verts=96))
    else:
        ring, teeth = lib.knurl_ring(0.0124, 0.0150, 0.0065, 0.0, C["black"], teeth=40)
        kit.G["bezel"] += [ring, teeth]
    if extended:
        CYL(11.6, 1.0, 13.0, 0, 0, cap_m, "cap", axis="Z", bw=2.4, verts=96)
    else:
        CYL(11.8, 1.0, 6.4, 0, 0, cap_m, "cap", axis="Z", bw=1.6, verts=96)
    CYL(4.0, -9, 1, 0, 0, C["white"], "head_spring", axis="Z", bw=0.3)
    helix("head_spring", (0, 0, -3), 8, 6.0, 5, 0.5, C["steel"], axis="Z")
    kind = ("NO", "3", "4") if color == "green" else ("NC", "1", "2")
    rear(C, M, [kind], metal)


def build_estop(M, key=False):
    C = mats(M, False)
    o = CYL(16, 0, 8, 0, 0, C["black"], "bezel", axis="Z", bw=1.5, verts=96)
    CYL(20, 9, 19, 0, 0, C["red"], "cap", axis="Z", bw=4.5, verts=128)
    CYL(10, 7, 10, 0, 0, C["red"], "cap", axis="Z", bw=0.8)
    if key:
        CYL(5.5, 18.5, 20.5, 0, 0, C["chrome"], "cap", axis="Z", bw=0.6)
        B(-0.9, 0.9, -3.0, 3.0, 20.0, 20.8, C["black"], "cap", bw=0.2)
        B(-1.2, 1.2, -6, 6, 20.4, 34, C["satin"], "cap", bw=0.5)
        B(-1.6, 1.6, -9, 9, 30, 40, C["black"], "cap", bw=1.5)
    else:
        CYL(11, 18.8, 19.4, 0, 0, C["yellow"], "cap", axis="Z", bw=0.2, verts=64)
        T("STOP", 0, -1.5, 19.5, 4.0, C["dark_ink"], "cap", rot=(0, 0, 0))
        for s in (-1, 1):
            B(-4, 4, s * 7.5 - 0.6, s * 7.5 + 0.6, 19.0, 19.6, C["dark_ink"], "cap", bw=0.1)
    B(-6, 6, -6, 6, -8, 8, C["white"], "head_spring", bw=0.4)
    helix("head_spring", (0, 0, 0), 10, 7.5, 5, 0.6, C["steel"], axis="Z")
    rear(C, M, [("NC", "1", "2"), ("NC", "1", "2")] if key else [("NC", "1", "2")], metal=False)


def build_selector(M):
    C = mats(M, True)
    o = CYL(14.9, 0, 6.0, 0, 0, C["chrome"], "bezel", axis="Z", bw=1.8, verts=96)
    cut(o, ccyl(12.4, -2, 10, 0, 0, axis="Z", verts=96))
    CYL(12.0, 0.5, 6.0, 0, 0, C["black"], "cap", axis="Z", bw=1.0, verts=96)
    lever = B(-3.8, 3.8, -11.5, 11.5, 5.5, 16, C["black"], "cap", bw=2.6)
    B(-0.6, 0.6, -10.5, -4, 15.9, 16.3, C["white"], "cap", bw=0.1)
    for o in kit.G["cap"][-2:]:
        o.rotation_euler = (0, 0, math.radians(-45))
    CYL(5.0, -9, 0.5, 0, 0, C["white"], "head_spring", axis="Z", bw=0.4)
    B(-1, 1, -8, 8, -6, -4, C["steel"], "head_spring", bw=0.2)
    rear(C, M, [("NO", "3", "4"), ("NO", "3", "4")], True)


def build_double(M):
    C = mats(M, False)
    B(-17, 17, -26, 26, 0, 7, C["grey"], "bezel", bw=1.5)
    B(-14.5, 14.5, 1.5, 23.5, 3, 8.5, C["red"], "cap", bw=1.2)
    B(-14.5, 14.5, -23.5, -1.5, 3, 8.5, C["green"], "cap", bw=1.2)
    o = lib.torus(0.0055, 0.0009, 0.0087, C["red"])
    o.location = (0, 0.0125, 0.0087)
    kit.G["cap"].append(o)
    B(-0.9, 0.9, -18, -7, 8.4, 9.2, C["green"], "cap", bw=0.2)
    CYL(4, -9, 0.5, 0, 0, C["white"], "head_spring", axis="Z", bw=0.3)
    rear(C, M, [("NC", "1", "2"), ("NO", "3", "4")], False)


def build_lamp(M, color=(0.02, 0.9, 0.08), on=True):
    C = mats(M, False)
    L = lib.lens(color, on)
    CYL(14.0, 0, 4.0, 0, 0, C["black"], "bezel", axis="Z", bw=1.2, verts=96)
    CYL(11.6, 2, 7.0, 0, 0, L, "lens", axis="Z", bw=2.0, verts=96)
    CYL(9.0, 0.5, 1.5, 0, 0, C["pcb"], "led", axis="Z", bw=0.2)
    for x, y in ((-3, -3), (3, -3), (-3, 3), (3, 3), (0, 0)):
        CYL(1.2, 1.5, 2.6, x, y, lib.mat("d_led", (0.9, 0.95, 0.9), rough=0.2, trans=0.5), "led", axis="Z", bw=0.3, verts=16)
    CYL(10.9, -30, 0, 0, 0, C["black"], "body", axis="Z", bw=0.8, verts=64)
    for i in range(10):
        kit.G["body"].append(lib.torus(0.0109, 0.0003, -0.002 - i * 0.0012, C["black"]))
    ring, teeth = lib.knurl_ring(0.0111, 0.0142, 0.0035, -0.0055, C["black"])
    kit.G["nut"] += [ring, teeth]
    B(-9, 9, -8, 8, -38, -30, C["black"], "body", bw=1.0)
    for x, n in ((-4.5, "X1"), (4.5, "X2")):
        screw(x, -8.6, -34, "-Y", M, n, "body", scale=0.75)
        T(n, x, -8.06, -30.6, 1.8, C["ink"], "body")
    T("AC/DC 230V", 0, -11.0, -20, 1.8, C["ink"], "body", rot=(90, 0, 0))
    B(-6, 6, -1, 1, -28, -12, C["pcb"], "driver", bw=0.2)
    CYL(1.2, -4, 4, -2, -22, lib.mat("d_res", (0.75, 0.62, 0.40), rough=0.5), "driver", axis="X", bw=0.3)
    CYL(2.5, 1, 6, 2.5, -17, lib.mat("d_cap", (0.1, 0.2, 0.6), rough=0.4), "driver", axis="Y", bw=0.4)
    if on:
        import bpy
        bpy.ops.object.light_add(type="POINT", location=(0, 0, 0.012))
        l = bpy.context.object
        l.name = "_glow"
        l.data.energy = 0.12
        l.data.color = color


def build_station(M, holes=2, estop_box=False):
    C = mats(M, False)
    L = 70.0 * holes if not estop_box else 72.0
    top_m = C["yellow"] if estop_box else C["white"]
    bot_m = C["black"] if estop_box else C["grey"]
    body = B(-36, 36, -L / 2, L / 2, -42, -6, bot_m, "body", bw=2.5)
    cut(body, cbox(-33, 33, -L / 2 + 3, L / 2 - 3, -40, 0))
    cover = B(-36, 36, -L / 2, L / 2, -6, 8, top_m, "cover", bw=2.5)
    cut(cover, cbox(-33, 33, -L / 2 + 3, L / 2 - 3, -8, 5))
    B(-34, 34, -L / 2 + 1.2, L / 2 - 1.2, -6.8, -5.6, lib.mat("d_gasket", (0.05, 0.05, 0.05), rough=0.8), "gasket", bw=0.3)
    ys = [(-L / 2 + 35 + 70 * i) for i in range(holes)] if not estop_box else [0]
    for y in ys:
        cut(cover, ccyl(11.2, 0, 12, 0, y, axis="Z"))
        if not estop_box:
            B(-11, 11, y - 25, y - 19, 8, 8.4, C["white"], "cover", bw=0.2)   # legend plate
    for x in (-31, 31):
        for y in (-L / 2 + 5, L / 2 - 5):
            CYL(2.4, 7.5, 9.0, x, y, C["steel"], "screws", axis="Z", bw=0.4, verts=24)
            CYL(0.9, -6, 7.5, x, y, C["steel"], "screws", axis="Z", bw=0.1, verts=12)
    CYL(9, -L / 2 - 8, -L / 2, 0, -26, C["grey"], "gland", axis="Y", bw=1.0)
    CYL(10, -L / 2 - 12, -L / 2 - 8, 0, -26, C["grey"], "gland", axis="Y", bw=1.0, verts=6)
    if estop_box:
        T("EMERGENCY", 0, -26, 8.1, 6.0, C["dark_ink"], "cover", rot=(0, 0, 0))
        CYL(20, 8, 20, 0, 0, C["red"], "cover", axis="Z", bw=4.5, verts=128)


class V:
    def __init__(self, parts, fn, **kw):
        self.PARTS, self.fn, self.kw = parts, fn, kw

    def build(self, M):
        self.fn(M, **self.kw)


VARIANTS = {
    "pb_green_metal":   (V(PB_PARTS, build_pb, color="green", metal=True), True),
    "pb_red_plastic":   (V(PB_PARTS, build_pb, color="red", metal=False), False),
    "pb_green_extended": (V(PB_PARTS, build_pb, color="green", metal=True, extended=True), False),
    "estop":            (V(ESTOP_PARTS, build_estop), True),
    "estop_key":        (V(ESTOP_PARTS, build_estop, key=True), False),
    "selector":         (V(SEL_PARTS, build_selector), True),
    "pb_double":        (V(PB_PARTS, build_double), False),
    "lamp_green":       (V(LAMP_PARTS, build_lamp, color=(0.02, 0.9, 0.08), on=True), True),
    "lamp_red":         (V(LAMP_PARTS, build_lamp, color=(1.0, 0.04, 0.02), on=True), False),
    "lamp_amber":       (V(LAMP_PARTS, build_lamp, color=(1.0, 0.45, 0.0), on=False), False),
    "station_2":        (V(STATION_PARTS, build_station, holes=2), True),
    "station_3":        (V(STATION_PARTS, build_station, holes=3), False),
    "estop_box":        (V(STATION_PARTS, build_station, holes=1, estop_box=True), False),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, expl = VARIANTS[n]
        st = n.startswith("station") or n == "estop_box"
        modes = ["assembled", "exploded"] if expl else ["assembled"]
        if len(sys.argv) > 2:
            modes = sys.argv[2].split(",")
        cam_a = dict(target=(0, 0, -0.012 if not st else -0.015), dist=0.17 if not st else 0.30 + (0.06 if n == "station_3" else 0), elev=24, azim=-35, lens_mm=60)
        cam_e = dict(target=(0, -0.020, -0.022 if not st else -0.004), dist=0.50 if not st else 0.5, elev=16, azim=-40, lens_mm=50)
        kit.run(n, mod, cam_a, cam_e, modes)
