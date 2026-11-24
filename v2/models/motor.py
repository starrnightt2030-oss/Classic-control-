"""Three-phase squirrel-cage induction motor (TEFC, IEC frame ~100), with terminal box (star / delta links).
Shaft along -X (drive end), Z up, front -Y. mm.  Run: python motor.py <variant|all> [modes]"""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

PARTS = {
    "frame":        ("جسم الموتور (الهيكل بالزعانف والرجول)", "Frame with cooling fins & feet", (0, 0, 0)),
    "stator":       ("العضو الثابت (الإستاتور) والملفات", "Stator core & windings", (0, -150, 0)),
    "rotor":        ("العضو الدوار (القفص السنجابي)", "Squirrel-cage rotor", (-40, -150, -150)),
    "shaft":        ("العمود والخابور", "Shaft & key", (-150, -150, -150)),
    "bearings":     ("رولمان البلي", "Ball bearings", (-90, -150, -110)),
    "end_shield_de": ("الغطاء الأمامي (جهة الحمل)", "Drive-end shield", (-150, 0, 0)),
    "end_shield_nde": ("الغطاء الخلفي", "Non-drive-end shield", (110, 0, 0)),
    "fan":          ("المروحة", "Cooling fan", (170, 0, 0)),
    "fan_cover":    ("غطاء المروحة", "Fan cowl", (240, 0, 0)),
    "terminal_box": ("علبة الترامل", "Terminal box", (0, 0, 110)),
    "nameplate":    ("لوحة البيانات", "Nameplate", (0, -60, 0), (0, -66, 10)),
}


def C_(M):
    return dict(
        paint=lib.mat("mo_paint", (0.03, 0.12, 0.30), metal=0.3, rough=0.45, bump=0.4),
        lam=kit.striped("mo_lam", (0.40, 0.41, 0.43), 0.9, 0.4, "X", 900.0, 0.4),
        copper=lib.mat("mo_cu", (0.85, 0.42, 0.20), metal=1.0, rough=0.3),
        alu=lib.mat("mo_alu", (0.78, 0.79, 0.81), metal=1.0, rough=0.35),
        steel=lib.mat("mo_steel", (0.70, 0.70, 0.72), metal=1.0, rough=0.25),
        black=lib.mat("mo_black", (0.03, 0.03, 0.03), rough=0.5),
        plate=lib.mat("mo_plate", (0.80, 0.80, 0.82), metal=1.0, rough=0.4),
        ink=lib.mat("mo_ink", (0.03, 0.03, 0.04), rough=0.6),
        brass=lib.mat("mo_brass", (0.82, 0.68, 0.38), metal=1.0, rough=0.25),
        board=lib.mat("mo_board", (0.08, 0.08, 0.09), rough=0.5),
    )


def build(M, cutaway=False, single=False):
    C = C_(M)
    # frame + fins + feet
    fr = CYL(62, -80, 80, 0, 0, C["paint"], "frame", axis="X", bw=2.0, verts=96)
    cut(fr, ccyl(58.5, -82, 82, 0, 0, axis="X", verts=96))
    for k in range(26):
        a = math.radians(-60 + k * (300 / 25))
        if -100 < math.degrees(a) - 270 < -80:
            continue
        o = B(-78, 78, -1.5, 1.5, 60, 72, C["paint"], "frame", bw=0.8)
        lib._sel(o)
        bpy.ops.object.transform_apply(location=True)
        o.rotation_euler = (a, 0, 0)
    for x in (-55, 55):
        f = B(x - 18, x + 18, -70, 70, -78, -62, C["paint"], "frame", bw=1.5)
        for y in (-58, 58):
            cut(f, ccyl(5, -80, -60, x, y, axis="Z"))
    CYL(8, 62, 74, 0, 0, C["steel"], "frame", axis="Z", bw=1.0) if False else None
    eb = lib.torus(0.010, 0.0025, 0, C["steel"])
    eb.rotation_euler = (math.radians(90), 0, 0)
    eb.location = (-0.045, 0, 0.086)
    kit.G["frame"].append(eb)
    CYL(4, 70, 76, -45, 0, C["steel"], "frame", axis="Z", bw=0.5)
    # stator core + end windings
    st = CYL(58, -55, 55, 0, 0, C["lam"], "stator", axis="X", bw=0.4, verts=96)
    cut(st, ccyl(36.5, -60, 60, 0, 0, axis="X", verts=96))
    for x in (-60, 60):
        t = lib.torus(0.047, 0.009, 0, C["copper"])
        t.rotation_euler = (0, math.radians(90), 0)
        t.location = (x * 0.001, 0, 0)
        kit.G["stator"].append(t)
    # rotor
    rt = CYL(35.5, -55, 55, 0, 0, C["lam"], "rotor", axis="X", bw=0.4, verts=96)
    for x in (-57, 57):
        CYL(36, x - 3, x + 3, 0, 0, C["alu"], "rotor", axis="X", bw=0.8, verts=96)
    for k in range(20):
        a = 2 * math.pi * k / 20
        o = B(-55, 55, -1.2, 1.2, 34.6, 36.0, C["alu"], "rotor", bw=0.1)
        lib._sel(o)
        bpy.ops.object.transform_apply(location=True)
        o.rotation_euler = (a + math.radians(4), math.radians(0), 0)
    # shaft + key + bearings
    CYL(12, -150, 128, 0, 0, C["steel"], "shaft", axis="X", bw=0.8, verts=64)
    B(-145, -105, -2.5, 2.5, 10.5, 13.5, C["steel"], "shaft", bw=0.3)
    for x in (-88, 88):
        o = CYL(24, x - 8, x + 8, 0, 0, C["steel"], "bearings", axis="X", bw=0.8, verts=64)
        cut(o, ccyl(12.2, x - 10, x + 10, 0, 0, axis="X"))
        lib.torus(0.018, 0.0045, 0, C["steel"]).name = "ball_race"
        bpy.context.object.rotation_euler = (0, math.radians(90), 0)
        bpy.context.object.location = (x * 0.001, 0, 0)
        kit.G["bearings"].append(bpy.context.object)
    # end shields
    for x0, x1, g in ((-96, -80, "end_shield_de"), (80, 96, "end_shield_nde")):
        o = CYL(62, x0, x1, 0, 0, C["paint"], g, axis="X", bw=3.0, verts=96)
        cut(o, ccyl(12.5, x0 - 5, x1 + 5, 0, 0, axis="X"))
        for k in range(4):
            a = math.radians(45 + 90 * k)
            CYL(3.2, x0 - 2 if x0 < 0 else x1, x0 if x0 < 0 else x1 + 2, 54 * math.cos(a), 54 * math.sin(a), C["steel"], g, axis="X", bw=0.5, verts=6)
    CYL(28, -104, -96, 0, 0, C["paint"], "end_shield_de", axis="X", bw=2.0, verts=64)
    # fan + cowl
    CYL(14, 98, 106, 0, 0, C["black"], "fan", axis="X", bw=1.0)
    for k in range(9):
        a = 2 * math.pi * k / 9
        o = B(98, 106, -1.6, 1.6, 14, 52, C["black"], "fan", bw=0.5)
        lib._sel(o)
        bpy.ops.object.transform_apply(location=True)
        o.rotation_euler = (a, 0, 0)
    cw = CYL(64, 92, 138, 0, 0, C["paint"], "fan_cover", axis="X", bw=3.0, verts=96)
    cut(cw, ccyl(61.5, 90, 135.5, 0, 0, axis="X", verts=96))
    for r in (18, 30, 42, 54):
        n = int(2 * math.pi * r / 9)
        for k in range(n):
            a = 2 * math.pi * k / n
            cut(cw, ccyl(2.8, 134, 140, r * math.cos(a), r * math.sin(a), axis="X", verts=12))
    # terminal box on top
    tb = B(-30, 35, -38, 38, 62, 96, C["paint"], "terminal_box", bw=2.0)
    cut(tb, cbox(-27, 32, -35, 35, 64, 99))
    B(-32, 37, -40, 40, 96, 101, C["paint"], "terminal_box", bw=2.0)
    for x, y in ((-27, -35), (32, -35), (-27, 35), (32, 35)):
        CYL(3, 101, 103, x, y, C["steel"], "terminal_box", axis="Z", bw=0.5, verts=6)
    for x in (-8, 16):
        CYL(10, -48, -38, x, 79, C["black"], "terminal_box", axis="Y", bw=1.5, verts=6)
        CYL(8, -54, -48, x, 79, C["black"], "terminal_box", axis="Y", bw=1.5)
    terminal_board(C, M, "terminal_box", z=66, links="single" if single else "delta")
    # nameplate
    B(-30, 30, -63, -61.5, -8, 28, C["plate"], "nameplate", bw=0.4)
    lines = (["1~ MOTOR  ELDAWLY  EM90L-4", "1.1 kW   230V   50Hz", "7.2 A   1420 rpm   cos 0.92",
              "Cs 150uF 250V  Cr 25uF 450V", "IP54   Ins.F   S1"] if single else
             ["3~ MOTOR  ELDAWLY  EM100L-4", "4 kW   400V D / 690V Y   50Hz", "8.2 A   1440 rpm   cos 0.82",
              "IP55   Ins.F   S1   IE3", "IEC 60034-1"])
    for i, l in enumerate(lines):
        T(l, 0, -63.06, 22 - i * 6.5, 2.6, C["ink"], "nameplate")


def terminal_board(C, M, g, z=66, links="delta"):
    B(-24, 28, -26, 26, z - 3, z, C["board"], g, bw=0.8)
    top = [("U1", -12), ("V1", 2), ("W1", 16)] if links != "single" else [("U1", -12), ("Z1", 2), ("L", 16)]
    bot = [("W2", -12), ("U2", 2), ("V2", 16)] if links != "single" else [("U2", -12), ("Z2", 2), ("N", 16)]
    for (lab, x), y in [(t, -10) for t in top] + [(b, 12) for b in bot]:
        CYL(2.5, z, z + 14, x, y, C["brass"], g, axis="Z", bw=0.2, verts=24)
        CYL(4.5, z + 9, z + 12, x, y, C["brass"], g, axis="Z", bw=0.5, verts=6)
        T(lab, x - 6.5, y - 6.5, z + 0.05, 3.0, lib.mat("mo_wink", (0.9, 0.9, 0.9), rough=0.6), g, rot=(0, 0, 0))
    cu = C["copper"]
    if links == "single":
        B(-15, -9, -13, 15, z + 6, z + 8, cu, g, bw=0.5)                    # U1-U2 bridge (example link)
    elif links == "delta":
        for x in (-12, 2, 16):
            B(x - 3, x + 3, -13, 15, z + 6, z + 8, cu, g, bw=0.5)          # U1-W2, V1-U2, W1-V2
    else:
        B(-15, 19, 9, 15, z + 6, z + 8, cu, g, bw=0.5)                     # W2-U2-V2 bridged
        B(-15, 5, 9, 15, z + 8, z + 10, cu, g, bw=0.5)


def build_board(M, links="delta"):
    C = C_(M)
    terminal_board(C, M, "terminal_box", z=0, links=links)


PARTS_1PH = dict(PARTS)
PARTS_1PH.update({
    "stator": ("الإستاتور: الملف الرئيسي والمساعد", "Stator: main & auxiliary windings", (0, -150, 0)),
    "terminal_box": ("علبة الترامل (U1-U2 و Z1-Z2)", "Terminal box (U1-U2 / Z1-Z2)", (0, 0, 110)),
    "run_capacitor": ("مكثف التشغيل الدائم", "Run capacitor", (0, -40, 170)),
    "start_capacitor": ("مكثف البدء", "Start capacitor", (60, 40, 170)),
    "centrifugal_switch": ("المفتاح الطارد المركزي", "Centrifugal switch", (90, -150, -90), (70, 0, 0)),
})


def build_1ph(M):
    build(M, single=True)
    C = C_(M)
    silver = lib.mat("mo_cap_s", (0.75, 0.76, 0.78), metal=0.6, rough=0.35)
    blk = lib.mat("mo_cap_b", (0.03, 0.03, 0.03), rough=0.4)
    CYL(15, 40, 92, -20, 80, silver, "run_capacitor", axis="X", bw=2.0)
    T("25uF 450V", 66, -20, 95.2, 3.0, C["ink"], "run_capacitor", rot=(0, 0, 0))
    for x in (50, 82):
        B(x - 3, x + 3, -36, -4, 62, 66, C["steel"], "run_capacitor", bw=0.4)
    CYL(15, 40, 92, 20, 80, blk, "start_capacitor", axis="X", bw=2.0)
    T("150uF 250V", 66, 20, 95.2, 3.0, lib.mat("mo_wink2", (0.9, 0.9, 0.9), rough=0.6), "start_capacitor", rot=(0, 0, 0))
    for x in (50, 82):
        B(x - 3, x + 3, 4, 36, 62, 66, C["steel"], "start_capacitor", bw=0.4)
    # centrifugal switch: rotating weights on shaft + stationary contact on NDE shield
    CYL(22, 66, 72, 0, 0, C["alu"], "centrifugal_switch", axis="X", bw=1.0)
    for s_ in (-1, 1):
        B(64, 74, -6, 6, s_ * 18 - 5, s_ * 18 + 5, C["steel"], "centrifugal_switch", bw=1.0)
    helix("centrifugal_switch", (69, 0, 0), 4, 16, 3, 0.4, C["steel"], axis="X")
    B(74, 78, -10, 10, 24, 40, lib.mat("mo_sw", (0.75, 0.62, 0.40), rough=0.5), "centrifugal_switch", bw=0.6)


class V:
    def __init__(self, parts, fn, **kw):
        self.PARTS, self.fn, self.kw = parts, fn, kw

    def build(self, M):
        self.fn(M, **self.kw)


TBP = {"terminal_box": ("لوحة ترامل الموتور", "Motor terminal board", (0, 0, 0))}
VARIANTS = {
    "motor":            (V(PARTS, build), True, (0.0, 0, 0.004), 0.62),
    "motor_tbox_delta": (V(TBP, build_board, links="delta"), False, (0.002, 0, 0.004), 0.17),
    "motor_tbox_star":  (V(TBP, build_board, links="star"), False, (0.002, 0, 0.004), 0.17),
    "motor_1ph":        (V(PARTS_1PH, build_1ph), True, (0.0, 0, 0.010), 0.62),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, expl, tgt, dist = VARIANTS[n]
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else (["assembled", "exploded"] if expl else ["assembled"])
        el = 24 if n == "motor" else 50
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=el, azim=-34, lens_mm=55),
                dict(target=(0.02, -0.06, -0.03), dist=1.25, elev=18, azim=-30, lens_mm=50), modes)
