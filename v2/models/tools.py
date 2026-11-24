"""Trainee tools: digital multimeter, clamp meter, test leads, wire stripper, ferrule crimper, screwdriver. Front -Y, Z up. mm."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix


def C_(M):
    return dict(
        red=lib.mat("t_red", (0.60, 0.03, 0.02), rough=0.5, bump=0.3),
        dark=lib.mat("t_dark", (0.06, 0.06, 0.065), rough=0.5, bump=0.2),
        black=lib.mat("t_black", (0.02, 0.02, 0.022), rough=0.45),
        yellow=lib.mat("t_yellow", (0.95, 0.65, 0.02), rough=0.45, bump=0.2),
        lcd=lib.mat("t_lcd", (0.55, 0.66, 0.62), rough=0.25),
        ink=lib.mat("t_ink", (0.02, 0.02, 0.03), rough=0.6),
        wink=lib.mat("t_wink", (0.9, 0.9, 0.9), rough=0.6),
        steel=lib.mat("t_steel", (0.74, 0.75, 0.77), metal=1.0, rough=0.25),
        blue=lib.mat("t_blue", (0.05, 0.20, 0.60), rough=0.5),
        orange=lib.mat("t_orange", (0.95, 0.45, 0.02), rough=0.45),
        grey=lib.mat("t_grey", (0.40, 0.41, 0.43), rough=0.5),
    )


def rot0(o, e):
    lib._sel(o)
    bpy.ops.object.transform_apply(location=True)
    o.rotation_euler = e
    return o


def build_multimeter(M):
    C = C_(M)
    B(-42, 42, -2, 26, -90, 90, C["red"], "body", bw=8.0)
    B(-36, 36, -4, 0, -84, 84, C["dark"], "body", bw=4.0)
    B(-30, 30, -5, -3.5, 36, 72, C["lcd"], "body", bw=1.5)
    T("230.4", 4, -5.06, 54, 16, C["ink"], "body")
    T("AC  V", -20, -5.06, 66, 4, C["ink"], "body")
    T("DIGITAL MULTIMETER", 0, -4.06, 30.5, 3.2, C["wink"], "body")
    for i, (x, col, lab) in enumerate(((-24, C["yellow"], "SEL"), (0, C["grey"], "OFF"), (24, C["blue"], "HOLD"))):
        B(x - 8, x + 8, -6, -3.5, 16, 24, col, "body", bw=1.5)
        T(lab, x, -6.06, 20, 3.0, C["ink"] if lab != "OFF" else C["wink"], "body")
    CYL(26, -8, -3.5, 0, -18, C["black"], "body", bw=2.5, verts=96)
    p = B(-5, 5, -14, -7.5, -42, 6, C["black"], "body", bw=2.5)
    B(-1.2, 1.2, -14.2, -13.8, -4, 4, C["red"], "body", bw=0.2)
    for i, lab in enumerate(["OFF", "V~", "V=", "mV", "Ω", "·))", "A", "mA", "Hz"]):
        a = math.radians(90 - i * 36)
        T(lab if lab not in ("Ω", "·))") else ("OHM" if lab == "Ω" else "BEEP"), 32 * math.cos(a), -4.06, -18 + 32 * math.sin(a), 3.4, C["wink"], "body")
    for x, col, lab in ((-28, C["red"], "10A"), (-9, C["red"], "mA"), (9, C["black"], "COM"), (28, C["red"], "VΩ")):
        CYL(5.2, -5, -3, x, -70, col, "body", bw=0.8)
        cut(kit.G["body"][-1], ccyl(2.2, -7, 0, x, -70))
        T(lab if lab != "VΩ" else "V OHM", x, -4.06, -61, 3.0, C["wink"], "body")


def build_clamp(M):
    C = C_(M)
    B(-30, 30, -2, 22, -110, 40, C["dark"], "body", bw=7.0)
    jaw = lib.torus(0.034, 0.0075, 0, C["yellow"])
    jaw.rotation_euler = (math.radians(90), 0, 0)
    jaw.location = (0, 0.010, 0.080)
    kit.G["body"].append(jaw)
    B(-4, 4, 2, 18, 40, 50, C["dark"], "body", bw=1.0)
    B(-40, -28, 0, 20, 20, 50, C["yellow"], "body", bw=4.0)                  # trigger
    B(-24, 24, -4, -2, -12, 18, C["lcd"], "body", bw=1.0)
    T("12.6", 2, -4.06, 5, 13, C["ink"], "body")
    T("AC  A", -14, -4.06, 14, 3, C["ink"], "body")
    CYL(18, -7, -2, 0, -40, C["black"], "body", bw=2.0, verts=96)
    B(-4, 4, -12, -6.5, -62, -18, C["black"], "body", bw=2.0)
    for i, lab in enumerate(["OFF", "ACA 200", "ACA 1000", "ACV 750", "DCV", "OHM"]):
        a = math.radians(150 - i * 24)
        T(lab, 25 * math.cos(a), -2.06, -40 + 25 * math.sin(a), 2.6, C["wink"], "body")
    for x, col, lab in ((-16, C["red"], "V OHM"), (0, C["black"], "COM"), (16, C["orange"], "EXT")):
        CYL(4.5, -4, -2, x, -92, col, "body", bw=0.6)
        T(lab, x, -2.06, -84, 2.6, C["wink"], "body")
    T("DIGITAL CLAMP METER", 0, -2.06, 27, 3.2, C["wink"], "body")


def build_leads(M):
    C = C_(M)
    for x, col in ((-8, C["red"]), (8, C["black"])):
        CYL(4.5, -60, 40, x, 0, col, "body", axis="Z", bw=1.5)
        CYL(6.5, 30, 34, x, 0, col, "body", axis="Z", bw=1.0)
        CYL(1.0, 40, 58, x, 0, C["steel"], "body", axis="Z", bw=0.2, r2=0.3)
        CYL(3.0, -80, -60, x, 0, col, "body", axis="Z", bw=0.4)
        CYL(2.0, -95, -80, x, 0, C["steel"], "body", axis="Z", bw=0.3)


def build_stripper(M):
    C = C_(M)
    for s in (-1, 1):
        h = B(-8, 8, -3, 3, -110, -10, C["blue"], "body", bw=3.0)
        B(-6, 6, -3.4, -2.6, -100, -40, C["dark"], "body", bw=1.0)
        rot0(h, (0, math.radians(s * 7), 0))
        h.location = (s * 0.004, 0, 0)
    B(-14, 14, -4, 4, -10, 40, C["steel"], "body", bw=1.5)
    for k, (z, r) in enumerate(((30, 1.2), (24, 0.9), (18, 0.7))):
        cut(kit.G["body"][-1], ccyl(r, -6, 6, -10, z))
        T(["2.5", "1.5", "1.0"][k], -4, -4.06, z, 2.6, C["ink"], "body")
    CYL(4, -6, 6, 0, 0, C["steel"], "body", bw=0.8)
    T("WIRE STRIPPER", 0, -4.06, 8, 2.6, C["ink"], "body")


def build_crimper(M):
    C = C_(M)
    for s in (-1, 1):
        h = B(-9, 9, -4, 4, -120, -20, C["red"], "body", bw=3.5)
        B(-9.2, 9.2, -4.4, 4.4, -95, -60, C["blue"], "body", bw=3.0)
        rot0(h, (0, math.radians(s * 9), 0))
        h.location = (s * 0.007, 0, 0)
    head = B(-24, 24, -5, 5, -22, 34, C["black"], "body", bw=6.0)
    cut(head, cbox(-4, 4, -7, 7, 2, 10))
    T("CRIMP 0.25-10mm²" if False else "CRIMP 0.25-10 mm2", 0, -5.06, -14, 3.0, C["wink"], "body")
    CYL(4, -6, 6, -12, 18, C["steel"], "body", bw=0.8)


def build_screwdriver(M):
    C = C_(M)
    CYL(14, 0, 95, 0, 0, C["red"], "body", axis="Z", bw=5.0, verts=8)
    CYL(14.2, 30, 70, 0, 0, C["yellow"], "body", axis="Z", bw=4.0, verts=8)
    CYL(3, 95, 200, 0, 0, C["steel"], "body", axis="Z", bw=0.4)
    CYL(3.5, 95, 200, 0, 0, C["red"], "body", axis="Z", bw=0.4) if False else None
    B(-2.5, 2.5, -0.5, 0.5, 200, 206, C["steel"], "body", bw=0.2)
    T("1000V", 0, -14.2, 50, 5, C["ink"], "body", rot=(90, 0, 0))


class V:
    def __init__(self, fn):
        self.PARTS = {"body": ("الأداة", "Tool", (0, 0, 0))}
        self.fn = fn

    def build(self, M):
        self.fn(M)


VARIANTS = {
    "multimeter": (V(build_multimeter), (0, 0, 0), 0.40, 14),
    "clamp_meter": (V(build_clamp), (0, 0, -0.010), 0.46, 14),
    "test_leads": (V(build_leads), (0, 0, -0.020), 0.40, 20),
    "wire_stripper": (V(build_stripper), (0, 0, -0.035), 0.42, 14),
    "ferrule_crimper": (V(build_crimper), (0, 0, -0.040), 0.46, 14),
    "screwdriver": (V(build_screwdriver), (0, 0, 0.100), 0.50, 24),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, tgt, dist, el = VARIANTS[n]
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=el, azim=-22, lens_mm=60), {}, ("assembled",))
