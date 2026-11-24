"""Miniature circuit breaker (IEC 60898-1), 18 mm per pole, with full internals.
X width, Y depth (front -Y, DIN rail +Y), Z height. mm.
Run: python mcb.py single [assembled,exploded] | python mcb.py multi"""
import sys, math
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

P = 17.6  # pole pitch

PARTS = {
    "housing_left":  ("نص الجسم الشمال", "Housing half (left)", (-34, 0, 0)),
    "housing_right": ("نص الجسم اليمين والطباعة", "Housing half (right) & markings", (34, 0, 0)),
    "handle":        ("ذراع التشغيل", "Operating handle (toggle)", (0, -40, 0), (0, -32, 2)),
    "mechanism":     ("آلية الفصل الحر والماسك", "Trip-free latch mechanism", (0, -26, -26)),
    "line_terminal": ("ترمينال الدخول", "Line terminal (cage clamp)", (0, 0, 34)),
    "magnetic_coil": ("الملف المغناطيسي (حماية القصر)", "Magnetic trip coil (short-circuit)", (0, 0, 20)),
    "contacts":      ("النقطة الثابتة والمتحركة", "Fixed & moving contacts", (16, 0, 0)),
    "arc_chute":     ("غرفة إطفاء الشرارة", "Arc chute (splitter plates)", (30, 30, 0)),
    "bimetal":       ("البايميتال (حماية زيادة الحمل)", "Bimetal (overload)", (0, -10, -26)),
    "load_terminal": ("ترمينال الخروج", "Load terminal (cage clamp)", (0, 0, -36)),
    "din_clip":      ("كلبس الدين ريل", "DIN-rail clip", (0, 24, -30)),
}


def mats(M, handle_color):
    return dict(
        body=lib.mat("mcb_body", (0.80, 0.80, 0.78), rough=0.45, bump=0.25),
        handle={"blue": lib.mat("mcb_blue", (0.01, 0.12, 0.55), rough=0.35, coat=0.3),
                "red": lib.mat("mcb_red", (0.55, 0.01, 0.01), rough=0.35, coat=0.3),
                "black": lib.mat("mcb_black", (0.02, 0.02, 0.022), rough=0.35, coat=0.3)}[handle_color],
        ink=lib.mat("mcb_ink", (0.03, 0.03, 0.04), rough=0.6),
        accent=lib.mat("mcb_accent", (0.02, 0.18, 0.62), rough=0.5) if handle_color == "blue" else lib.mat("mcb_accent_r", (0.62, 0.02, 0.02), rough=0.5),
        green=lib.mat("mcb_green", (0.02, 0.35, 0.06), rough=0.4),
        copper=lib.mat("mcb_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        silver=lib.mat("mcb_ag", (0.93, 0.93, 0.95), metal=1.0, rough=0.18),
        steel=lib.mat("mcb_steel", (0.62, 0.63, 0.65), metal=1.0, rough=0.32),
        zinc=M["zinc"],
        brass=lib.mat("mcb_brass", (0.82, 0.68, 0.38), metal=1.0, rough=0.25),
        mech=lib.mat("mcb_mech", (0.08, 0.08, 0.09), rough=0.45),
        steelb=lib.mat("mcb_bimetal_a", (0.55, 0.56, 0.58), metal=1.0, rough=0.35),
        brassb=lib.mat("mcb_bimetal_b", (0.78, 0.62, 0.30), metal=1.0, rough=0.3),
        braid=kit.striped("mcb_braid", (0.85, 0.5, 0.33), 1.0, 0.45, "Z", 900.0, 0.6),
    )


def housing_half(C, x0, x1, g, prints, cx):
    """Classic modular profile; cavity opened toward x=cx."""
    pieces = [  # (x0,x1,y0,y1,z0,z1, cavity y0,y1,z0,z1)
        (x0, x1, -6, 36.5, -45, 45, -6.2, 34.7, -43.2, 43.2),        # rear body
        (x0, x1, -14, -6, -45, 45, -12.2, -5.8, -43.2, 43.2),        # shoulders (full height)
        (x0, x1, -36.5, -14, -22.5, 22.5, -34.7, -13.8, -20.7, 20.7), # front escutcheon
    ]
    inner = (cx - 0.1, cx + 7.0) if x0 >= cx else (cx - 7.0, cx + 0.1)
    for (a, b, y0, y1, z0, z1, cy0, cy1, cz0, cz1) in pieces:
        o = B(a, b, y0, y1, z0, z1, C["body"], g, bw=1.0)
        cut(o, cbox(inner[0], inner[1], cy0, cy1, cz0, cz1))
        for z in (33, -33):                    # screw access holes
            cut(o, ccyl(3.2, -16, -4, cx, z))
        cut(o, cbox(cx - 5.4, cx + 5.4, -38, -30, -19.5, 4.5))  # handle slot
        cut(o, cbox(cx - 2.6, cx + 2.6, -38, -34, 7.5, 11.5))   # indicator window
        for z in (46, -46):                    # wire entries (top/bottom)
            cut(o, cbox(cx - 4.5, cx + 4.5, -10, 2, z - 5, z + 5))
    # DIN rail groove + fixed hook on rear
    g_ = B(x0, x1, 34.5, 36.5, 17.5, 22, C["body"], g, bw=0.3)


def pole(C, M, cx, idx, n, rating, handle_color):
    # ---- housing halves
    housing_half(C, cx - P / 2 + 0.05, cx, "housing_left", False, cx)
    housing_half(C, cx, cx + P / 2 - 0.05, "housing_right", True, cx)
    # ---- front prints (right half)
    xr = cx
    if idx == 0:
        T(lib.BRAND, xr, -36.56, 19.4, 1.9, C["accent"], "housing_right")
        T("EB1-63", xr, -36.56, 16.0 + 4.6, 1.6, C["ink"], "housing_right") if False else None
        T(rating, xr, -36.56, 14.8, 3.2, C["ink"], "housing_right")
        T("6000", xr, -36.56, -21.3, 1.2, C["ink"], "housing_right")
    else:
        B(xr - 6.5, xr + 6.5, -36.8, -36.4, 18.8, 20.2, C["accent"], "housing_right", bw=0.1)
        T(str(2 * idx + 1) + "-" + str(2 * idx + 2), xr, -36.56, 14.8, 1.8, C["ink"], "housing_right")
    B(xr - 2.4, xr + 2.4, -35.2, -34.4, 7.7, 11.3, C["green"], "mechanism", bw=0.1)   # indicator flag (OFF green)
    T("I ON", xr, -36.56, 25.8 - 2.6, 1.0, C["ink"], "housing_right") if False else None
    # terminal numbers on shoulder faces
    T(str(2 * idx + 1), xr + 5.6, -14.06, 39.5, 2.0, C["ink"], "housing_right")
    T(str(2 * idx + 2), xr + 5.6, -14.06, -39.5, 2.0, C["ink"], "housing_right")
    # ---- handle (ON = up). pivot at y -24, z -3
    hb = B(xr - 5.0, xr + 5.0, -40.5, -27.5, -8.0, 3.5, C["handle"], "handle", bw=1.2)
    hb.rotation_euler = (math.radians(-14), 0, 0)
    for k in range(4):
        B(xr - 5.05, xr + 5.05, -40.6, -40.3, -6.5 + k * 2.6, -5.7 + k * 2.6, C["handle"], "handle", bw=0.1).rotation_euler = (math.radians(-14), 0, 0)
    CYL(2.2, -27.5, -20, xr, -8, C["mech"], "handle", bw=0.3, axis="Y")
    if idx == 0:
        T("O-OFF", xr, -40.66, -0.8, 1.4, M["print_white"], "handle").rotation_euler = (math.radians(76), 0, 0)
    # ---- mechanism: latch plate, link, main spring
    B(xr - 3.0, xr + 3.0, -20, -4, -10, 10, C["mech"], "mechanism", bw=0.5)
    B(xr - 0.6, xr + 0.6, -6, 10, -8, -5, C["steel"], "mechanism", bw=0.2)
    helix("mechanism", (xr, -12, 12), 10, 1.6, 7, 0.32, C["steel"], axis="Z")
    # ---- line terminal (top) — cage clamp + screw
    for zc, g in ((33, "line_terminal"), (-33, "load_terminal")):
        B(xr - 4.6, xr + 4.6, -8, 3, zc - 4.6, zc + 4.6, C["zinc"], g, bw=0.4)
        cut(kit.G[g][-1], cbox(xr - 3.6, xr + 3.6, -6.5, 1.5, zc - 7, zc + 7))
        screw(xr, -9.0, zc, "-Y", M, str(2 * idx + (1 if zc > 0 else 2)), g, scale=0.9)
        CYL(1.4, -8, 2, xr, zc, C["zinc"], g, axis="Y", bw=0.1, verts=16)
    # ---- magnetic coil: copper helix on bobbin + plunger (axis Y)
    B(xr - 2.0, xr + 2.0, -3, 6, 25, 28.4, C["copper"], "magnetic_coil", bw=0.3)        # strap from line terminal
    CYL(3.0, 2, 18, xr, 17, C["mech"], "magnetic_coil", bw=0.3, axis="Y")               # bobbin
    helix("magnetic_coil", (xr, 10, 17), 14, 4.2, 7, 0.75, C["copper"], axis="Y")
    CYL(1.9, -2, 22, xr, 17, C["steel"], "magnetic_coil", bw=0.2, axis="Y")             # striker plunger
    # ---- contacts: fixed (from coil) and moving arm (pivot)
    B(xr - 2.0, xr + 2.0, 18, 21, 4, 17, C["copper"], "contacts", bw=0.3)
    CYL(1.8, 17.2, 18.2, xr, 6, C["silver"], "contacts", bw=0.2, axis="Y")
    arm = B(xr - 1.6, xr + 1.6, 9, 16.8, -9, 7.5, C["copper"], "contacts", bw=0.3)
    CYL(1.8, 16.3, 17.2, xr, 6, C["silver"], "contacts", bw=0.2, axis="Y")
    CYL(1.4, -3, 3, 9.8 * 0 + 12.5, -8, C["steel"], "contacts", axis="X", bw=0.1, verts=16).location.x = xr * 0.001
    # ---- arc chute: splitter plates + runners
    for k in range(9):
        z = -7 + k * 2.1
        pl = B(xr - 5.5, xr + 5.5, 21.5, 33, z, z + 0.7, C["steel"], "arc_chute", bw=0.1)
    B(xr - 6.2, xr - 5.5, 21, 33.5, -8, 12.5, C["mech"], "arc_chute", bw=0.1)
    B(xr + 5.5, xr + 6.2, 21, 33.5, -8, 12.5, C["mech"], "arc_chute", bw=0.1)
    B(xr - 1.6, xr + 1.6, 19, 22, 13, 15, C["copper"], "arc_chute", bw=0.2)               # upper runner
    B(xr - 1.6, xr + 1.6, 19, 22, -10, -8, C["copper"], "arc_chute", bw=0.2)              # lower runner
    # ---- bimetal + flexible braid to moving arm, then to load terminal
    B(xr - 2.2, xr + 2.2, -2.0, -1.1, -29, -11, C["steelb"], "bimetal", bw=0.15)
    B(xr - 2.2, xr + 2.2, -1.1, -0.2, -29, -11, C["brassb"], "bimetal", bw=0.15)
    B(xr - 1.2, xr + 1.2, -1, 10, -12, -10.6, C["braid"], "bimetal", bw=0.3)
    B(xr - 2.0, xr + 2.0, -3, 2, -30, -28.4, C["copper"], "bimetal", bw=0.3)
    # ---- DIN clip (slider latch)
    B(xr - 4, xr + 4, 30, 36.5, -50, -40, C["body"], "din_clip", bw=0.6)
    B(xr - 2, xr + 2, 30.5, 33, -50, -47.5, C["body"], "din_clip", bw=0.2)


def build_n(M, n=1, rating="C16", handle_color="blue"):
    C = mats(M, handle_color)
    xs = [(i - (n - 1) / 2) * P for i in range(n)]
    for i, x in enumerate(xs):
        pole(C, M, x, i, n, rating, handle_color)
    if n > 1:   # handle tie bar
        o = B(xs[0] - 4, xs[-1] + 4, -40.0, -36.0, -4.5, -0.5, C["handle"], "handle", bw=0.8)
        o.rotation_euler = (math.radians(-14), 0, 0)


class Mod:
    def __init__(self, n, rating, color):
        self.PARTS = PARTS
        self.n, self.rating, self.color = n, rating, color

    def build(self, M):
        build_n(M, self.n, self.rating, self.color)


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "single"
    if what == "single":
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else ["assembled", "exploded"]
        kit.run("mcb_1p", Mod(1, "C16", "blue"),
                dict(target=(0, -0.008, 0), dist=0.24, elev=14, azim=-30, lens_mm=60),
                dict(target=(0, -0.002, 0), dist=0.50, elev=16, azim=-58, lens_mm=50), modes)
    else:
        for n, col, r in ((2, "blue", "C32"), (3, "red", "C25"), (4, "red", "C32")):
            kit.run(f"mcb_{n}p", Mod(n, r, col),
                    dict(target=(0, -0.008, 0), dist=0.24 + 0.03 * n, elev=14, azim=-28, lens_mm=60), {}, ("assembled",))
