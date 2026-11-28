"""Residential wiring components for أكاديمية التمديدات الكهربية (Blender, procedural).

Front faces -Y, Z up, units mm (kit helpers). Every device that takes wires sits on a
grey training-board terminal strip whose screw terminals face the front, so the board
view can show where each wire lands. Terminal empties are TERM_<id>.

    python residential.py              # every model -> wiring/app/assets/models/<name>.glb
    python residential.py sw1 lamp     # only these
    python residential.py --hero ...   # also a studio render (assets/renders/<name>.jpg)
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "v2", "models"))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import kit  # noqa: E402
import lib  # noqa: E402
from kit import B, CYL, T  # noqa: E402

OUT = os.path.join(HERE, "..", "app", "assets", "models")
REN = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
os.makedirs(REN, exist_ok=True)


# ------------------------------------------------------------------ materials
def C_(M):
    return dict(
        plate=lib.mat("r_plate", (0.86, 0.86, 0.84), rough=0.32, coat=0.4, bump=0.15),
        plate2=lib.mat("r_plate2", (0.80, 0.80, 0.78), rough=0.4, bump=0.2),
        base=lib.mat("r_base", (0.30, 0.31, 0.33), rough=0.55, bump=0.25),
        dark=lib.mat("r_dark", (0.05, 0.05, 0.055), rough=0.45, bump=0.2),
        ink=lib.mat("r_ink", (0.02, 0.02, 0.025), rough=0.6),
        wink=lib.mat("r_wink", (0.92, 0.92, 0.92), rough=0.6),
        red=lib.mat("r_red", (0.55, 0.02, 0.02), rough=0.35, coat=0.5),
        blue=lib.mat("r_blue", (0.02, 0.12, 0.55), rough=0.4),
        green=lib.mat("r_green", (0.02, 0.32, 0.06), rough=0.4),
        yellow=lib.mat("r_yellow", (0.85, 0.62, 0.02), rough=0.4),
        orange=lib.mat("r_orange", (0.9, 0.35, 0.02), rough=0.4),
        ceramic=lib.mat("r_ceramic", (0.90, 0.88, 0.82), rough=0.18, coat=0.8),
        glass=lib.mat("r_glass", (0.95, 0.95, 0.95), rough=0.03, trans=1.0, ior=1.5),
        frost=lib.mat("r_frost", (0.95, 0.95, 0.93), rough=0.35, trans=0.6, ior=1.45),
        steel=M["satin"],
        zinc=M["zinc"],
        brass=M["brass"],
        copper=M["copper"],
        chrome=M["chrome"],
        rubber=lib.mat("r_rubber", (0.02, 0.02, 0.02), rough=0.8),
        pvc_grey=lib.mat("r_pvc", (0.55, 0.56, 0.57), rough=0.5, bump=0.2),
        pvc_orange=lib.mat("r_pvco", (0.85, 0.36, 0.05), rough=0.45),
        wood=lib.mat("r_wood", (0.55, 0.33, 0.15), rough=0.6, bump=0.4),
    )


def glow(name, color, strength):
    return lib.mat(name, color, rough=0.3, emit=(color, strength))


def strip(C, M, g, xs, z, labels, y=0.0, pad=7.0):
    """Training-board terminal strip with front screws at (x, z)."""
    B(min(xs) - pad, max(xs) + pad, y - 1, y + 8, z - 7, z + 7, C["base"], g, bw=1.2)
    for x, lab in zip(xs, labels):
        B(x - 4.2, x + 4.2, y - 1.6, y - 0.9, z - 5.6, z + 5.6, C["dark"], g, bw=0.4)
        kit.screw(x, y - 1.6, z, "-Y", M, lab, g, metal="brass")
        T(lab, x, y - 1.05, z + 9.5 if z + 9.5 < z + 12 else z, 3.2, C["wink"], g)


def plate(C, g, w=86, h=86, z0=0, d=9):
    B(-w / 2, w / 2, -d, 0, z0, z0 + h, C["plate"], g, bw=3.5)
    return z0 + h / 2


def rocker(C, g, x0, x1, zc, on, h=56, label=None):
    """Rocker seen from the front: on = pressed at the bottom (top raised)."""
    o = B(x0, x1, -14, -8, -h / 2, h / 2, C["plate2"], g, bw=2.5)
    o.rotation_euler = (math.radians(-6 if on else 6), 0, 0)
    o.location.z += zc * kit.mm
    # the pressed half shows a red stripe so ON/OFF reads at a glance
    m = B(x0 + 3, x1 - 3, -14.6, -13.4, -h / 2 + 4, -h / 2 + 8, C["red"] if on else C["plate2"], g, bw=0.4)
    m.rotation_euler = o.rotation_euler
    m.location.z += zc * kit.mm
    if label:
        T(label, (x0 + x1) / 2, -14.2, zc + h / 2 - 8, 4, C["red"] if on else C["ink"], g)
    return o


# ------------------------------------------------------------------- devices
PARTS_STD = {"body": ("الجسم", "Body", (0, -30, 0)), "mech": ("الميكانيزم والأطراف", "Mechanism & terminals", (0, 30, 0))}


def wall_switch(kind, state):
    def build(M):
        C = C_(M)
        zc = plate(C, "body", z0=19)
        B(-31, 31, -10.5, -8.5, zc - 33, zc + 33, C["plate2"], "body", bw=1.5)
        if kind == "swd":
            rocker(C, "body", -29, -1.5, zc, state[0] == "1")
            rocker(C, "body", 1.5, 29, zc, state[1] == "1")
        elif kind == "dimmer":
            CYL(18, -24, -10, 0, zc, C["plate2"], "body", axis="Y", bw=1.5, verts=64)
            CYL(15, -27, -24, 0, zc, C["plate"], "body", axis="Y", bw=1.0, verts=64)
            B(-1.2, 1.2, -27.5, -26.5, zc + 5, zc + 14, C["dark"], "body", bw=0.3)
        else:
            rocker(C, "body", -27, 27, zc, state == "1")
            if kind == "sw2":
                T("2", 22, -10.6, zc + 28, 4, C["ink"], "body")
            if kind == "swi":
                T("X", 22, -10.6, zc + 28, 4, C["ink"], "body")
        terms = {"sw1": ["L", "1"], "dimmer": ["L", "1"], "sw2": ["C", "1", "2"], "swd": ["L", "1", "2"], "swi": ["A1", "A2", "B1", "B2"]}[kind]
        pitch = 16 if len(terms) == 4 else 20
        xs = [(i - (len(terms) - 1) / 2) * pitch for i in range(len(terms))]
        strip(C, M, "mech", xs, 9, terms)
    return build


def bell_push(state):
    def build(M):
        C = C_(M)
        zc = plate(C, "body", w=70, h=70, z0=19)
        CYL(17, -12, -9, 0, zc, C["plate2"], "body", axis="Y", bw=1.0)
        CYL(11, -17 if state == "0" else -13, -11, 0, zc, C["yellow"], "body", axis="Y", bw=1.2)
        T("🔔" if False else "BELL", 0, -17.2 if state == "0" else -13.2, zc - 1.5, 4, C["ink"], "body")
        strip(C, M, "mech", [-12, 12], 9, ["1", "2"])
    return build


def socket(M):
    C = C_(M)
    zc = plate(C, "body", z0=19)
    CYL(25, -18, -9, 0, zc, C["plate2"], "body", axis="Y", bw=2.0, verts=96)
    o = CYL(21, -19, -14, 0, zc, C["plate"], "body", axis="Y", bw=1.0, verts=96)
    for x in (-9.5, 9.5):
        h = kit.ccyl(2.4, -21, -12, x, zc, axis="Y")
        kit.cut(o, h)
    for zz in (zc + 21, zc - 21):
        B(-4, 4, -18.5, -14, zz - 2, zz + 2, C["steel"], "body", bw=0.5)
    strip(C, M, "mech", [-20, 0, 20], 9, ["L", "N", "PE"])


def lamp(kind, on):
    def build(M):
        C = C_(M)
        # batten holder
        CYL(34, 0, 18, 0, 0, C["ceramic"], "body", axis="Z", bw=3.0, verts=96)
        CYL(18, 18, 44, 0, 0, C["ceramic"], "body", axis="Z", bw=2.0, verts=64)
        CYL(14.5, 44, 54, 0, 0, C["zinc"], "body", axis="Z", bw=0.8, verts=64)
        for k in range(5):
            kit.G["body"].append(lib.torus(14.6 * kit.mm, 0.9 * kit.mm, (45.5 + k * 1.9) * kit.mm, C["zinc"]))
        if kind == "led":
            CYL(16, 54, 66, 0, 0, C["plate"], "glass", axis="Z", bw=2.0, verts=64, r2=27)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=30 * kit.mm, location=(0, 0, 86 * kit.mm), segments=64, ring_count=32)
            g = bpy.context.object
            g.scale.z = 0.95
            g.data.materials.append(glow("r_led_on", (1.0, 0.97, 0.92), 9.0) if on else C["frost"])
            lib._sel(g)
            bpy.ops.object.shade_smooth()
            kit.G["glass"].append(g)
        else:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=31 * kit.mm, location=(0, 0, 92 * kit.mm), segments=64, ring_count=32)
            g = bpy.context.object
            g.data.materials.append(glow("r_inc_on", (1.0, 0.78, 0.45), 3.5) if on else lib.mat("r_bulb", (0.97, 0.96, 0.93), rough=0.25, trans=0.35, ior=1.45))
            lib._sel(g)
            bpy.ops.object.shade_smooth()
            kit.G["glass"].append(g)
            CYL(13, 54, 70, 0, 0, C["glass"], "glass", axis="Z", bw=1.0, verts=48, r2=17)
            CYL(2.2, 56, 82, 0, 0, C["glass"], "glass", axis="Z", bw=0.3, verts=24)
            fil = glow("r_fil_on", (1.0, 0.62, 0.22), 60.0) if on else C["dark"]
            kit.helix("glass", (0, 0, 92), 14, 1.4, 9, 0.35, fil, axis="X")
            for x in (-7, 7):
                cu = CYL(0.4, 70, 92, x, 0, C["steel"], "glass", axis="Z", bw=0, verts=8)
        strip(C, M, "mech", [-14, 14], -7, ["L", "N"], y=-36)
    return build


def bell(M):
    C = C_(M)
    B(-30, 30, -6, 6, 0, 18, C["base"], "body", bw=2.0)
    CYL(28, -14, -6, 0, 50, C["red"], "gong", axis="Y", bw=1.0, verts=96)
    CYL(25, -16, -14, 0, 50, C["red"], "gong", axis="Y", bw=1.2, verts=96, r2=18)
    CYL(4, -18, -16, 0, 50, C["chrome"], "gong", axis="Y", bw=0.5)
    B(-3, 3, -10, -6, 18, 30, C["dark"], "body", bw=0.5)
    CYL(3.5, -12, -8, 0, 24, C["chrome"], "body", axis="Y")
    strip(C, M, "mech", [-12, 12], 10, ["1", "2"], y=-12)


def door_lock(open_):
    def build(M):
        C = C_(M)
        B(-30, 30, -12, 6, 30, 110, C["steel"], "body", bw=2.0)
        B(-24, 24, -13, -12, 36, 104, C["plate2"], "body", bw=1.0)
        T("12-220V", 0, -13.1, 92, 5, C["ink"], "body")
        bx = 30 if not open_ else 12
        B(bx - 26, bx, -8, 2, 60, 74, C["chrome"], "bolt", bw=2.0)
        strip(C, M, "mech", [-12, 12], 12, ["1", "2"])
    return build


def tube(on):
    def build(M):
        C = C_(M)
        L = 300
        B(-L / 2 - 16, L / 2 + 16, -4, 12, -20, 20, C["plate"], "body", bw=4.0)
        tm = glow("r_tube_on", (0.96, 0.98, 1.0), 14.0) if on else C["frost"]
        CYL(13, -L / 2, L / 2, -14, 0, tm, "tube", axis="X", bw=2.0, verts=64)
        for x in (-L / 2 - 4, L / 2 + 4):
            CYL(14, x - 8 if x < 0 else x - 4, x + 4 if x < 0 else x + 8, -14, 0, C["steel"], "tube", axis="X", bw=1.0)
        for side, (a, b) in ((-1, ("A1", "A2")), (1, ("B1", "B2"))):
            x = side * (L / 2 + 6)
            kit.screw(x, -4.6, 10, "-Y", M, a, "body", metal="brass")
            kit.screw(x, -4.6, -10, "-Y", M, b, "body", metal="brass")
    return build


def ballast(M):
    C = C_(M)
    B(-70, 70, -15, 15, -18, 18, C["dark"], "body", bw=2.0)
    B(-80, 80, -2, 2, -22, 22, C["steel"], "body", bw=0.8)
    B(-45, 45, -15.3, -15, -12, 12, C["plate2"], "body", bw=0.5)
    T("BALLAST 40W  220V", 0, -15.4, 3, 5, C["ink"], "body")
    T("0.43A  50Hz", 0, -15.4, -6, 4, C["ink"], "body")
    for x, lab in ((-62, "1"), (62, "2")):
        B(x - 7, x + 7, -17, -15, -10, 10, C["plate2"], "body", bw=0.8)
        kit.screw(x, -17.4, 0, "-Y", M, lab, "body", metal="brass")


def starter(M):
    C = C_(M)
    B(-20, 20, -4, 8, 0, 14, C["base"], "body", bw=1.2)
    CYL(10.5, 14, 52, 0, 0, C["blue"], "body", axis="Z", bw=2.0, verts=64)
    T("S10", 0, -10.6, 40, 4, C["wink"], "body", )
    T("4-65W", 0, -10.6, 33, 3, C["wink"], "body")
    kit.screw(-11, -4.4, 7, "-Y", M, "1", "body", metal="brass")
    kit.screw(11, -4.4, 7, "-Y", M, "2", "body", metal="brass")


def stair_timer(M):
    C = C_(M)
    B(-9, 9, -2, 50, -45, 45, C["plate"], "body", bw=1.0)
    B(-9, 9, -12, -2, -22, 22, C["plate"], "body", bw=1.0)
    CYL(5.5, -15, -12, 0, 8, C["plate2"], "body", axis="Y", bw=0.6)
    B(-0.6, 0.6, -15.6, -14.8, 9, 13, C["ink"], "body", bw=0)
    CYL(1.6, -13, -11.8, 0, -8, glow("r_led_g", (0.1, 1.0, 0.2), 6.0), "body", axis="Y")
    T("TIMER", 0, -12.1, -16, 2.6, C["ink"], "body")
    for x, z, lab in ((-5.5, 37, "L"), (0, 37, "N"), (5.5, 37, "S"), (0, -37, "O")):
        kit.screw(x, -2.4, z, "-Y", M, lab, "body", scale=0.75)


def driver(M):
    C = C_(M)
    B(-60, 60, -14, 14, -22, 22, C["plate"], "body", bw=3.0)
    T("LED DRIVER", 0, -14.2, 8, 6, C["ink"], "body")
    T("AC 220V  →  DC 36V 300mA", 0, -14.2, -4, 3.6, C["ink"], "body")
    for x, z, lab in ((-50, 10, "L"), (-50, -10, "N"), (50, 10, "+"), (50, -10, "-")):
        B(x - 7, x + 7, -15, -14, z - 6, z + 6, C["dark"], "body", bw=0.4)
        kit.screw(x, -15.4, z, "-Y", M, lab, "body", metal="brass")


def led_panel(on):
    def build(M):
        C = C_(M)
        B(-60, 60, -4, 10, 0, 120, C["plate"], "body", bw=3.0)
        B(-52, 52, -5, -3, 8, 112, glow("r_panel_on", (1.0, 1.0, 1.0), 10.0) if on else C["frost"], "body", bw=1.0)
        strip(C, M, "mech", [-12, 12], -10, ["+", "-"])
    return build


def bar(kind):
    def build(M):
        C = C_(M)
        col = C["blue"] if kind == "n" else C["green"]
        for x in (-48, 48):
            B(x - 6, x + 6, -2, 10, -12, 12, col, "body", bw=1.5)
        B(-55, 55, -10, -2, -6, 6, C["brass"], "bar", bw=0.8)
        labels = ["n1", "n2", "n3", "n4"] if kind == "n" else ["e1", "e2", "e3", "e4"]
        for x, lab in zip((-39, -13, 13, 39), labels):
            kit.screw(x, -10.2, 0, "-Y", M, lab, "bar", metal="zinc")
        T("N" if kind == "n" else "PE", -48, -2.2, 0, 7, C["wink"], "body")
    return build


def jbox(n):
    def build(M):
        C = C_(M)
        cols = n // 2
        w = 34 + cols * 16
        B(-w / 2, w / 2, 0, 30, -40, 40, C["pvc_grey"], "body", bw=3.0)
        o = B(-w / 2 + 4, w / 2 - 4, -1, 26, -36, 36, C["pvc_grey"], "body", bw=1.0)
        # knock-outs
        for x in (-w / 4, w / 4):
            CYL(8, 39, 41, x, 15, C["pvc_grey"], "body", axis="Z", bw=0.5)
            CYL(8, -41, -39, x, 15, C["pvc_grey"], "body", axis="Z", bw=0.5)
        # connector strip ("domino"), two rows: top row t1..tc, bottom row tc+1..tn
        for row, zz in ((0, 14), (1, -14)):
            B(-cols * 8 - 3, cols * 8 + 3, -4, 2, zz - 8, zz + 8, C["plate"], "mech", bw=1.0)
            for i in range(cols):
                x = (i - (cols - 1) / 2) * 16
                kit.screw(x, -4.3, zz, "-Y", M, "t%d" % (row * cols + i + 1), "mech", metal="brass")
    return build


def supply(M):
    C = C_(M)
    B(-60, 60, -2, 40, 0, 90, C["dark"], "body", bw=4.0)
    B(-50, 50, -3, -2, 56, 84, C["base"], "body", bw=1.0)
    T("220V ~ 50Hz", 0, -3.1, 74, 8, C["wink"], "body")
    T("SUPPLY", 0, -3.1, 63, 5, C["yellow"], "body")
    CYL(6, -6, -2, 44, 74, glow("r_pilot", (1.0, 0.05, 0.02), 10), "body", axis="Y", bw=0.8)
    for x, lab, col in ((-30, "L", C["orange"]), (0, "N", C["blue"]), (30, "PE", C["green"])):
        B(x - 11, x + 11, -3, -2, 8, 40, col, "body", bw=0.6)
        kit.screw(x, -3.4, 22, "-Y", M, lab, "body", metal="brass")
        T(lab, x, -3.1, 35, 5, C["wink"], "body")


# --------------------------------------------------------------------- tools
def pliers(kind):
    def build(M):
        C = C_(M)
        grip = C["red"] if kind == "pliers" else C["yellow"]
        for s in (-1, 1):
            for k in range(6):
                z = -10 - k * 22
                B(s * 4 - 7 + s * k * 2.2, s * 4 + 7 + s * k * 2.2, -6, 6, z - 12, z + 12, grip, "grip", bw=4.0)
            B(s * 3 - 5, s * 3 + 5, -5, 5, -10, 30, C["steel"], "head", bw=1.5)
        if kind == "pliers":
            B(-7, 7, -5, 5, 30, 75, C["steel"], "head", bw=2.0)
            for k in range(10):
                B(-7.5, 7.5, -5.2, -4.8, 48 + k * 2.5, 49 + k * 2.5, C["dark"], "head", bw=0)
        else:
            CYL(13, -5, 5, 0, 44, C["steel"], "head", axis="Y", bw=1.5, r2=None)
        CYL(5, -6, 6, 0, 22, C["chrome"], "head", axis="Y")
        T("1000V", 0, -6.2, -60, 5, C["wink"], "grip")
    return build


def tester(M):
    C = C_(M)
    CYL(1.6, -60, 0, 0, 0, C["steel"], "blade", axis="Z", bw=0.3)
    B(-1.8, 1.8, -0.4, 0.4, -66, -58, C["steel"], "blade", bw=0.1)
    CYL(7, 0, 110, 0, 0, glow("r_tester_body", (0.9, 0.3, 0.05), 0.0) if False else lib.mat("r_tbody", (0.95, 0.55, 0.08), rough=0.2, trans=0.5), "body", axis="Z", bw=2.0)
    CYL(2.0, 30, 60, 0, -4, lib.mat("r_neon", (1.0, 0.25, 0.05), rough=0.2, emit=((1.0, 0.25, 0.05), 4.0)), "body", axis="Z")
    CYL(7.5, 110, 116, 0, 0, C["chrome"], "body", axis="Z", bw=1.0)
    T("100-500V", 0, -7.2, 80, 4, C["ink"], "body", rot=(90, 0, 90))


def hammer(M):
    C = C_(M)
    B(-9, 9, -9, 9, 0, 260, C["wood"], "handle", bw=5.0)
    B(-55, 45, -12, 12, 250, 280, C["steel"], "head", bw=2.0)
    CYL(14, -70, -55, 0, 265, C["steel"], "head", axis="X", bw=1.5)


def tape(M):
    C = C_(M)
    CYL(25, -9, 9, 0, 0, C["blue"], "body", axis="Y", bw=1.0, verts=96)
    CYL(16, -9.3, 9.3, 0, 0, lib.mat("r_core", (0.7, 0.6, 0.45), rough=0.7), "body", axis="Y", verts=96)
    CYL(14, -10, 10, 0, 0, C["dark"], "body", axis="Y", verts=64)


def conduit(M):
    C = C_(M)
    for k, z in enumerate((0, 30, 60)):
        CYL(10, -150, 150, 0, z, C["pvc_grey"], "pipe", axis="X", bw=0.8, verts=64)
    CYL(12, -150, 150, 0, 95, C["pvc_orange"], "flex", axis="X", bw=0.5, verts=64)
    for k in range(40):
        kit.G["flex"].append(lib.torus(12.4 * kit.mm, 1.0 * kit.mm, 0, C["pvc_orange"]))
        o = kit.G["flex"][-1]
        o.rotation_euler = (0, math.radians(90), 0)
        o.location = ((-145 + k * 7.4) * kit.mm, 0, 95 * kit.mm)


def coil(color):
    def build(M):
        C = C_(M)
        m = {"brown": lib.mat("r_wbr", (0.25, 0.09, 0.03), rough=0.35, coat=0.5),
             "blue": lib.mat("r_wbu", (0.02, 0.12, 0.55), rough=0.35, coat=0.5),
             "earth": lib.mat("r_wge", (0.1, 0.45, 0.08), rough=0.35, coat=0.5)}[color]
        for i in range(9):
            for j in range(4):
                kit.G["coil"].append(lib.torus((38 + j * 3.2) * kit.mm, 1.6 * kit.mm, (i * 3.2) * kit.mm, m))
        CYL(1.2, -10, 30, 55, 0, C["copper"], "coil", axis="X", bw=0)
    return build


def flush_box(M):
    C = C_(M)
    o = B(-35, 35, -35, 35, 0, 45, C["pvc_orange"], "body", bw=2.0)
    kit.cut(o, kit.cbox(-32, 32, -32, 32, 3, 50))
    for x in (-25, 25):
        CYL(3, 0, 45, x, 0, C["pvc_orange"], "body", axis="Z", bw=0.5)


def earth_rod(M):
    C = C_(M)
    CYL(8, 0, 600, 0, 0, C["copper"], "rod", axis="Z", bw=0.5, r2=None)
    CYL(8, -30, 0, 0, 0, C["copper"], "rod", axis="Z", bw=0.5, r2=1)
    B(-14, 14, -14, 14, 560, 590, C["brass"], "clamp", bw=2.0)
    CYL(4, -24, 24, 0, 575, C["zinc"], "clamp", axis="Y")


# ------------------------------------------------------------------ registry
MODELS = {
    "supply": (supply, "مصدر التغذية"),
    "nbar": (bar("n"), "قضيب النيوترال"),
    "ebar": (bar("e"), "قضيب الأرضي"),
    "sw1_0": (wall_switch("sw1", "0"), "مفتاح مفرد"), "sw1_1": (wall_switch("sw1", "1"), "مفتاح مفرد"),
    "sw2_0": (wall_switch("sw2", "0"), "مفتاح دفياتير"), "sw2_1": (wall_switch("sw2", "1"), "مفتاح دفياتير"),
    "swi_0": (wall_switch("swi", "0"), "مفتاح انترميديت"), "swi_1": (wall_switch("swi", "1"), "مفتاح انترميديت"),
    "swd_00": (wall_switch("swd", "00"), "مفتاح مزدوج"), "swd_10": (wall_switch("swd", "10"), "مفتاح مزدوج"),
    "swd_01": (wall_switch("swd", "01"), "مفتاح مزدوج"), "swd_11": (wall_switch("swd", "11"), "مفتاح مزدوج"),
    "dimmer": (wall_switch("dimmer", "0"), "دايمر"),
    "pb_0": (bell_push("0"), "ضاغط جرس"), "pb_1": (bell_push("1"), "ضاغط جرس"),
    "socket": (socket, "بريزة"),
    "lamp_0": (lamp("inc", False), "لمبة"), "lamp_1": (lamp("inc", True), "لمبة"),
    "ledbulb_0": (lamp("led", False), "لمبة LED"), "ledbulb_1": (lamp("led", True), "لمبة LED"),
    "bell": (bell, "جرس"),
    "lock_0": (door_lock(False), "كالون"), "lock_1": (door_lock(True), "كالون"),
    "tube_0": (tube(False), "فلورسنت"), "tube_1": (tube(True), "فلورسنت"),
    "ballast": (ballast, "بلاست"), "starter": (starter, "ستارتر"),
    "stair": (stair_timer, "ماكينة السلم"), "driver": (driver, "درايفر"),
    "ledpanel_0": (led_panel(False), "كشاف LED"), "ledpanel_1": (led_panel(True), "كشاف LED"),
    "jbox4": (jbox(4), "علبة 4"), "jbox6": (jbox(6), "علبة 6"), "jbox8": (jbox(8), "علبة 8"), "jbox10": (jbox(10), "علبة 10"),
    # tools and materials (3D viewer / library only)
    "pliers": (pliers("pliers"), "زرادية"), "cutter": (pliers("cutter"), "قصافة"),
    "tester": (tester, "مفك اختبار"), "hammer": (hammer, "شاكوش"), "tape": (tape, "شريط عازل"),
    "conduit": (conduit, "مواسير"), "coil_brown": (coil("brown"), "لفة سلك"), "coil_blue": (coil("blue"), "لفة سلك"),
    "coil_earth": (coil("earth"), "لفة سلك"), "flush_box": (flush_box, "علبة مفتاح"), "earth_rod": (earth_rod, "عمود أرضي"),
}

TOOLS = {"pliers", "cutter", "tester", "hammer", "tape", "conduit", "coil_brown", "coil_blue", "coil_earth", "flush_box", "earth_rod"}


def build_one(name):
    fn, ar = MODELS[name]
    M = kit.start()
    fn(M)
    groups = [g for g in kit.G if kit.G[g]]
    parts = {g: ({"body": "الجسم", "mech": "الأطراف", "glass": "اللمبة", "gong": "الجرس", "bolt": "اللسان", "tube": "الأنبوبة",
                  "bar": "القضيب", "grip": "اليد المعزولة", "head": "الرأس", "blade": "السلاح", "handle": "اليد", "pipe": "ماسورة صلبة",
                  "flex": "خرطوم مرن", "coil": "اللفة", "rod": "العمود", "clamp": "الكلامب"}.get(g, g), g, (0, 0, 0)) for g in groups}
    kit.merge(parts)
    lib.OUT = OUT + os.sep
    lib.export(name)
    return name


def hero(name):
    """studio render for the library card"""
    M = kit.start()
    MODELS[name][0](M)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    c = (lo + hi) / 2
    span = max(hi - lo)
    lib.studio(target=tuple(c), dist=span * 2.6, elev=18, azim=-28, lens_mm=60, res=(900, 900), bg=(0.035, 0.07, 0.16), key=2.6, samples=48)
    lib.OUT = REN + os.sep
    lib.render(name)


if __name__ == "__main__":
    args = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else sys.argv[1:]
    want_hero = "--hero" in args
    names = [a for a in args if not a.startswith("--")] or list(MODELS)
    for n in names:
        print("build", n, flush=True)
        build_one(n)
        if want_hero:
            hero(n)
