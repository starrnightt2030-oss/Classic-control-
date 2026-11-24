"""Control relays, sockets and timers. Z up, front -Y, mm.
Run: python relays.py <variant|all> [modes]"""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit, lib, din
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

MY4_PARTS = {
    "cover":    ("الغطاء الشفاف", "Transparent cover", (0, 0, 44)),
    "coil":     ("الكويل", "Coil", (0, -32, 18), (0, 4, 14)),
    "yoke":     ("القلب والإطار الحديد", "Core & yoke", (0, 30, 18)),
    "armature": ("الذراع المتحرك (الأرماتشر)", "Armature", (0, -20, 30)),
    "contacts": ("طقم النقط (4 تحويلة)", "Contact set (4 changeover)", (0, -44, 4)),
    "led":      ("ليد البيان", "Status LED", (30, -20, 30)),
    "base":     ("القاعدة والرجول", "Base & pins", (0, 0, -6)),
    "socket":   ("القاعدة على الريل (14 ترمينال)", "DIN socket (14 terminals)", (0, 0, -40)),
}
ST3P_PARTS = {
    "case":    ("العلبة", "Case", (0, 0, 44)),
    "dial":    ("قرص ضبط الزمن والغطا الشفاف", "Time dial & clear knob", (0, -46, 30), (0, -26, 10)),
    "pcb":     ("الدايرة الإلكترونية", "Timing circuit (PCB)", (0, -14, 18)),
    "range_sw": ("سويتشات مدى الزمن", "Time-range DIP switches", (32, -20, 18)),
    "relay":   ("ريلاي الخرج", "Output relay", (-34, -10, 18)),
    "base":    ("القاعدة والرجول (8 رجل)", "Base & octal pins", (0, 0, -4)),
    "socket":  ("قاعدة 8 رجل على الريل", "8-pin DIN socket", (0, 0, -36)),
}


def M_(M):
    return dict(
        black=lib.mat("r_black", (0.02, 0.02, 0.022), rough=0.45, bump=0.25),
        clear=lib.mat("r_clear", (0.65, 0.78, 0.92), rough=0.05, trans=0.92, ior=1.5),
        cream=lib.mat("r_cream", (0.78, 0.74, 0.60), rough=0.45, bump=0.2),
        white=lib.mat("r_white", (0.82, 0.82, 0.80), rough=0.45),
        copper=lib.mat("r_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        winding=kit.striped("r_wind", (0.80, 0.40, 0.18), 1.0, 0.25, "Z", 1400.0, 0.4),
        iron=lib.mat("r_iron", (0.45, 0.46, 0.48), metal=0.9, rough=0.4),
        silver=lib.mat("r_ag", (0.93, 0.93, 0.95), metal=1.0, rough=0.18),
        tin=lib.mat("r_tin", (0.80, 0.80, 0.82), metal=1.0, rough=0.25),
        steel=lib.mat("r_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        orange=lib.mat("r_orange", (0.95, 0.40, 0.02), rough=0.4),
        ink=lib.mat("r_ink", (0.85, 0.85, 0.85), rough=0.6),
        dink=lib.mat("r_dink", (0.03, 0.03, 0.04), rough=0.6),
        pcb=lib.mat("r_pcb", (0.02, 0.22, 0.08), rough=0.4),
        red=lib.mat("r_red", (0.9, 0.05, 0.02), rough=0.3, emit=((1, 0.05, 0.02), 4.0)),
        blue=lib.mat("r_blue", (0.02, 0.1, 0.5), rough=0.4),
    )


def socket14(C, M, g, z_top):
    """PYF14A-style DIN socket for square 14-pin relay."""
    b = B(-15, 15, -19, 19, z_top - 30, z_top, C["black"], g, bw=0.8)
    cut(b, cbox(-11.5, 11.5, -15, 15, z_top - 6, z_top + 1))
    nums = [["13", "9", "5", "1"], ["14", "10", "6", "2"], ["15", "11", "7", "3"], ["16", "12", "8", "4"]]
    # two tiers of screws front & back
    for row, (y, z) in enumerate(((-17.5, z_top - 12), (-21.0, z_top - 24))):
        step = B(-15, 15, y - 3.5 if row == 1 else y, -19 + (0 if row == 0 else 0), z - 6, z + 6, C["black"], g, bw=0.6) if row == 1 else None
        for i, x in enumerate((-10.5, -3.5, 3.5, 10.5)):
            cut(b if row == 0 else step, ccyl(2.6, y - 6, y + 2, x, z))
            screw(x, (-17.6 if row == 0 else -23.1), z, "-Y", M, nums[row][i], g, scale=0.6)
            T(nums[row][i], x, (y if row == 0 else y - 3.5) - 0.06, z + 4.4, 1.6, C["ink"], g)
    B(-6, 6, -22, -18, z_top - 34, z_top - 30, C["orange"], g, bw=0.5)          # release clip
    B(-15, 15, 17, 19, z_top - 12, z_top - 8, C["black"], g, bw=0.3)


def build_my4(M):
    C = M_(M)
    # base with 14 flat pins
    B(-10.8, 10.8, -14, 14, 0, 3.5, C["black"], "base", bw=0.6)
    for ix in range(4):
        for iy in range(4):
            if iy in (1, 2) and ix in (1, 2):
                continue
            x, y = -7.5 + ix * 5, -10.5 + iy * 7
            B(x - 0.25, x + 0.25, y - 1.0, y + 1.0, -6.5, 0, C["tin"], "base", bw=0.05)
    for x in (-2.5, 2.5):
        B(x - 0.25, x + 0.25, -1, 1, -6.5, 0, C["tin"], "base", bw=0.05)     # coil pins 13/14
    # transparent cover
    cv = B(-10.8, 10.8, -14, 14, 3.5, 36, C["clear"], "cover", bw=0.8)
    cut(cv, cbox(-10.0, 10.0, -13.2, 13.2, 3, 35.2))
    T("24VDC", 0, -14.06, 30.5, 2.2, C["dink"], "cover")
    T(lib.BRAND, 0, -14.06, 27.0, 1.8, C["dink"], "cover")
    # coil + yoke + armature (coil axis Z, at back)
    CYL(4.2, 4, 24, 0, 6, C["winding"], "coil", axis="Z", bw=0.4)
    CYL(5.0, 4, 5.2, 0, 6, C["black"], "coil", axis="Z", bw=0.2)
    CYL(5.0, 22.8, 24, 0, 6, C["black"], "coil", axis="Z", bw=0.2)
    CYL(2.2, 24, 25.5, 0, 6, C["iron"], "yoke", axis="Z", bw=0.2)
    B(-5, 5, 11, 12.5, 4, 26, C["iron"], "yoke", bw=0.2)                     # L-yoke
    B(-5, 5, 6, 12.5, 26, 27.5, C["iron"], "yoke", bw=0.2)
    B(-5.5, 5.5, -2, 9, 27, 28.2, C["iron"], "armature", bw=0.2)
    B(-9.5, 9.5, -3.6, -2.4, 12, 30, C["white"], "armature", bw=0.3)           # card actuator
    helix("armature", (0, 8, 31), 4, 1.2, 4, 0.25, C["steel"], axis="Z")
    # 4 changeover contact sets (fixed NO / NC + moving blade)
    for x in (-7.5, -2.5, 2.5, 7.5):
        B(x - 0.9, x + 0.9, -4.5, -4.1, 6, 24, C["copper"], "contacts", bw=0.1)      # moving blade
        CYL(0.9, -4.9, -4.5, x, 22, C["silver"], "contacts", bw=0.1)
        CYL(0.9, -4.1, -3.7, x, 22, C["silver"], "contacts", bw=0.1)
        B(x - 0.9, x + 0.9, -7.5, -5.0, 20.5, 23.5, C["copper"], "contacts", bw=0.1)  # NO fixed
        B(x - 0.9, x + 0.9, -3.6, -1.0, 20.5, 23.5, C["copper"], "contacts", bw=0.1) if False else None
        B(x - 0.9, x + 0.9, -7.5, -6.9, 4, 20.5, C["copper"], "contacts", bw=0.1)
    CYL(1.2, -13.5, -12.5, 7, 32, C["red"], "led", bw=0.3)
    B(4, 10, -12.5, -11.5, 29, 35, C["pcb"], "led", bw=0.1)
    socket14(C, M, "socket", -6.5)


def socket_round(C, M, g, z_top, pins=8):
    b = B(-19, 19, -16, 16, z_top - 26, z_top, C["black"], g, bw=0.8)
    cut(b, ccyl(14.5, z_top - 4, z_top + 1, 0, 0, axis="Z"))
    k = pins // 2
    for row, z in enumerate((z_top - 10, z_top - 20)):
        for i in range(k):
            x = (i - (k - 1) / 2) * (34 / k)
            n = str(1 + i + row * k)
            cut(b, ccyl(2.4, -18, -11, x, z))
            screw(x, -14.7, z, "-Y", M, n, g, scale=0.55)
            T(n, x, -16.06, z + 4.0, 1.5, C["ink"], g)
    B(-5, 5, -18, -15, z_top - 30, z_top - 26, C["orange"], g, bw=0.4)


def build_st3p(M):
    C = M_(M)
    B(-11, 11, -11, 11, -1, 3, C["black"], "base", bw=0.6)
    CYL(7.0, -5, 0, 0, 0, C["black"], "base", axis="Z", bw=0.4)
    for i in range(8):
        a = 2 * math.pi * i / 8 + math.pi / 8
        CYL(0.8, -16, -4, 8.5 * math.cos(a), 8.5 * math.sin(a), C["tin"], "base", axis="Z", bw=0.1, verts=12)
    case = B(-18, 18, -24, 24, 3, 60, C["cream"], "case", bw=1.5)
    cut(case, cbox(-16, 16, -22, 22, 2, 58))
    B(-18.2, 18.2, -24.2, -23.6, 3, 60, C["cream"], "case", bw=0.4)
    T("220VAC", 11, -24.3, 54, 2.0, C["dink"], "case")
    T("UP", 13.5, -24.3, 45, 2.0, C["dink"], "case")
    T("ON", 13.5, -24.3, 17, 2.0, C["dink"], "case")
    T("TYPE ET3P", -8, -24.3, 8, 2.0, C["dink"], "case")
    for z, col in ((41.5, C["red"]), (13.5, lib.mat("r_grn", (0.05, 0.9, 0.1), rough=0.3, emit=((0.05, 1, 0.1), 3.0)))):
        CYL(1.1, -24.8, -23.8, 13.5, z, col, "case", bw=0.2, verts=16)
    # dial: black face with scale + clear knurled knob
    CYL(14.5, -25.4, -24.0, -2, 31, C["black"], "dial", bw=0.4, verts=96)
    for i in range(11):
        a = math.radians(225 - i * 27)
        T(str(i), -2 + 11.6 * math.cos(a), -25.5, 31 + 11.6 * math.sin(a), 2.1, C["ink"], "dial")
    T("SEC.", -2, -25.5, 22.5, 2.4, C["ink"], "dial")
    CYL(9.5, -32, -25.4, -2, 31, C["clear"], "dial", bw=1.2, verts=96)
    for k in range(48):
        a = 2 * math.pi * k / 48
        o = B(9.2, 10.0, -31.5, -25.6, -0.5, 0.5, C["clear"], "dial", bw=0.1)
        import bpy
        lib._sel(o)
        bpy.ops.object.transform_apply(location=True)
        o.rotation_euler = (0, a, 0)
        o.location = (-0.002, 0, 0.031)
    CYL(4.0, -33, -26, -2, 31, C["clear"], "dial", bw=0.8)
    B(-2.5, -1.5, -33.2, -32.8, 29, 37, lib.mat("r_ptr", (0.9, 0.15, 0.05), rough=0.4), "dial", bw=0.1)
    # internals
    B(-15, 15, -6, -4.4, 6, 56, C["pcb"], "pcb", bw=0.2)
    for x, z in ((-8, 14), (6, 20), (-6, 46), (8, 40), (0, 28)):
        B(x - 3, x + 3, -9, -6, z - 2, z + 2, C["black"], "pcb", bw=0.3)
    CYL(3.0, -12, -6, 8, 50, C["blue"], "pcb", bw=0.4)
    B(9, 15, -9, -6, 24, 34, C["blue"], "range_sw", bw=0.3)
    for k in range(4):
        B(10, 14, -9.6, -9.0, 25 + k * 2.4, 26.4 + k * 2.4, C["white"], "range_sw", bw=0.1)
    B(-14, -2, -4.4, 8, 10, 24, C["black"], "relay", bw=0.6)
    T("RELAY", -8, -4.46, 17, 1.6, C["ink"], "relay", rot=(90, 0, 0)) if False else None
    socket_round(C, M, "socket", -16, 8)


def build_mk3p(M):
    C = M_(M)
    B(-17.5, 17.5, -17.5, 17.5, 0, 4, C["black"], "base", bw=0.8)
    CYL(7.5, -5, 0, 0, 0, C["black"], "base", axis="Z", bw=0.4)
    for i in range(11):
        a = 2 * math.pi * i / 11
        CYL(0.8, -16, -4, 9.5 * math.cos(a), 9.5 * math.sin(a), C["tin"], "base", axis="Z", bw=0.1, verts=12)
    cv = B(-17.5, 17.5, -17.5, 17.5, 4, 54, C["clear"], "cover", bw=1.2)
    cut(cv, cbox(-16.5, 16.5, -16.5, 16.5, 3, 53))
    CYL(6.5, 8, 34, 0, 6, C["winding"], "coil", axis="Z", bw=0.5)
    B(-10, 10, 10, 12, 6, 40, C["iron"], "yoke", bw=0.2)
    for x in (-9, 0, 9):
        B(x - 1.2, x + 1.2, -8, -7.4, 10, 36, C["copper"], "contacts", bw=0.1)
        CYL(1.1, -9, -8, x, 32, C["silver"], "contacts", bw=0.1)
    T("230VAC", 0, -17.56, 47, 2.4, C["dink"], "cover")
    T(lib.BRAND + " EMK3P", 0, -17.56, 43, 1.8, C["dink"], "cover")
    socket_round(C, M, "socket", -16, 12)


def build_socket(M, pins=8):
    C = M_(M)
    socket_round(C, M, "socket", 0, pins)


def build_din_timer(M, star_delta=False):
    C = M_(M)
    n = 1
    top = ("A1", "15", "A3") if not star_delta else ("A1", "17", "A2")
    bot = ("16", "18", "A2") if not star_delta else ("18", "28", "")
    bot = tuple(b for b in bot if b)
    W, body, ink = din.housing(M, "case", n=n, top=top, bot=bot, front_y=-28)
    CYL(4.2, -30.5, -28, 0, 10, C["white"], "dial", bw=0.6)
    CYL(3.2, -32, -30.5, 0, 10, lib.mat("r_teal", (0.0, 0.45, 0.5), rough=0.4), "dial", bw=0.5)
    B(-0.4, 0.4, -32.2, -31.8, 7.8, 12.2, C["white"], "dial", bw=0.05)
    for v, a in (("0.1", 220), ("15", 90), ("30", -40)):
        r = math.radians(a)
        T(v, 6.6 * math.cos(r), -28.06, 10 + 6.6 * math.sin(r), 1.5, C["dink"], "case")
    T("sec.", 0, -28.06, 2.6, 1.4, C["dink"], "case")
    for z, col, lab in ((-5, C["red"], "ON"), (-10, lib.mat("r_grn2", (0.05, 0.9, 0.1), rough=0.3, emit=((0.05, 1, 0.1), 3.0)), "OUT")):
        B(-6.5, -3.5, -28.6, -27.8, z - 1, z + 1, col, "case", bw=0.1)
        T(lab, 2, -28.06, z, 1.6, C["dink"], "case")
    T(lib.BRAND, 0, -28.06, 19.5, 1.5, lib.mat("r_brand", (0.0, 0.35, 0.45), rough=0.5), "case")
    T("Y-Δ TIMER" if star_delta else "ETR-30", 0, -28.06, -16.5, 1.5, C["dink"], "case")
    B(-3, 3, 32, 36, 45, 48, lib.mat("r_teal2", (0.0, 0.45, 0.5), rough=0.4), "case", bw=0.4)


class V:
    def __init__(self, parts, fn, **kw):
        self.PARTS, self.fn, self.kw = parts, fn, kw

    def build(self, M):
        self.fn(M, **self.kw)


SIMPLE = {"case": ("العلبة", "Case", (0, 0, 0)), "dial": ("قرص الضبط", "Dial", (0, -20, 0)),
          "socket": ("القاعدة", "Socket", (0, 0, -30)), "base": ("القاعدة", "Base", (0, 0, -10)),
          "cover": ("الغطاء", "Cover", (0, 0, 30)), "coil": ("الكويل", "Coil", (0, -20, 10)),
          "yoke": ("القلب", "Yoke", (0, 20, 10)), "contacts": ("النقط", "Contacts", (0, -30, 0))}
VARIANTS = {
    "relay_my4":      (V(MY4_PARTS, build_my4), True, (0, 0, -0.010), 0.21),
    "relay_mk3p":     (V(SIMPLE, build_mk3p), False, (0, 0, 0.004), 0.24),
    "socket_8pin":    (V(SIMPLE, build_socket, pins=8), False, (0, 0, -0.012), 0.15),
    "socket_11pin":   (V(SIMPLE, build_socket, pins=12), False, (0, 0, -0.012), 0.15),
    "timer_st3p":     (V(ST3P_PARTS, build_st3p), True, (0, 0, 0.012), 0.26),
    "timer_din":      (V(SIMPLE, build_din_timer), False, (0, -0.006, 0), 0.24),
    "timer_star_delta": (V(SIMPLE, build_din_timer, star_delta=True), False, (0, -0.006, 0), 0.24),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, expl, tgt, dist = VARIANTS[n]
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else (["assembled", "exploded"] if expl else ["assembled"])
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=20, azim=-35, lens_mm=60),
                dict(target=(0, -0.012, 0.004), dist=0.52, elev=14, azim=-42, lens_mm=50), modes)
