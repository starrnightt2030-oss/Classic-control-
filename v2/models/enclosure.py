"""Wall-mounting control enclosure 400x300x200 (RAL 7035) + a fully populated DOL panel showcase built from the library GLBs.
X width, Z height, Y depth (front -Y). mm.
Run: python enclosure.py enclosure [modes]  |  python enclosure.py showcase"""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "assets", "models")
W, H, D = 300, 400, 200

PARTS = {
    "body":     ("جسم الصندوق", "Enclosure body", (0, 0, 0)),
    "door":     ("الباب", "Door", (0, -260, 0)),
    "gasket":   ("جوان الباب", "Door gasket", (0, -180, 0)),
    "hinges":   ("المفصلات", "Hinges", (-90, -140, 0)),
    "lock":     ("القفل", "Door lock", (60, -300, 0), (110, -104, 0)),
    "plate":    ("لوحة التركيب", "Mounting plate", (0, -120, 0)),
    "glands":   ("جلاندات الكابلات", "Cable glands", (0, 0, -90)),
    "earth":    ("مسمار الأرضي", "Earthing stud", (0, -60, 60), (120, 92, 170)),
}


def C_(M):
    return dict(
        ral=lib.mat("e_ral7035", (0.60, 0.61, 0.58), rough=0.55, bump=0.6),
        zinc=lib.mat("e_zinc", (0.72, 0.73, 0.74), metal=1.0, rough=0.45, bump=0.3),
        rubber=lib.mat("e_rubber", (0.04, 0.04, 0.04), rough=0.85),
        black=lib.mat("e_black", (0.03, 0.03, 0.03), rough=0.45),
        grey=lib.mat("e_grey", (0.40, 0.41, 0.43), rough=0.45),
        steel=lib.mat("e_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        yellow=lib.mat("e_yellow", (0.85, 0.65, 0.05), rough=0.45),
        green=lib.mat("e_green", (0.08, 0.45, 0.10), rough=0.45),
    )


def build(M, door_holes=True):
    C = C_(M)
    bd = B(-W / 2, W / 2, -D / 2, D / 2, -H / 2, H / 2, C["ral"], "body", bw=3.0)
    cut(bd, cbox(-W / 2 + 1.5, W / 2 - 1.5, -D / 2 - 5, D / 2 - 1.5, -H / 2 + 1.5, H / 2 - 1.5))
    for x in (-110, 110):
        for z in (-170, 170):
            CYL(5, D / 2 - 2, D / 2 + 6, x, z, C["ral"], "body", bw=1.0)          # wall-mount lugs
    dr = B(-W / 2 - 1, W / 2 + 1, -D / 2 - 22, -D / 2 - 20.5, -H / 2 - 1, H / 2 + 1, C["ral"], "door", bw=2.0)
    for s in (-1, 1):
        B(-W / 2 - 1, W / 2 + 1, -D / 2 - 20.5, -D / 2 - 2, s * (H / 2 + 1) - (1.5 if s > 0 else -1.5), s * (H / 2 + 1), C["ral"], "door", bw=0.8) if False else None
    B(-W / 2, -W / 2 + 1.5, -D / 2 - 20.5, -D / 2 - 2, -H / 2, H / 2, C["ral"], "door", bw=0.5)
    B(W / 2 - 1.5, W / 2, -D / 2 - 20.5, -D / 2 - 2, -H / 2, H / 2, C["ral"], "door", bw=0.5)
    B(-W / 2, W / 2, -D / 2 - 20.5, -D / 2 - 2, H / 2 - 1.5, H / 2, C["ral"], "door", bw=0.5)
    B(-W / 2, W / 2, -D / 2 - 20.5, -D / 2 - 2, -H / 2, -H / 2 + 1.5, C["ral"], "door", bw=0.5)
    if door_holes:
        for x, z in ((-70, 120), (0, 120), (70, 120), (-70, 50), (0, 50), (70, 50)):
            cut(dr, ccyl(11.2, -D / 2 - 25, -D / 2 - 18, x, z))
    o = B(-W / 2 + 8, W / 2 - 8, -D / 2 - 4, -D / 2 - 1, -H / 2 + 8, H / 2 - 8, C["rubber"], "gasket", bw=0.8)
    cut(o, cbox(-W / 2 + 14, W / 2 - 14, -D / 2 - 6, -D / 2 + 1, -H / 2 + 14, H / 2 - 14))
    for z in (-140, 140):
        CYL(4.5, z - 25, z + 25, -W / 2 - 4, -D / 2 - 12, C["steel"], "hinges", axis="Z", bw=0.8)
        B(-W / 2 - 4, -W / 2 + 14, -D / 2 - 14, -D / 2 - 10, z - 25, z + 25, C["steel"], "hinges", bw=0.6)
    CYL(9, -D / 2 - 32, -D / 2 - 22, W / 2 - 40, 0, C["black"], "lock", bw=2.0)
    B(W / 2 - 42, W / 2 - 38, -D / 2 - 34, -D / 2 - 31, -4, 4, C["steel"], "lock", bw=0.3)
    B(W / 2 - 46, W / 2 - 34, -D / 2 - 20, -D / 2 - 4, -12, 12, C["black"], "lock", bw=0.8)
    pl = B(-W / 2 + 15, W / 2 - 15, D / 2 - 12, D / 2 - 9.5, -H / 2 + 15, H / 2 - 15, C["zinc"], "plate", bw=0.8)
    for x in (-W / 2 + 25, W / 2 - 25):
        for z in (-H / 2 + 25, H / 2 - 25):
            cut(pl, ccyl(3.2, D / 2 - 14, D / 2 - 7, x, z))
    for i, x in enumerate((-90, -30, 30, 90)):
        o = CYL(10 if i % 2 else 8, -H / 2 - 14, -H / 2 + 2, x, 20, C["grey"], "glands", axis="Z", bw=1.0, verts=6)
        CYL(8 if i % 2 else 6.5, -H / 2 - 22, -H / 2 - 14, x, 20, C["grey"], "glands", axis="Z", bw=2.0)
    CYL(3, D / 2 - 30, D / 2 - 9, 120, 170, C["steel"], "earth", bw=0.4)
    CYL(5, D / 2 - 28, D / 2 - 25, 120, 170, C["steel"], "earth", bw=0.6, verts=6)
    B(105, 135, D / 2 - 9.4, D / 2 - 9, 150, 160, C["yellow"], "earth", bw=0.3)
    T("PE", 120, D / 2 - 9.46, 155, 6, C["green"], "earth")


# ---------------------------------------------------------------- showcase
def imp(name, loc_mm, rot_deg=(0, 0, 0), parent=None):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ASSETS, name + ".glb"))
    new = [o for o in bpy.context.scene.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    bpy.ops.object.empty_add(location=(0, 0, 0))
    e = bpy.context.object
    e.name = "_grp_" + name
    for r in roots:
        r.parent = e
    e.rotation_euler = tuple(math.radians(a) for a in rot_deg)
    e.location = tuple(v * 0.001 for v in loc_mm)
    if parent:
        bpy.context.view_layer.update()
        mw = e.matrix_world.copy()
        e.parent = parent
        e.matrix_world = mw
    for o in new:
        if o.type == "EMPTY" and o.name.startswith("TERM_"):
            o.hide_render = True
    return e


def wire(pts, col, r=1.0):
    cu = bpy.data.curves.new("w", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r * 0.001
    cu.bevel_resolution = 3
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp.bezier_points, pts):
        bp.co = tuple(v * 0.001 for v in p)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new("w", cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(col)
    return o


def showcase():
    M = kit.start()
    build(M, door_holes=True)
    parts = kit.merge(PARTS)
    C = C_(M)
    # door pivot (opened 105 deg)
    bpy.ops.object.empty_add(location=(-W / 2 * 0.001 - 0.004, (-D / 2 - 12) * 0.001, 0))
    piv = bpy.context.object
    piv.name = "_door_pivot"
    bpy.context.view_layer.update()
    for g in ("door", "lock"):
        mw = parts[g].matrix_world.copy()
        parts[g].parent = piv
        parts[g].matrix_world = mw
    # DIN rails & ducts on the plate (plate front y = D/2-12 = 88)
    pf = D / 2 - 12
    zinc = C["zinc"]
    duct = lib.mat("sc_duct", (0.55, 0.56, 0.57), rough=0.5)
    for z in (115, 5):
        B(-118, 118, pf - 7.5, pf, z - 13.5, z + 13.5, zinc, "", bw=0.3)
        B(-118, 118, pf - 7.5, pf - 6.5, z - 17.5, z + 17.5, zinc, "", bw=0.2)
    for z in (60, -55, 170):
        B(-118, 118, pf - 40, pf, z - 12.5, z + 12.5, duct, "", bw=0.5)
    for x in (-125, 125):
        B(x - 10, x + 10, pf - 40, pf, -160, 175, duct, "", bw=0.5)
    rail_front = pf - 7.5
    imp("mcb_3p", (-70, rail_front - 36.5, 115))
    imp("mpcb", (10, rail_front - 45, 115))
    imp("contactor", (-40, rail_front - 41, 5))
    imp("overload", (-40, rail_front - 41, 5 - 62))
    imp("timer_din", (30, rail_front - 34, 5))
    imp("fuse_holder", (55, rail_front - 34, 5))
    imp("terminal_strip", (0, rail_front - 13.5 + 6, -115), rot_deg=(0, 0, 0))
    # door devices (axis Z -> -Y)
    dz = (-D / 2 - 22) * 1.0
    for name, x, z in (("pb_green_metal", -70, 120), ("pb_red_plastic", 0, 120), ("estop", 70, 120),
                       ("lamp_green", -70, 50), ("lamp_red", 0, 50), ("lamp_amber", 70, 50)):
        imp(name, (x, dz, z), rot_deg=(90, 0, 0), parent=piv)
    # some wiring
    cols = [lib.mat("sc_br", (0.20, 0.08, 0.03), rough=0.45), lib.mat("sc_bk", (0.02, 0.02, 0.02), rough=0.45),
            lib.mat("sc_gy", (0.35, 0.35, 0.36), rough=0.45)]
    for i, dx in enumerate((-16.5, -5.5, 5.5)):
        a = (-70 + (i - 1) * 17.6, pf - 88, 82)
        b = (-40 + dx, pf - 56, 29)
        wire([a, (a[0], pf - 70, 60), (b[0], pf - 70, 52), b], cols[i], 1.3)
        c = (-40 + dx, pf - 56, -72)
        d = (-18.2 + i * 5.2, pf - 30, -100)
        wire([c, (c[0], pf - 70, -60), (d[0], pf - 60, -60), d], cols[i], 1.3)
    red = lib.mat("sc_ctl", (0.6, 0.02, 0.02), rough=0.45)
    for k in range(5):
        wire([(-118, pf - 30, 150 - k * 6), (-138, -40, 150 - k * 6), (-150, -95, 120 - k * 4), (-145, -120, 60 - k * 4)], red, 0.7)
    piv.rotation_euler = (0, 0, math.radians(-110))
    lib.studio(target=(-0.06, -0.06, 0.0), dist=1.25, elev=12, azim=-24, lens_mm=45, samples=64, res=(1600, 1200), key=3.0)
    lib.render("panel_dol_showcase")
    print("DONE showcase")


class Mod:
    PARTS = PARTS

    @staticmethod
    def build(M):
        build(M)


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "enclosure"
    if what == "showcase":
        showcase()
    else:
        modes = sys.argv[2].split(",") if len(sys.argv) > 2 else ["assembled", "exploded"]
        kit.run("enclosure", Mod, dict(target=(0, 0, 0), dist=1.25, elev=18, azim=-32, lens_mm=55),
                dict(target=(0, -0.1, 0), dist=2.4, elev=16, azim=-40, lens_mm=50), modes)
