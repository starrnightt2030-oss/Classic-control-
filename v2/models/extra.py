"""Control transformer (single-phase, EI core) and 24 V DC switch-mode power supply (DIN rail). Front -Y, Z up, mm."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib, din
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

TR_PARTS = {
    "core":       ("القلب الحديد (رقايق E و I)", "Laminated EI core", (0, 0, 70), (0, -22, 74)),
    "primary":    ("الملف الابتدائي", "Primary winding", (0, -70, 0), (-20, -30, 45)),
    "secondary":  ("الملف الثانوي", "Secondary winding", (0, -110, -10), (20, -30, 45)),
    "bobbin":     ("البكرة العازلة", "Insulating bobbin", (0, -40, 0)),
    "terminals":  ("ترامل الدخول والخروج", "Primary & secondary terminals", (0, 0, 120)),
    "bracket":    ("حامل التثبيت والأرجل", "Mounting frame & feet", (0, 0, -40)),
    "label":      ("ليبل البيانات", "Rating label", (60, -40, 0), (44, 0, 50)),
}
PSU_PARTS = {
    "case":       ("العلبة والترامل", "Case & terminals", (0, 60, 0)),
    "pcb":        ("كارت التحكم الإلكتروني", "Control PCB", (0, -40, 0)),
    "transformer": ("محول الفريت عالي التردد", "High-frequency ferrite transformer", (0, -80, 30)),
    "capacitors": ("مكثفات التنعيم", "Smoothing capacitors", (0, -80, -34)),
    "heatsink":   ("مشتت الحرارة", "Heatsink", (40, -60, 0)),
    "front":      ("لوحة الواجهة (ليد وضبط الجهد)", "Front panel (LED & V.adj)", (0, -110, 0)),
}


def build_trafo(M):
    lam = kit.striped("tr_lam", (0.42, 0.43, 0.45), 0.9, 0.4, "Y", 900.0, 0.5)
    green = kit.striped("tr_wind", (0.15, 0.32, 0.18), 0.4, 0.35, "Z", 300.0, 0.2)
    green2 = kit.striped("tr_wind2", (0.12, 0.27, 0.15), 0.4, 0.35, "Z", 300.0, 0.2)
    black = lib.mat("tr_black", (0.03, 0.03, 0.03), rough=0.45)
    orange = lib.mat("tr_orange", (0.95, 0.45, 0.03), rough=0.45, bump=0.2)
    steel = lib.mat("tr_steel", (0.78, 0.79, 0.81), metal=1.0, rough=0.3)
    white = lib.mat("tr_white", (0.92, 0.92, 0.9), rough=0.5)
    ink = lib.mat("tr_ink", (0.03, 0.03, 0.04), rough=0.6)
    core = B(-42, 42, -22, 22, 10, 80, lam, "core", bw=0.4)
    for x0, x1 in ((-30, -11), (11, 30)):
        cut(core, cbox(x0, x1, -30, 30, 22, 68))
    # windings around centre leg: primary (inner/left label) + secondary (outer) as two stacked sections
    for g, m, z0, z1 in (("primary", green, 23, 45), ("secondary", green2, 46, 67)):
        w = B(-29.5, 29.5, -34, 34, z0, z1, m, g, bw=2.5)
        cut(w, cbox(-11.2, 11.2, -23, 23, z0 - 2, z1 + 2))
    for z in (22, 67.6):
        f = B(-30, 30, -35, 35, z - 0.6, z + 0.6, black, "bobbin", bw=0.3)
        cut(f, cbox(-11.2, 11.2, -23, 23, z - 3, z + 3))
    # terminal blocks on top (two rows): primary 0-220-380, secondary 0-24-48
    B(-36, 36, -30, 30, 80, 82, black, "terminals", bw=0.4)
    for row_y, labs in ((-14, ("0", "220", "380")), (14, ("0", "24", "48"))):
        for i, lab in enumerate(labs):
            x = -22 + i * 22
            b = B(x - 9, x + 9, row_y - 9, row_y + 9, 82, 100, orange, "terminals", bw=1.2)
            for k, xx in enumerate((x - 4, x + 4)):
                cut(b, cbox(xx - 2, xx + 2, row_y - 10, row_y - 3, 86, 94))
            screw(x, row_y, 100.2, "+Z", M, ("P" if row_y < 0 else "S") + lab, "terminals", scale=0.75)
            T(lab + "V", x, row_y - 9.06, 96.5, 2.4, ink, "terminals")
    T("PRI", -40, -23.06, 90, 2.6, ink, "terminals", align="LEFT") if False else None
    # mounting frame: clamp plates front/back + feet
    for s in (-1, 1):
        p = B(-46, 46, s * 22 - (2 if s > 0 else 0) if False else min(s * 22, s * 24), max(s * 22, s * 24), 2, 22, steel, "bracket", bw=0.5)
        B(-46, 46, min(s * 22, s * 24), max(s * 22, s * 24), 74, 82, steel, "bracket", bw=0.5)
        for x in (-38, 38):
            CYL(3.2, min(s * 24, s * 26), max(s * 24, s * 26), x, 14, steel, "bracket", bw=0.5)
    foot = B(-56, 56, -26, 26, 0, 2, steel, "bracket", bw=0.4)
    for x in (-50, 50):
        cut(foot, cbox(x - 2.5, x + 2.5, -16, 16, -1, 3))
    B(42, 44.5, -16, 16, 36, 64, white, "label", bw=0.3)
    for i, l in enumerate(("ELDAWLY", "ECT-250", "250 VA", "PRI 0-220-380V", "SEC 0-24-48V", "50/60Hz")):
        T(l, 44.56, 0, 60 - i * 4.6, 2.2, ink, "label", rot=(90, 0, 90))


def build_psu(M):
    W, body, ink = din.housing(M, "case", n=3, color=(0.72, 0.73, 0.75), top=("L", "N", "PE"), bot=("+V", "+V", "-V", "-V"), front_y=-30)
    vents = lib.mat("psu_vent", (0.05, 0.05, 0.05), rough=0.6)
    for k in range(7):
        B(-W / 2 + 6, W / 2 - 6, 33, 34.1, -40 + k * 12, -36 + k * 12, vents, "case", bw=0.3) if False else None
    grn = lib.mat("psu_led", (0.05, 0.9, 0.1), rough=0.3, emit=((0.05, 1, 0.1), 4.0))
    B(-24, 24, -30.4, -29.9, -21, 21, lib.mat("psu_front", (0.14, 0.15, 0.17), rough=0.45), "front", bw=0.4)
    T("24V DC  2.5A", 0, -30.46, 14, 3.0, lib.mat("psu_wink", (0.9, 0.9, 0.9), rough=0.6), "front")
    T("ELDAWLY  EPS-60", 0, -30.46, 8, 2.2, lib.mat("psu_wink2", (0.9, 0.9, 0.9), rough=0.6), "front")
    CYL(1.4, -31.2, -30.0, -12, -6, grn, "front", bw=0.2, verts=16)
    T("DC OK", -12, -30.46, -10.5, 1.8, lib.mat("psu_wink3", (0.9, 0.9, 0.9), rough=0.6), "front")
    CYL(3.0, -32, -30, 10, -6, lib.mat("psu_pot", (0.85, 0.85, 0.85), rough=0.4), "front", bw=0.5)
    B(9.6, 10.4, -32.2, -31.8, -8, -4, ink, "front", bw=0.05)
    T("V.ADJ", 10, -30.46, -10.5, 1.8, lib.mat("psu_wink4", (0.9, 0.9, 0.9), rough=0.6), "front")
    pcb = lib.mat("psu_pcb", (0.02, 0.22, 0.08), rough=0.4)
    B(-22, 22, 2, 3.6, -36, 36, pcb, "pcb", bw=0.2)
    for x, z in ((-12, -24), (8, -20), (14, 22), (-14, 26)):
        B(x - 3, x + 3, -2, 2, z - 2, z + 2, lib.mat("psu_ic", (0.03, 0.03, 0.03), rough=0.4), "pcb", bw=0.2)
    fer = lib.mat("psu_ferrite", (0.08, 0.08, 0.09), metal=0.3, rough=0.5)
    B(-8, 8, -12, 2, -2, 16, fer, "transformer", bw=0.6)
    B(-6, 6, -13, 2, 2, 12, kit.striped("psu_wind", (0.85, 0.65, 0.15), 0.2, 0.4, "Z", 900, 0.3), "transformer", bw=0.6)
    capm = lib.mat("psu_cap", (0.05, 0.10, 0.45), rough=0.4)
    for x in (-12, 0, 12):
        CYL(5, -16, 2, x, -10 if x else -12, capm, "capacitors", bw=0.8)
    alu = lib.mat("psu_alu", (0.75, 0.76, 0.78), metal=1.0, rough=0.35)
    B(16, 18, -18, 2, -34, 34, alu, "heatsink", bw=0.3)
    for k in range(6):
        B(18, 24, -18, 2, -32 + k * 12.5, -30 + k * 12.5, alu, "heatsink", bw=0.2)


class V:
    def __init__(self, parts, fn):
        self.PARTS, self.fn = parts, fn

    def build(self, M):
        self.fn(M)


VARIANTS = {
    "control_transformer": (V(TR_PARTS, build_trafo), (0, 0, 0.050), 0.34),
    "power_supply_24v":    (V(PSU_PARTS, build_psu), (0, -0.006, 0), 0.28),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, tgt, dist = VARIANTS[n]
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else ["assembled", "exploded"]
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=22, azim=-32, lens_mm=60),
                dict(target=(tgt[0], -0.030, tgt[2]), dist=dist * 2.3, elev=18, azim=-38, lens_mm=50), modes)
