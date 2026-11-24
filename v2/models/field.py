"""Field devices: proximity sensors, photo sensor, limit switches, float & pressure switches, solenoid valve, beacon, siren, signal tower. mm.
Run: python field.py <variant|all> [modes]"""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw


def C_(M):
    return dict(
        brass=lib.mat("f_brass", (0.80, 0.62, 0.30), metal=1.0, rough=0.35),
        nickel=lib.mat("f_nickel", (0.78, 0.76, 0.72), metal=1.0, rough=0.25),
        orange=lib.mat("f_orange", (0.85, 0.35, 0.02), rough=0.45),
        black=lib.mat("f_black", (0.02, 0.02, 0.022), rough=0.45, bump=0.25),
        beige=lib.mat("f_beige", (0.70, 0.66, 0.56), metal=0.2, rough=0.5, bump=0.5),
        alu=lib.mat("f_alu", (0.78, 0.79, 0.81), metal=1.0, rough=0.35),
        white=lib.mat("f_white", (0.82, 0.82, 0.80), rough=0.45),
        grey=lib.mat("f_grey", (0.45, 0.46, 0.48), rough=0.45),
        blue=lib.mat("f_blue", (0.02, 0.12, 0.5), rough=0.4),
        red=lib.mat("f_red", (0.55, 0.01, 0.01), rough=0.3, coat=0.5),
        rubber=lib.mat("f_rubber", (0.03, 0.03, 0.03), rough=0.85),
        copper=lib.mat("f_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        winding=kit.striped("f_wind", (0.80, 0.40, 0.18), 1.0, 0.25, "X", 1400.0, 0.4),
        ferrite=lib.mat("f_ferrite", (0.08, 0.08, 0.09), metal=0.4, rough=0.5),
        pcb=lib.mat("f_pcb", (0.02, 0.22, 0.08), rough=0.4),
        steel=lib.mat("f_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        ink=lib.mat("f_ink", (0.03, 0.03, 0.04), rough=0.6),
        winkt=lib.mat("f_wink", (0.88, 0.88, 0.88), rough=0.6),
        amber=lib.mat("f_amber", (1.0, 0.5, 0.05), rough=0.3, emit=((1.0, 0.5, 0.05), 3.0)),
    )


def rot0(o, e):
    lib._sel(o)
    bpy.ops.object.transform_apply(location=True)
    o.rotation_euler = e
    return o


def hexnut(r, a0, a1, m, g, axis="X", y=0, z=0):
    o = CYL(r, a0, a1, y, z, m, g, axis=axis, bw=0.6, verts=6)
    cut(o, ccyl(r * 0.72, a0 - 1, a1 + 1, y, z, axis=axis))
    return o


# ---------------------------------------------------------------- proximity sensors
IND_PARTS = {
    "sensing_face": ("وش الحساس", "Sensing face (cap)", (-30, 0, 0)),
    "coil_core":    ("الملف والقلب الفريت", "Coil & ferrite pot core", (-16, -24, 0)),
    "electronics":  ("دايرة المذبذب والمقارن", "Oscillator & trigger electronics", (6, -30, 0)),
    "housing":      ("الجسم المقلوظ", "Threaded housing", (0, 0, 0)),
    "nuts":         ("صواميل التثبيت", "Lock nuts", (0, 0, 26)),
    "led":          ("ليد الحالة", "Status LED", (24, 0, 18)),
    "connector":    ("وصلة M12 والكابل", "M12 connector", (34, 0, 0)),
}


def build_inductive(M, size=18, face="orange", cap=False):
    C = C_(M)
    r = size / 2
    L0, L1 = -32, 20
    body = CYL(r - 0.3, L0 + 1, L1, 0, 0, C["nickel"] if not cap else C["grey"], "housing", axis="X", bw=0.3, verts=64)
    for i in range(int((L1 - L0 - 4) / 1.5)):
        o = lib.torus(r * 0.001, 0.00035, 0, C["nickel"] if not cap else C["grey"])
        o.rotation_euler = (0, math.radians(90), 0)
        o.location = ((L0 + 3 + i * 1.5) * 0.001, 0, 0)
        kit.G["housing"].append(o)
    CYL(r - 0.4, L0, L0 + 1.2, 0, 0, C[face] if face in C else C["orange"], "sensing_face", axis="X", bw=0.6, verts=64)
    hexnut(r + 3.6, -18, -14, C["nickel"], "nuts")
    hexnut(r + 3.6, 4, 8, C["nickel"], "nuts")
    CYL(r - 1.5, L0 + 1.5, L0 + 6, 0, 0, C["ferrite"], "coil_core", axis="X", bw=0.3)
    CYL(r - 3.2, L0 + 1.4, L0 + 5, 0, 0, C["winding"], "coil_core", axis="X", bw=0.3)
    B(L0 + 8, L1 - 4, -1, 1, -r + 2.5, r - 2.5, C["pcb"], "electronics", bw=0.2)
    for x in (L0 + 12, L0 + 20, L0 + 30):
        B(x, x + 3, 1, 3, -2, 2, C["black"], "electronics", bw=0.2)
    CYL(r - 0.6, L1, L1 + 5, 0, 0, C["black"], "led", axis="X", bw=0.5)
    CYL(1.2, L1 + 1, L1 + 4, 0, r - 0.3, C["amber"], "led", axis="X", bw=0.3) if False else None
    B(L1 + 1.5, L1 + 3.5, -1.5, 1.5, r - 1.2, r - 0.2, C["amber"], "led", bw=0.2)
    CYL(6.5, L1 + 5, L1 + 14, 0, 0, C["nickel"], "connector", axis="X", bw=0.5)
    for i in range(4):
        a = math.radians(45 + i * 90)
        CYL(0.5, L1 + 14, L1 + 16, 2.5 * math.cos(a), 2.5 * math.sin(a), C["brass"], "connector", axis="X", bw=0.05, verts=10)
    T("M%d  PNP NO" % size, -6, -r - 0.1, 0, 2.0, C["ink"], "housing", rot=(90, 0, 0)) if False else None
    if cap:
        CYL(1.5, L1 + 2, L1 + 5.5, 0, -r + 3, C["brass"], "led", axis="X", bw=0.2)


def build_square(M):
    C = C_(M)
    B(-20, 20, -20, 20, -20, 20, C["blue"], "housing", bw=2.0)
    B(-17, 17, -20.6, -19.6, -17, 17, C["orange"], "sensing_face", bw=1.0)
    B(-20, 20, -20, 20, -40, -20, C["black"], "housing", bw=1.5)
    CYL(3.0, -48, -40, 0, 0, C["black"], "connector", axis="Z", bw=0.5)
    B(8, 12, -20.4, -19.6, -34, -30, C["amber"], "led", bw=0.2)
    T("PS40-20DP", 0, 20.06, 0, 3, C["winkt"], "housing", rot=(90, 0, 180))


def build_photo(M):
    C = C_(M)
    B(-10, 10, -16, 16, -25, 25, C["grey"], "housing", bw=1.5)
    for z in (8, -8):
        CYL(5.5, -17.2, -15.9, 0, z, lib.mat("f_lens", (0.12, 0.12, 0.14), rough=0.05, coat=1.0), "sensing_face", bw=0.6)
    B(-8, -4, -16.4, -15.8, 18, 21, C["amber"], "led", bw=0.2)
    B(4, 8, -16.4, -15.8, 18, 21, lib.mat("f_grn", (0.1, 0.9, 0.1), rough=0.3, emit=((0.1, 1, 0.1), 3.0)), "led", bw=0.2)
    CYL(4, -30, -25, 0, 0, C["black"], "connector", axis="Z", bw=0.6)
    CYL(2.5, -60, -30, 0, 0, C["black"], "connector", axis="Z", bw=0.4)
    T("DIFFUSE 300mm", 0, -16.06, -18, 2.0, C["winkt"], "housing")


# ---------------------------------------------------------------- limit switch
LS_PARTS = {
    "lever":     ("الذراع والبكرة", "Lever arm & roller", (0, -10, 40)),
    "head":      ("الراس الدوارة وعمود الكامة", "Rotary head & cam shaft", (0, 0, 22)),
    "cover":     ("الغطاء الأمامي", "Front cover", (0, -40, 0)),
    "switch":    ("وحدة المفتاح السريع (Snap)", "Snap-action switch unit", (0, -24, -6)),
    "body":      ("الجسم الألومنيوم", "Die-cast body", (0, 22, 0)),
    "gland":     ("جلاند الكابل", "Conduit gland", (0, 0, -30)),
}


def build_limit(M, kind="roller"):
    C = C_(M)
    body = B(-20, 20, -16, 16, -40, 28, C["beige"], "body", bw=2.0)
    cut(body, cbox(-15, 15, -18, 12, -34, 22))
    B(-20, 20, -18, -16, -40, 28, C["beige"], "cover", bw=1.2)
    B(-14, 14, -18.4, -17.8, -12, 14, lib.mat("f_label", (0.85, 0.84, 0.78), rough=0.5), "cover", bw=0.2)
    T("LIMIT SWITCH", 0, -18.46, 9.5, 2.6, C["ink"], "cover")
    T("ELS-2", 0, -18.46, 4.5, 3.0, C["ink"], "cover")
    T("10A 250VAC  IP65", 0, -18.46, -1, 1.8, C["ink"], "cover")
    T("NO 13-14  NC 21-22", 0, -18.46, -6, 1.8, C["ink"], "cover")
    for x, z in ((-15, 23), (15, 23), (-15, -35), (15, -35)):
        CYL(2.0, -19.4, -18, x, z, C["steel"], "cover", bw=0.4, verts=24)
    # head
    if kind in ("roller", "rod", "wand"):
        B(-11, 11, -12, 12, 28, 44, C["alu"], "head", bw=1.5)
        CYL(3.0, -16, -12, 0, 38, C["steel"], "head", bw=0.4)
        B(-3, 3, -3, 3, 8, 30, C["white"], "head", bw=0.5)
        helix("head", (0, 6, 36), 6, 2.4, 4, 0.4, C["steel"], axis="Y")
        if kind == "roller":
            arm = B(-3, 3, -21, -16, 33, 70, C["alu"], "lever", bw=1.0)
            CYL(9, -24, -16, 0, 68, C["black"], "lever", bw=1.5, verts=64)
            CYL(2.5, -26, -14, 0, 68, C["steel"], "lever", bw=0.3)
        elif kind == "rod":
            B(-3, 3, -21, -16, 33, 50, C["alu"], "lever", bw=1.0)
            CYL(1.6, -20, -17, 0, 48, C["steel"], "lever", axis="Y", bw=0.2)
            CYL(1.5, 48, 110, 0, -18.5, C["steel"], "lever", axis="Z", bw=0.2, verts=16)
        else:
            CYL(2.0, 44, 56, 0, 0, C["black"], "lever", axis="Z", bw=0.4)
            helix("lever", (0, 0, 62), 12, 2.0, 10, 0.55, C["steel"], axis="Z")
            CYL(0.8, 68, 140, 0, 0, C["steel"], "lever", axis="Z", bw=0.1, verts=12)
    else:   # plunger / roller plunger
        CYL(8, 28, 36, 0, 0, C["alu"], "head", axis="Z", bw=1.0)
        hexnut(11, 36, 40, C["nickel"], "head", axis="Z")
        CYL(4, 40, 52, 0, 0, C["steel"], "lever", axis="Z", bw=1.2)
    # snap switch unit
    B(-11, 11, -10, 6, -24, 6, C["black"], "switch", bw=0.8)
    for x, z, n in ((-6, 2, "13"), (6, 2, "14"), (-6, -20, "21"), (6, -20, "22")):
        screw(x, -10.2 + 2.0, z, "-Y", M, n, "switch", scale=0.6)
        T(n, x + 4.2, -10.06, z, 1.6, C["winkt"], "switch")
    CYL(1.8, 6, 12, 0, 0, C["white"], "switch", axis="Z", bw=0.3)
    # gland
    CYL(7, -48, -40, 0, 0, C["black"], "gland", axis="Z", bw=0.8, verts=6)
    CYL(5, -54, -48, 0, 0, C["black"], "gland", axis="Z", bw=0.8)


# ---------------------------------------------------------------- float & pressure switches
def build_float(M):
    C = C_(M)
    o = CYL(18, -40, 40, 0, 0, lib.mat("f_float", (0.85, 0.65, 0.05), rough=0.35), "housing", axis="Z", bw=17.0, verts=64)
    CYL(4, 38, 52, 0, 0, lib.mat("f_float2", (0.85, 0.65, 0.05), rough=0.35), "housing", axis="Z", bw=1.5)
    cab = bpy.data.curves.new("cable", "CURVE")
    cab.dimensions = "3D"
    cab.bevel_depth = 0.004
    sp = cab.splines.new("BEZIER")
    sp.bezier_points.add(3)
    for bp, p in zip(sp.bezier_points, ((0, 0, 52), (0, 10, 90), (30, 20, 130), (60, 30, 140))):
        bp.co = tuple(v * 0.001 for v in p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new("cable", cab)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(C["black"])
    kit.G["connector"].append(ob)
    CYL(9, 96, 110, 9, 18, C["black"], "connector", axis="Z", bw=2.0)       # counterweight


def build_pressure(M):
    C = C_(M)
    B(-30, 30, -22, 22, -35, 45, lib.mat("f_pblue", (0.05, 0.10, 0.25), rough=0.45, bump=0.3), "housing", bw=3.0)
    B(-26, 26, -23, -21.5, -30, 40, C["grey"], "cover", bw=1.0)
    for x, lab in ((-12, "RANGE"), (12, "DIFF")):
        B(x - 7, x + 7, -23.6, -23.0, 10, 34, C["white"], "cover", bw=0.3)
        T(lab, x, -23.66, 36.5, 2.2, C["winkt"], "cover")
        for k in range(6):
            B(x - 3, x - 1, -23.7, -23.6, 12 + k * 4, 12.4 + k * 4, C["ink"], "cover", bw=0.05)
        CYL(3.5, 45, 56, x, 0, C["steel"], "lever", axis="Z", bw=0.6)
        B(x - 0.4, x + 0.4, -1, 1, 55.5, 56.4, C["black"], "lever", bw=0.05)
    T("PRESSURE SWITCH", 0, -23.66, 2, 3.0, C["winkt"], "cover")
    T("EKP-5   0.2-8 bar", 0, -23.66, -5, 2.4, C["winkt"], "cover")
    hexnut(9, -45, -35, C["brass"], "connector", axis="Z")
    CYL(4.5, -56, -45, 0, 0, C["brass"], "connector", axis="Z", bw=0.3)
    CYL(7, -10, 0, 30, -15, C["grey"], "connector", axis="X", bw=0.8, verts=6)


# ---------------------------------------------------------------- solenoid valve
SV_PARTS = {
    "coil":      ("الكويل", "Solenoid coil", (0, 0, 52), (0, -16, 52)),
    "nut":       ("صامولة تثبيت الكويل", "Coil retaining nut", (0, 0, 88)),
    "tube":      ("أنبوبة القلب والقلب المتحرك", "Armature tube & plunger", (0, -48, 40)),
    "bonnet":    ("الغطا ومساميره", "Bonnet & screws", (0, 0, 24)),
    "diaphragm": ("الرق (الديافرام)", "Diaphragm", (0, -40, 12)),
    "body":      ("الجسم النحاس (دخول وخروج)", "Brass body (inlet / outlet)", (0, 0, -10)),
}


def build_valve(M):
    C = C_(M)
    body = B(-38, 38, -20, 20, -22, 14, C["brass"], "body", bw=3.0)
    for s in (-1, 1):
        hexnut(22, s * 38 - (6 if s > 0 else -6) - 0 if False else min(s * 38, s * 46), max(s * 38, s * 46), C["brass"], "body", axis="X", y=0, z=-4)
        cut(body, ccyl(12.5, min(s * 30, s * 48), max(s * 30, s * 48), 0, -4, axis="X"))
    T("→", 0, -20.06, -12, 6, C["ink"], "body")
    B(-34, 34, -30, 30, 14, 22, C["brass"], "bonnet", bw=2.0)
    for x in (-27, 27):
        for y in (-23, 23):
            CYL(3.2, 22, 26, x, y, C["steel"], "bonnet", axis="Z", bw=0.6, verts=6)
    CYL(28, 13.6, 14.6, 0, 0, C["rubber"], "diaphragm", axis="Z", bw=0.4, verts=64)
    CYL(9, 14.6, 16, 0, 0, C["brass"], "diaphragm", axis="Z", bw=0.4)
    CYL(8, 22, 78, 0, 0, C["nickel"], "tube", axis="Z", bw=1.0)
    CYL(6.5, 24, 50, 0, 0, C["steel"], "tube", axis="Z", bw=1.0) if False else None
    helix("tube", (0, 0, 60), 10, 5.5, 6, 0.5, C["steel"], axis="Z")
    co = CYL(22, 28, 70, 0, 0, C["black"], "coil", axis="Z", bw=3.0, verts=64)
    lab = B(-18, 18, -22.4, -21.4, 34, 64, C["white"], "coil", bw=0.5)
    T("AC220V", 0, -22.46, 58, 3.0, C["ink"], "coil")
    T("NC  2W-25", 0, -22.46, 52, 2.6, C["ink"], "coil")
    T("0-1.0 MPa", 0, -22.46, 46, 2.6, C["ink"], "coil")
    CYL(7.5, -34, -22, -12, 52, C["grey"], "coil", axis="X", bw=1.0, verts=6)
    hexnut(7, 78, 84, C["nickel"], "nut", axis="Z")
    CYL(5.5, 84, 90, 0, 0, C["nickel"], "nut", axis="Z", bw=2.5)


# ---------------------------------------------------------------- beacon / siren / tower
def build_beacon(M):
    C = C_(M)
    CYL(28, 0, 22, 0, 0, C["white"], "housing", axis="Z", bw=2.0, verts=96)
    CYL(25, 22, 70, 0, 0, lib.mat("f_dome", (0.8, 0.02, 0.01), rough=0.1, trans=0.6, coat=1.0, ior=1.5), "cover", axis="Z", bw=12, verts=96)
    for k in range(12):
        a = 2 * math.pi * k / 12
        o = B(-0.8, 0.8, 24.2, 25.6, 24, 60, lib.mat("f_dome2", (0.8, 0.02, 0.01), rough=0.1, trans=0.6, ior=1.5), "cover", bw=0.4)
        lib._sel(o)
        bpy.ops.object.transform_apply(location=True)
        o.rotation_euler = (0, 0, a)
    B(-12, 12, -28.4, -27.6, 4, 16, C["red"], "housing", bw=0.3)
    T("WARNING LIGHT", 0, -28.46, 12.5, 2.0, C["winkt"], "housing")
    T("220VAC", 0, -28.46, 7.5, 2.0, C["winkt"], "housing")
    CYL(10, 30, 50, 0, 0, C["steel"], "lever", axis="Z", bw=1.0)
    bpy.ops.object.light_add(type="POINT", location=(0, 0, 0.045))
    l = bpy.context.object
    l.name = "_glow"
    l.data.energy = 0.4
    l.data.color = (1, 0.1, 0.05)


def build_siren(M):
    C = C_(M)
    CYL(30, -45, 20, 0, 0, C["red"], "housing", axis="Y", bw=3.0, verts=96)
    CYL(30, 20, 45, 0, 0, C["red"], "housing", axis="Y", bw=14, verts=96)
    for k in range(6):
        a = math.radians(k * 60)
        rot0(B(-2.5, 2.5, -30, -10, 27, 31, C["black"], "cover", bw=0.6), (0, a, 0))
    o = CYL(26, -46, -44, 0, 0, C["black"], "cover", axis="Y", bw=0.6, verts=96)
    for k in range(5):
        a = math.radians(k * 72)
        rot0(B(-1.5, 1.5, -46.6, -45.6, 3, 22, C["red"], "cover", bw=0.3), (0, a, 0))
    B(-12, 12, -50, 50, -40, -36, C["red"], "lever", bw=1.0)
    B(-12, 12, -10, 10, -36, -28, C["red"], "lever", bw=1.0)
    B(-14, 14, 10, 12, 20, 32, lib.mat("f_label2", (0.85, 0.85, 0.85), rough=0.5), "housing", bw=0.2)


def build_tower(M):
    C = C_(M)
    CYL(28, 0, 12, 0, 0, C["grey"], "housing", axis="Z", bw=2.0, verts=96)
    CYL(10, 12, 70, 0, 0, C["grey"], "housing", axis="Z", bw=1.0)
    cols = [((0.05, 0.9, 0.1), False), ((1.0, 0.5, 0.0), False), ((1.0, 0.05, 0.02), True)]
    z = 70
    for c, on in cols:
        CYL(25, z, z + 34, 0, 0, lib.lens(c, on), "cover", axis="Z", bw=1.0, verts=96)
        CYL(25.4, z + 34, z + 37, 0, 0, C["grey"], "cover", axis="Z", bw=0.8, verts=96)
        z += 37
    CYL(22, z, z + 6, 0, 0, C["grey"], "cover", axis="Z", bw=4.0, verts=96)


class V:
    def __init__(self, parts, fn, **kw):
        self.PARTS, self.fn, self.kw = parts, fn, kw

    def build(self, M):
        self.fn(M, **self.kw)


GEN = {"housing": ("الجسم", "Housing", (0, 0, 0)), "cover": ("الغطاء", "Cover", (0, -20, 0)),
       "sensing_face": ("وش الحساس", "Sensing face", (0, -20, 0)), "led": ("ليد", "LED", (0, -20, 10)),
       "connector": ("الوصلة", "Connector", (0, 0, -20)), "lever": ("الذراع", "Lever", (0, 0, 20))}
VARIANTS = {
    "prox_inductive_m18": (V(IND_PARTS, build_inductive, size=18), True, (0.004, 0, 0), 0.20),
    "prox_capacitive_m30": (V(IND_PARTS, build_inductive, size=30, face="white", cap=True), False, (0.004, 0, 0), 0.26),
    "prox_square":        (V(GEN, build_square), False, (0, 0, -0.008), 0.24),
    "photo_sensor":       (V(GEN, build_photo), False, (0, 0, -0.010), 0.24),
    "limit_roller":       (V(LS_PARTS, build_limit, kind="roller"), True, (0, 0, 0.012), 0.36),
    "limit_rod":          (V(LS_PARTS, build_limit, kind="rod"), False, (0, 0, 0.030), 0.46),
    "limit_wand":         (V(LS_PARTS, build_limit, kind="wand"), False, (0, 0, 0.040), 0.50),
    "limit_plunger":      (V(LS_PARTS, build_limit, kind="plunger"), False, (0, 0, 0.004), 0.32),
    "float_switch":       (V(GEN, build_float), False, (0.01, 0, 0.040), 0.48),
    "pressure_switch":    (V(GEN, build_pressure), False, (0, 0, 0.004), 0.36),
    "solenoid_valve":     (V(SV_PARTS, build_valve), True, (0, 0, 0.030), 0.40),
    "beacon":             (V(GEN, build_beacon), False, (0, 0, 0.032), 0.32),
    "siren":              (V(GEN, build_siren), False, (0, 0, 0), 0.36),
    "signal_tower":       (V(GEN, build_tower), False, (0, 0, 0.090), 0.62),
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = list(VARIANTS) if which == "all" else which.split(",")
    for n in names:
        mod, expl, tgt, dist = VARIANTS[n]
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else (["assembled", "exploded"] if expl else ["assembled"])
        kit.run(n, mod, dict(target=tgt, dist=dist, elev=20, azim=-35, lens_mm=60),
                dict(target=(tgt[0], -0.016, tgt[2]), dist=dist * 2.2, elev=16, azim=-40, lens_mm=50), modes)
