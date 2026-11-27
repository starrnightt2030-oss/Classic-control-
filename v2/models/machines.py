"""Machines driven by the schematic simulator (lib/sim/plant.dart), as real-scale GLB models.
Units: metres. Z up, front -Y, X along the machine.

Moving parts are empties with fixed names; assets/web/machine.js finds them by name and
moves them from the simulation state:
  cart   : cart (x), wheel1..4 (spin)
  hoist  : hook (z), rope (scale z from the drum down), drum (spin)
  lift   : car (z), door_l / door_r (x, children of car), cw (z), rope_car, sheave (spin)
  sort   : rod (y), proto_metal / proto_plastic (cloned per box)
  press  : ram (z), part_raw / part_pressed
  fill   : stream, proto_bottle (+ proto_liquid, scaled by the fill)
Sensor and valve lamps are meshes named lamp_<TAG> with their own material.

Run:  python machines.py [cart hoist lift sort press fill]   -> out/machine_<key>.glb
Then: python publish.py machine_
"""
import math
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import lib  # noqa: E402

G = defaultdict(list)


# ----------------------------------------------------------------- materials
def P():
    m = lib.mat
    return dict(
        yellow=m("paint_yellow", (0.78, 0.46, 0.01), rough=0.42, coat=0.3),
        blue=m("paint_blue", (0.012, 0.09, 0.30), rough=0.38, coat=0.3),
        grey=m("paint_grey", (0.18, 0.19, 0.2), rough=0.5),
        dark=m("paint_dark", (0.035, 0.037, 0.04), rough=0.45),
        white=m("paint_white", (0.72, 0.73, 0.72), rough=0.4),
        orange=m("plastic_orange", (0.85, 0.22, 0.02), rough=0.35),
        red=m("paint_red", (0.5, 0.01, 0.01), rough=0.35, coat=0.4),
        green=m("paint_green", (0.01, 0.25, 0.05), rough=0.35, coat=0.4),
        steel=m("steel", (0.62, 0.63, 0.65), metal=1.0, rough=0.3),
        chrome=m("chrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.08),
        alu=m("aluminium", (0.8, 0.81, 0.83), metal=1.0, rough=0.35),
        rubber=m("rubber", (0.015, 0.015, 0.016), rough=0.85),
        belt=m("belt_rubber", (0.03, 0.032, 0.035), rough=0.9),
        concrete=m("concrete", (0.3, 0.3, 0.29), rough=0.95, bump=0.3),
        wood=m("wood", (0.42, 0.22, 0.08), rough=0.7, bump=0.3),
        cardboard=m("cardboard", (0.55, 0.35, 0.16), rough=0.8),
        glass=m("glass_clear", (0.8, 0.92, 1.0), rough=0.05, alpha=0.3),
        water=m("water_blue", (0.05, 0.35, 0.9), rough=0.1, alpha=0.75),
        copper=m("copper", (0.93, 0.55, 0.38), metal=1.0, rough=0.25),
        stainless=m("stainless", (0.75, 0.76, 0.78), metal=1.0, rough=0.22),
    )


def lamp_mat(tag, color):
    m = bpy.data.materials.new("lamp_" + tag)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.25
    return m


# ----------------------------------------------------------------- primitives
def B(c, s, m, g="frame", bw=0.004):
    o = lib.box(s[0], s[1], s[2], c, m, bw=bw)
    G[g].append(o)
    return o


def BX(x0, x1, y0, y1, z0, z1, m, g="frame", bw=0.004):
    return B(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), m, g, bw)


def C(r, p0, p1, m, g="frame", verts=32, bw=0.002, r2=None):
    p0, p1 = Vector(p0), Vector(p1)
    v = p1 - p0
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=v.length, vertices=verts, location=(p0 + p1) / 2)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=v.length, vertices=verts, location=(p0 + p1) / 2)
    o = bpy.context.object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(v.normalized())
    bpy.ops.object.transform_apply(rotation=True)
    lib.finish(o, bw, mats=[m])
    G[g].append(o)
    return o


def SPH(r, c, m, g="frame"):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=c, segments=24, ring_count=12)
    o = bpy.context.object
    lib.finish(o, 0, mats=[m])
    G[g].append(o)
    return o


def lamp(tag, c, color=(0.1, 0.9, 0.3), r=0.018, base=True, g=None):
    """indicator lens on a small black housing; lit by machine.js"""
    if base:
        C(r * 1.25, (c[0], c[1], c[2] - r * 0.9), (c[0], c[1], c[2] - r * 0.2), P_["dark"], g or "frame", verts=24)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=c, segments=24, ring_count=12)
    o = bpy.context.object
    o.name = "lamp_" + tag
    o.data.materials.append(lamp_mat(tag, color))
    bpy.ops.object.shade_smooth()
    if g:
        G[g + "#keep"].append(o)
    return o


def label(text, loc, size, m, rot=(90, 0, 0), g="frame"):
    o = lib.text(text, size, loc, m, rot=rot, depth=0.002, bold=True)
    G[g].append(o)
    return o


def empty(name, loc):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    e = bpy.context.object
    e.name = name
    e.empty_display_size = 0.05
    return e


def parent(child, par):
    w = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = w


def nodes(pivots, parents=None):
    """join each group into one mesh; groups with a pivot become a named empty (the moving node)"""
    made = {}
    for name in list(G.keys()):
        if name.endswith("#keep"):
            continue
        objs = G[name]
        if not objs:
            continue
        mesh = lib.join(objs, name + ("_mesh" if name in pivots else ""))
        if name in pivots:
            e = empty(name, pivots[name])
            parent(mesh, e)
            made[name] = e
        else:
            made[name] = mesh
        for o in G.get(name + "#keep", []):
            parent(o, made[name])
    for c, p in (parents or {}).items():
        parent(made[c], made[p])
    return made


def plinth(x0, x1, y0, y1):
    """concrete floor with a yellow / black safety edge"""
    BX(x0, x1, y0, y1, -0.05, 0.0, P_["concrete"], bw=0.006)
    n = 0
    for (a0, a1, b0, b1, along) in [(x0, x1, y0, y0 + 0.06, "x"), (x0, x1, y1 - 0.06, y1, "x"), (x0, x0 + 0.06, y0, y1, "y"), (x1 - 0.06, x1, y0, y1, "y")]:
        L = (a1 - a0) if along == "x" else (b1 - b0)
        k = max(1, int(L / 0.2))
        for i in range(k):
            m = P_["yellow"] if (i + n) % 2 == 0 else P_["dark"]
            if along == "x":
                BX(a0 + i * L / k, a0 + (i + 1) * L / k, b0, b1, 0.0, 0.004, m, bw=0)
            else:
                BX(a0, a1, b0 + i * L / k, b0 + (i + 1) * L / k, 0.0, 0.004, m, bw=0)
        n += k


def motor(x, y, z, axis="Y", length=0.26, r=0.075, g="frame"):
    """small TEFC gear motor: finned body, fan cowl, terminal box, gearbox"""
    d = Vector((0, 1, 0)) if axis == "Y" else Vector((1, 0, 0))
    p = Vector((x, y, z))
    C(r, p, p + d * length, P_["blue"], g, verts=36)
    for i in range(8):
        a = i * math.pi / 4
        off = (Vector((math.cos(a), 0, math.sin(a))) if axis == "Y" else Vector((0, math.cos(a), math.sin(a)))) * r
        C(0.006, p + off + d * 0.02, p + off + d * (length - 0.03), P_["blue"], g, verts=8, bw=0)
    C(r * 1.02, p + d * length, p + d * (length + 0.06), P_["dark"], g, verts=36)
    tb = p + d * (length * 0.45) + Vector((0, 0, r + 0.025))
    B(tuple(tb), (0.09, 0.09, 0.05) if axis == "Y" else (0.09, 0.09, 0.05), P_["blue"], g)
    gb = p - d * 0.07
    B(tuple(gb), (0.16, 0.14, 0.16) if axis == "Y" else (0.14, 0.16, 0.16), P_["grey"], g)


def limit_switch(x, y, z, tag, g="frame", lever_dir=(1, 0, 0)):
    """roller-lever limit switch with its indicator lamp"""
    BX(x - 0.03, x + 0.03, y - 0.025, y + 0.025, z, z + 0.09, P_["grey"], g)
    BX(x - 0.032, x + 0.032, y - 0.027, y + 0.027, z + 0.09, z + 0.11, P_["dark"], g)
    d = Vector(lever_dir)
    a = Vector((x, y - 0.03, z + 0.1))
    b = a + d * 0.07 + Vector((0, 0, 0.03))
    C(0.005, a, b, P_["steel"], g, verts=8)
    C(0.016, b - Vector((0, 0.012, 0)), b + Vector((0, 0.012, 0)), P_["rubber"], g, verts=20)
    lamp(tag, (x, y + 0.03, z + 0.125), (1.0, 0.25, 0.05), r=0.012, g=g)


def m18(x, y, z, tag, axis="Z", length=0.08, g="frame", color=(1.0, 0.55, 0.05)):
    """M18 inductive sensor barrel with nuts and an LED at the back"""
    d = Vector((0, 0, -1)) if axis == "Z" else Vector((0, 1, 0)) if axis == "Y" else Vector((1, 0, 0))
    p = Vector((x, y, z))
    C(0.009, p, p + d * length, P_["chrome"], g, verts=24)
    C(0.0095, p + d * (length - 0.004), p + d * length, P_["orange"], g, verts=24)
    for k in (0.025, 0.04):
        C(0.014, p + d * (k - 0.003), p + d * (k + 0.003), P_["steel"], g, verts=6)
    lamp(tag, tuple(p - d * 0.006), color, r=0.007, base=False, g=g)


def photo_eye(x, y, z, tag, facing=(0, 1, 0), g="frame"):
    BX(x - 0.025, x + 0.025, y - 0.02, y + 0.02, z - 0.04, z + 0.04, P_["dark"], g)
    f = Vector(facing)
    C(0.01, Vector((x, y, z)) + f * 0.02, Vector((x, y, z)) + f * 0.024, P_["glass"], g, verts=20)
    lamp(tag, (x, y, z + 0.05), (1.0, 0.6, 0.05), r=0.008, base=False, g=g)


def conveyor(L, w, top, g="frame", legs=4):
    """belt conveyor along X from 0 to L, centred on y = 0, belt surface at z = top"""
    for s in (-1, 1):
        BX(0, L, s * (w / 2 + 0.005), s * (w / 2 + 0.045), top - 0.12, top + 0.02, P_["alu"], g)
        for i in range(legs):
            x = 0.12 + i * (L - 0.24) / (legs - 1)
            BX(x - 0.025, x + 0.025, s * (w / 2 + 0.01) - 0.02, s * (w / 2 + 0.01) + 0.02, 0, top - 0.12, P_["alu"], g)
            BX(x - 0.05, x + 0.05, s * (w / 2 + 0.01) - 0.05, s * (w / 2 + 0.01) + 0.05, 0, 0.012, P_["steel"], g)
    for i in range(legs):
        x = 0.12 + i * (L - 0.24) / (legs - 1)
        BX(x - 0.015, x + 0.015, -w / 2, w / 2, 0.25, 0.28, P_["alu"], g)
    BX(0.02, L - 0.02, -w / 2, w / 2, top - 0.012, top, P_["belt"], g, bw=0.002)
    BX(0.04, L - 0.04, -w / 2, w / 2, top - 0.1, top - 0.088, P_["belt"], g, bw=0.002)
    for x in (0.04, L - 0.04):
        C(0.05, (x, -w / 2, top - 0.05), (x, w / 2, top - 0.05), P_["belt"], g, verts=32)
        C(0.012, (x, -w / 2 - 0.06, top - 0.05), (x, w / 2 + 0.06, top - 0.05), P_["steel"], g, verts=12)


def crate(x, y, z, sx, sy, sz, m, g):
    """a box with a darker frame on its edges"""
    BX(x - sx / 2, x + sx / 2, y - sy / 2, y + sy / 2, z, z + sz, m, g, bw=0.006)
    t = 0.02
    for (dx, dy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        BX(x + dx * sx / 2 - (t if dx > 0 else 0), x + dx * sx / 2 + (t if dx < 0 else 0), y + dy * sy / 2 - (t if dy > 0 else 0),
           y + dy * sy / 2 + (t if dy < 0 else 0), z, z + sz, P_["wood"], g, bw=0.002)


# ----------------------------------------------------------------- machines
def cart():
    L = 4.4
    plinth(-0.2, L + 0.2, -0.9, 0.9)
    k = 0
    x = 0.15
    while x < L - 0.1:
        BX(x - 0.06, x + 0.06, -0.45, 0.45, 0.0, 0.06, P_["wood"], bw=0.004)
        x += 0.35
        k += 1
    for y in (-0.3, 0.3):
        BX(0, L, y - 0.05, y + 0.05, 0.06, 0.075, P_["steel"])
        BX(0, L, y - 0.007, y + 0.007, 0.075, 0.15, P_["steel"])
        BX(0, L, y - 0.025, y + 0.025, 0.15, 0.18, P_["steel"])
    for x0, x1 in ((0.0, 0.16), (L - 0.16, L)):
        BX(x0, x1, -0.45, 0.45, 0.0, 0.42, P_["grey"])
        for i in range(4):
            BX(x0 - 0.002 + (0 if x0 == 0 else -0.0), x1 + 0.002, -0.4 + i * 0.2, -0.3 + i * 0.2, 0.25, 0.4, P_["yellow"] if i % 2 == 0 else P_["dark"], bw=0)
        xb = x1 if x0 == 0 else x0
        C(0.06, (xb, -0.3, 0.3), (xb + (0.08 if x0 == 0 else -0.08), -0.3, 0.3), P_["rubber"])
        C(0.06, (xb, 0.3, 0.3), (xb + (0.08 if x0 == 0 else -0.08), 0.3, 0.3), P_["rubber"])
    # limit switches on posts beside the track
    for xs, tag, d in ((0.35, "LS1", (-1, 0, 0)), (L - 0.35, "LS2", (1, 0, 0))):
        BX(xs - 0.03, xs + 0.03, -0.6, -0.54, 0.0, 0.38, P_["grey"])
        limit_switch(xs, -0.57, 0.38, tag, lever_dir=(0.0, 1.0, 0.0))
        label(tag, (xs, -0.62, 0.2), 0.06, P_["white"], rot=(90, 0, 0))
    # the cart, centred on x = 0 (machine.js moves it)
    g = "cart"
    BX(-0.55, 0.55, -0.42, 0.42, 0.25, 0.37, P_["yellow"], g, bw=0.008)
    BX(-0.6, -0.55, -0.35, 0.35, 0.25, 0.35, P_["dark"], g)
    BX(0.55, 0.6, -0.35, 0.35, 0.25, 0.35, P_["dark"], g)
    for sx in (-1, 1):
        for sy in (-1, 1):
            BX(sx * 0.4 - 0.08, sx * 0.4 + 0.08, sy * 0.36 - 0.03, sy * 0.36 + 0.03, 0.2, 0.3, P_["grey"], g)
    motor(-0.3, -0.38, 0.45, axis="Y", length=0.22, r=0.06, g=g)
    BX(-0.42, -0.18, -0.08, 0.12, 0.37, 0.5, P_["grey"], g)
    crate(0.12, 0.0, 0.37, 0.62, 0.62, 0.42, P_["cardboard"], g)
    C(0.012, (0.45, 0.32, 0.37), (0.45, 0.32, 0.62), P_["dark"], g, verts=12)
    lamp("RUN", (0.45, 0.32, 0.65), (1.0, 0.55, 0.0), r=0.03, base=False, g=g)
    # wheels (each spins on its own)
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        wg = "wheel%d" % (i + 1)
        y = sy * 0.3
        C(0.09, (sx * 0.4, y - 0.025, 0.27), (sx * 0.4, y + 0.025, 0.27), P_["steel"], wg, verts=40)
        C(0.1, (sx * 0.4, y + sy * 0.025, 0.27), (sx * 0.4, y + sy * 0.035, 0.27), P_["steel"], wg, verts=40)
        BX(sx * 0.4 - 0.07, sx * 0.4 + 0.07, y - sy * 0.03 - 0.006, y - sy * 0.03 + 0.006, 0.26, 0.28, P_["dark"], wg, bw=0)
    made = nodes({"cart": (0, 0, 0), **{"wheel%d" % (i + 1): ((-0.4, 0.4)[i % 2], (-0.3, 0.3)[i // 2], 0.27) for i in range(4)}},
                 parents={"wheel%d" % (i + 1): "cart" for i in range(4)})
    made["cart"].location.x = 0.8


def hoist():
    plinth(-0.3, 3.3, -1.0, 1.0)
    y = P_["yellow"]
    for x in (0.3, 2.7):
        for s in (-1, 1):
            C(0.05, (x, s * 0.7, 0.05), (x, 0.0, 2.6), y, verts=6, bw=0.004)
        BX(x - 0.06, x + 0.06, -0.8, 0.8, 0.0, 0.1, y)
        for s in (-1, 1):
            C(0.05, (x, s * 0.75, 0.1), (x, s * 0.75, 0.0), P_["rubber"], verts=20)
    BX(0.1, 2.9, -0.08, 0.08, 2.6, 2.64, y)
    BX(0.1, 2.9, -0.012, 0.012, 2.64, 2.84, y)
    BX(0.1, 2.9, -0.08, 0.08, 2.84, 2.88, y)
    label("2 TON", (1.5, -0.09, 2.74), 0.09, P_["dark"])
    # the electric hoist under the beam
    BX(1.2, 1.9, -0.18, 0.18, 2.2, 2.58, P_["blue"], bw=0.01)
    C(0.13, (1.9, 0.0, 2.38), (2.02, 0.0, 2.38), P_["blue"], verts=36)
    C(0.13, (2.02, 0.0, 2.38), (2.08, 0.0, 2.38), P_["dark"], verts=36)
    for x in (1.25, 1.85):
        for s in (-1, 1):
            C(0.04, (x, s * 0.11, 2.62), (x, s * 0.09, 2.62), P_["steel"], verts=20)
    C(0.008, (1.3, -0.15, 2.2), (1.3, -0.15, 1.3), P_["dark"], verts=8)
    BX(1.26, 1.34, -0.18, -0.12, 1.1, 1.3, P_["yellow"])
    for i, m in enumerate((P_["green"], P_["red"])):
        C(0.012, (1.3, -0.18, 1.25 - i * 0.07), (1.3, -0.19, 1.25 - i * 0.07), m, verts=16)
    C(0.085, (1.35, 0.0, 2.25), (1.75, 0.0, 2.25), P_["steel"], "drum", verts=40)
    for i in range(10):
        C(0.088, (1.37 + i * 0.038, 0.0, 2.25), (1.385 + i * 0.038, 0.0, 2.25), P_["dark"], "drum", verts=24, bw=0)
    # rope: unit length downward from the drum, stretched by machine.js
    C(0.007, (1.55, 0.0, 2.16), (1.55, 0.0, 1.16), P_["steel"], "rope", verts=8, bw=0)
    # hook block, slings and the load (hook z = 2.0 at the top)
    g = "hook"
    BX(1.47, 1.63, -0.05, 0.05, 1.92, 2.12, P_["yellow"], g, bw=0.01)
    C(0.05, (1.55, -0.03, 2.04), (1.55, 0.03, 2.04), P_["steel"], g, verts=24)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.05, minor_radius=0.014, location=(1.55, 0, 1.84), rotation=(math.pi / 2, 0, 0))
    t = bpy.context.object
    lib.finish(t, 0, mats=[P_["steel"]])
    G[g].append(t)
    C(0.012, (1.55, 0, 1.92), (1.55, 0, 1.88), P_["steel"], g, verts=12)
    for sx in (-1, 1):
        for sy in (-1, 1):
            C(0.006, (1.55, 0, 1.8), (1.55 + sx * 0.33, sy * 0.28, 1.3), P_["dark"], g, verts=6, bw=0)
    BX(1.15, 1.95, -0.35, 0.35, 0.86, 0.94, P_["wood"], g)
    crate(1.55, 0, 0.94, 0.7, 0.6, 0.36, P_["blue"], g)
    # limit switches on a post: B1 bottom, B2 top
    BX(2.25, 2.3, -0.55, -0.5, 0.0, 2.3, P_["grey"])
    limit_switch(2.275, -0.48, 0.95, "B1", lever_dir=(-1, 0, 0))
    limit_switch(2.275, -0.48, 1.9, "B2", lever_dir=(-1, 0, 0))
    label("B1", (2.36, -0.56, 0.9), 0.06, P_["white"])
    label("B2", (2.36, -0.56, 1.85), 0.06, P_["white"])
    made = nodes({"hook": (1.55, 0, 2.0), "rope": (1.55, 0, 2.16), "drum": (1.55, 0, 2.25)})
    made["hook"].location.z = 2.0 - 0.95


def lift():
    H = 7.8
    plinth(-0.5, 2.5, -1.4, 2.0)
    cols = [(0.0, 0.0), (2.0, 0.0), (0.0, 1.8), (2.0, 1.8)]
    for x, y in cols:
        BX(x - 0.04, x + 0.04, y - 0.04, y + 0.04, 0.0, H, P_["grey"])
    for z in (0.02, 2.6, 5.2, H - 0.05):
        for (a, b) in ((cols[0], cols[1]), (cols[2], cols[3]), (cols[0], cols[2]), (cols[1], cols[3])):
            if a[1] == b[1] and a[1] == 0.0 and z < H - 1:
                continue
            BX(min(a[0], b[0]) - 0.03, max(a[0], b[0]) + 0.03, min(a[1], b[1]) - 0.03, max(a[1], b[1]) + 0.03, z, z + 0.05, P_["grey"])
    # guide rails and the back wall (glass, so the counterweight shows)
    for x in (0.12, 1.88):
        BX(x - 0.015, x + 0.015, 0.85, 0.95, 0.0, H - 0.1, P_["steel"])
    BX(0.0, 2.0, 1.83, 1.85, 0.0, H, P_["glass"], bw=0)
    # landings: floor slab, door frame, number and the floor sensor
    for f in range(3):
        z = f * 2.6
        BX(-0.4, 2.4, -1.1, -0.05, z - 0.15 if f else -0.05, z, P_["white"] if f else P_["concrete"])
        for x0, x1 in ((0.2, 0.55), (1.45, 1.8)):
            BX(x0, x1, -0.06, -0.02, z, z + 2.2, P_["stainless"])
        BX(0.2, 1.8, -0.06, -0.02, z + 2.2, z + 2.4, P_["stainless"])
        BX(0.6, 1.4, -0.07, -0.05, z + 2.25, z + 2.37, P_["dark"])
        label(str(f), (1.0, -0.075, z + 2.27), 0.09, P_["white"])
        BX(1.88, 1.96, 0.05, 0.11, z + 0.35, z + 0.45, P_["dark"])
        lamp("B%d" % (f + 1), (1.92, 0.04, z + 0.4), (0.1, 1.0, 0.3), r=0.014, base=False)
        BX(1.85, 1.95, -0.1, -0.06, z + 1.0, z + 1.2, P_["stainless"])
        C(0.015, (1.9, -0.1, z + 1.1), (1.9, -0.11, z + 1.1), P_["green"], verts=16)
    # machine on top: motor, gearbox and the traction sheave
    BX(-0.05, 2.05, -0.05, 1.85, H, H + 0.08, P_["grey"])
    motor(0.6, 1.0, H + 0.25, axis="X", length=0.4, r=0.12)
    C(0.26, (1.2, 0.9, H + 0.32), (1.26, 0.9, H + 0.32), P_["steel"], "sheave", verts=48)
    for i in range(4):
        C(0.03, (1.2, 0.9, H + 0.32), (1.26, 0.9 + 0.2 * math.cos(i * math.pi / 2), H + 0.32 + 0.2 * math.sin(i * math.pi / 2)), P_["steel"], "sheave", verts=8, bw=0)
    # car (floor at z = 0), its doors and the counterweight
    g = "car"
    BX(0.2, 1.8, 0.05, 1.65, 0.0, 0.12, P_["dark"], g)
    BX(0.2, 1.8, 1.6, 1.65, 0.12, 2.3, P_["stainless"], g)
    BX(0.2, 0.25, 0.05, 1.65, 0.12, 2.3, P_["stainless"], g)
    BX(1.75, 1.8, 0.05, 1.65, 0.12, 2.3, P_["stainless"], g)
    BX(0.2, 1.8, 0.05, 1.65, 2.3, 2.4, P_["white"], g)
    BX(0.2, 0.6, 0.05, 0.1, 0.12, 2.3, P_["stainless"], g)
    BX(1.4, 1.8, 0.05, 0.1, 0.12, 2.3, P_["stainless"], g)
    BX(0.25, 1.75, 1.1, 1.58, 0.95, 1.0, P_["chrome"], g)
    BX(0.6, 1.4, 0.05, 0.1, 2.15, 2.3, P_["stainless"], g)
    lamp("CAR", (1.0, 0.85, 2.29), (1.0, 0.95, 0.8), r=0.05, base=False, g=g)
    C(0.012, (1.0, 0.9, 2.4), (1.0, 0.9, 2.6), P_["steel"], g, verts=8)
    for x in (0.12, 1.88):
        BX(x - 0.04, x + 0.04, 0.83, 0.97, 0.0, 0.18, P_["dark"], g)
        BX(x - 0.04, x + 0.04, 0.83, 0.97, 2.2, 2.38, P_["dark"], g)
    BX(0.6, 1.0, 0.02, 0.05, 0.12, 2.15, P_["stainless"], "door_l")
    BX(1.0, 1.4, 0.02, 0.05, 0.12, 2.15, P_["stainless"], "door_r")
    BX(0.995, 1.0, 0.015, 0.02, 0.12, 2.15, P_["dark"], "door_l", bw=0)
    BX(0.3, 1.7, 1.66, 1.78, 0.0, 1.2, P_["dark"], "cw")
    for i in range(6):
        BX(0.3, 1.7, 1.65, 1.79, 0.18 * i + 0.1, 0.18 * i + 0.12, P_["grey"], "cw", bw=0)
    C(0.01, (1.0, 0.9, H + 0.06 - 1.0), (1.0, 0.9, H + 0.06), P_["steel"], "rope_car", verts=8, bw=0)
    made = nodes({"car": (0, 0, 0), "door_l": (0, 0, 0), "door_r": (0, 0, 0), "cw": (0, 0, 0), "rope_car": (1.0, 0.9, H + 0.06),
                  "sheave": (1.23, 0.9, H + 0.32)}, parents={"door_l": "car", "door_r": "car"})


def belt_machine(L, w):
    conveyor(L, w, 0.82, legs=4)
    motor(L - 0.15, -(w / 2 + 0.1), 0.6, axis="Y", length=0.2, r=0.06)
    BX(L - 0.25, L - 0.05, -(w / 2 + 0.1), -(w / 2 + 0.03), 0.55, 0.72, P_["grey"])
    # control box on a leg
    BX(0.3, 0.6, -(w / 2 + 0.2), -(w / 2 + 0.06), 0.9, 1.25, P_["grey"])
    for i, m in enumerate((P_["green"], P_["red"])):
        C(0.02, (0.38 + i * 0.12, -(w / 2 + 0.2), 1.1), (0.38 + i * 0.12, -(w / 2 + 0.22), 1.1), m, verts=20)
    C(0.012, (0.55, -(w / 2 + 0.13), 1.25), (0.55, -(w / 2 + 0.13), 1.45), P_["dark"], verts=12)
    lamp("M1", (0.55, -(w / 2 + 0.13), 1.48), (0.1, 1.0, 0.3), r=0.025, base=False)


def sort():
    L, w = 3.2, 0.5
    plinth(-0.6, L + 0.3, -1.2, 1.3)
    belt_machine(L, w)
    px = 0.6 * L
    # feeder chute at the start
    for s in (-1, 1):
        BX(-0.5, 0.15, s * 0.2 - 0.01, s * 0.2 + 0.01, 0.95, 1.1, P_["alu"])
    BX(-0.5, 0.15, -0.2, 0.2, 0.93, 0.95, P_["steel"])
    BX(-0.5, -0.45, -0.2, 0.2, 0.0, 0.95, P_["alu"])
    # side guide rails
    for s in (-1, 1):
        BX(0.15, px - 0.35, s * (w / 2 - 0.01) - 0.01, s * (w / 2 - 0.01) + 0.01, 0.86, 0.9, P_["yellow"])
    BX(px + 0.35, L, -(w / 2), -(w / 2) + 0.02, 0.86, 0.9, P_["yellow"])
    BX(px + 0.35, L, w / 2 - 0.02, w / 2, 0.86, 0.9, P_["yellow"])
    # bin for metal on the far side, with a slide from the belt
    BX(px - 0.35, px + 0.35, 0.42, 1.0, 0.0, 0.02, P_["blue"])
    for (a, b, c, d) in ((px - 0.35, px + 0.35, 0.42, 0.44), (px - 0.35, px + 0.35, 0.98, 1.0), (px - 0.35, px - 0.33, 0.42, 1.0), (px + 0.33, px + 0.35, 0.42, 1.0)):
        BX(a, b, c, d, 0.0, 0.55, P_["blue"])
    label("METAL", (px, 0.415, 0.3), 0.07, P_["white"])
    for s in (-1, 1):
        BX(px + s * 0.18 - 0.01, px + s * 0.18 + 0.01, w / 2 + 0.03, 0.42, 0.6, 0.8, P_["alu"])
    # inductive sensor above the belt edge (B2) on a bracket
    BX(px - 0.02, px + 0.02, w / 2 + 0.05, w / 2 + 0.09, 0.82, 1.08, P_["alu"])
    BX(px - 0.02, px + 0.02, w / 2 - 0.1, w / 2 + 0.09, 1.04, 1.08, P_["alu"])
    m18(px, w / 2 - 0.08, 1.04, "B2", axis="Z", length=0.08)
    label("B2", (px + 0.06, w / 2 + 0.05, 1.12), 0.05, P_["white"], rot=(90, 0, 180))
    # photo eye at the end (B1) and its reflector
    BX(L - 0.12, L - 0.08, -(w / 2 + 0.12), -(w / 2 + 0.08), 0.0, 0.92, P_["alu"])
    photo_eye(L - 0.1, -(w / 2 + 0.06), 0.92, "B1")
    BX(L - 0.12, L - 0.08, w / 2 + 0.06, w / 2 + 0.08, 0.86, 0.98, P_["red"])
    # pneumatic cylinder on the near side, pushing across the belt
    yb = -(w / 2 + 0.08)
    BX(px - 0.12, px + 0.12, yb - 0.7, yb - 0.05, 0.0, 0.78, P_["alu"])
    C(0.045, (px, yb - 0.62, 0.92), (px, yb - 0.08, 0.92), P_["alu"], verts=32)
    for yy in (yb - 0.62, yb - 0.1):
        BX(px - 0.055, px + 0.055, yy - 0.02, yy + 0.02, 0.865, 0.975, P_["steel"])
    for dz in (-0.03, 0.03):
        for dx in (-0.035, 0.035):
            C(0.005, (px + dx, yb - 0.62, 0.92 + dz), (px + dx, yb - 0.1, 0.92 + dz), P_["chrome"], verts=8, bw=0)
    BX(px - 0.12, px + 0.12, yb - 0.66, yb - 0.6, 0.78, 0.87, P_["steel"])
    # valve Y1 with its coil lamp, and the hoses
    BX(px + 0.08, px + 0.2, yb - 0.5, yb - 0.38, 0.98, 1.05, P_["dark"])
    BX(px + 0.1, px + 0.18, yb - 0.5, yb - 0.42, 1.05, 1.12, P_["blue"])
    lamp("Y1", (px + 0.14, yb - 0.46, 1.135), (1.0, 0.75, 0.05), r=0.01, base=False)
    C(0.006, (px + 0.1, yb - 0.4, 1.0), (px + 0.03, yb - 0.12, 0.96), P_["blue"], verts=8, bw=0)
    C(0.006, (px + 0.1, yb - 0.48, 1.0), (px + 0.03, yb - 0.58, 0.96), P_["blue"], verts=8, bw=0)
    # reed switches on the body: B3 rod in, B4 rod out
    for yy, tag in ((yb - 0.58, "B3"), (yb - 0.14, "B4")):
        BX(px - 0.012, px + 0.012, yy - 0.02, yy + 0.02, 0.965, 0.978, P_["dark"])
        lamp(tag, (px, yy, 0.985), (1.0, 0.3, 0.05), r=0.006, base=False)
    # rod and pusher plate (rod in): moved along +Y by machine.js
    g = "rod"
    C(0.014, (px, yb - 0.1, 0.92), (px, yb + 0.02, 0.92), P_["chrome"], g, verts=20)
    BX(px - 0.16, px + 0.16, yb + 0.02, yb + 0.04, 0.84, 1.0, P_["yellow"], g)
    # parts to clone: a steel box and a plastic box (bottom centre at the origin)
    crate(0, 0, 0, 0.22, 0.22, 0.16, P_["steel"], "proto_metal")
    BX(-0.11, 0.11, -0.11, 0.11, 0.0, 0.16, P_["orange"], "proto_plastic", bw=0.01)
    BX(-0.07, 0.07, -0.111, -0.109, 0.06, 0.1, P_["white"], "proto_plastic", bw=0)
    made = nodes({"rod": (0, 0, 0), "proto_metal": (0, 0, 0), "proto_plastic": (0, 0, 0)})
    made["proto_metal"].location = (0.4, 0.0, 0.82)
    made["proto_plastic"].location = (0.9, 0.0, 0.82)


def press():
    plinth(-1.0, 1.0, -0.9, 0.9)
    BX(-0.6, 0.6, -0.4, 0.4, 0.06, 0.85, P_["blue"], bw=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            BX(sx * 0.55 - 0.06, sx * 0.55 + 0.06, sy * 0.35 - 0.06, sy * 0.35 + 0.06, 0.0, 0.06, P_["dark"])
    BX(-0.62, 0.62, -0.42, 0.42, 0.85, 0.88, P_["steel"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            C(0.035, (sx * 0.42, sy * 0.24, 0.88), (sx * 0.42, sy * 0.24, 2.0), P_["chrome"], verts=32)
            C(0.05, (sx * 0.42, sy * 0.24, 0.88), (sx * 0.42, sy * 0.24, 0.94), P_["steel"], verts=6)
            C(0.05, (sx * 0.42, sy * 0.24, 2.12), (sx * 0.42, sy * 0.24, 2.17), P_["steel"], verts=6)
    BX(-0.55, 0.55, -0.32, 0.32, 2.0, 2.12, P_["blue"], bw=0.01)
    label("PRESS 5T", (0, -0.325, 2.03), 0.06, P_["white"])
    C(0.13, (0, 0, 2.12), (0, 0, 2.18), P_["steel"], verts=40)
    C(0.11, (0, 0, 2.18), (0, 0, 2.62), P_["alu"], verts=48)
    C(0.13, (0, 0, 2.62), (0, 0, 2.68), P_["steel"], verts=40)
    for a in range(4):
        c = (0.1 * math.cos(a * math.pi / 2 + math.pi / 4), 0.1 * math.sin(a * math.pi / 2 + math.pi / 4))
        C(0.008, (c[0], c[1], 2.12), (c[0], c[1], 2.7), P_["chrome"], verts=8, bw=0)
    # reed switches: B1 ram up (top), B2 ram down (bottom)
    for z, tag in ((2.58, "B1"), (2.25, "B2")):
        BX(0.105, 0.125, -0.02, 0.02, z - 0.02, z + 0.02, P_["dark"])
        lamp(tag, (0.13, 0, z), (1.0, 0.3, 0.05), r=0.008, base=False)
        label(tag, (0.2, -0.0, z - 0.02), 0.04, P_["white"], rot=(90, 0, 90))
    # valve Y1 and hoses
    BX(0.3, 0.48, -0.1, 0.05, 2.12, 2.2, P_["dark"])
    BX(0.33, 0.45, -0.08, 0.03, 2.2, 2.28, P_["blue"])
    lamp("Y1", (0.39, -0.025, 2.295), (1.0, 0.75, 0.05), r=0.01, base=False)
    C(0.007, (0.33, -0.02, 2.2), (0.12, -0.02, 2.6), P_["blue"], verts=8, bw=0)
    C(0.007, (0.33, 0.0, 2.2), (0.12, 0.0, 2.2), P_["blue"], verts=8, bw=0)
    # die and the photo eye (B3)
    BX(-0.22, 0.22, -0.16, 0.16, 0.88, 0.96, P_["dark"])
    BX(-0.16, 0.16, -0.11, 0.11, 0.955, 0.962, P_["steel"])
    BX(0.52, 0.56, -0.42, -0.38, 0.88, 1.2, P_["alu"])
    photo_eye(0.54, -0.36, 1.0, "B3", facing=(-1, 0, 0))
    # light curtain posts and a two-hand station
    for sx in (-1, 1):
        BX(sx * 0.6 - 0.02, sx * 0.6 + 0.02, -0.5, -0.46, 0.85, 1.7, P_["yellow"])
    BX(-0.3, 0.3, -0.85, -0.65, 0.95, 1.05, P_["yellow"])
    C(0.03, (0, -0.75, 0.0), (0, -0.75, 0.95), P_["grey"], verts=16)
    for x, m in ((-0.2, P_["green"]), (0.2, P_["green"]), (0, P_["red"])):
        C(0.03 if x else 0.04, (x, -0.75, 1.05), (x, -0.75, 1.08), m, verts=24)
    # ram: rod, platen sliding on the columns and the punch (punch bottom at z = 1.3 when up)
    g = "ram"
    C(0.035, (0, 0, 1.45), (0, 0, 2.3), P_["chrome"], g, verts=24)
    BX(-0.5, 0.5, -0.3, 0.3, 1.4, 1.5, P_["steel"], g, bw=0.008)
    for sx in (-1, 1):
        for sy in (-1, 1):
            C(0.055, (sx * 0.42, sy * 0.24, 1.38), (sx * 0.42, sy * 0.24, 1.52), P_["copper"], g, verts=24)
    BX(-0.13, 0.13, -0.09, 0.09, 1.3, 1.4, P_["dark"], g)
    # the part: raw blank and the pressed shape
    BX(-0.12, 0.12, -0.08, 0.08, 0.962, 1.0, P_["copper"], "part_raw", bw=0.004)
    BX(-0.15, 0.15, -0.1, 0.1, 0.962, 0.975, P_["steel"], "part_pressed", bw=0.002)
    C(0.06, (0, 0, 0.975), (0, 0, 0.99), P_["steel"], "part_pressed", verts=32)
    nodes({"ram": (0, 0, 0), "part_raw": (0, 0, 0), "part_pressed": (0, 0, 0)})


def fill():
    L, w = 3.2, 0.3
    plinth(-0.3, L + 0.3, -1.0, 1.0)
    belt_machine(L, w)
    nx = 0.5 * L
    for s in (-1, 1):
        BX(0.1, L - 0.1, s * (w / 2 - 0.06) - 0.006, s * (w / 2 - 0.06) + 0.006, 0.9, 0.93, P_["stainless"], bw=0.002)
    # portal and tank
    for s in (-1, 1):
        BX(nx - 0.04, nx + 0.04, s * 0.42 - 0.04, s * 0.42 + 0.04, 0.0, 1.62, P_["stainless"])
    BX(nx - 0.06, nx + 0.06, -0.46, 0.46, 1.62, 1.68, P_["stainless"])
    C(0.24, (nx, 0, 1.75), (nx, 0, 2.2), P_["stainless"], verts=48)
    C(0.24, (nx, 0, 1.75), (nx, 0, 1.68), P_["stainless"], verts=48, r2=0.06)
    C(0.245, (nx, 0, 2.2), (nx, 0, 2.23), P_["stainless"], verts=48)
    label("H2O", (nx, -0.245, 2.0), 0.08, P_["blue"])
    C(0.02, (nx, 0, 1.68), (nx, 0, 1.45), P_["stainless"], verts=16)
    BX(nx - 0.06, nx + 0.06, -0.05, 0.05, 1.37, 1.45, P_["dark"])
    BX(nx + 0.06, nx + 0.14, -0.04, 0.04, 1.38, 1.44, P_["blue"])
    lamp("Y1", (nx + 0.1, 0, 1.455), (1.0, 0.75, 0.05), r=0.01, base=False)
    C(0.012, (nx, 0, 1.37), (nx, 0, 1.2), P_["stainless"], verts=16, r2=0.006)
    C(0.006, (nx, 0, 1.2), (nx, 0, 0.84), P_["water"], "stream", verts=12, bw=0)
    # level probe (B2) next to the nozzle
    C(0.004, (nx + 0.05, 0, 1.4), (nx + 0.05, 0, 1.08), P_["chrome"], verts=8, bw=0)
    BX(nx + 0.03, nx + 0.07, -0.02, 0.02, 1.4, 1.46, P_["dark"])
    lamp("B2", (nx + 0.05, -0.02, 1.47), (0.1, 1.0, 0.3), r=0.008, base=False)
    # photo eye (B1) looking across the belt at the bottle
    BX(nx - 0.02, nx + 0.02, -(w / 2 + 0.12), -(w / 2 + 0.08), 0.0, 0.96, P_["alu"])
    photo_eye(nx, -(w / 2 + 0.06), 0.96, "B1")
    BX(nx - 0.02, nx + 0.02, w / 2 + 0.06, w / 2 + 0.08, 0.9, 1.02, P_["red"])
    # crate for the full bottles at the end
    crate(L + 0.12, 0.0, 0.0, 0.3, 0.45, 0.55, P_["blue"], "frame")
    # the bottle to clone (bottom centre at the origin) and its water
    g = "proto_bottle"
    C(0.035, (0, 0, 0.0), (0, 0, 0.17), P_["glass"], g, verts=32, bw=0.004)
    C(0.035, (0, 0, 0.17), (0, 0, 0.21), P_["glass"], g, verts=32, r2=0.014, bw=0)
    C(0.014, (0, 0, 0.21), (0, 0, 0.235), P_["glass"], g, verts=20, bw=0)
    C(0.016, (0, 0, 0.235), (0, 0, 0.255), P_["red"], g, verts=20)
    BX(-0.0352, 0.0352, -0.02, 0.02, 0.06, 0.12, P_["white"], g, bw=0)
    C(0.032, (0, 0, 0.004), (0, 0, 0.2), P_["water"], "proto_liquid", verts=32, bw=0)
    made = nodes({"stream": (nx, 0, 1.2), "proto_bottle": (0, 0, 0), "proto_liquid": (0, 0, 0)}, parents={"proto_liquid": "proto_bottle"})
    made["proto_bottle"].location = (0.4, 0.0, 0.82)


# ----------------------------------------------------------------- production lines
def belt():
    """packing conveyor: boxes come from a feeder table, ride the belt and stop on a
    roller table at the end; photo eye B1 sees a box waiting at the end"""
    L, w = 3.6, 0.5
    plinth(-0.7, L + 1.0, -1.1, 1.1)
    belt_machine(L, w)
    # feeder table with boxes waiting at the start
    BX(-0.6, 0.0, -0.3, 0.3, 0.8, 0.84, P_["steel"])
    for x in (-0.56, -0.04):
        for y in (-0.26, 0.26):
            BX(x - 0.02, x + 0.02, y - 0.02, y + 0.02, 0.0, 0.8, P_["alu"])
    crate(-0.3, 0.0, 0.84, 0.3, 0.3, 0.22, P_["cardboard"], "frame")
    crate(-0.3, 0.0, 1.06, 0.28, 0.28, 0.2, P_["cardboard"], "frame")
    # side guides
    for s in (-1, 1):
        BX(0.1, L - 0.1, s * (w / 2 - 0.01) - 0.01, s * (w / 2 - 0.01) + 0.01, 0.86, 0.9, P_["yellow"])
    # roller table at the end with an end stop
    BX(L, L + 0.8, -0.3, -0.27, 0.72, 0.8, P_["alu"])
    BX(L, L + 0.8, 0.27, 0.3, 0.72, 0.8, P_["alu"])
    for i in range(9):
        x = L + 0.05 + i * 0.085
        C(0.022, (x, -0.27, 0.79), (x, 0.27, 0.79), P_["chrome"], verts=16)
    for x in (L + 0.06, L + 0.74):
        for y in (-0.285, 0.285):
            BX(x - 0.02, x + 0.02, y - 0.02, y + 0.02, 0.0, 0.72, P_["alu"])
    BX(L + 0.78, L + 0.82, -0.3, 0.3, 0.72, 0.98, P_["yellow"])
    # photo eye (B1) across the roller table, and its reflector
    xe = L + 0.55
    BX(xe - 0.02, xe + 0.02, -0.42, -0.38, 0.0, 0.92, P_["alu"])
    photo_eye(xe, -0.36, 0.92, "B1")
    BX(xe - 0.02, xe + 0.02, 0.36, 0.38, 0.8, 0.98, P_["red"])
    BX(xe - 0.02, xe + 0.02, 0.38, 0.42, 0.0, 0.8, P_["alu"])
    label("B1", (xe, -0.43, 1.02), 0.06, P_["white"])
    label("M1", (L - 0.15, -(w / 2 + 0.17), 0.5), 0.06, P_["white"])
    # the box to clone (bottom centre at the origin)
    crate(0, 0, 0, 0.3, 0.3, 0.22, P_["cardboard"], "proto_box")
    BX(-0.152, 0.152, -0.04, 0.04, 0.0, 0.222, P_["yellow"], "proto_box", bw=0)
    made = nodes({"proto_box": (0, 0, 0)})
    made["proto_box"].location = (0.4, 0.0, 0.82)


FAN_FRAMES = 6   # blade layers 0°, 15° … 75° (four blades repeat every 90°)


def fan():
    """axial exhaust fan in a factory wall, its motor on the hub; the blades turn"""
    plinth(-1.4, 1.4, -0.9, 0.6)
    # wall with a square opening
    for (x0, x1, z0, z1) in ((-1.3, -0.62, 0.0, 2.6), (0.62, 1.3, 0.0, 2.6), (-0.62, 0.62, 0.0, 0.68), (-0.62, 0.62, 1.92, 2.6)):
        BX(x0, x1, 0.0, 0.24, z0, z1, P_["concrete"], bw=0.006)
    for i in range(13):
        BX(-1.3, 1.3, -0.002, 0.0, i * 0.2, i * 0.2 + 0.006, P_["grey"], bw=0)
    # square housing, round venturi and the guard rings
    cz = 1.3
    for (x0, x1, z0, z1) in ((-0.62, -0.56, 0.68, 1.92), (0.56, 0.62, 0.68, 1.92), (-0.62, 0.62, 0.68, 0.74), (-0.62, 0.62, 1.86, 1.92)):
        BX(x0, x1, -0.12, 0.06, z0, z1, P_["steel"])
    # dark duct behind, the open venturi tube with rolled lips, the guard ring
    C(0.6, (0, 0.2, cz), (0, 0.24, cz), P_["dark"], verts=64)
    for (x0, x1, z0, z1) in ((-0.56, 0.56, 0.74, 0.79), (-0.56, 0.56, 1.81, 1.86), (-0.56, -0.51, 0.74, 1.86), (0.51, 0.56, 0.74, 1.86)):
        BX(x0, x1, -0.1, 0.06, z0, z1, P_["grey"], bw=0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.53, depth=0.3, vertices=72, end_fill_type="NOTHING", location=(0, 0.05, cz), rotation=(math.pi / 2, 0, 0))
    t = bpy.context.object
    bpy.ops.object.transform_apply(rotation=True)
    lib.finish(t, 0, mats=[P_["grey"]])
    G["frame"].append(t)
    for y, mr in ((-0.1, 0.022), (0.2, 0.015)):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.53, minor_radius=mr, location=(0, y, cz), rotation=(math.pi / 2, 0, 0), major_segments=72)
        t = bpy.context.object
        lib.finish(t, 0, mats=[P_["steel"]])
        G["frame"].append(t)
    for r in (0.53, 0.36):
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.006, location=(0, -0.17, cz), rotation=(math.pi / 2, 0, 0), major_segments=72)
        t = bpy.context.object
        lib.finish(t, 0, mats=[P_["chrome"]])
        G["frame"].append(t)
    for a in (0, 90):
        r = math.radians(a)
        C(0.006, (-0.53 * math.cos(r), -0.17, cz - 0.53 * math.sin(r)), (0.53 * math.cos(r), -0.17, cz + 0.53 * math.sin(r)), P_["chrome"], verts=8, bw=0)
    # motor behind the hub on a cross bracket
    C(0.13, (0, 0.06, cz), (0, 0.36, cz), P_["blue"], verts=40)
    C(0.135, (0, 0.36, cz), (0, 0.42, cz), P_["dark"], verts=40)
    BX(-0.05, 0.05, 0.12, 0.22, cz + 0.12, cz + 0.2, P_["blue"])
    for a in (45, 135):
        r = math.radians(a)
        C(0.012, (-0.55 * math.cos(r), 0.1, cz - 0.55 * math.sin(r)), (0.55 * math.cos(r), 0.1, cz + 0.55 * math.sin(r)), P_["steel"], verts=8)
    label("M1", (0.0, -0.121, 0.705), 0.06, P_["dark"])
    label("EXHAUST", (0.0, -0.002, 2.1), 0.09, P_["yellow"])
    # local control station on the wall with its run lamp
    BX(0.8, 1.05, -0.08, 0.0, 1.2, 1.55, P_["grey"])
    for i, m in enumerate((P_["green"], P_["red"])):
        C(0.025, (0.86 + i * 0.13, -0.08, 1.33), (0.86 + i * 0.13, -0.1, 1.33), m, verts=20)
    lamp("RUN", (0.925, -0.09, 1.48), (0.1, 1.0, 0.3), r=0.02, base=False)
    # blades: hub and four twisted blades, turning about Y (centre at the pivot)
    g = "blades"
    C(0.09, (0, -0.15, cz), (0, -0.04, cz), P_["dark"], g, verts=32)
    C(0.09, (0, -0.15, cz), (0, -0.19, cz), P_["dark"], g, verts=32, r2=0.03)
    for k in range(4):
        # a paddle blade, wider at the tip, pitched 28°
        bm = bpy.data.meshes.new("blade")
        r0, r1, w0, w1, t = 0.08, 0.5, 0.07, 0.2, 0.006
        v = [(r0, -t, -w0 / 2), (r1, -t, -w1 / 2), (r1, -t, w1 / 2), (r0, -t, w0 / 2), (r0, t, -w0 / 2), (r1, t, -w1 / 2), (r1, t, w1 / 2), (r0, t, w0 / 2)]
        f = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        bm.from_pydata(v, [], f)
        o = bpy.data.objects.new("blade", bm)
        bpy.context.collection.objects.link(o)
        bpy.context.view_layer.objects.active = o
        for x in bpy.context.selected_objects:
            x.select_set(False)
        o.select_set(True)
        o.location = (0, -0.1, 0)
        bpy.ops.object.transform_apply(location=True)
        o.rotation_euler = (math.radians(28), 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        o.rotation_euler = (0, math.radians(k * 90), 0)
        bpy.ops.object.transform_apply(rotation=True)
        o.location = (0, 0, cz)
        bpy.ops.object.transform_apply(location=True)
        lib.finish(o, 0.004, mats=[P_["alu"]])
        G[g].append(o)
    nodes({"blades": (0, -0.1, cz)})


GATE_TRAVEL = 2.2


def gate():
    """sliding factory gate on a ground rail with its gear motor, two limit switches
    (LS1 closed, LS2 open) and an amber beacon that flashes while it moves"""
    plinth(-2.8, 3.1, -1.0, 1.0)
    # posts and the fence section the gate slides behind
    for x in (0.0, 2.3):
        BX(x - 0.1, x + 0.1, -0.1, 0.1, 0.0, 2.0, P_["grey"], bw=0.008)
        BX(x - 0.12, x + 0.12, -0.12, 0.12, 2.0, 2.06, P_["dark"])
    for x in (-2.4,):
        BX(x - 0.06, x + 0.06, 0.18, 0.3, 0.0, 1.9, P_["grey"])
    BX(-2.4, 0.0, 0.2, 0.28, 1.8, 1.86, P_["grey"])
    for i in range(12):
        x = -2.35 + i * 0.2
        C(0.012, (x, 0.24, 0.05), (x, 0.24, 1.8), P_["grey"], verts=8, bw=0)
    BX(-2.4, 0.0, 0.2, 0.28, 0.05, 0.1, P_["grey"])
    # ground rail
    BX(-2.6, 2.4, -0.03, 0.03, 0.0, 0.03, P_["steel"])
    # gear motor operator beside the post, with its limit switches
    # (right of the opening, in front: the leaf never passes over it)
    BX(2.5, 2.9, -0.42, -0.14, 0.0, 0.42, P_["grey"], bw=0.01)
    BX(2.49, 2.91, -0.43, -0.13, 0.42, 0.45, P_["dark"])
    label("M1", (2.7, -0.43, 0.3), 0.07, P_["white"])
    C(0.03, (2.55, -0.14, 0.16), (2.55, -0.06, 0.16), P_["steel"], verts=16)
    BX(2.3, 2.55, -0.08, -0.05, 0.12, 0.16, P_["dark"])
    for xs, tag in ((2.57, "LS1"), (2.83, "LS2")):
        BX(xs - 0.025, xs + 0.025, -0.47, -0.43, 0.16, 0.26, P_["yellow"])
        lamp(tag, (xs, -0.48, 0.3), (1.0, 0.25, 0.05), r=0.012, base=False)
        label(tag, (xs, -0.48, 0.07), 0.045, P_["white"])
    # beacon on the post
    C(0.05, (2.3, 0, 2.06), (2.3, 0, 2.1), P_["dark"], verts=24)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=(2.3, 0, 2.15), segments=24, ring_count=12)
    o = bpy.context.object
    o.name = "lamp_RUN"
    o.data.materials.append(lamp_mat("RUN", (1.0, 0.55, 0.0)))
    bpy.ops.object.shade_smooth()
    # the gate leaf (closed: spans the opening 0 … 2.3), moved along X
    g = "leaf"
    BX(0.0, 2.3, -0.05, 0.05, 0.1, 0.18, P_["yellow"], g, bw=0.006)
    BX(0.0, 2.3, -0.05, 0.05, 1.72, 1.8, P_["yellow"], g, bw=0.006)
    for x in (0.0, 2.24):
        BX(x, x + 0.06, -0.05, 0.05, 0.1, 1.8, P_["yellow"], g, bw=0.006)
    for i in range(1, 15):
        x = i * 2.3 / 15
        C(0.014, (x, 0, 0.18), (x, 0, 1.72), P_["yellow"], g, verts=10, bw=0)
    BX(0.0, 2.3, -0.06, -0.04, 0.12, 0.16, P_["dark"], g, bw=0)
    for x in (0.3, 2.0):
        C(0.06, (x, -0.025, 0.07), (x, 0.025, 0.07), P_["steel"], g, verts=24)
    BX(0.9, 1.4, -0.06, -0.055, 0.9, 1.1, P_["red"], g, bw=0)
    label("STOP", (1.15, -0.062, 0.97), 0.07, P_["white"], g=g)
    nodes({"leaf": (0, 0, 0)})


def spinner(g, c, axis, r, spokes, m, width=0.05, thick=0.03, hub=0.06):
    """a wheel / blade set of [spokes] arms around centre c, turning about axis X / Y / Z"""
    c = Vector(c)
    ax = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[axis]
    u = Vector((0, 0, 1)) if axis != "Z" else Vector((1, 0, 0))
    v = ax.cross(u)
    C(hub, c - ax * thick, c + ax * thick, P_["dark"], g, verts=24)
    for k in range(spokes):
        a = 2 * math.pi * k / spokes
        d = u * math.cos(a) + v * math.sin(a)
        C(width / 2, c + d * hub * 0.8, c + d * r, m, g, verts=10)


def crusher():
    """jaw crusher in a quarry: hopper, jaw body, a big flywheel on each side, V-belt
    drive from the motor (M1, started star-delta) and the conveyor taking the gravel"""
    plinth(-1.6, 2.6, -1.3, 1.3)
    # concrete base and the steel body
    BX(-0.9, 0.9, -0.7, 0.7, 0.0, 0.5, P_["concrete"], bw=0.01)
    BX(-0.7, 0.7, -0.5, 0.5, 0.5, 1.6, P_["yellow"], bw=0.012)
    for sy in (-1, 1):
        for x in (-0.55, -0.2, 0.2, 0.55):
            BX(x - 0.03, x + 0.03, sy * 0.5 - 0.02, sy * 0.5 + 0.02, 0.5, 1.6, P_["yellow"], bw=0.004)
    # hopper with rocks
    for (a, b) in ((-1, 1), (1, -1)):
        pass
    BX(-0.75, 0.75, -0.55, 0.55, 1.6, 1.68, P_["dark"])
    for sx in (-1, 1):
        BX(sx * 0.75 - 0.03, sx * 0.75 + 0.03, -0.55, 0.55, 1.68, 2.1, P_["grey"])
    for sy in (-1, 1):
        BX(-0.75, 0.75, sy * 0.55 - 0.03, sy * 0.55 + 0.03, 1.68, 2.1, P_["grey"])
    import random
    rnd = random.Random(4)
    for i in range(16):
        x, y = rnd.uniform(-0.6, 0.6), rnd.uniform(-0.42, 0.42)
        SPH(rnd.uniform(0.07, 0.13), (x, y, 1.75 + rnd.uniform(0, 0.15)), P_["concrete"])
    label("CRUSHER", (0, -0.505, 1.25), 0.11, P_["dark"])
    # bearings and the shaft through the body
    for sy in (-1, 1):
        BX(-0.15, 0.15, sy * 0.5, sy * 0.62, 1.05, 1.35, P_["dark"])
    C(0.06, (0, -0.85, 1.2), (0, 0.85, 1.2), P_["steel"], verts=24)
    # gravel conveyor under the outlet
    BX(0.8, 2.5, -0.25, 0.25, 0.35, 0.42, P_["belt"])
    for x in (0.9, 2.4):
        for sy in (-1, 1):
            BX(x - 0.03, x + 0.03, sy * 0.25 - 0.03, sy * 0.25 + 0.03, 0.0, 0.35, P_["alu"])
    for i in range(10):
        SPH(0.04, (1.0 + i * 0.14, (i % 3 - 1) * 0.08, 0.44), P_["concrete"])
    # motor on its slide rail, V-belt to the near flywheel
    BX(-1.5, -0.95, -1.1, -0.7, 0.0, 0.12, P_["dark"])
    motor(-1.22, -0.98, 0.32, axis="Y", length=0.3, r=0.15)
    label("M1", (-1.22, -1.14, 0.55), 0.08, P_["white"])
    C(0.1, (-1.22, -1.0, 0.32), (-1.22, -0.92, 0.32), P_["steel"], verts=32)
    for dz in (-0.1, 0.1):
        C(0.012, (-1.22, -0.96, 0.32 + dz), (0.0, -0.96, 1.2 + dz * 6), P_["rubber"], verts=8, bw=0)
    # far flywheel (still), near flywheel turns (frames rendered by render_machines.py)
    C(0.62, (0, 0.85, 1.2), (0, 0.93, 1.2), P_["dark"], verts=64)
    spinner("fly", (0, -0.92, 1.2), "Y", 0.6, 6, P_["red"], width=0.07, thick=0.05, hub=0.1)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.6, minor_radius=0.05, location=(0, -0.92, 1.2), rotation=(math.pi / 2, 0, 0), major_segments=64)
    t = bpy.context.object
    lib.finish(t, 0, mats=[P_["red"]])
    G["fly"].append(t)
    # a white mark on the rim so the turning shows
    BX(-0.05, 0.05, -0.99, -0.95, 1.77, 1.82, P_["white"], "fly", bw=0)
    nodes({"fly": (0, -0.92, 1.2)})


CRANE_X, CRANE_Y, CRANE_Z = 2.4, 1.6, 1.6   # travel of trolley (x), bridge (y), hook (z)


def crane():
    """overhead travelling crane in a bay: runway on columns, the bridge travels along Y
    (M3), the trolley along the bridge in X (M2) and the hook up / down (M1); a roller
    limit switch at each end of each travel"""
    plinth(-0.6, 3.6, -1.5, 2.2)
    H = 3.0
    for x in (-0.3, 3.3):
        for y in (-1.2, 0.6, 1.9):
            BX(x - 0.07, x + 0.07, y - 0.07, y + 0.07, 0.0, H, P_["grey"])
        BX(x - 0.1, x + 0.1, -1.3, 2.0, H, H + 0.18, P_["yellow"])
        BX(x - 0.02, x + 0.02, -1.3, 2.0, H + 0.18, H + 0.21, P_["steel"])
    # load to lift and its pallet
    BX(0.9, 1.7, -0.35, 0.25, 0.0, 0.1, P_["wood"])
    crate(1.3, -0.05, 0.1, 0.7, 0.5, 0.45, P_["blue"], "frame")
    # pendant-free limit switches with lamps: B1/B2 hook top/bottom are on the trolley,
    # B3/B4 trolley ends on the bridge girder, B5/B6 bridge ends on the runway
    for (x, y, z, tag) in ((3.3, -1.25, H + 0.25, "B5"), (3.3, 1.95, H + 0.25, "B6")):
        BX(x - 0.03, x + 0.03, y - 0.03, y + 0.03, z - 0.05, z + 0.03, P_["dark"])
        lamp(tag, (x, y, z + 0.05), (1.0, 0.3, 0.05), r=0.02, base=False)
        label(tag, (x + 0.12, y, z), 0.07, P_["white"], rot=(90, 0, 90))
    # bridge girder (at bridge y = 0) with its end trucks, along X
    g = "bridge"
    BX(-0.4, 3.4, -0.12, 0.12, H + 0.21, H + 0.55, P_["yellow"], g, bw=0.01)
    for x in (-0.3, 3.3):
        BX(x - 0.12, x + 0.12, -0.35, 0.35, H + 0.21, H + 0.4, P_["yellow"], g)
    label("5 TON", (1.5, -0.125, H + 0.35), 0.11, P_["dark"], g=g)
    for (x, tag) in ((0.15, "B3"), (2.85, "B4")):
        BX(x - 0.03, x + 0.03, -0.17, -0.12, H + 0.3, H + 0.4, P_["dark"], g)
        lamp(tag, (x, -0.18, H + 0.44), (1.0, 0.3, 0.05), r=0.018, base=False, g=g)
    motor(3.3, -0.4, H + 0.3, axis="Y", length=0.18, r=0.06, g=g)
    # trolley (at trolley x = 0 → world x 0.3) running on the girder, with the hoist
    g = "trolley"
    BX(0.05, 0.55, -0.3, 0.3, H + 0.55, H + 0.75, P_["blue"], g, bw=0.01)
    C(0.12, (0.15, -0.2, H + 0.86), (0.45, -0.2, H + 0.86), P_["blue"], g, verts=32)
    C(0.1, (0.15, 0.15, H + 0.86), (0.45, 0.15, H + 0.86), P_["steel"], g, verts=32)
    for (x, tag) in ((0.3, "B1"),):
        BX(x - 0.03, x + 0.03, -0.33, -0.3, H + 0.6, H + 0.7, P_["dark"], g)
        lamp(tag, (x, -0.34, H + 0.72), (1.0, 0.3, 0.05), r=0.016, base=False, g=g)
    # hook block (top of block at z = 0 relative, world hung at 1.4)
    g = "hook"
    BX(0.2, 0.4, -0.06, 0.06, 1.3, 1.55, P_["yellow"], g, bw=0.01)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.07, minor_radius=0.018, location=(0.3, 0, 1.2), rotation=(math.pi / 2, 0, 0))
    t = bpy.context.object
    lib.finish(t, 0, mats=[P_["steel"]])
    G[g].append(t)
    lamp("B2", (0.3, -0.07, 1.5), (1.0, 0.3, 0.05), r=0.014, base=False, g=g)
    nodes({"bridge": (0, 0, 0), "trolley": (0, 0, 0), "hook": (0.3, 0, 1.55)})


def oven():
    """paint-drying oven: insulated cabinet, glass door, three heater elements inside
    (they glow with the temperature), thermostat B1 and the cooling fan on the roof (M1)"""
    plinth(-0.4, 2.2, -1.0, 1.0)
    BX(0.0, 1.8, -0.6, 0.6, 0.0, 0.1, P_["dark"])
    BX(0.0, 1.8, -0.6, 0.6, 0.1, 1.9, P_["white"], bw=0.015)
    # dark inside behind the glass door
    BX(0.15, 1.65, -0.61, -0.59, 0.3, 1.65, P_["dark"], bw=0)
    BX(0.12, 1.68, -0.63, -0.61, 0.27, 0.32, P_["steel"], bw=0)
    BX(0.12, 1.68, -0.63, -0.61, 1.63, 1.68, P_["steel"], bw=0)
    for x in (0.12, 1.63):
        BX(x, x + 0.05, -0.63, -0.61, 0.27, 1.68, P_["steel"], bw=0)
    C(0.015, (1.5, -0.66, 0.8), (1.5, -0.66, 1.15), P_["chrome"], verts=12)
    # racks with painted panels
    for z in (0.55, 1.0, 1.4):
        BX(0.2, 1.6, -0.6, -0.55, z, z + 0.02, P_["steel"], bw=0)
    for x in (0.4, 0.9, 1.3):
        BX(x, x + 0.25, -0.58, -0.57, 1.02, 1.35, P_["red"], bw=0)
    # heater rods (cold), the glowing copy is the layer "glow"
    for z in (0.4, 0.75, 1.55):
        C(0.02, (0.2, -0.59, z), (1.6, -0.59, z), P_["steel"], verts=12)
        C(0.024, (0.2, -0.6, z), (1.6, -0.6, z), P_["orange"], "glow", verts=12, bw=0)
    label("DRYING OVEN", (0.9, -0.615, 1.78), 0.08, P_["dark"])
    # control box with the thermostat dial and its lamp
    BX(1.82, 2.1, -0.3, 0.1, 0.8, 1.4, P_["grey"])
    C(0.06, (1.96, -0.3, 1.2), (1.96, -0.32, 1.2), P_["white"], verts=32)
    C(0.008, (1.96, -0.33, 1.2), (1.99, -0.33, 1.24), P_["red"], verts=8, bw=0)
    lamp("B1", (1.96, -0.31, 1.02), (1.0, 0.3, 0.05), r=0.02, base=False)
    lamp("E1", (1.96, -0.31, 0.92), (1.0, 0.6, 0.1), r=0.02, base=False)
    label("B1", (1.96, -0.305, 1.32), 0.05, P_["white"])
    # cooling fan housing on the roof, its blades turn about Z
    C(0.3, (0.9, 0.0, 1.9), (0.9, 0.0, 2.15), P_["grey"], verts=48)
    C(0.27, (0.9, 0.0, 2.15), (0.9, 0.0, 2.152), P_["dark"], verts=48)
    label("M1", (0.9, -0.31, 2.0), 0.07, P_["white"])
    spinner("fan", (0.9, 0.0, 2.17), "Z", 0.25, 4, P_["alu"], width=0.09, thick=0.01, hub=0.05)
    for a in (0, 60, 120):
        r = math.radians(a)
        C(0.004, (0.9 - 0.3 * math.cos(r), -0.3 * math.sin(r), 2.2), (0.9 + 0.3 * math.cos(r), 0.3 * math.sin(r), 2.2), P_["chrome"], verts=6, bw=0)
    nodes({"glow": (0.9, -0.6, 1.0), "fan": (0.9, 0.0, 2.17)})


def mixer():
    """spiral dough mixer: bowl on a pedestal, a two-arm hook turning about Z (M1, both
    directions), and a safety guard with its switch B1 (closed = guard down)"""
    plinth(-1.0, 1.2, -1.0, 1.0)
    BX(-0.55, 0.55, -0.45, 0.45, 0.0, 0.7, P_["white"], bw=0.02)
    BX(0.2, 0.55, -0.35, 0.35, 0.7, 1.75, P_["white"], bw=0.02)
    BX(-0.55, 0.55, -0.35, 0.35, 1.6, 1.85, P_["white"], bw=0.02)
    label("DOUGH MIXER", (0.0, -0.455, 0.5), 0.07, P_["dark"])
    # control panel on the column
    BX(0.25, 0.5, -0.37, -0.35, 1.0, 1.4, P_["grey"], bw=0)
    for i, m in enumerate((P_["green"], P_["blue"], P_["red"])):
        C(0.02, (0.31 + i * 0.07, -0.37, 1.2), (0.31 + i * 0.07, -0.39, 1.2), m, verts=16)
    lamp("RUN", (0.38, -0.38, 1.33), (0.1, 1.0, 0.3), r=0.018, base=False)
    # bowl with dough
    C(0.4, (-0.2, 0.0, 0.7), (-0.2, 0.0, 1.15), P_["stainless"], verts=64)
    C(0.37, (-0.2, 0.0, 1.0), (-0.2, 0.0, 1.151), P_["cardboard"], verts=64)
    # guard grid over the bowl and its switch
    bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.012, location=(-0.2, 0, 1.22), major_segments=64)
    t = bpy.context.object
    lib.finish(t, 0, mats=[P_["chrome"]])
    G["frame"].append(t)
    for a in range(0, 180, 30):
        r = math.radians(a)
        C(0.006, (-0.2 - 0.42 * math.cos(r), -0.42 * math.sin(r), 1.22), (-0.2 + 0.42 * math.cos(r), 0.42 * math.sin(r), 1.22), P_["chrome"], verts=6, bw=0)
    BX(0.18, 0.24, -0.45, -0.38, 1.18, 1.26, P_["yellow"])
    lamp("B1", (0.21, -0.46, 1.29), (1.0, 0.3, 0.05), r=0.012, base=False)
    # the hook: two spiral arms down into the dough, turning about Z
    g = "hook"
    C(0.03, (-0.2, 0, 1.6), (-0.2, 0, 1.05), P_["chrome"], g, verts=16)
    for k in (0, 1):
        pts = []
        for i in range(9):
            a = k * math.pi + i * 0.35
            rr = 0.05 + i * 0.022
            pts.append(Vector((-0.2 + rr * math.cos(a), rr * math.sin(a), 1.32 - i * 0.04)))
        for p0, p1 in zip(pts, pts[1:]):
            C(0.018, p0, p1, P_["chrome"], g, verts=10, bw=0)
    nodes({"hook": (-0.2, 0, 1.3)})


def tank2():
    """water tank with two pumps (M1, M2) and two floats (B1 low, B2 high); the water
    level is a layer the lab clips to the level"""
    plinth(-1.2, 1.6, -1.1, 1.1)
    # tank on legs, glass front so the level shows
    for x in (-0.5, 0.5):
        for y in (-0.4, 0.4):
            BX(x - 0.04, x + 0.04, y - 0.04, y + 0.04, 0.0, 0.6, P_["steel"])
    C(0.62, (0, 0, 0.6), (0, 0, 0.65), P_["steel"], verts=64)
    C(0.6, (0, 0, 0.65), (0, 0, 2.05), P_["glass"], verts=64, bw=0)
    C(0.62, (0, 0, 2.05), (0, 0, 2.1), P_["steel"], verts=64)
    for z in (1.0, 1.5):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.605, minor_radius=0.012, location=(0, 0, z), major_segments=64)
        t = bpy.context.object
        lib.finish(t, 0, mats=[P_["steel"]])
        G["frame"].append(t)
    label("WATER", (0, -0.63, 1.85), 0.1, P_["blue"])
    # float switches on rods: B1 low, B2 high
    for (z, tag) in ((0.95, "B1"), (1.8, "B2")):
        C(0.006, (0.35, 0.0, 2.1), (0.35, 0.0, z), P_["chrome"], verts=8, bw=0)
        SPH(0.05, (0.35, 0.0, z), P_["orange"])
        lamp(tag, (0.35, -0.2, 2.13), (0.1, 1.0, 0.3) if tag == "B2" else (1.0, 0.3, 0.05), r=0.02, base=False)
        label(tag, (0.35, -0.21, 2.25), 0.06, P_["white"])
    # outlet pipe to the factory
    C(0.04, (0.6, 0.0, 0.75), (1.5, 0.0, 0.75), P_["blue"], verts=20)
    # two pumps on the floor, pipes up into the tank top
    for (x, tag) in ((-0.9, "M1"), (0.9, "M2")):
        y = -0.75
        BX(x - 0.25, x + 0.25, y - 0.15, y + 0.15, 0.0, 0.08, P_["dark"])
        motor(x - 0.05, y, 0.22, axis="X", length=0.25, r=0.1)
        C(0.11, (x - 0.15, y, 0.22), (x - 0.27, y, 0.22), P_["blue"], verts=32)
        C(0.035, (x - 0.21, y, 0.33), (x - 0.21, y, 2.2), P_["blue"], verts=16)
        C(0.035, (x - 0.21, y, 2.2), (x * 0.25, 0, 2.2), P_["blue"], verts=16)
        lamp(tag, (x + 0.05, y - 0.12, 0.42), (0.1, 1.0, 0.3), r=0.02, base=False)
        label(tag, (x + 0.05, y - 0.16, 0.5), 0.07, P_["white"])
    # the water (full); the lab clips it to the level
    C(0.59, (0, 0, 0.66), (0, 0, 2.04), P_["water"], "water", verts=64, bw=0)
    nodes({"water": (0, 0, 0.66)})


def washer():
    """bottle washer: a tunnel cabinet over a chain conveyor with three zones,
    wash (Y1), rinse (Y2) and hot-air dry (Y3), each with its spray / air layer; the door
    switch B1 is closed while the doors are shut"""
    L = 3.0
    plinth(-0.6, L + 0.6, -1.0, 1.0)
    conveyor(L + 0.4, 0.4, 0.8, legs=4)
    for (i, (x0, name, col)) in enumerate(((0.3, "WASH", P_["blue"]), (1.2, "RINSE", P_["green"]), (2.1, "DRY", P_["orange"]))):
        x1 = x0 + 0.8
        BX(x0, x1, -0.32, 0.32, 0.82, 0.86, P_["stainless"])
        BX(x0, x1, 0.3, 0.34, 0.86, 1.7, P_["stainless"])
        BX(x0, x1, -0.32, 0.34, 1.7, 1.78, P_["stainless"])
        BX(x0, x0 + 0.04, -0.34, 0.34, 0.86, 1.78, P_["stainless"])
        BX(x1 - 0.04, x1, -0.34, 0.34, 0.86, 1.78, P_["stainless"])
        BX(x0 + 0.04, x1 - 0.04, -0.34, -0.32, 1.25, 1.7, P_["glass"], bw=0)
        BX(x0 + 0.1, x1 - 0.1, -0.345, -0.33, 1.6, 1.68, col, bw=0)
        label(name, ((x0 + x1) / 2, -0.35, 1.61), 0.05, P_["white"])
        tag = "Y%d" % (i + 1)
        lamp(tag, ((x0 + x1) / 2, 0.0, 1.82), (1.0, 0.75, 0.05), r=0.025)
        label(tag, ((x0 + x1) / 2 + 0.12, -0.0, 1.85), 0.06, P_["white"], rot=(90, 0, 0))
        # nozzles
        for k in range(3):
            C(0.012, (x0 + 0.2 + k * 0.2, 0.0, 1.7), (x0 + 0.2 + k * 0.2, 0.0, 1.62), P_["chrome"], verts=10)
        g = ("wash", "rinse", "air")[i]
        for k in range(3):
            xx = x0 + 0.2 + k * 0.2
            C(0.012, (xx, 0.0, 1.62), (xx, 0.0, 0.9), P_["water"] if i < 2 else P_["glass"], g, verts=12, bw=0, r2=0.07)
    # bottles standing in the zones (crate on the chain)
    for x in (0.55, 0.75, 1.45, 1.65, 2.35, 2.55):
        C(0.035, (x, 0, 0.86), (x, 0, 1.05), P_["glass"], verts=24, bw=0)
        C(0.014, (x, 0, 1.05), (x, 0, 1.12), P_["glass"], verts=16, bw=0)
    # door switch B1 and the control box
    BX(L + 0.15, L + 0.45, -0.55, -0.4, 0.9, 1.4, P_["grey"])
    lamp("B1", (L + 0.3, -0.56, 1.3), (0.1, 1.0, 0.3), r=0.02, base=False)
    lamp("DONE", (L + 0.3, -0.56, 1.18), (0.1, 0.5, 1.0), r=0.02, base=False)
    label("B1", (L + 0.3, -0.56, 1.02), 0.05, P_["white"])
    nodes({"wash": (0, 0, 0), "rinse": (0, 0, 0), "air": (0, 0, 0)})


def hpress():
    """hydraulic press: oil tank with the pump motor (M1), directional valve with two
    coils (Y1 down, Y2 up), pressure switch B2 and the top limit switch B1"""
    plinth(-1.2, 1.4, -1.0, 1.0)
    BX(-0.6, 0.6, -0.4, 0.4, 0.0, 0.9, P_["green"], bw=0.012)
    BX(-0.65, 0.65, -0.45, 0.45, 0.9, 0.98, P_["steel"])
    for sx in (-1, 1):
        BX(sx * 0.5 - 0.1, sx * 0.5 + 0.1, -0.3, 0.3, 0.98, 2.4, P_["green"], bw=0.01)
    BX(-0.65, 0.65, -0.4, 0.4, 2.4, 2.75, P_["green"], bw=0.012)
    label("HYDRAULIC 40T", (0, -0.405, 2.55), 0.08, P_["white"])
    C(0.2, (0, 0, 2.75), (0, 0, 3.25), P_["steel"], verts=48)
    C(0.22, (0, 0, 3.25), (0, 0, 3.3), P_["dark"], verts=48)
    BX(-0.25, 0.25, -0.2, 0.2, 0.98, 1.06, P_["dark"])
    BX(-0.18, 0.18, -0.14, 0.14, 1.06, 1.1, P_["copper"], bw=0.004)
    # top limit switch B1 on the frame, pressure switch B2 on the valve block
    BX(0.38, 0.4, -0.32, -0.3, 2.0, 2.35, P_["steel"], bw=0)
    BX(0.36, 0.42, -0.36, -0.3, 2.25, 2.35, P_["yellow"])
    lamp("B1", (0.39, -0.37, 2.38), (1.0, 0.3, 0.05), r=0.015, base=False)
    label("B1", (0.39, -0.37, 2.18), 0.05, P_["white"])
    # power pack at the side: oil tank, pump motor, valve with two coils, gauge
    BX(0.8, 1.3, -0.4, 0.4, 0.0, 0.6, P_["blue"], bw=0.01)
    motor(1.05, 0.0, 0.85, axis="Y", length=0.3, r=0.12)
    label("M1", (1.05, -0.41, 0.4), 0.08, P_["white"])
    BX(0.82, 1.0, -0.45, -0.25, 0.6, 0.78, P_["dark"])
    for (y, tag) in ((-0.47, "Y1"), (-0.23, "Y2")):
        pass
    BX(0.75, 0.82, -0.42, -0.28, 0.63, 0.75, P_["red"])
    BX(1.0, 1.07, -0.42, -0.28, 0.63, 0.75, P_["blue"])
    lamp("Y1", (0.785, -0.43, 0.79), (1.0, 0.75, 0.05), r=0.014, base=False)
    lamp("Y2", (1.035, -0.43, 0.79), (1.0, 0.75, 0.05), r=0.014, base=False)
    label("Y1", (0.72, -0.43, 0.69), 0.04, P_["white"])
    label("Y2", (1.12, -0.43, 0.69), 0.04, P_["white"])
    C(0.05, (0.91, -0.47, 0.95), (0.91, -0.45, 0.95), P_["white"], verts=32)
    BX(0.89, 0.93, -0.46, -0.44, 0.78, 0.9, P_["dark"])
    lamp("B2", (0.91, -0.48, 1.04), (1.0, 0.3, 0.05), r=0.013, base=False)
    label("B2", (0.98, -0.48, 1.04), 0.04, P_["white"])
    for dz in (0.0, 0.05):
        C(0.012, (0.9, -0.35, 0.78 + dz), (0.2, -0.2, 2.8 + dz), P_["dark"], verts=8, bw=0)
    # ram: rod and platen (up), moved down along Z
    g = "ram"
    C(0.08, (0, 0, 1.95), (0, 0, 2.8), P_["chrome"], g, verts=32)
    BX(-0.38, 0.38, -0.28, 0.28, 1.85, 1.97, P_["steel"], g, bw=0.008)
    BX(-0.16, 0.16, -0.12, 0.12, 1.75, 1.85, P_["dark"], g)
    nodes({"ram": (0, 0, 0)})


def line3():
    """packing line: three conveyors in a row (M1 → M2 → M3), the last one into a
    wrapping station; photo eye B1 counts the boxes leaving the line"""
    seg = 1.6
    plinth(-0.4, 3 * seg + 1.2, -1.1, 1.1)
    for i in range(3):
        x0 = i * seg
        for s in (-1, 1):
            BX(x0, x0 + seg - 0.04, s * 0.27, s * 0.3, 0.68, 0.8, P_["alu"])
            for x in (x0 + 0.15, x0 + seg - 0.2):
                BX(x - 0.025, x + 0.025, s * 0.27, s * 0.3, 0.0, 0.68, P_["alu"])
        BX(x0 + 0.02, x0 + seg - 0.06, -0.26, 0.26, 0.79, 0.81, P_["belt"], bw=0.002)
        BX(x0 + 0.1, x0 + 0.3, -0.31, -0.27, 0.69, 0.79, (P_["blue"], P_["green"], P_["red"])[i])
        motor(x0 + seg - 0.2, -0.42, 0.58, axis="Y", length=0.16, r=0.05)
        tag = "M%d" % (i + 1)
        lamp(tag, (x0 + seg - 0.2, -0.45, 0.72), (0.1, 1.0, 0.3), r=0.018, base=False)
        label(tag, (x0 + 0.5, -0.31, 0.72), 0.06, P_["white"])
    # wrapping station over the end
    X = 3 * seg
    for s in (-1, 1):
        BX(X - 0.2, X + 0.5, s * 0.42, s * 0.48, 0.0, 1.5, P_["blue"])
    BX(X - 0.2, X + 0.5, -0.48, 0.48, 1.5, 1.6, P_["blue"])
    label("WRAP", (X + 0.15, -0.485, 1.53), 0.07, P_["white"])
    BX(X + 0.5, X + 1.1, -0.3, 0.3, 0.7, 0.78, P_["steel"])
    # photo eye B1 at the exit and the stack light
    BX(X + 0.55, X + 0.59, -0.42, -0.38, 0.0, 0.9, P_["alu"])
    photo_eye(X + 0.57, -0.36, 0.9, "B1")
    BX(X + 0.55, X + 0.59, 0.36, 0.38, 0.78, 0.96, P_["red"])
    C(0.015, (X + 0.9, -0.5, 0.0), (X + 0.9, -0.5, 1.6), P_["dark"], verts=12)
    for k, (tag, col) in enumerate((("H3", (1.0, 0.1, 0.1)), ("H2", (1.0, 0.7, 0.05)), ("H1", (0.1, 1.0, 0.3)))):
        C(0.05, (X + 0.9, -0.5, 1.6 + k * 0.12), (X + 0.9, -0.5, 1.71 + k * 0.12), P_["glass"], verts=24, bw=0)
        lamp(tag, (X + 0.9, -0.5, 1.655 + k * 0.12), col, r=0.045, base=False)
    # the box to clone
    crate(0, 0, 0, 0.3, 0.3, 0.22, P_["cardboard"], "proto_box")
    BX(-0.152, 0.152, -0.04, 0.04, 0.0, 0.222, P_["yellow"], "proto_box", bw=0)
    made = nodes({"proto_box": (0, 0, 0)})
    made["proto_box"].location = (0.3, 0.0, 0.8)


MACHINES = dict(cart=cart, hoist=hoist, lift=lift, sort=sort, press=press, fill=fill, belt=belt, fan=fan, gate=gate,
                crusher=crusher, crane=crane, oven=oven, mixer=mixer, tank2=tank2, washer=washer, hpress=hpress, line3=line3)


def main(keys):
    global P_
    for k in keys:
        lib.reset()
        G.clear()
        P_ = P()
        MACHINES[k]()
        lib.export("machine_" + k)
        print("machine_%s.glb" % k)


P_ = None
if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a in MACHINES] or list(MACHINES)
    main(args)
