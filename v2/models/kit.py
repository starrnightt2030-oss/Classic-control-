"""Generic component pipeline: mm-based primitives, named part groups, explode, anchors, renders, GLB, callouts.
A component module defines PARTS = {id: (ar, en, (dx,dy,dz) mm)} and build(M) that fills kit.G[id] lists.
"""
import sys, math, json, bpy
from collections import defaultdict
from mathutils import Vector
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import lib

G = defaultdict(list)
TERMS = []
mm = 0.001


def start():
    lib.reset()
    G.clear()
    TERMS.clear()
    return lib.M()


# ---------------------------------------------------------------- primitives (mm)
def B(x0, x1, y0, y1, z0, z1, m, g, bw=0.5):
    o = lib.box((x1 - x0) * mm, (y1 - y0) * mm, (z1 - z0) * mm,
                ((x0 + x1) / 2 * mm, (y0 + y1) / 2 * mm, (z0 + z1) / 2 * mm), m, bw=bw * mm, name=g or "b")
    if g:
        G[g].append(o)
    return o


def CYL(r, a0, a1, u, v, m, g, axis="Y", bw=0.3, verts=48, r2=None):
    """Cylinder along axis from a0..a1; (u,v) = the other two coords: Y-axis->(x,z), Z-axis->(x,y), X-axis->(y,z)."""
    h = (a1 - a0)
    if axis == "Y":
        o = lib.cyl(r * mm, h * mm, a0 * mm, m, x=u * mm, y=v * mm, verts=verts, bw=bw * mm, axis="Y", r2=None if r2 is None else r2 * mm)
    elif axis == "Z":
        o = lib.cyl(r * mm, h * mm, a0 * mm, m, x=u * mm, y=v * mm, verts=verts, bw=bw * mm, axis="Z", r2=None if r2 is None else r2 * mm)
    else:
        o = lib.cyl(r * mm, h * mm, a0 * mm, m, x=u * mm, y=v * mm, verts=verts, bw=bw * mm, axis="X", r2=None if r2 is None else r2 * mm)
    if g:
        G[g].append(o)
    return o


def cbox(x0, x1, y0, y1, z0, z1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2 * mm, (y0 + y1) / 2 * mm, (z0 + z1) / 2 * mm))
    c = bpy.context.object
    c.scale = ((x1 - x0) * mm, (y1 - y0) * mm, (z1 - z0) * mm)
    bpy.ops.object.transform_apply(scale=True)
    return c


def ccyl(r, a0, a1, u, v, axis="Y", verts=48):
    rot = {"Y": (math.radians(90), 0, 0), "Z": (0, 0, 0), "X": (0, math.radians(90), 0)}[axis]
    c = (a0 + a1) / 2
    loc = {"Y": (u, c, v), "Z": (u, v, c), "X": (c, u, v)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(radius=r * mm, depth=abs(a1 - a0) * mm, vertices=verts,
                                        location=tuple(x * mm for x in loc), rotation=rot)
    return bpy.context.object


def cut(o, c):
    lib.cut(o, c)


def T(body, x, y, z, size, m, g, rot=(90, 0, 0), align="CENTER"):
    o = lib.text(body, size * mm, (x * mm, y * mm, z * mm), m, rot=rot, depth=0.05 * mm, align=align)
    G[g].append(o)
    return o


def helix(g, center, length, r, turns, wire, m, axis="Y"):
    cu = bpy.data.curves.new("helix", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = wire * mm
    cu.bevel_resolution = 3
    sp = cu.splines.new("POLY")
    n = max(12, int(turns * 24))
    sp.points.add(n)
    cx, cy, cz = center
    for i in range(n + 1):
        t = i / n
        a = t * turns * 2 * math.pi
        c1, c2, ax = r * math.cos(a), r * math.sin(a), length * (t - 0.5)
        p = {"Y": (cx + c1, cy + ax, cz + c2), "Z": (cx + c1, cy + c2, cz + ax), "X": (cx + ax, cy + c1, cz + c2)}[axis]
        sp.points[i].co = (p[0] * mm, p[1] * mm, p[2] * mm, 1)
    o = bpy.data.objects.new("helix", cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    G[g].append(o)
    return o


def screw(x, y, z, facing, M, label, g, metal="zinc", scale=1.0):
    parts, e = lib.screw_terminal((x * mm, y * mm, z * mm), facing, M, label=label, metal=metal)
    for p in parts:
        p.scale = (scale, scale, scale)
    G[g] += parts
    TERMS.append((e, g))
    return e


def striped(name, color, metal, rough, direction, scale, strength):
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
    bm = nt.nodes.new("ShaderNodeBump")
    bm.inputs["Strength"].default_value = strength
    bm.inputs["Distance"].default_value = 0.0002
    nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
    nt.links.new(w.outputs["Fac"], bm.inputs["Height"])
    nt.links.new(bm.outputs["Normal"], b.inputs["Normal"])
    return m


# ---------------------------------------------------------------- parts
def merge(PARTS):
    parts = {}
    for gid in PARTS:
        objs = [o for o in G[gid] if o.type in ("MESH", "CURVE")]
        if not objs:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        p = bpy.context.object
        p.name = gid
        ar, en, off = PARTS[gid][:3]
        p["name_ar"], p["name_en"], p["explode_mm"] = ar, en, list(off)
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        parts[gid] = p
    for e, g in TERMS:
        if g in parts:
            mw = e.matrix_world.copy()
            e.parent = parts[g]
            e.matrix_world = mw
    return parts


def explode(parts, PARTS, k=1.0):
    for gid, p in parts.items():
        p.location = p.location + Vector(PARTS[gid][2]) * mm * k


def anchors(parts, PARTS):
    pts = {}
    for gid, p in parts.items():
        if len(PARTS[gid]) > 3 and PARTS[gid][3] is not None:   # explicit local anchor (mm, assembled coords)
            pts[gid] = Vector(PARTS[gid][3]) * mm + Vector(PARTS[gid][2]) * mm
        else:
            bb = [p.matrix_world @ Vector(c) for c in p.bound_box]
            pts[gid] = sum(bb, Vector()) / 8
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


def run(name, module, cam_a, cam_e, modes=("assembled", "exploded")):
    """cam_a / cam_e: dict(target=(m), dist, elev, azim, lens_mm[, res])"""
    for md in modes:
        M = start()
        module.build(M)
        parts = module_parts = merge(module.PARTS)
        if hasattr(module, "post"):
            module.post(parts)
        if md == "assembled":
            lib.export(name)
            lib.studio(samples=56, res=cam_a.pop("res", (1100, 1100)), **cam_a)
            lib.render(name + "_assembled")
        else:
            explode(parts, module.PARTS)
            lib.studio(samples=56, res=cam_e.pop("res", (1800, 1100)), **cam_e)
            json.dump({k: list(v) for k, v in project(anchors(parts, module.PARTS)).items()},
                      open(lib.OUT + name + "_anchors.json", "w"))
            lib.render(name + "_exploded")
        print("DONE", name, md)
