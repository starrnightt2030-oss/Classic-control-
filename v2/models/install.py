"""Installation material: DIN rail, wire duct, terminal blocks (screw / push-in, colours, jumper, end plate, end stop),
ferrules & lugs, wire samples. X = length/width, Y = depth (front -Y), Z up. mm."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw


def C_(M):
    return dict(
        zinc=lib.mat("i_zinc", (0.75, 0.76, 0.78), metal=1.0, rough=0.35),
        duct=lib.mat("i_duct", (0.55, 0.56, 0.57), rough=0.5, bump=0.2),
        grey=lib.mat("i_grey", (0.58, 0.59, 0.60), rough=0.45, bump=0.2),
        blue=lib.mat("i_blue", (0.05, 0.25, 0.65), rough=0.45, bump=0.2),
        green=lib.mat("i_green", (0.08, 0.45, 0.10), rough=0.45),
        yellow=lib.mat("i_yellow", (0.85, 0.70, 0.05), rough=0.45),
        orange=lib.mat("i_orange", (0.95, 0.40, 0.02), rough=0.4),
        red=lib.mat("i_red", (0.65, 0.03, 0.02), rough=0.45),
        black=lib.mat("i_black", (0.02, 0.02, 0.022), rough=0.45),
        white=lib.mat("i_white", (0.86, 0.86, 0.84), rough=0.45),
        brown=lib.mat("i_brown", (0.25, 0.10, 0.04), rough=0.45),
        copper=lib.mat("i_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        tin=lib.mat("i_tin", (0.80, 0.80, 0.82), metal=1.0, rough=0.25),
        steel=lib.mat("i_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        ink=lib.mat("i_ink", (0.03, 0.03, 0.04), rough=0.6),
    )


def rail(C, g, x0=-100, x1=100, y_front=0):
    yf = y_front
    B(x0, x1, yf + 6.5, yf + 7.5, -13.5, 13.5, C["zinc"], g, bw=0.2)
    for s in (-1, 1):
        B(x0, x1, yf, yf + 7.5, s * 12.5 - 0.5, s * 13.5 + (0.0 if s > 0 else 0), C["zinc"], g, bw=0.15) if s > 0 else B(x0, x1, yf, yf + 7.5, -13.5, -12.5, C["zinc"], g, bw=0.15)
        B(x0, x1, yf, yf + 1.0, min(s * 13.5, s * 17.5), max(s * 13.5, s * 17.5), C["zinc"], g, bw=0.15)
    crown = kit.G[g][0]
    x = x0 + 12.5
    while x < x1 - 10:
        cut(crown, cbox(x - 7.5, x + 7.5, yf + 5, yf + 9, -2.6, 2.6))
        x += 25


def build_rail(M):
    C = C_(M)
    rail(C, "rail")
    T("35 x 7.5", -60, -0.06, 15.5, 2.2, C["ink"], "rail")


def build_duct(M):
    C = C_(M)
    L = 200
    base = B(-L / 2, L / 2, 0, 2, -20, 20, C["duct"], "duct", bw=0.3)
    for s in (-1, 1):
        w = B(-L / 2, L / 2, -60, 0, min(s * 18.2, s * 20), max(s * 18.2, s * 20), C["duct"], "duct", bw=0.3)
        x = -L / 2 + 6
        while x < L / 2 - 3:
            cut(w, cbox(x - 2.2, x + 2.2, -61, -14, s * 21, s * 17) if s > 0 else cbox(x - 2.2, x + 2.2, -61, -14, -21, -17))
            x += 8
        for k in range(2):
            pass
    for x in (-60, 0, 60):
        cut(base, ccyl(2.5, -1, 3, x, 0))
    cov = B(-L / 2 + 20, L / 2 + 20, -64, -61.5, -21.5, 21.5, C["duct"], "cover", bw=0.6)
    for s in (-1, 1):
        B(-L / 2 + 20, L / 2 + 20, -64, -58, min(s * 21.5, s * 20.2), max(s * 21.5, s * 20.2), C["duct"], "cover", bw=0.3)
    T("40 x 60", 40, -64.06, 0, 4, C["ink"], "cover")


TB_PARTS = {
    "housing":  ("جسم الترمينال العازل", "Insulating housing", (0, 0, 0)),
    "bar":      ("قضيب التوصيل النحاس", "Current bar", (0, -34, 0)),
    "clamps":   ("مشابك الربط (القفص)", "Clamping cages", (0, -52, 0)),
    "screws":   ("مسامير الربط", "Clamping screws", (0, -72, 0)),
    "marker":   ("علامة الترقيم", "Marker tag", (0, -40, 26)),
    "foot":     ("رجل الدين ريل", "DIN-rail foot", (0, 26, 0)),
}


def terminal(C, M, x, color="grey", pushin=False, tag=None, single=False):
    w = 5.2
    body = C[color]
    g = "housing"
    o = B(x - w / 2, x + w / 2, -38, 0, -24, 24, body, g, bw=0.5)
    for z in (13, -13):
        cut(o, cbox(x - w / 2 + 0.7, x + w / 2 - 0.7, -42, -30, z - 4.5, z + 4.5))     # screw access
        cut(o, cbox(x - 1.8, x + 1.8, -30, -20, z * 1.9 - 3, z * 1.9 + 3))           # wire entry
    cut(o, cbox(x - w / 2 + 0.6, x + w / 2 - 0.6, -42, -34, -2.5, 2.5))               # jumper channel
    B(x - w / 2, x + w / 2, -2, 6, -12, 12, body, "foot", bw=0.5)
    if not single:
        rail(C, "foot", -0.5 + x - w / 2, 0.5 + x + w / 2, 6)
    cu = C["copper"] if color != "green" else C["tin"]
    B(x - 1.4, x + 1.4, -24, -21.5, -22, 22, C["tin"], "bar", bw=0.2)
    for z in (13, -13):
        if pushin:
            B(x - 1.9, x + 1.9, -43, -33, z - 3.8, z + 3.8, C["orange"], "screws", bw=0.6)
        else:
            parts, e = lib.screw_terminal((x * 0.001, -31.5 * 0.001, z * 0.001), "-Y", M, label="%s_%d" % (tag or "T", 1 if z > 0 else 2), metal="zinc")
            for p in parts:
                p.scale = (0.75, 0.75, 0.75)
            kit.G["screws"] += parts
            kit.TERMS.append((e, "screws"))
        B(x - 2.0, x + 2.0, -31, -21, z * 1.9 - 3.2, z * 1.9 + 3.2, C["zinc"], "clamps", bw=0.3)
    if tag:
        B(x - w / 2 + 0.3, x + w / 2 - 0.3, -40.5, -38, -6, -3, C["white"], "marker", bw=0.3)
        T(tag, x, -40.56, -4.5, 1.8, C["ink"], "marker")
    if color == "green":
        for k in range(5):
            B(x - w / 2 - 0.01, x + w / 2 + 0.01, -38.02, 0.02, -20 + k * 8, -16 + k * 8, C["yellow"], "housing", bw=0.0)


def build_tb_single(M):
    C = C_(M)
    terminal(C, M, 0, "grey", tag="X1", single=True)


def build_tb_strip(M):
    C = C_(M)
    rail(C, "foot", -40, 40, 6)
    cols = ["grey", "grey", "grey", "blue", "green", "grey", "grey", "grey"]
    tags = ["L1", "L2", "L3", "N", "PE", "1", "2", "3"]
    for i, (c, t) in enumerate(zip(cols, tags)):
        terminal(C, M, -18.2 + i * 5.2, c, pushin=(i >= 5), tag=t, single=True)
    B(-18.2 + 7 * 5.2 + 2.6, -18.2 + 7 * 5.2 + 3.8, -38, 0, -24, 24, C["grey"], "housing", bw=0.3)   # end plate
    for x in (-24.5, 23.5):
        B(x - 3, x + 3, -12, 6, -14, 14, C["black"], "foot", bw=0.8)                         # end stops
        kit.CYL(1.3, -14, -10, x, 0, C["steel"], "foot", bw=0.2)
    jb = B(-18.2 - 1, -18.2 + 2 * 5.2 + 1, -37, -33, -2, 2, C["red"], "bar", bw=0.5)          # jumper L1..L3? (example bridge)
    for i in range(3):
        kit.CYL(1.0, -35, -24, -18.2 + i * 5.2, 0, C["tin"], "bar", bw=0.1)


def build_ferrules(M):
    C = C_(M)
    sizes = [("white", 0.5, 1.0), ("grey", 0.75, 1.2), ("red", 1.0, 1.4), ("black", 1.5, 1.7), ("blue", 2.5, 2.2), ("grey", 4.0, 2.8), ("yellow", 6.0, 3.5)]
    for i, (c, mm2, d) in enumerate(sizes):
        x = -42 + i * 14
        CYL(d / 2 + 1.0, 0, 8, x, 0, C[c], "ferrules", axis="Z", bw=0.4)
        CYL(d / 2 + 1.4, 6, 8, x, 0, C[c], "ferrules", axis="Z", bw=0.4)
        o = CYL(d / 2 + 0.25, -10, 0.5, x, 0, C["tin"], "ferrules", axis="Z", bw=0.1)
        T("%gmm²" % mm2 if False else str(mm2), x, -8, -16, 2.6, C["ink"], "ferrules", rot=(90, 0, 0))
    # insulated ring & fork lugs (red / blue / yellow)
    for j, (c, lab) in enumerate((("red", "0.5-1.5"), ("blue", "1.5-2.5"), ("yellow", "4-6"))):
        for k, kind in enumerate(("ring", "fork")):
            x = -42 + (j * 2 + k) * 17
            y = 40
            CYL(3.2, -4, 10, x, y, C[c], "lugs", axis="Z", bw=1.2)
            B(x - 1.0, x + 1.0, y - 0.4, y + 0.4, -14, -4, C["tin"], "lugs", bw=0.1) if False else None
            o = B(x - 4.2, x + 4.2, y - 0.5, y + 0.5, -16, -4, C["tin"], "lugs", bw=0.3)
            if kind == "ring":
                cut(o, ccyl(2.1, y - 2, y + 2, x, -10))
            else:
                cut(o, cbox(x - 1.9, x + 1.9, y - 2, y + 2, -18, -9))
            T(lab, x, y - 5, 14, 2.2, C["ink"], "lugs", rot=(90, 0, 0)) if k == 0 else None
    # wire with ferrule + marker sleeve
    for j, c in enumerate(("brown", "black", "grey", "blue")):
        y = 70 + j * 6
        CYL(1.6, -40, 30, y, -6, C[c], "wires", axis="X", bw=0.4)
        CYL(0.8, 30, 34, y, -6, C["copper"], "wires", axis="X", bw=0.1)
        CYL(2.2, 34, 41, y, -6, C["black" if c != "black" else "red"], "wires", axis="X", bw=0.3)
        CYL(1.0, 41, 49, y, -6, C["tin"], "wires", axis="X", bw=0.1)
        CYL(2.6, 10, 20, y, -6, C["white"], "wires", axis="X", bw=0.3)
        T(str(j + 1), 15, y, -3.3, 2.2, C["ink"], "wires", rot=(0, 0, 0))


class V:
    def __init__(self, parts, fn, **kw):
        self.PARTS, self.fn, self.kw = parts, fn, kw

    def build(self, M):
        self.fn(M, **self.kw)


GEN = lambda keys: {k: (k, k, (0, 0, 0)) for k in keys}
VARIANTS = {
    "din_rail":         (V({"rail": ("الدين ريل 35 مللي", "DIN rail 35 mm", (0, 0, 0))}, build_rail), False, (0, 0.004, 0), 0.32),
    "wire_duct":        (V({"duct": ("مجرى الأسلاك", "Wire duct", (0, 0, 0)), "cover": ("غطاء المجرى", "Duct cover", (0, -40, 0))}, build_duct), True, (0, -0.030, 0), 0.40),
    "terminal_block":   (V(TB_PARTS, build_tb_single), True, (0, -0.016, 0), 0.16),
    "terminal_strip":   (V(TB_PARTS, build_tb_strip), False, (0, -0.016, 0), 0.20),
    "ferrules_lugs":    (V({"ferrules": ("الجلب (الفيرول)", "Wire ferrules", (0, 0, 0)), "lugs": ("أطراف الكابلات", "Cable lugs", (0, 0, 0)),
                            "wires": ("أسلاك بجلب وأرقام", "Wires with ferrules & markers", (0, 0, 0))}, build_ferrules), False, (0, 0.035, -0.004), 0.30),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, expl, tgt, dist = VARIANTS[n]
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else (["assembled", "exploded"] if expl else ["assembled"])
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=24, azim=-35, lens_mm=60),
                dict(target=(tgt[0], -0.030, tgt[2]), dist=dist * 2.4, elev=18, azim=-40, lens_mm=50), modes)
