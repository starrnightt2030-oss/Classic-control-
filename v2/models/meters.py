"""Measuring & protection devices, main switches, fuse holder. Front -Y, Z up, mm.
Run: python meters.py <variant|all> [modes]"""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib, din
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw


def C_(M):
    return dict(
        black=lib.mat("m_black", (0.02, 0.02, 0.022), rough=0.45, bump=0.25),
        white=lib.mat("m_white", (0.86, 0.86, 0.84), rough=0.5),
        glass=lib.mat("m_glass", (0.9, 0.92, 0.95), rough=0.02, trans=0.95, ior=1.5),
        red=lib.mat("m_red", (0.7, 0.02, 0.01), rough=0.4),
        ink=lib.mat("m_ink", (0.03, 0.03, 0.04), rough=0.6),
        winkt=lib.mat("m_wink", (0.9, 0.9, 0.9), rough=0.6),
        brass=lib.mat("m_brass", (0.82, 0.68, 0.38), metal=1.0, rough=0.25),
        steel=lib.mat("m_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        copper=lib.mat("m_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        winding=kit.striped("m_wind", (0.80, 0.40, 0.18), 1.0, 0.25, "Z", 1200.0, 0.4),
        iron=lib.mat("m_iron", (0.35, 0.36, 0.38), metal=0.9, rough=0.4),
        silver=lib.mat("m_plate", (0.78, 0.79, 0.81), metal=1.0, rough=0.35),
        blue=lib.mat("m_blue", (0.02, 0.15, 0.6), rough=0.4, bump=0.2),
        yellow=lib.mat("m_yellow", (0.85, 0.55, 0.0), rough=0.4),
        orange=lib.mat("m_orange", (0.95, 0.35, 0.02), rough=0.4),
        lcd=lib.mat("m_lcd", (0.55, 0.65, 0.62), rough=0.3),
        led_red=lib.mat("m_7seg_r", (1, 0.05, 0.02), rough=0.3, emit=((1, 0.05, 0.02), 6.0)),
        led_yel=lib.mat("m_7seg_y", (1, 0.75, 0.05), rough=0.3, emit=((1, 0.75, 0.05), 6.0)),
        led_grn=lib.mat("m_led_g", (0.05, 0.9, 0.1), rough=0.3, emit=((0.05, 1, 0.1), 4.0)),
        dark=lib.mat("m_dark", (0.05, 0.052, 0.056), rough=0.45, bump=0.2),
        ceramic=lib.mat("m_ceramic", (0.88, 0.86, 0.80), rough=0.6),
        sand=lib.mat("m_sand", (0.85, 0.80, 0.68), rough=0.95, bump=1.0),
    )


def rot0(o, e):
    lib._sel(o)
    bpy.ops.object.transform_apply(location=True)
    o.rotation_euler = e
    return o


# ---------------------------------------------------------------- analog panel meter 72x72
METER_PARTS = {
    "bezel":    ("الإطار والعلبة", "Bezel & case", (0, 30, 0)),
    "glass":    ("الزجاج الأمامي", "Front window", (0, -60, 0)),
    "scale":    ("لوحة التدريج", "Scale plate", (0, -42, 0)),
    "pointer":  ("المؤشر", "Pointer", (0, -50, 22), (0, -9, -4)),
    "movement": ("آلية الحديد المتحرك والملف", "Moving-iron movement & coil", (0, -18, -30), (0, 6, -14)),
    "zero":     ("مسمار ضبط الصفر", "Zero adjuster", (0, -66, -30), (0, -12, -30)),
    "terminals": ("ترامل التوصيل", "Connection studs", (0, 60, 0)),
}


def build_meter(M, kind="A"):
    C = C_(M)
    bz = B(-36, 36, -12, -6, -36, 36, C["black"], "bezel", bw=1.5)
    cut(bz, cbox(-31, 31, -14, -4, -31, 31))
    case = B(-33, 33, -6, 40, -33, 33, C["black"], "bezel", bw=1.5)
    B(-31, 31, -10.5, -10, -31, 31, C["glass"], "glass", bw=0.3)
    B(-30, 30, -8, -7.2, -30, 30, C["white"], "scale", bw=0.2)
    B(-30, 30, -8.2, -7.9, -30, -14, C["black"], "scale", bw=0.1)              # lower dark band (movement cover)
    rng = ["0", "20", "40", "60", "80", "100"] if kind == "A" else ["0", "100", "200", "300", "400", "500"]
    for i, v in enumerate(rng):
        a = math.radians(140 - i * 20)
        T(v, 26 * math.cos(a), -8.06, -10 + 26 * math.sin(a), 3.0, C["ink"], "scale")
        for k in range(5 if i < 5 else 1):
            aa = math.radians(140 - i * 20 - k * 4)
            o = B(-0.25, 0.25, -8.1, -8.0, 0, 3.5 if k == 0 else 2.0, C["ink"], "scale", bw=0.02)
            rot0(o, (0, -(math.pi / 2 - aa), 0))
            o.location = (0.021 * math.cos(aa), 0, -0.010 + 0.021 * math.sin(aa))
    T(kind, 0, -8.06, 3, 7, C["ink"], "scale")
    T("~  1.5  ⊥", 18, -8.06, -11, 2.4, C["ink"], "scale") if False else None
    T("CL 1.5", 18, -8.06, -11, 2.4, C["winkt"], "scale")
    T("100/5A" if kind == "A" else "0-500V", -16, -8.06, -11, 2.4, C["winkt"], "scale")
    p = B(-0.5, 0.5, -9.2, -8.6, -10, 22, C["red"], "pointer", bw=0.1)
    rot0(p, (0, math.radians(-28), 0))
    p.location = (0, 0, -0.010)
    CYL(2.2, -9.4, -8.3, 0, -10, C["black"], "pointer", bw=0.3)
    CYL(9, -4, 20, 0, -12, C["winding"], "movement", bw=1.0)
    B(-4, 4, 2, 14, -18, -6, C["iron"], "movement", bw=0.5)
    helix("movement", (0, -3, -12), 2, 2.5, 3, 0.15, C["brass"], axis="Y")
    CYL(2.5, -12.5, -10.2, 0, -30, C["black"], "zero", bw=0.5)
    B(-1.5, 1.5, -12.6, -12.4, -30.3, -29.7, C["winkt"], "zero", bw=0.05)
    for x in (-14, 14):
        CYL(3, 40, 52, x, 0, C["brass"], "terminals", bw=0.3)
        CYL(5, 44, 47, x, 0, C["brass"], "terminals", bw=0.4, verts=6)


# ---------------------------------------------------------------- current transformer (window type)
CT_PARTS = {
    "case":     ("العلبة العازلة", "Insulating case", (0, 0, 0)),
    "core":     ("القلب الحلقي", "Toroidal core", (0, -40, 0)),
    "winding":  ("الملف الثانوي", "Secondary winding", (0, -60, 0)),
    "terminals": ("ترامل الثانوي S1 و S2", "Secondary terminals S1 / S2", (0, 0, 30)),
}


def build_ct(M):
    C = C_(M)
    o = B(-35, 35, -16, 16, -40, 40, C["dark"], "case", bw=4.0)
    cut(o, cbox(-15, 15, -20, 20, -15, 15))
    B(-20, 20, -16.6, -16, 18, 34, C["white"], "case", bw=0.3)
    T("CT 100/5A", 0, -16.66, 30, 3.4, C["ink"], "case")
    T("5VA  CL 0.5", 0, -16.66, 25, 2.6, C["ink"], "case")
    T("P1 →", 0, -16.66, 20.5, 2.6, C["ink"], "case")
    t = lib.torus(0.024, 0.006, 0, C["iron"])
    t.rotation_euler = (math.radians(90), 0, 0)
    kit.G["core"].append(t)
    for k in range(36):
        a = 2 * math.pi * k / 36
        o = lib.torus(0.0065, 0.0006, 0, C["winding"])
        o.rotation_euler = (0, a, 0)
        o.location = (0.024 * math.cos(a), 0, 0.024 * math.sin(a))
        kit.G["winding"].append(o)
    for x, lab in ((-12, "S1"), (12, "S2")):
        B(x - 6, x + 6, -10, 10, 40, 47, C["dark"], "terminals", bw=1.0)
        screw(x, -8.5, 43.5, "-Y", M, lab, "terminals", scale=0.8)
        T(lab, x, -10.06, 48.5, 2.6, C["winkt"], "terminals")


# ---------------------------------------------------------------- cam switch 1-0-2 / voltmeter selector / isolator
CAM_PARTS = {
    "front_plate": ("اللوحة الأمامية", "Front escutcheon plate", (0, -40, 0)),
    "knob":        ("المقبض", "Handle", (0, -66, 0)),
    "shaft":       ("العمود وآلية الطقة", "Shaft & detent mechanism", (0, -20, 34)),
    "decks":       ("طوابق النقط (الكامات)", "Contact decks (cams)", (0, 24, 0)),
    "terminals":   ("ترامل التوصيل", "Terminals", (0, 40, -40)),
}


def build_cam(M, positions=("1", "0", "2"), decks=3, isolator=False, volt=False):
    C = C_(M)
    if isolator:
        B(-33, 33, -8, -4, -33, 33, C["yellow"], "front_plate", bw=1.0)
        CYL(10, -12, -8, 0, 0, C["red"], "knob", bw=1.0)
        B(-6, 6, -22, -12, -28, 10, C["red"], "knob", bw=2.5)
        T("0", -18, -8.06, 22, 6, C["ink"], "front_plate")
        T("I", 18, -8.06, 22, 6, C["ink"], "front_plate")
        T("OFF", -18, -8.06, 14, 3, C["ink"], "front_plate")
        T("ON", 18, -8.06, 14, 3, C["ink"], "front_plate")
    else:
        B(-33, 33, -6, -2, -33, 33, C["black"], "front_plate", bw=1.5)
        B(-29, 29, -6.4, -5.8, -29, 29, C["silver"], "front_plate", bw=0.3)
        n = len(positions)
        for i, p in enumerate(positions):
            a = math.radians(90 + (i - (n - 1) / 2) * (-90 if n <= 3 else -45))
            T(p, 21 * math.cos(a), -6.46, 21 * math.sin(a) - 2, 4.5 if len(p) < 3 else 2.6, C["ink"], "front_plate")
        CYL(12, -12, -6, 0, -2, C["black"], "knob", bw=1.0, verts=64)
        B(-6, 6, -22, -12, -24, 10, C["black"], "knob", bw=2.5)
        B(-1, 1, -22.2, -21.8, 2, 8, C["white"], "knob", bw=0.1)
    CYL(3, -6, 70, 0, 0, C["steel"], "shaft", bw=0.4)
    B(-14, 14, -2, 6, -14, 14, C["black"], "shaft", bw=1.0)
    deck_m = C["blue"] if not isolator else C["dark"]
    for d in range(decks):
        y0 = 6 + d * 16
        B(-24, 24, y0, y0 + 15.5, -22, 22, deck_m, "decks", bw=1.2)
        CYL(8, y0 + 3, y0 + 12, 0, 0, C["white"], "decks", bw=0.6, verts=6)
        for s in (-1, 1):
            B(-20, 20, y0 + 2, y0 + 13.5, s * 22, s * 26, deck_m, "decks", bw=0.8)
            for x in (-11, 11):
                screw(x, y0 + 7.8, s * 26 + s * 0.6, "+Z" if s > 0 else "-Z", M, str(4 * d + (1 if x < 0 else 2) + (0 if s > 0 else 2)), "terminals", scale=0.7)
        T("%d %d" % (4 * d + 1, 4 * d + 2), 0, y0 + 7.8, 26.1, 2.2, C["winkt"], "decks", rot=(0, 0, 0))


# ---------------------------------------------------------------- DIN electronic devices
def build_kwh(M):
    C = C_(M)
    W, body, ink = din.housing(M, "case", n=2, top=("1", "4"), bot=("3", "6"), front_y=-28)
    B(-14, 14, -28.4, -27.8, 4, 18, C["lcd"], "case", bw=0.4)
    T("000123.4", 0, -28.46, 13.5, 3.6, C["ink"], "case")
    T("231.6 V   kWh", 0, -28.46, 7.5, 2.4, C["ink"], "case")
    T("EKW-80  5(80)A  1600imp/kWh", 0, -28.06, -4, 1.4, C["ink"], "case")
    CYL(1.1, -28.6, -27.6, -10, -12, C["led_red"], "case", bw=0.2, verts=16)
    T("PULSE", -2, -28.06, -12, 1.6, C["ink"], "case")


def build_avr(M):
    C = C_(M)
    W, body, ink = din.housing(M, "case", n=2, top=("N", "L"), bot=("N", "L"), front_y=-28)
    for z, txt, m in ((11, "230", C["led_red"]), (2, "12.5", C["led_yel"])):
        B(-11, 13, -28.4, -27.8, z - 3.5, z + 3.5, C["black"], "case", bw=0.3)
        T(txt, 1, -28.46, z, 5.0, m, "case")
    for z, lab in ((14, "U>"), (10, "U<"), (6, "A>")):
        CYL(0.9, -28.5, -27.6, -14.5, z, C["led_red"], "case", bw=0.1, verts=12)
    for i, x in enumerate((-12, -4, 4, 12)):
        CYL(2.6, -29.5, -27.6, x, -10, C["blue"], "case", bw=0.8)
    T("V-A PROTECTOR 63A", 0, -28.06, -16.5, 1.6, C["ink"], "case")


def build_phase_relay(M, pmv=False):
    C = C_(M)
    col = (0.86, 0.86, 0.84) if pmv else (0.10, 0.11, 0.12)
    W, body, ink = din.housing(M, "case", n=2 if pmv else 1, color=col, top=("L1", "L2", "L3") if True else (),
                               bot=("11", "12", "14") if not pmv else ("11", "12", "14", "N"), front_y=-28,
                               ink=None if pmv else C["winkt"])
    knob_m = C["orange"] if pmv else C["white"]
    xs = [(-7, 14), (7, 14), (-7, 2), (7, 2), (-7, -10), (7, -10)] if pmv else [(0, 14), (0, 6), (0, -2)]
    for x, z in xs:
        CYL(2.8, -29.6, -27.6, x, z, knob_m, "case", bw=0.6)
        B(x - 0.3, x + 0.3, -29.8, -29.5, z - 2, z + 2, C["black"] if pmv else C["ink"], "case", bw=0.03)
    CYL(0.9, -28.5, -27.6, 0 if not pmv else 13, -12 if not pmv else 18, C["led_grn"], "case", bw=0.1, verts=12)
    CYL(0.9, -28.5, -27.6, 4 if not pmv else 13, -12 if not pmv else 14, C["led_red"], "case", bw=0.1, verts=12)
    T("PMV-50" if pmv else "EPR-3", 0, -28.06, 20, 1.6, C["ink"] if pmv else C["winkt"], "case")


def build_counter(M):
    C = C_(M)
    B(-24, 24, -6, 60, -24, 24, C["black"], "case", bw=1.5)
    B(-24, 24, -10, -6, -24, 24, C["dark"], "case", bw=1.2)
    B(-20, 20, -10.5, -10, 2, 18, C["black"], "case", bw=0.3)
    T("001250", 0, -10.56, 10, 7.5, C["led_red"], "case")
    for x, lab in ((-12, "RST"), (0, "▲"), (12, "SET")):
        B(x - 4.5, x + 4.5, -11.5, -10, -18, -10, C["dark"], "case", bw=0.8)
        T(lab if lab != "▲" else "UP", x, -11.56, -14, 2.0, C["winkt"], "case")
    T("COUNTER", 0, -10.06, -4, 2.4, C["winkt"], "case")


# ---------------------------------------------------------------- fuse holder + cartridge fuse 10x38
FUSE_PARTS = {
    "holder":   ("جسم حامل الفيوز", "Fuse-holder base", (0, 30, 0)),
    "carrier":  ("الدرج القلاب", "Hinged fuse carrier", (0, -40, 30)),
    "fuse":     ("فيوز الخرطوشة 10x38", "Cartridge fuse 10x38", (0, -70, 30), (0, -14, 4)),
    "element":  ("سلك الانصهار والرمل", "Fuse element & quartz sand", (0, -100, 30), (0, -14, 4)),
    "clips":    ("أقطاب التلامس", "Contact clips", (0, -10, 60)),
}


def build_fuse(M):
    C = C_(M)
    W, body, ink = din.housing(M, "holder", n=1, top=("1",), bot=("2",), front_y=-18)
    car = B(-8.6, 8.6, -30, -18, -30, 30, lib.mat("fz_car", (0.85, 0.85, 0.83), rough=0.45), "carrier", bw=1.2)
    B(-5, 5, -31, -29.6, 20, 26, lib.mat("fz_tab", (0.02, 0.02, 0.022), rough=0.45), "carrier", bw=0.5)
    T("10x38", 0, -30.06, -24, 1.8, C["ink"], "carrier")
    T("gG 10A", 0, -30.06, -20.5, 1.8, C["ink"], "carrier")
    CYL(0.9, -30.6, -29.6, 0, 14, C["led_red"], "carrier", bw=0.1, verts=12)
    # cartridge fuse along Z
    CYL(5.0, -14, 14, 0, -14, C["ceramic"], "fuse", axis="Z", bw=0.6)
    for z0, z1 in ((-19, -14), (14, 19)):
        CYL(5.2, z0, z1, 0, -14, C["silver"], "fuse", axis="Z", bw=0.8)
    T("10A gG 500V", 0, -19.1, 0, 2.0, C["ink"], "fuse", rot=(90, 0, 0)) if False else None
    CYL(4.0, -13, 13, 0, -14, C["sand"], "element", axis="Z", bw=0.5)
    B(-1.6, 1.6, -14.2, -13.8, -13, 13, C["copper"], "element", bw=0.05)
    for z in (-14, 14):
        B(-3, 3, -14 - 3, -14 + 3, z - 1.2 if z < 0 else z + 0.2, z + 1.2 if z > 0 else z - 0.2, C["copper"], "clips", bw=0.3) if False else None
        B(-3.5, 3.5, -18.5, -9.5, (z * 1.4) - 1, (z * 1.4) + 1, C["copper"], "clips", bw=0.3)


class V:
    def __init__(self, parts, fn, **kw):
        self.PARTS, self.fn, self.kw = parts, fn, kw

    def build(self, M):
        self.fn(M, **self.kw)


GEN = {"case": ("الجسم", "Case", (0, 0, 0))}
VARIANTS = {
    "ammeter":          (V(METER_PARTS, build_meter, kind="A"), True, (0, 0.004, 0), 0.24),
    "voltmeter":        (V(METER_PARTS, build_meter, kind="V"), False, (0, 0.004, 0), 0.24),
    "current_transformer": (V(CT_PARTS, build_ct), True, (0, 0, 0.004), 0.28),
    "cam_switch":       (V(CAM_PARTS, build_cam), True, (0, 0.010, 0), 0.30),
    "voltmeter_selector": (V(CAM_PARTS, build_cam, positions=("0", "L1-N", "L2-N", "L3-N", "L1-L2", "L2-L3", "L3-L1"), decks=2), False, (0, 0.006, 0), 0.28),
    "main_isolator":    (V(CAM_PARTS, build_cam, decks=3, isolator=True), False, (0, 0.010, 0), 0.30),
    "kwh_meter":        (V(GEN, build_kwh), False, (0, -0.006, 0), 0.26),
    "va_protector":     (V(GEN, build_avr), False, (0, -0.006, 0), 0.26),
    "phase_relay":      (V(GEN, build_phase_relay), False, (0, -0.006, 0), 0.24),
    "voltage_monitor":  (V(GEN, build_phase_relay, pmv=True), False, (0, -0.006, 0), 0.26),
    "counter":          (V(GEN, build_counter), False, (0, 0.006, 0), 0.22),
    "fuse_holder":      (V(FUSE_PARTS, build_fuse), True, (0, -0.006, 0), 0.24),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, expl, tgt, dist = VARIANTS[n]
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else (["assembled", "exploded"] if expl else ["assembled"])
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=18, azim=-32, lens_mm=60),
                dict(target=(tgt[0], -0.014, tgt[2] + 0.004), dist=dist * 2.2, elev=16, azim=-42, lens_mm=50), modes)
