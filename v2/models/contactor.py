"""3-pole AC contactor (LC1-D style, 9-18 A frame) with real internal parts.
Axes: X = width, Y = depth (front = -Y, mounting plate = +Y), Z = height. Built in mm, exported in metres.
Run: python contactor.py [assembled|exploded|energized|all]
"""
import sys, math, json, bpy
from collections import defaultdict
from mathutils import Vector
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import lib

G = defaultdict(list)          # part group -> objects
mm = 0.001

PARTS = {  # id: (Arabic, English, explode offset mm (dx,dy,dz))
    "front_housing":   ("الغطاء الأمامي وحاضن الترامل", "Front housing & terminal shroud", (0, -118, 0)),
    "fixed_top":       ("النقط الثابتة (جهة الدخول)", "Fixed contacts (line side)", (0, -78, 34)),
    "fixed_bottom":    ("النقط الثابتة (جهة الخروج)", "Fixed contacts (load side)", (0, -78, -34)),
    "moving_contacts": ("الكباري المتحركة", "Moving contact bridges", (0, -74, 0)),
    "carrier":         ("حامل النقط المتحرك", "Contact carrier", (0, -42, 0)),
    "armature":        ("القلب المتحرك", "Moving armature", (0, -16, 0)),
    "return_springs":  ("سوستة الإرجاع", "Return springs", (0, -3, 0)),
    "coil":            ("الكويل (الملف)", "Coil", (0, 14, 0)),
    "fixed_core":      ("القلب الحديد الثابت", "Fixed magnetic core", (0, 34, 0)),
    "base":            ("القاعدة وكلبس الدين ريل", "Base & DIN-rail clip", (0, 78, 0)),
}


# ------------------------------------------------------------------ helpers (mm)
def B(x0, x1, y0, y1, z0, z1, m, g, bw=0.5, name=None):
    o = lib.box((x1 - x0) * mm, (y1 - y0) * mm, (z1 - z0) * mm,
                ((x0 + x1) / 2 * mm, (y0 + y1) / 2 * mm, (z0 + z1) / 2 * mm), m, bw=bw * mm, name=name or g)
    if g:
        G[g].append(o)
    return o


def CY(r, y0, y1, x, z, m, g, bw=0.3, verts=48):
    """cylinder along Y from y0 to y1."""
    o = lib.cyl(r * mm, (y1 - y0) * mm, y0 * mm, m, x=x * mm, y=z * mm, verts=verts, bw=bw * mm, axis="Y")
    if g:
        G[g].append(o)
    return o


def cutter_box(x0, x1, y0, y1, z0, z1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2 * mm, (y0 + y1) / 2 * mm, (z0 + z1) / 2 * mm))
    c = bpy.context.object
    c.scale = ((x1 - x0) * mm, (y1 - y0) * mm, (z1 - z0) * mm)
    bpy.ops.object.transform_apply(scale=True)
    return c


def cutter_cyl(r, y0, y1, x, z):
    bpy.ops.mesh.primitive_cylinder_add(radius=r * mm, depth=(y1 - y0) * mm, vertices=48,
                                        location=(x * mm, (y0 + y1) / 2 * mm, z * mm), rotation=(math.radians(90), 0, 0))
    return bpy.context.object


def T(body, x, y, z, size, m, g, rot=(90, 0, 0), align="CENTER"):
    o = lib.text(body, size * mm, (x * mm, y * mm, z * mm), m, rot=rot, depth=0.05 * mm, align=align)
    G[g].append(o)
    return o


def helix(g, center, axis_len, r, turns, wire, m, axis="Y"):
    cu = bpy.data.curves.new("spring", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = wire * mm
    cu.bevel_resolution = 3
    sp = cu.splines.new("POLY")
    n = int(turns * 24)
    sp.points.add(n)
    cx, cy, cz = center
    for i in range(n + 1):
        t = i / n
        a = t * turns * 2 * math.pi
        p = (r * math.cos(a), axis_len * (t - 0.5), r * math.sin(a))
        if axis == "Y":
            x, y, z = cx + p[0], cy + p[1], cz + p[2]
        sp.points[i].co = (x * mm, y * mm, z * mm, 1)
    o = bpy.data.objects.new("spring", cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    G[g].append(o)
    return o


def mat_striped(name, color, metal, rough, direction, scale, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    tc = nt.nodes.new("ShaderNodeTexCoord")
    w = nt.nodes.new("ShaderNodeTexWave")
    w.wave_type = "BANDS"
    w.bands_direction = direction
    w.inputs["Scale"].default_value = scale
    w.inputs["Distortion"].default_value = 0.0
    bm = nt.nodes.new("ShaderNodeBump")
    bm.inputs["Strength"].default_value = strength
    bm.inputs["Distance"].default_value = 0.0002
    nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
    nt.links.new(w.outputs["Fac"], bm.inputs["Height"])
    nt.links.new(bm.outputs["Normal"], b.inputs["Normal"])
    return m


# ------------------------------------------------------------------ build
def build():
    lib.reset()
    G.clear()
    M = lib.M()
    housing = lib.mat("housing", (0.05, 0.052, 0.056), rough=0.5, bump=0.25)
    cream = lib.mat("shroud", (0.70, 0.67, 0.56), rough=0.5, bump=0.2)
    navy = lib.mat("navy_print", (0.02, 0.05, 0.22), rough=0.6)
    blue = lib.mat("flag_blue", (0.012, 0.06, 0.32), rough=0.35)
    lblue = lib.mat("coil_label", (0.10, 0.28, 0.65), rough=0.5)
    carrier_m = lib.mat("carrier", (0.62, 0.62, 0.60), rough=0.4, bump=0.2)
    silver = lib.mat("silver", (0.93, 0.93, 0.95), metal=1.0, rough=0.18)
    copper = lib.mat("copper_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22)
    steel = lib.mat("spring_steel", (0.7, 0.7, 0.72), metal=1.0, rough=0.3)
    lam = mat_striped("laminations", (0.32, 0.33, 0.35), 0.9, 0.42, "Z", 260.0, 0.35)
    winding = mat_striped("winding", (0.80, 0.40, 0.18), 1.0, 0.25, "Y", 900.0, 0.5)
    bobbin = lib.mat("bobbin", (0.03, 0.03, 0.03), rough=0.5)

    cols = [-16.5, -5.5, 5.5, 16.5]
    top_lab = ["1/L1", "3/L2", "5/L3", "13 NO"]
    bot_lab = ["2/T1", "4/T2", "6/T3", "14 NO"]

    # ---------------- base (rear) with DIN clip + mounting ears
    base = B(-22.5, 22.5, 4, 41, -37, 37, housing, "base", bw=1.2)
    cut_in = cutter_box(-19, 19, 3, 37.5, -33, 33)            # hollow: holds coil + core
    lib.cut(base, cut_in)
    for (x0, x1, z0, z1, hx, hz) in ((-28.5, -22.0, 25, 36.5, -25.3, 30.5), (22.0, 28.5, -36.5, -25, 25.3, -30.5)):
        ear = B(x0, x1, 36, 41, z0, z1, housing, "base", bw=0.8)
        lib.cut(ear, cutter_cyl(2.1, 30, 45, hx, hz))
    B(-7, 7, 34, 41, -41, -36.5, housing, "base", bw=0.6)       # DIN latch tab
    B(-22.5, 22.5, 39.0, 41, 17.5, 20.0, housing, "base", bw=0.3)   # DIN hook lip
    for z in (-24, -12, 0, 12, 24):                              # moulded side ribs
        B(22.4, 23.0, 8, 34, z - 0.6, z + 0.6, housing, "base", bw=0.2)
        B(-23.0, -22.4, 8, 34, z - 0.6, z + 0.6, housing, "base", bw=0.2)

    # ---------------- front housing
    top_rear = B(-22.5, 22.5, -8, 4, 31, 37, cream, "front_housing", bw=0.9)
    top_main = B(-22.5, 22.5, -20, 4, 15, 31, cream, "front_housing", bw=0.9)
    mid = B(-22.5, 22.5, -30, 4, -15, 15, housing, "front_housing", bw=1.0)
    bot_main = B(-22.5, 22.5, -20, 4, -31, -15, cream, "front_housing", bw=0.9)
    bot_rear = B(-22.5, 22.5, -8, 4, -37, -31, cream, "front_housing", bw=0.9)
    for x in cols:
        lib.cut(top_main, cutter_cyl(4.2, -25, -15, x, 24))
        lib.cut(bot_main, cutter_cyl(4.2, -25, -15, x, -24))
    for x in (-15, 15):
        lib.cut(top_rear, cutter_cyl(3.3, -12, -4, x, 34))
    lib.cut(mid, cutter_box(-8.5, 8.5, -32, -19, -7, 12))        # carrier window
    for x in (-16, 16):
        lib.cut(mid, cutter_box(x - 3.6, x + 3.6, -32, -28.5, -1, 8))  # flag windows
        B(x - 3.4, x + 3.4, -29.2, -28.4, -0.8, 7.8, blue, "front_housing", bw=0.2)
    # barriers between poles
    for x in (-11, 0, 11):
        B(x - 0.8, x + 0.8, -23.5, -19.5, 15.5, 31, housing, "front_housing", bw=0.4)
        B(x - 0.8, x + 0.8, -23.5, -19.5, -31, -15.5, housing, "front_housing", bw=0.4)
    # prints
    for x, a, b in zip(cols, top_lab, bot_lab):
        T(a, x, -20.06, 17.6, 2.6, navy, "front_housing")
        T(b, x, -20.06, -29.7, 2.2, navy, "front_housing")
    T("A1", -9.0, -8.06, 34.0, 2.6, navy, "front_housing")
    T("A2", 9.0, -8.06, 34.0, 2.6, navy, "front_housing")
    B(-5.5, 5.5, -8.5, -7.9, 32.0, 36.2, lblue, "front_housing", bw=0.1)
    T("220V 50Hz", 0, -8.56, 34.1, 1.6, M["print_white"], "front_housing")
    T(lib.BRAND, -20.5, -30.06, 11.0, 2.4, M["print_white"], "front_housing", align="LEFT")
    T("EC1-D09", -20.5, -30.06, -10.5, 2.4, M["print_white"], "front_housing", align="LEFT")
    T("10", 17.5, -30.06, 11.0, 2.6, M["print_white"], "front_housing")
    B(-8, 8, -30.4, -29.9, -14, -9.5, M["white"], "front_housing", bw=0.1)   # marking label

    # terminal screws (+ wiring points)
    G["terms"] = []
    for x, a, b in zip(cols, top_lab, bot_lab):
        for z, lab in ((24, a), (-24, b)):
            parts, e = lib.screw_terminal((x * mm, -15 * mm, z * mm), "-Y", M, label=lab.replace("/", "_").replace(" ", ""), metal="yzinc")
            G["front_housing"] += parts
            G["terms"].append(e)
    for x, lab in ((-15, "A1"), (15, "A2")):
        parts, e = lib.screw_terminal((x * mm, -4.5 * mm, 34 * mm), "-Y", M, label=lab, metal="yzinc")
        G["front_housing"] += parts
        G["terms"].append(e)

    # ---------------- fixed contacts (copper strips + silver tips)
    for sgn, g in ((1, "fixed_top"), (-1, "fixed_bottom")):
        for x in cols:
            w = 2.2 if x != 16.5 else 1.8
            B(x - 3.6, x + 3.6, -15, -13.4, sgn * 20, sgn * 28, copper, g, bw=0.3)                  # clamp plate
            B(x - w, x + w, -13.4, -6.5, min(sgn * 26, sgn * 28), max(sgn * 26, sgn * 28), copper, g, bw=0.3)
            z0, z1 = sorted((sgn * 5.5, sgn * 28))
            B(x - w, x + w, -8.0, -6.5, z0, z1, copper, g, bw=0.3)                                  # contact arm
            CY(1.7, -9.0, -8.0, x, sgn * 7, silver, g, bw=0.25)                                     # silver tip

    # ---------------- moving bridges + contact springs (in carrier)
    for x in cols:
        w = 2.6 if x != 16.5 else 2.1
        B(x - w, x + w, -13.0, -11.8, -9.5, 9.5, copper, "moving_contacts", bw=0.35)
        for z in (7, -7):
            CY(1.7, -11.8, -11.0, x, z, silver, "moving_contacts", bw=0.25)
        helix("moving_contacts", (x, -15.2, 0), 4.2, 1.6, 4, 0.28, steel)

    # ---------------- carrier
    B(-21, 21, -17.6, -13.3, -11.5, 11.5, carrier_m, "carrier", bw=0.6)          # cross frame
    for x in cols:                                                               # bridge windows (side rails)
        for s in (-1, 1):
            B(x + s * 3.4 - 0.5, x + s * 3.4 + 0.5, -13.3, -11.2, -11.5, 11.5, carrier_m, "carrier", bw=0.2)
    B(-4, 4, -13.3, 15, -4, 4, carrier_m, "carrier", bw=0.5)                      # stem to armature
    for x in (-3.6, 3.6):                                                        # visible indicator tabs
        B(x - 2.1, x + 2.1, -26.5, -17.6, -5, 10.5, blue, "carrier", bw=0.5)
    B(-6, 6, -22, -17.6, -6.5, -4.5, carrier_m, "carrier", bw=0.3)

    # ---------------- armature (moving E-core)
    B(-16, 16, 15, 20, -12, 12, lam, "armature", bw=0.3)
    B(-5, 5, 20, 22, -12, 12, lam, "armature", bw=0.2)
    for s in (-1, 1):
        B(s * 10, s * 16, 20, 22, -12, 12, lam, "armature", bw=0.2) if s > 0 else B(-16, -10, 20, 22, -12, 12, lam, "armature", bw=0.2)
        B(min(s * 16, s * 21), max(s * 16, s * 21), 15, 18, -3, 3, carrier_m, "armature", bw=0.3)   # spring ears

    # ---------------- return springs
    for s in (-1, 1):
        helix("return_springs", (s * 18.8, 22.5, 0), 9.0, 1.9, 6, 0.42, steel)

    # ---------------- fixed core (E) + shading rings
    B(-16, 16, 33, 39, -12, 12, lam, "fixed_core", bw=0.3)
    B(-5, 5, 25, 33, -12, 12, lam, "fixed_core", bw=0.2)
    B(10, 16, 25, 33, -12, 12, lam, "fixed_core", bw=0.2)
    B(-16, -10, 25, 33, -12, 12, lam, "fixed_core", bw=0.2)
    for x0, x1 in ((10, 16), (-16, -10)):
        B(x0 - 0.5, x1 + 0.5, 24.7, 27.0, 2.5, 4.5, copper, "fixed_core", bw=0.3)    # shading ring

    # ---------------- coil on bobbin
    wnd = B(-9.3, 9.3, 26.6, 32.4, -16.0, 16.0, winding, "coil", bw=2.0)
    lib.cut(wnd, cutter_box(-5.6, 5.6, 20, 40, -12.6, 12.6))
    for y0, y1 in ((25.6, 26.6), (32.4, 33.2)):
        f = B(-10.2, 10.2, y0, y1, -17.6, 17.6, bobbin, "coil", bw=0.4)
        lib.cut(f, cutter_box(-5.6, 5.6, 20, 40, -12.6, 12.6))
    for x in (-6, 6):                                                      # coil lead tags
        B(x - 0.8, x + 0.8, 28.8, 30.2, 16, 21, copper, "coil", bw=0.2)

    # ---------------- merge groups into named parts
    parts = {}
    for gid in PARTS:
        objs = G[gid]
        meshes = [o for o in objs if o.type == "MESH"]
        curves = [o for o in objs if o.type == "CURVE"]
        bpy.ops.object.select_all(action="DESELECT")
        for o in meshes + curves:
            o.select_set(True)
        bpy.context.view_layer.objects.active = (meshes + curves)[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        p = bpy.context.object
        p.name = gid
        ar, en, off = PARTS[gid]
        p["name_ar"], p["name_en"] = ar, en
        p["explode_mm"] = list(off)
        # origin at part centre for clean animation in-app
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        parts[gid] = p
    for e in G["terms"]:
        mw = e.matrix_world.copy()
        e.parent = parts["front_housing"]
        e.matrix_world = mw
    return parts


# ------------------------------------------------------------------ states
def explode(parts, k=1.0):
    for gid, p in parts.items():
        d = Vector(PARTS[gid][2]) * mm * k
        p.location = p.location + d


def energize(parts):
    travel = 3.0 * mm  # armature closes the 3 mm air gap
    for gid in ("armature", "carrier", "moving_contacts", "return_springs"):
        parts[gid].location.y += travel if gid != "return_springs" else 0
    parts["return_springs"].scale.y = (9.0 - 3.0) / 9.0


def anchors(parts):
    """Label anchor = a characteristic visible point on each part (world space)."""
    pts = {}
    for gid, p in parts.items():
        bb = [p.matrix_world @ Vector(c) for c in p.bound_box]
        c = sum(bb, Vector()) / 8
        pts[gid] = c
    return pts


def project(points):
    from bpy_extras.object_utils import world_to_camera_view
    S = bpy.context.scene
    W, H = S.render.resolution_x, S.render.resolution_y
    out = {}
    for k, v in points.items():
        co = world_to_camera_view(S, S.camera, v)
        out[k] = (co.x * W, (1 - co.y) * H)
    return out


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    modes = ["assembled", "exploded", "energized"] if mode == "all" else [mode]
    for md in modes:
        parts = build()
        if md == "assembled":
            lib.export("contactor")
            lib.studio(target=(0, -0.004, 0), dist=0.21, elev=16, azim=-32, lens_mm=60, samples=64, res=(1100, 1100))
            lib.render("contactor_assembled")
        elif md == "energized":
            energize(parts)
            parts["front_housing"].hide_render = True
            parts["base"].hide_render = True
            lib.studio(target=(0, 0.004, 0), dist=0.22, elev=20, azim=-50, lens_mm=60, samples=64, res=(1100, 1100))
            lib.render("contactor_energized_inside")
        else:
            explode(parts)
            lib.studio(target=(0, -0.012, 0), dist=0.60, elev=21, azim=-48, lens_mm=52, samples=64, res=(1800, 1100))
            pts = anchors(parts)
            pts["silver_tip"] = Vector((-0.0165, (-11.4 - 74) * mm, 0.007))
            pts["terminal_screw"] = parts["front_housing"].matrix_world @ (parts["front_housing"].matrix_world.inverted() @ Vector((5.5 * mm, (-18 - 118) * mm, 24 * mm)))
            json.dump({k: list(v) for k, v in project(pts).items()}, open(lib.OUT + "contactor_exploded_anchors.json", "w"))
            lib.render("contactor_exploded")
        print("DONE", md)
