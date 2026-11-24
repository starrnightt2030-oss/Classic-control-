"""Reversing contactor pair with mechanical interlock unit and reversing power links (L1/L3 swap). mm."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, screw

PARTS = {
    "contactor_fwd": ("كونتاكتور الاتجاه الأمامي KM1", "Forward contactor KM1", (-78, 0, 0)),
    "contactor_rev": ("كونتاكتور الاتجاه العكسي KM2", "Reverse contactor KM2", (78, 0, 0)),
    "interlock_housing": ("وحدة الانترلوك الميكانيكي", "Mechanical interlock unit", (0, -10, 0)),
    "interlock_rocker": ("الذراع المتأرجح (الميزان)", "Interlock rocker lever", (0, -50, 52)),
    "interlock_contacts": ("نقط الانترلوك الكهربي 01-02", "Electrical interlock contacts 01-02", (0, -50, -56)),
    "power_links": ("كباري القوى (عكس فازتين)", "Power links (two phases swapped)", (0, -70, 0)),
}
XC = 27.3   # contactor centre offset


def wire(g, pts, m, r=1.1):
    cu = bpy.data.curves.new("w", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r * 0.001
    cu.bevel_resolution = 4
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = tuple(v * 0.001 for v in p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new("wire", cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    kit.G[g].append(o)


def build(M):
    import contactor
    cparts = contactor.build()                       # builds one contactor (resets scene)
    lib._MATS.clear()
    M = lib.M()
    bpy.ops.object.select_all(action="DESELECT")
    objs = list(cparts.values())
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    c1 = bpy.context.object
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY" and o.name.startswith("TERM_"):
            bpy.data.objects.remove(o)
    c2 = c1.copy()
    c2.data = c1.data.copy()
    bpy.context.scene.collection.objects.link(c2)
    c1.location.x -= XC * 0.001
    c2.location.x += XC * 0.001
    kit.G["contactor_fwd"].append(c1)
    kit.G["contactor_rev"].append(c2)
    T("KM1", -XC, -30.06, 0.5, 3.0, M["print_white"], "contactor_fwd")
    T("KM2", XC, -30.06, 0.5, 3.0, M["print_white"], "contactor_rev")

    dark = lib.mat("il_dark", (0.06, 0.062, 0.066), rough=0.5, bump=0.25)
    ink = lib.mat("il_ink", (0.85, 0.85, 0.85), rough=0.6)
    hb = B(-4.6, 4.6, -24, 40, -33, 33, dark, "interlock_housing", bw=0.8)
    cut(hb, cbox(-3.4, 3.4, -10, 30, -24, 24))
    for z, lab in ((26, "01"), (-26, "02")):
        cut(hb, ccyl(2.4, -26, -20, 0, z))
        screw(0, -22.2, z, "-Y", M, lab, "interlock_housing", scale=0.6)
        T(lab, 0, -24.06, z + (4.6 if z > 0 else -4.6), 1.7, ink, "interlock_housing")
    T("NC", 0, -24.06, 10, 1.6, ink, "interlock_housing")
    T("EIL-1", 0, -24.06, -10, 1.4, ink, "interlock_housing")
    rocker = B(-2.6, 2.6, 4, 9, -20, 20, lib.mat("il_rocker", (0.62, 0.62, 0.60), rough=0.4), "interlock_rocker", bw=0.5)
    CYL(1.4, -6, 6, 0, 0, lib.mat("il_pin", (0.7, 0.7, 0.72), metal=1, rough=0.3), "interlock_rocker", axis="X", bw=0.1).location = (0, 0.0065, 0)
    for z in (17, -17):
        CYL(1.2, -14, 14, 0, z, lib.mat("il_pin2", (0.7, 0.7, 0.72), metal=1, rough=0.3), "interlock_rocker", axis="X", bw=0.1).location = (0, 0.0065, z * 0.001)
    cu = lib.mat("il_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22)
    for z in (6, -6):
        B(-1.4, 1.4, -14, -12.8, z - 4, z + 4, cu, "interlock_contacts", bw=0.2)
    B(-1.6, 1.6, -16, -15, -8, 8, cu, "interlock_contacts", bw=0.2)

    # reversing power links: tops in parallel, bottoms with L1/L3 swapped
    cols = {"L1": lib.mat("w_brown", (0.18, 0.07, 0.03), rough=0.45), "L2": lib.mat("w_black", (0.02, 0.02, 0.02), rough=0.45),
            "L3": lib.mat("w_grey", (0.35, 0.35, 0.36), rough=0.45)}
    xs = {"L1": -16.5, "L2": -5.5, "L3": 5.5}
    for ph, dx in xs.items():
        a = (-XC + dx, -17, 24)
        b = (XC + dx, -17, 24)
        wire("power_links", [a, (a[0], -20, 44 + dx * 0.25), (b[0], -20, 44 + dx * 0.25), b], cols[ph])
    for ph_f, ph_r in (("L1", "L3"), ("L2", "L2"), ("L3", "L1")):
        a = (-XC + xs[ph_f], -17, -24)
        b = (XC + xs[ph_r], -17, -24)
        zz = -44 - (xs[ph_f] + 20) * 0.3
        wire("power_links", [a, (a[0], -20, zz), (b[0], -20, zz - 3), b], cols[ph_f])


if __name__ == "__main__":
    import reversing
    modes = sys.argv[1].split(",") if len(sys.argv) > 1 else ["assembled", "exploded"]
    kit.run("reversing_contactor", reversing,
            dict(target=(0, -0.008, 0), dist=0.36, elev=16, azim=-28, lens_mm=60),
            dict(target=(0, -0.020, 0), dist=0.70, elev=16, azim=-38, lens_mm=50), modes)
