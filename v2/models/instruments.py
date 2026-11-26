"""Measuring instruments and their practice benches, as GLB models for the app's
«أجهزة القياس» tab (assets/web/instruments.js, lib/meters/).

Units: metres. Z up, the instrument face looks to -Y (the viewer).

Instruments (each part a named node the app can highlight; moving parts are empties):
  inst_avo     analog multimeter: needle, knob, zero_screw, ohm_adj, jacks
  inst_dmm     digital multimeter: knob, lcd, jacks
  inst_clamp   clamp meter: jaw (opens), trigger, knob, lcd, hold, jacks, jaw_center
  inst_megger  insulation tester: needle, knob, test (button), lamp_live, jacks
  inst_watt    wattmeter: needle, zero_screw, binding posts
  inst_leads   probes, banana plugs, crocodile clips (cloned by the page; cable drawn there)
Benches:
  inst_board   a real distribution board: main switch, MCBs, terminals, N and PE bars
  inst_motor   a three-phase motor with its terminal box open and a local isolator
Every jack mouth is an empty J_<name> (plug axis = its local Z, pointing out of the jack);
every test point is an empty pt_<name> (local Z = the way a probe comes in);
every clamp place is clamp_<name> (local Z = along the wire, local X = where the meter body goes);
mount_* empties carry an instrument's resting pose; view_*/cam_* empties the camera presets.

Run:  python3.13 instruments.py [avo dmm clamp megger watt leads board motor] [--render]
Then: python3.13 publish.py inst_
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

import inst_faces as faces  # noqa: E402
import lib  # noqa: E402
import machines as mc  # noqa: E402

G = mc.G
FACES = {}


# ----------------------------------------------------------------- materials
def mats():
    m = lib.mat
    p = mc.P()
    p.update(dict(
        case_black=m("case_black", (0.025, 0.025, 0.028), rough=0.55, bump=0.35),
        case_grey=m("case_grey", (0.09, 0.095, 0.1), rough=0.5, bump=0.3),
        holster=m("holster_yellow", (0.85, 0.52, 0.0), rough=0.65, bump=0.5),
        meg_yellow=m("meg_yellow", (0.80, 0.55, 0.02), rough=0.45, bump=0.25),
        bakelite=m("bakelite", (0.10, 0.07, 0.05), rough=0.35, coat=0.4),
        knob_black=m("knob_black", (0.015, 0.015, 0.017), rough=0.35, bump=0.2),
        jack_red=m("jack_red", (0.55, 0.02, 0.02), rough=0.35),
        jack_black=m("jack_black", (0.02, 0.02, 0.02), rough=0.35),
        jack_green=m("jack_green", (0.02, 0.3, 0.06), rough=0.35),
        glass=m("meter_glass", (0.9, 0.95, 1.0), rough=0.02, alpha=0.12),
        needle=m("needle_black", (0.01, 0.01, 0.01), rough=0.4),
        needle_red=m("needle_red", (0.7, 0.03, 0.02), rough=0.4),
        print_white=m("print_white", (0.85, 0.85, 0.85), rough=0.6),
        print_black=m("print_black", (0.01, 0.01, 0.01), rough=0.6),
        brass=m("brass", (0.82, 0.68, 0.38), metal=1.0, rough=0.22),
        nickel=m("nickel", (0.8, 0.8, 0.78), metal=1.0, rough=0.18),
        ral7035=m("ral7035", (0.62, 0.64, 0.62), rough=0.5, bump=0.15),
        galv=m("galvanised", (0.66, 0.68, 0.7), metal=0.9, rough=0.42, bump=0.2),
        mcb_white=m("mcb_white", (0.8, 0.8, 0.78), rough=0.4, bump=0.15),
        lever_blue=m("lever_blue", (0.02, 0.08, 0.35), rough=0.35),
        lever_red=m("lever_red", (0.5, 0.02, 0.02), rough=0.35),
        term_grey=m("term_grey", (0.42, 0.43, 0.44), rough=0.45),
        term_blue=m("term_blue", (0.03, 0.15, 0.55), rough=0.45),
        term_gy=m("term_gy", (0.25, 0.5, 0.05), rough=0.45),
        w_brown=m("w_brown", (0.18, 0.06, 0.02), rough=0.4),
        w_black=m("w_black", (0.012, 0.012, 0.014), rough=0.4),
        w_grey=m("w_grey", (0.3, 0.3, 0.32), rough=0.4),
        w_blue=m("w_blue", (0.02, 0.12, 0.6), rough=0.4),
        w_gy=m("w_gy", (0.35, 0.6, 0.02), rough=0.4),
        sheath=m("sheath_grey", (0.25, 0.26, 0.28), rough=0.55),
        sheath_black=m("sheath_black", (0.02, 0.02, 0.022), rough=0.55),
        motor_paint=m("motor_paint", (0.03, 0.12, 0.30), metal=0.3, rough=0.45, bump=0.4),
        iron=m("cast_iron", (0.2, 0.2, 0.21), metal=0.8, rough=0.6, bump=0.4),
        floor=m("epoxy_floor", (0.16, 0.2, 0.18), rough=0.55, bump=0.2),
        wall=m("wall_paint", (0.55, 0.56, 0.54), rough=0.85, bump=0.3),
        wood=m("bench_wood", (0.45, 0.26, 0.11), rough=0.6, bump=0.3),
        lcd_off=m("lcd", (0.42, 0.5, 0.44), rough=0.25),
        led_red=m("led_red", (0.6, 0.02, 0.02), rough=0.2),
    ))
    return p


def tex_mat(name, key, rough=0.55):
    path = FACES[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(path)
    t.interpolation = "Cubic"
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    return m


# ----------------------------------------------------------------- helpers
B, BX, C, SPH = mc.B, mc.BX, mc.C, mc.SPH


def face(g, key, x0, x1, z0, z1, y, rough=0.55, name=None):
    """a printed plate facing -Y, image upright"""
    bpy.ops.mesh.primitive_plane_add(size=1, location=((x0 + x1) / 2, y, (z0 + z1) / 2))
    o = bpy.context.object
    o.scale = (x1 - x0, z1 - z0, 1)
    o.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.data.materials.append(tex_mat(name or ("face_" + key), key, rough))
    G[g].append(o)
    return o


def plane_y(g, x0, x1, z0, z1, y, m):
    bpy.ops.mesh.primitive_plane_add(size=1, location=((x0 + x1) / 2, y, (z0 + z1) / 2))
    o = bpy.context.object
    o.scale = (x1 - x0, z1 - z0, 1)
    o.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.data.materials.append(m)
    G[g].append(o)
    return o


def cutbox(target, x0, x1, y0, y1, z0, z1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    c = bpy.context.object
    c.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(scale=True)
    lib.cut(target, c)


def cutcyl(target, r, p0, p1, verts=32):
    p0, p1 = Vector(p0), Vector(p1)
    v = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=v.length, vertices=verts, location=(p0 + p1) / 2)
    c = bpy.context.object
    c.rotation_mode = "QUATERNION"
    c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(v.normalized())
    lib.cut(target, c)


def text(g, s, loc, size, m, rot=(90, 0, 0), depth=0.0003):
    o = lib.text(s, size, loc, m, rot=rot, depth=depth)
    G[g].append(o)
    return o


def point(name, loc, normal=(0, 0, 1), xdir=None):
    """an empty whose local Z points along normal (and local X along xdir, when given)"""
    z = Vector(normal).normalized()
    if xdir is None:
        q = Vector((0, 0, 1)).rotation_difference(z)
        mat = q.to_matrix().to_4x4()
    else:
        x = Vector(xdir)
        x = (x - z * x.dot(z)).normalized()
        y = z.cross(x)
        mat = Matrix((x, y, z)).transposed().to_4x4()
    bpy.ops.object.empty_add(type="ARROWS", location=loc)
    e = bpy.context.object
    e.name = name
    e.empty_display_size = 0.01
    e.matrix_world = Matrix.Translation(Vector(loc)) @ mat
    return e


def pose(name, loc, rot_deg=(0, 0, 0)):
    """an empty carrying a resting pose (location + Euler XYZ degrees)"""
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    e = bpy.context.object
    e.name = name
    e.rotation_euler = Euler([math.radians(a) for a in rot_deg])
    e.empty_display_size = 0.03
    return e


def jack(g, x, z, y_face, m, r=0.0052, name=None, depth=0.006):
    """a shrouded 4 mm safety jack in the face y_face, J_<name> at its mouth"""
    o = C(r, (x, y_face + 0.002, z), (x, y_face - depth, z), m, g, verts=40, bw=0.0006)
    cutcyl(o, 0.0024, (x, y_face + 0.01, z), (x, y_face - depth - 0.01, z))
    C(0.0023, (x, y_face - 0.001, z), (x, y_face + 0.0005, z), P_["nickel"], g, verts=24, bw=0)
    if name:
        point("J_" + name, (x, y_face - depth, z), (0, -1, 0))
    return o


def knurled_knob(g, center, r, depth, m, ridges=24, bar=True, pointer=True):
    """a rotary knob on a face looking -Y, built round its own centre"""
    x, y, z = center
    C(r, (x, y, z), (x, y - depth, z), m, g, verts=64, bw=0.0015)
    for i in range(ridges):
        a = 2 * math.pi * i / ridges
        dx, dz = math.cos(a) * r, math.sin(a) * r
        C(0.0008, (x + dx, y - 0.0005, z + dz), (x + dx, y - depth + 0.0008, z + dz), m, g, verts=8, bw=0)
    if bar:
        BX(x - 0.0045, x + 0.0045, y - depth - 0.006, y - depth + 0.001, z - r * 0.92, z + r * 0.92, m, g, bw=0.002)
    if pointer:
        BX(x - 0.0009, x + 0.0009, y - depth - 0.0062, y - depth - 0.0055, z + r * 0.35, z + r * 0.88, P_["print_white"], g, bw=0)


def needle(g, pivot, length, y, m=None, tip=None, w=0.0007):
    x, _, z = pivot
    BX(x - w / 2, x + w / 2, y - 0.0003, y + 0.0003, z, z + length * 0.82, m or P_["needle"], g, bw=0)
    BX(x - w * 0.3, x + w * 0.3, y - 0.0003, y + 0.0003, z + length * 0.82, z + length, tip or m or P_["needle"], g, bw=0)
    BX(x - 0.004, x + 0.004, y - 0.0004, y + 0.0004, z - 0.012, z - 0.004, P_["needle"], g, bw=0)  # counterweight arm


def wire(g, pts, r, m, res=10):
    """a cable through the points (Catmull-Rom), as a mesh"""
    P = [Vector(p) for p in pts]
    if len(P) > 2:
        dense = []
        ext = [P[0] + (P[0] - P[1])] + P + [P[-1] + (P[-1] - P[-2])]
        for i in range(1, len(ext) - 2):
            p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
            for k in range(res):
                t = k / res
                t2, t3 = t * t, t * t * t
                dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        dense.append(P[-1])
        P = dense
    cu = bpy.data.curves.new("wire", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(P) - 1)
    for i, p in enumerate(P):
        sp.points[i].co = (p.x, p.y, p.z, 1)
    o = bpy.data.objects.new("wire", cu)
    bpy.context.scene.collection.objects.link(o)
    lib._sel(o)
    bpy.ops.object.convert(target="MESH")
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    G[g].append(o)
    return o


def screw_head(g, loc, normal=(0, -1, 0), r=0.0028, m=None):
    n = Vector(normal).normalized()
    p = Vector(loc)
    o = C(r, tuple(p), tuple(p + n * 0.0018), m or P_["nickel"], g, verts=24, bw=0.0006)
    # slot
    return o


def finish_nodes(pivots, parents=None):
    return mc.nodes(pivots, parents)


# ================================================================= instruments
def avo():
    """analog multimeter (the «أفوميتر»): body 112 x 175 x 40 mm"""
    g = "case"
    body = BX(-0.056, 0.056, -0.040, 0.0, 0.0, 0.175, P_["case_black"], g, bw=0.007)
    cutbox(body, -0.048, 0.048, -0.05, -0.030, 0.097, 0.163)          # the window recess
    # raised bezel round the window and the panel
    for (x0, x1, z0, z1) in ((-0.052, 0.052, 0.163, 0.168), (-0.052, 0.052, 0.092, 0.097), (-0.052, -0.048, 0.092, 0.168), (0.048, 0.052, 0.092, 0.168)):
        BX(x0, x1, -0.0415, -0.039, z0, z1, P_["case_grey"], "window", bw=0.0008)
    # rubber feet and a back stand
    for x in (-0.045, 0.045):
        BX(x - 0.006, x + 0.006, -0.010, 0.002, -0.002, 0.003, P_["rubber"], g, bw=0.001)
    BX(-0.04, 0.04, 0.0, 0.004, 0.02, 0.15, P_["case_grey"], g, bw=0.002)
    face("scale", "avo_card", -0.048, 0.048, 0.097, 0.163, -0.031, rough=0.45)
    plane_y("window", -0.048, 0.048, 0.097, 0.163, -0.0392, P_["glass"])
    face("panel", "avo_panel", -0.052, 0.052, 0.004, 0.094, -0.0402)
    needle("needle", (0.0, 0.0, 0.093), 0.061, -0.0335, tip=P_["needle_red"])
    # mechanical zero screw (flat head) just under the window
    C(0.0042, (0, -0.040, 0.0885), (0, -0.0425, 0.0885), P_["case_grey"], "zero_screw", verts=32, bw=0.0006)
    BX(-0.0032, 0.0032, -0.0428, -0.0420, 0.0880, 0.0890, P_["knob_black"], "zero_screw", bw=0)
    # the range selector
    knurled_knob("knob", (0, -0.0402, 0.050), 0.019, 0.008, P_["knob_black"], ridges=36)
    # 0 ohm adjust
    knurled_knob("ohm_adj", (0.040, -0.0402, 0.078), 0.0075, 0.007, P_["knob_black"], ridges=18, bar=False)
    BX(0.0396, 0.0404, -0.0475, -0.0470, 0.081, 0.0845, P_["print_white"], "ohm_adj", bw=0)
    # jacks
    jack("jack_com", -0.040, 0.014, -0.0402, P_["jack_black"], name="com")
    jack("jack_v", 0.040, 0.014, -0.0402, P_["jack_red"], name="v")
    jack("jack_10a", -0.040, 0.078, -0.0402, P_["jack_red"], name="10a")
    point("view_face", (0, -0.04, 0.12), (0, -1, 0))
    finish_nodes({"needle": (0, -0.0335, 0.093), "knob": (0, -0.0402, 0.050), "zero_screw": (0, -0.04, 0.0885),
                  "ohm_adj": (0.040, -0.0402, 0.078)})


def dmm():
    """digital multimeter in its rubber holster: 90 x 185 x 36 mm"""
    g = "case"
    BX(-0.045, 0.045, -0.034, 0.0, 0.0, 0.185, P_["holster"], "holster", bw=0.009)
    BX(-0.040, 0.040, -0.0375, -0.030, 0.006, 0.179, P_["case_black"], g, bw=0.004)
    face("panel", "dmm_panel", -0.038, 0.038, 0.008, 0.104, -0.0377)
    BX(-0.036, 0.036, -0.0382, -0.0372, 0.112, 0.170, P_["case_grey"], g, bw=0.001)
    plane_y("lcd", -0.032, 0.032, 0.118, 0.164, -0.0384, P_["lcd_off"])
    plane_y("window", -0.0325, 0.0325, 0.1175, 0.1645, -0.0386, P_["glass"])
    for x, n in ((-0.02, "sel"), (0.0, "hold"), (0.02, "range")):
        BX(x - 0.0065, x + 0.0065, -0.0392, -0.0372, 0.106, 0.1105, P_["case_grey"], "buttons", bw=0.001)
    knurled_knob("knob", (0, -0.0377, 0.058), 0.016, 0.007, P_["knob_black"], ridges=30)
    for x, n, mm in ((-0.028, "10a", "jack_red"), (-0.009, "ma", "jack_red"), (0.010, "com", "jack_black"), (0.028, "v", "jack_red")):
        jack("jack_" + n, x, 0.030, -0.0377, P_[mm], name=n)
    point("view_face", (0, -0.038, 0.11), (0, -1, 0))
    finish_nodes({"knob": (0, -0.0377, 0.058)})


def clamp():
    """clamp meter: 70 x 240 x 36 mm, the jaw opens round a hinge at its bottom left"""
    g = "case"
    BX(-0.032, 0.032, -0.034, 0.0, 0.0, 0.150, P_["case_grey"], g, bw=0.008)
    BX(-0.024, 0.024, -0.031, -0.003, 0.140, 0.178, P_["case_grey"], g, bw=0.006)
    BX(-0.036, 0.036, -0.035, 0.001, 0.146, 0.153, P_["meg_yellow"], "guard", bw=0.002)      # finger guard
    face("panel", "clamp_panel", -0.029, 0.029, 0.006, 0.098, -0.0342)
    BX(-0.028, 0.028, -0.0348, -0.0338, 0.100, 0.144, P_["case_black"], g, bw=0.001)
    plane_y("lcd", -0.025, 0.025, 0.104, 0.140, -0.0350, P_["lcd_off"])
    plane_y("window", -0.0255, 0.0255, 0.1035, 0.1405, -0.0352, P_["glass"])
    BX(0.012, 0.024, -0.037, -0.034, 0.078, 0.086, P_["meg_yellow"], "hold", bw=0.001)
    knurled_knob("knob", (0, -0.0342, 0.050), 0.0125, 0.007, P_["knob_black"], ridges=24)
    jack("jack_v", -0.014, 0.026, -0.0342, P_["jack_red"], name="v")
    jack("jack_com", 0.014, 0.026, -0.0342, P_["jack_black"], name="com")
    # the jaws: a split ring; the left half swings open
    cz, cy, R, r = 0.206, -0.017, 0.027, 0.0075
    for half, grp, m in ((-1, "jaw", P_["meg_yellow"]), (1, "jaw_fixed", P_["meg_yellow"])):
        bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=72, minor_segments=18,
                                         location=(0, cy, cz), rotation=(math.radians(90), 0, 0))
        o = bpy.context.object
        bpy.ops.object.transform_apply(location=True, rotation=True)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(half, 0, 0), clear_outer=True, clear_inner=False)
        bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
        bm.to_mesh(o.data)
        bm.free()
        lib.finish(o, 0, mats=[m])
        bpy.ops.object.shade_smooth()
        G[grp].append(o)
        # dark tips where the jaws meet
        BX(-0.0008, 0.0008, cy - r, cy + r, cz + R - r, cz + R + r, P_["case_black"], grp, bw=0)
    BX(-0.012, 0.012, -0.030, -0.004, 0.176, 0.181, P_["case_grey"], g, bw=0.002)
    # the trigger on the left side
    BX(-0.044, -0.031, -0.028, -0.006, 0.122, 0.168, P_["meg_yellow"], "trigger", bw=0.004)
    point("jaw_center", (0, cy, cz), (0, 1, 0), xdir=(0, 0, -1))
    point("view_face", (0, -0.034, 0.12), (0, -1, 0))
    finish_nodes({"knob": (0, -0.0342, 0.050), "jaw": (-0.0005, cy, cz - R), "trigger": (-0.031, -0.017, 0.160)},
                 parents={})


def megger():
    """insulation resistance tester: 170 x 75 x 130 mm"""
    g = "case"
    body = BX(-0.085, 0.085, -0.075, 0.0, 0.0, 0.130, P_["case_black"], g, bw=0.010)
    cutbox(body, -0.050, 0.050, -0.09, -0.064, 0.064, 0.122)
    BX(-0.080, 0.080, -0.0765, -0.0745, 0.005, 0.125, P_["meg_yellow"], "panel", bw=0.003)
    cutbox(G["panel"][-1], -0.050, 0.050, -0.09, -0.06, 0.064, 0.122)
    face("scale", "megger_card", -0.050, 0.050, 0.064, 0.122, -0.065, rough=0.45)
    plane_y("window", -0.050, 0.050, 0.064, 0.122, -0.0745, P_["glass"])
    face("panel", "megger_panel", -0.075, 0.075, 0.008, 0.058, -0.0768)
    needle("needle", (0, 0, 0.058), 0.062, -0.0675, tip=P_["needle"])
    knurled_knob("knob", (0.027, -0.0768, 0.032), 0.0125, 0.008, P_["knob_black"], ridges=24)
    # test button (press and turn to lock)
    C(0.012, (-0.045, -0.0768, 0.030), (-0.045, -0.080, 0.030), P_["case_black"], "test", verts=48, bw=0.001)
    C(0.0095, (-0.045, -0.080, 0.030), (-0.045, -0.0855, 0.030), P_["red"], "test", verts=48, bw=0.0015)
    # live-circuit warning LED
    C(0.0032, (-0.011, -0.0768, 0.044), (-0.011, -0.0795, 0.044), P_["led_red"], "lamp_live", verts=24, bw=0.0008)
    jack("jack_line", 0.060, 0.040, -0.0768, P_["jack_red"], name="line", r=0.0058)
    jack("jack_earth", 0.060, 0.022, -0.0768, P_["jack_black"], name="earth", r=0.0058)
    # carrying strap lugs and strap
    for x in (-0.088, 0.088):
        BX(x - 0.004, x + 0.004, -0.05, -0.025, 0.095, 0.115, P_["nickel"], g, bw=0.001)
    wire("strap", [(-0.092, -0.0375, 0.105), (-0.07, -0.0375, 0.15), (0.0, -0.0375, 0.17), (0.07, -0.0375, 0.15), (0.092, -0.0375, 0.105)], 0.004, P_["sheath_black"])
    point("view_face", (0, -0.075, 0.075), (0, -1, 0))
    finish_nodes({"needle": (0, -0.0675, 0.058), "knob": (0.027, -0.0768, 0.032), "test": (-0.045, -0.0768, 0.030)})


def watt():
    """portable analog wattmeter: 190 x 120 x 160 mm, bakelite case, binding posts"""
    g = "case"
    body = BX(-0.095, 0.095, -0.12, 0.0, 0.0, 0.160, P_["bakelite"], g, bw=0.008)
    cutbox(body, -0.062, 0.062, -0.14, -0.108, 0.072, 0.134)
    BX(-0.066, 0.066, -0.1215, -0.1195, 0.068, 0.138, P_["nickel"], "window", bw=0.002)
    cutbox(G["window"][-1], -0.062, 0.062, -0.13, -0.11, 0.072, 0.134)
    face("scale", "watt_card", -0.062, 0.062, 0.072, 0.134, -0.109, rough=0.45)
    plane_y("window", -0.062, 0.062, 0.072, 0.134, -0.1192, P_["glass"])
    face("panel", "watt_panel", -0.090, 0.090, 0.008, 0.042, -0.1202)
    needle("needle", (0, 0, 0.064), 0.072, -0.1115, tip=P_["needle"], w=0.0008)
    C(0.005, (0, -0.120, 0.057), (0, -0.1225, 0.057), P_["nickel"], "zero_screw", verts=32, bw=0.0006)
    BX(-0.0038, 0.0038, -0.1228, -0.1222, 0.0565, 0.0575, P_["knob_black"], "zero_screw", bw=0)
    # carrying handle on top
    for x in (-0.07, 0.07):
        BX(x - 0.008, x + 0.008, -0.07, -0.05, 0.160, 0.172, P_["nickel"], g, bw=0.002)
    wire(g, [(-0.07, -0.06, 0.168), (-0.06, -0.06, 0.19), (0.06, -0.06, 0.19), (0.07, -0.06, 0.168)], 0.006, P_["sheath_black"])
    # binding posts: hex base, knurled cap, cross hole
    for x, n, m in ((-0.065, "ia", P_["jack_red"]), (-0.025, "i5", P_["jack_black"]), (0.025, "vc", P_["jack_red"]), (0.065, "v300", P_["jack_black"])):
        grp = "post_" + n
        C(0.0075, (x, -0.1202, 0.016), (x, -0.124, 0.016), P_["brass"], grp, verts=6, bw=0.0005)
        C(0.0068, (x, -0.124, 0.016), (x, -0.137, 0.016), m, grp, verts=40, bw=0.0015)
        point("J_" + n, (x, -0.137, 0.016), (0, -1, 0))
    point("view_face", (0, -0.12, 0.10), (0, -1, 0))
    finish_nodes({"needle": (0, -0.1115, 0.064), "zero_screw": (0, -0.12, 0.057)})


def leads():
    """protos the page clones: probes (tip at origin, body up +Z), banana plugs (pin below the origin,
    body up +Z) and crocodile clips (jaw tip at origin, body up +Z). The cable leaves each at TAIL."""
    for col in ("red", "black"):
        m = P_["jack_red"] if col == "red" else P_["jack_black"]
        g = "probe_" + col
        C(0.0010, (0, 0, 0), (0, 0, 0.004), P_["nickel"], g, verts=16, bw=0, r2=0.0002) if False else None
        C(0.0001, (0, 0, 0.0), (0, 0, 0.0035), P_["nickel"], g, verts=16, bw=0, r2=0.0009)
        C(0.0009, (0, 0, 0.0035), (0, 0, 0.016), P_["nickel"], g, verts=16, bw=0)
        C(0.0026, (0, 0, 0.012), (0, 0, 0.022), m, g, verts=24, bw=0.0005)          # insulated shroud
        C(0.0075, (0, 0, 0.022), (0, 0, 0.026), m, g, verts=40, bw=0.0012)          # finger guard
        C(0.0048, (0, 0, 0.026), (0, 0, 0.115), m, g, verts=32, bw=0.0015)
        for k in range(10):
            z = 0.04 + k * 0.006
            C(0.0051, (0, 0, z), (0, 0, z + 0.0025), m, g, verts=32, bw=0.0005)      # grip rings
        C(0.0040, (0, 0, 0.115), (0, 0, 0.135), m, g, verts=24, bw=0.001, r2=0.0022)
        g = "plug_" + col
        C(0.0019, (0, 0, -0.012), (0, 0, 0.0), P_["nickel"], g, verts=20, bw=0)
        C(0.0042, (0, 0, -0.008), (0, 0, 0.0), m, g, verts=32, bw=0.0006)          # shroud sleeve
        C(0.0055, (0, 0, 0.0), (0, 0, 0.032), m, g, verts=32, bw=0.0015, r2=0.0047)
        C(0.0035, (0, 0, 0.032), (0, 0, 0.045), m, g, verts=24, bw=0.001, r2=0.0021)
        g = "croc_" + col
        BX(-0.003, 0.003, -0.0016, 0.0016, 0.0, 0.030, P_["nickel"], g, bw=0.0006)
        BX(-0.004, 0.004, -0.007, -0.0016, 0.004, 0.022, P_["nickel"], g, bw=0.0008)
        BX(-0.0045, 0.0045, -0.008, 0.0045, 0.018, 0.062, m, g, bw=0.003)          # insulating boot
        C(0.0026, (0, -0.002, 0.062), (0, -0.002, 0.075), m, g, verts=20, bw=0.0008, r2=0.0021)
    nodes = {k: (0, 0, 0) for k in list(G.keys())}
    made = finish_nodes(nodes)
    for i, (k, e) in enumerate(made.items()):
        e.location = (i * 0.04, 0, 0)


# ================================================================= benches
def mcb(g, x0, poles, z, y, label, lever_m, tog_name):
    """a DIN-rail breaker, `poles` x 18 mm, 90 mm tall around z, front at y"""
    w = 0.018 * poles
    x1 = x0 + w
    BX(x0 + 0.0003, x1 - 0.0003, y + 0.015, y + 0.045, z - 0.045, z + 0.045, P_["mcb_white"], g, bw=0.0015)
    BX(x0 + 0.0003, x1 - 0.0003, y, y + 0.016, z - 0.022, z + 0.022, P_["mcb_white"], g, bw=0.0015)
    # label strip
    BX(x0 + 0.002, x1 - 0.002, y - 0.0003, y + 0.001, z + 0.012, z + 0.020, P_["print_white"], g, bw=0)
    text(g, label, ((x0 + x1) / 2, y - 0.0006, z + 0.016), 0.0055, P_["print_black"])
    # lever (a node that turns round X)
    BX(x0 + 0.002, x1 - 0.002, y - 0.012, y + 0.002, z - 0.003, z + 0.003, lever_m, tog_name, bw=0.0015)
    BX(x0 + 0.002, x1 - 0.002, y - 0.014, y - 0.010, z - 0.004, z + 0.004, lever_m, tog_name, bw=0.0015)
    pts = []
    for i in range(poles):
        cx = x0 + 0.009 + i * 0.018
        for zz, side in ((z + 0.037, "top"), (z - 0.037, "bot")):
            BX(cx - 0.0045, cx + 0.0045, y + 0.012, y + 0.015, zz - 0.004, zz + 0.004, P_["case_black"], g, bw=0)
            screw_head(g, (cx, y + 0.012, zz), (0, -1, 0), r=0.0027)
            BX(cx - 0.0006, cx + 0.0006, y + 0.0098, y + 0.0103, zz - 0.0022, zz + 0.0022, P_["case_black"], g, bw=0)
            pts.append((cx, y + 0.0095, zz, side, i))
    return pts


def terminal(g, x, z, y, m, label=None, w=0.0062):
    """a feed-through terminal block on the rail: screws at top and bottom"""
    BX(x - w / 2 + 0.0002, x + w / 2 - 0.0002, y + 0.008, y + 0.04, z - 0.028, z + 0.028, m, g, bw=0.0008)
    BX(x - w / 2 + 0.0002, x + w / 2 - 0.0002, y, y + 0.01, z - 0.012, z + 0.012, m, g, bw=0.0008)
    for zz in (z + 0.020, z - 0.020):
        screw_head(g, (x, y + 0.008, zz), (0, -1, 0), r=0.0022)
    if label:
        BX(x - w / 2 + 0.0006, x + w / 2 - 0.0006, y - 0.0004, y + 0.001, z - 0.004, z + 0.004, P_["print_white"], g, bw=0)
        text(g, label, (x, y - 0.0007, z), 0.0034, P_["print_black"])
    return (x, y + 0.0075, z + 0.020), (x, y + 0.0075, z - 0.020)


def busbar(g, x0, x1, z, y, base_m, label):
    BX(x0, x1, y + 0.01, y + 0.03, z - 0.009, z + 0.009, base_m, g, bw=0.002)
    BX(x0 + 0.004, x1 - 0.004, y + 0.002, y + 0.012, z - 0.005, z + 0.005, P_["brass"], g, bw=0.001)
    pts = []
    n = int((x1 - x0) / 0.016)
    for i in range(n):
        x = x0 + 0.01 + i * (x1 - x0 - 0.02) / max(1, n - 1)
        screw_head(g, (x, y + 0.002, z), (0, -1, 0), r=0.0025)
        pts.append((x, y + 0.0005, z))
    text(g, label, ((x0 + x1) / 2, y + 0.009, z - 0.014), 0.008, P_["print_black"])
    return pts


def board():
    """a wall distribution board, door open: main switch, motor breaker Q1, lighting Q2, heater Q3,
    terminals X1 (motor) and X2 (heater, with a test link), N and PE bars"""
    # wall and floor
    BX(-1.2, 1.2, 0.0, 0.03, 0.0, 2.2, P_["wall"], "room", bw=0)
    BX(-1.2, 1.2, -1.6, 0.03, -0.02, 0.0, P_["floor"], "room", bw=0)
    # enclosure (600 x 800 x 200), RAL 7035
    X0, X1, Z0, Z1, D = -0.30, 0.30, 0.60, 1.40, 0.20
    t = 0.0015
    BX(X0, X1, -D + 0.0, -0.0, Z0, Z0 + t * 2, P_["ral7035"], "enclosure", bw=0.002)
    BX(X0, X1, -D, 0.0, Z1 - t * 2, Z1, P_["ral7035"], "enclosure", bw=0.002)
    BX(X0, X0 + t * 2, -D, 0.0, Z0, Z1, P_["ral7035"], "enclosure", bw=0.002)
    BX(X1 - t * 2, X1, -D, 0.0, Z0, Z1, P_["ral7035"], "enclosure", bw=0.002)
    BX(X0, X1, -0.004, 0.0, Z0, Z1, P_["ral7035"], "enclosure", bw=0.002)
    # front frame lip
    for (a0, a1, b0, b1) in ((X0, X1, Z0, Z0 + 0.02), (X0, X1, Z1 - 0.02, Z1), (X0, X0 + 0.02, Z0, Z1), (X1 - 0.02, X1, Z0, Z1)):
        BX(a0, a1, -D, -D + 0.004, b0, b1, P_["ral7035"], "enclosure", bw=0.001)
    # mounting plate
    BX(X0 + 0.02, X1 - 0.02, -0.03, -0.006, Z0 + 0.02, Z1 - 0.02, P_["galv"], "enclosure", bw=0.002)
    PY = -0.03  # plate front
    # the door, hinged on the right, open 100 degrees
    door = "door"
    # (door local: x from the hinge, -y = its inner face)
    BX(0.0, 0.6, 0.0, 0.02, 0.0, 0.8, P_["ral7035"], door, bw=0.004)
    for (a0, a1, b0, b1) in ((0.02, 0.58, 0.02, 0.03), (0.02, 0.58, 0.77, 0.78), (0.02, 0.03, 0.02, 0.78), (0.57, 0.58, 0.02, 0.78)):
        BX(a0, a1, -0.004, 0.0, b0, b1, P_["rubber"], door, bw=0.001)     # gasket
    BX(0.12, 0.48, -0.0025, -0.0015, 0.45, 0.70, P_["print_white"], door, bw=0)  # circuit chart
    for i in range(6):
        BX(0.14, 0.46, -0.003, -0.0026, 0.66 - i * 0.03, 0.665 - i * 0.03, P_["print_black"], door, bw=0)
    BX(0.565, 0.59, 0.02, 0.04, 0.37, 0.43, P_["case_black"], door, bw=0.004)  # lock
    made_door = None
    # DIN rail 1 (z = 1.20) devices
    RY = PY - 0.035                              # device fronts
    rz = 1.20
    BX(X0 + 0.04, X1 - 0.04, PY - 0.0075, PY, rz - 0.0175, rz + 0.0175, P_["galv"], "rails", bw=0.0005)
    pts = {}
    p = mcb("main", -0.245, 4, rz, RY, "MAIN 63A", P_["lever_red"], "tog_main")
    for (x, y, z, side, i) in p:
        if side == "top":
            pts["IN_" + ["L1", "L2", "L3", "N"][i]] = (x, y, z)
        else:
            pts["MAIN_" + ["L1", "L2", "L3", "N"][i]] = (x, y, z)
    p = mcb("devices", -0.150, 3, rz, RY, "Q1 C16", P_["lever_blue"], "tog_Q1")
    for (x, y, z, side, i) in p:
        pts[("Q1IN_" if side == "top" else "Q1_") + ["L1", "L2", "L3"][i]] = (x, y, z)
    p = mcb("devices", -0.080, 1, rz, RY, "Q2 B10", P_["lever_blue"], "tog_Q2")
    for (x, y, z, side, i) in p:
        pts[("Q2IN" if side == "top" else "Q2_L")] = (x, y, z)
    p = mcb("devices", -0.054, 1, rz, RY, "Q3 B20", P_["lever_blue"], "tog_Q3")
    for (x, y, z, side, i) in p:
        pts[("Q3IN" if side == "top" else "Q3_L")] = (x, y, z)
    # ---- wiring, the professional way: short stubs into slotted ducts
    cols = [P_["w_brown"], P_["w_black"], P_["w_grey"], P_["w_blue"]]
    DY = PY - 0.04                               # duct front

    def duct(x0, x1, z0, z1, vertical=False):
        BX(x0, x1, DY, PY, z0, z1, P_["term_grey"], "duct", bw=0.002)
        BX(x0 - 0.001, x1 + 0.001, DY - 0.003, DY, z0 - 0.001, z1 + 0.001, P_["term_grey"], "duct", bw=0.0015)  # cover
        if vertical:
            n = int((z1 - z0) / 0.02)
            for i in range(n):
                z = z0 + 0.008 + i * 0.02
                for x in (x0 - 0.0005, x1 - 0.0005):
                    BX(x, x + 0.001, DY + 0.004, PY - 0.004, z, z + 0.004, P_["case_grey"], "duct", bw=0)
        else:
            n = int((x1 - x0) / 0.02)
            for i in range(n):
                x = x0 + 0.008 + i * 0.02
                for z in (z0 - 0.0005, z1 - 0.0005):
                    BX(x, x + 0.004, DY + 0.004, PY - 0.004, z, z + 0.001, P_["case_grey"], "duct", bw=0)

    duct(-0.27, 0.27, 1.285, 1.325)                       # top duct
    duct(-0.27, 0.27, 1.08, 1.12)                         # middle duct
    duct(-0.27, 0.27, 0.735, 0.775)                       # bottom duct
    duct(-0.27, -0.24, 0.775, 1.08, vertical=True)        # left riser
    duct(-0.27, -0.24, 1.12, 1.285, vertical=True)

    def stub(p, z_duct, m, r=0.0026, dx=0.0):
        """from a screw straight into a duct above / below it"""
        x, y, z = p
        up = z_duct > z
        wire("cables", [(x, y, z), (x, y - 0.006, z + (0.006 if up else -0.006)), (x + dx, DY + 0.012, z_duct + (-0.012 if up else 0.012)), (x + dx, DY + 0.016, z_duct)], r, m)

    # incoming 5-core cable into the top gland
    gx = -0.20
    wire("cables", [(gx, -0.10, 1.75), (gx, -0.10, 1.40)], 0.012, P_["sheath"])
    C(0.016, (gx, -0.10, 1.40), (gx, -0.10, 1.43), P_["case_black"], "cables", verts=6)
    for i, m in enumerate(cols + [P_["w_gy"]]):
        x = gx + (i - 2) * 0.006
        wire("cables", [(x, -0.10, 1.40), (x, -0.09, 1.36), (x, DY + 0.012, 1.335), (x, DY + 0.016, 1.325)], 0.0028, m)
    for i, k in enumerate(["L1", "L2", "L3", "N"]):
        stub(pts["IN_" + k], 1.285, cols[i], 0.0028)
        stub(pts["MAIN_" + k], 1.12, cols[i], 0.0028)
    # comb busbar across Q1..Q3 tops, fed from the top duct
    BX(-0.150, -0.036, RY + 0.003, RY + 0.012, rz + 0.031, rz + 0.042, P_["term_grey"], "devices", bw=0.001)
    for i, k in enumerate(["L1", "L2", "L3"]):
        stub(pts["Q1IN_" + k], 1.285, cols[i])
    for k, i in (("Q1_L1", 0), ("Q1_L2", 1), ("Q1_L3", 2), ("Q2_L", 0), ("Q3_L", 0)):
        stub(pts[k], 1.12, cols[i])
    # N and PE bars (bottom)
    nb = busbar("nbar", -0.235, -0.165, 0.69, PY - 0.03, P_["term_blue"], "N")
    pb = busbar("pebar", 0.165, 0.245, 0.69, PY - 0.03, P_["term_gy"], "PE")
    pts["N"] = nb[1]
    pts["PE"] = pb[1]
    stub(nb[0], 0.735, P_["w_blue"], 0.0028)
    stub(nb[-1], 0.735, P_["w_blue"])
    stub(pb[0], 0.735, P_["w_gy"], 0.003)
    stub(pb[-1], 0.735, P_["w_gy"])
    # DIN rail 2 (z = 0.85): X1 motor terminals, X2 heater terminals with a test link
    tz = 0.85
    BX(X0 + 0.04, X1 - 0.04, PY - 0.0075, PY, tz - 0.0175, tz + 0.0175, P_["galv"], "rails", bw=0.0005)
    tx = {}
    xs = [-0.16, -0.1535, -0.147, -0.1405]
    for x, lab, m in zip(xs, ["1", "2", "3", "PE"], [P_["term_grey"]] * 3 + [P_["term_gy"]]):
        top, bot = terminal("terminals", x, tz, PY - 0.045, m, lab)
        tx["X1_" + {"1": "L1", "2": "L2", "3": "L3", "PE": "PE"}[lab]] = (top, bot)
    text("terminals", "X1", (-0.15, PY - 0.046, tz + 0.045), 0.009, P_["print_black"])
    xs2 = [0.02, 0.035, 0.05]
    for x, lab, m in zip(xs2, ["L", "L'", "N"], [P_["term_grey"], P_["term_grey"], P_["term_blue"]]):
        top, bot = terminal("terminals", x, tz, PY - 0.045, m, lab)
        tx["X2_" + {"L": "L", "L'": "Lo", "N": "N"}[lab]] = (top, bot)
    text("terminals", "X2", (0.035, PY - 0.046, tz + 0.045), 0.009, P_["print_black"])
    # end plates and end stops
    for x in (-0.168, -0.1355, 0.012, 0.055):
        BX(x, x + 0.0025, PY - 0.045, PY - 0.006, tz - 0.03, tz + 0.03, P_["case_grey"], "terminals", bw=0.0005)
    # the X2 test link (a node: the page hides it when the wattmeter current coil goes in)
    BX(0.017, 0.038, PY - 0.0545, PY - 0.0505, tz - 0.003, tz + 0.003, P_["brass"], "link_X2", bw=0.0005)
    for x in (0.02, 0.035):
        screw_head("link_X2", (x, PY - 0.0545, tz), (0, -1, 0), r=0.0018)
    # middle duct -> X1, fanned out so a clamp fits round each wire
    fan = [-0.215, -0.135, -0.055]
    for i, k in enumerate(["L1", "L2", "L3"]):
        tt = tx["X1_" + k][0]
        fx = fan[i]
        wire("cables", [(fx, DY + 0.016, 1.08), (fx, DY + 0.006, 1.065), (fx, DY - 0.01, 1.03), (fx, DY - 0.01, 0.97), (fx * 0.5 + tt[0] * 0.5, DY - 0.006, 0.925), (tt[0], tt[1] - 0.012, tt[2] + 0.016), (tt[0], tt[1] - 0.003, tt[2] + 0.005), tt], 0.0026, cols[i])
        point("clamp_" + k, (fx, DY - 0.01, 1.0), (0, 0, 1), xdir=(0, -1, -0.25))
    tt = tx["X1_PE"][0]
    wire("cables", [(-0.25, DY + 0.016, 1.08), (-0.25, DY + 0.006, 1.06), (-0.19, DY - 0.004, 0.93), (tt[0], tt[1] - 0.012, tt[2] + 0.016), tt], 0.0026, P_["w_gy"])
    # middle duct -> X2 L (heater feed from Q3, clamp-able) and X2 N
    tt = tx["X2_L"][0]
    wire("cables", [(0.07, DY + 0.016, 1.08), (0.07, DY + 0.006, 1.065), (0.07, DY - 0.01, 1.03), (0.07, DY - 0.01, 0.97), (tt[0], tt[1] - 0.012, tt[2] + 0.016), (tt[0], tt[1] - 0.003, tt[2] + 0.005), tt], 0.0026, P_["w_brown"])
    point("clamp_Q3", (0.07, DY - 0.01, 1.0), (0, 0, 1), xdir=(0, -1, -0.25))
    tt = tx["X2_N"][0]
    wire("cables", [(0.12, DY + 0.016, 1.08), (0.12, DY + 0.006, 1.065), (0.11, DY - 0.004, 0.96), (tt[0], tt[1] - 0.012, tt[2] + 0.016), (tt[0], tt[1] - 0.003, tt[2] + 0.005), tt], 0.0026, P_["w_blue"])
    # terminal bottoms into the bottom duct
    for k, m in (("X1_L1", cols[0]), ("X1_L2", cols[1]), ("X1_L3", cols[2]), ("X1_PE", P_["w_gy"]), ("X2_L", P_["w_brown"]), ("X2_Lo", P_["w_brown"]), ("X2_N", P_["w_blue"])):
        if k == "X2_L":
            continue
        stub(tx[k][1], 0.775, m)
    # outgoing cables from the bottom duct through the bottom glands: motor (4 core) and heater (3 core)
    for sx, ms, rr in ((-0.12, cols[:3] + [P_["w_gy"]], 0.011), (0.06, [P_["w_brown"], P_["w_blue"], P_["w_gy"]], 0.008)):
        for i, m in enumerate(ms):
            x = sx + (i - (len(ms) - 1) / 2) * 0.006
            wire("cables", [(x, DY + 0.016, 0.735), (x, DY + 0.008, 0.70), (x, -0.10, 0.63), (x, -0.10, 0.60)], 0.0026, m)
        C(rr + 0.004, (sx, -0.10, 0.605), (sx, -0.10, 0.575), P_["case_black"], "cables", verts=6)
    sx = -0.12
    wire("cables", [(sx, -0.10, 0.60), (sx, -0.10, 0.30), (sx + 0.05, -0.06, 0.05), (sx + 0.4, -0.04, 0.0)], 0.011, P_["sheath"])
    point("clamp_CABLE", (sx, -0.10, 0.45), (0, 0, 1), xdir=(0, -1, -0.2))
    wire("cables", [(0.06, -0.10, 0.60), (0.06, -0.10, 0.30), (0.16, -0.05, 0.05), (0.6, -0.04, 0.0)], 0.008, P_["sheath"])
    # labels on the plate
    text("enclosure", "DB-1   400/230V  50Hz", (0.16, PY - 0.0005, 1.33), 0.016, P_["print_black"])
    # a small trolley at the left for the bigger instruments
    tx0, tx1, ty0, ty1, th = -0.78, -0.40, -0.62, -0.30, 0.62
    BX(tx0, tx1, ty0, ty1, th - 0.025, th, P_["wood"], "trolley", bw=0.003)
    BX(tx0 + 0.02, tx1 - 0.02, ty0 + 0.02, ty1 - 0.02, 0.15, 0.17, P_["case_grey"], "trolley", bw=0.003)
    for x in (tx0 + 0.02, tx1 - 0.02):
        for y in (ty0 + 0.02, ty1 - 0.02):
            C(0.012, (x, y, 0.05), (x, y, th - 0.025), P_["steel"], "trolley", verts=16)
            SPH(0.03, (x, y, 0.03), P_["rubber"], "trolley")
    # test points: every probe comes in from the front (-Y), a little from below
    out = (0, -1, 0.15)
    for k in ["IN_L1", "IN_L2", "IN_L3", "IN_N", "Q1_L1", "Q1_L2", "Q1_L3", "Q2_L", "Q3_L"]:
        point("pt_" + k, pts[k], out)
    point("pt_N", pts["N"], out)
    point("pt_PE", pts["PE"], out)
    for k, (top, bot) in tx.items():
        point("pt_" + k, top, out)
    made = finish_nodes({"tog_main": (-0.209, RY - 0.005, rz), "tog_Q1": (-0.123, RY - 0.005, rz), "tog_Q2": (-0.071, RY - 0.005, rz),
                         "tog_Q3": (-0.045, RY - 0.005, rz), "door": (0.0, 0.0, 0.0), "link_X2": (0.0275, PY - 0.05, tz)})
    d = made["door"]
    d.location = (X1, -D, Z0)
    d.rotation_euler = (0, 0, math.radians(280))
    # where the instruments rest
    pose("mount_meter", (0.345, -0.497, 0.98), (0, 0, -80))   # hanging inside the open door (magnetic strap)
    pose("mount_clamp", (-0.62, -0.40, th + 0.018), (90, 0, 30))
    pose("mount_box", (-0.60, -0.46, th), (0, 0, 25))
    # camera presets: target + camera position
    for k, tgt, cam in (("all", (-0.08, -0.15, 1.0), (-0.65, -1.95, 1.35)),
                        ("top", (-0.15, -0.08, 1.20), (-0.25, -0.72, 1.32)),
                        ("terminals", (-0.05, -0.08, 0.88), (-0.12, -0.70, 1.0)),
                        ("cable", (-0.15, -0.10, 0.55), (-0.45, -0.75, 0.75))):
        point("view_" + k, tgt)
        point("cam_" + k, cam)


def motor():
    """a 4 kW three-phase motor on its base, terminal box open, with a local isolator"""
    BX(-1.4, 1.4, -1.6, 1.0, -0.02, 0.0, P_["floor"], "room", bw=0)
    BX(-1.4, 1.4, 0.98, 1.0, 0.0, 2.0, P_["wall"], "room", bw=0)
    # base frame (channel steel) on a plinth
    BX(-0.36, 0.42, -0.24, 0.24, 0.0, 0.08, P_["concrete"], "base", bw=0.006)
    for y in (-0.13, 0.13):
        BX(-0.32, 0.38, y - 0.03, y + 0.03, 0.08, 0.14, P_["yellow"], "base", bw=0.004)
    cz = 0.14 + 0.112   # shaft height 112 mm above the feet
    L, R = 0.36, 0.105
    x0 = -0.22
    g = "motor"
    C(R, (x0, 0, cz), (x0 + L, 0, cz), P_["motor_paint"], g, verts=64, bw=0.004)
    n = 28
    for k in range(n):
        a = 2 * math.pi * k / n
        if abs(math.sin(a) - 1) < 0.08 or abs(math.sin(a) + 1) < 0.3:
            continue
        dy, dz = math.cos(a), math.sin(a)
        BX(x0 + 0.02, x0 + L - 0.02, -0.002, 0.002, -0.014, 0.014, P_["motor_paint"], "fins", bw=0.001)
        o = G["fins"][-1]
        o.location = (o.location.x, dy * (R + 0.008), cz + dz * (R + 0.008))
        o.rotation_euler = (a - math.pi / 2, 0, 0)
    # feet
    for x in (x0 + 0.06, x0 + L - 0.06):
        BX(x - 0.03, x + 0.03, -0.12, 0.12, 0.14, 0.152, P_["motor_paint"], g, bw=0.003)
        BX(x - 0.02, x + 0.02, -0.07, 0.07, 0.15, cz - R + 0.02, P_["motor_paint"], g, bw=0.003)
        for y in (-0.1, 0.1):
            C(0.009, (x, y, 0.152), (x, y, 0.162), P_["steel"], g, verts=6)
    # end shields, shaft, fan cowl
    C(R * 0.98, (x0 + L, 0, cz), (x0 + L + 0.03, 0, cz), P_["motor_paint"], g, verts=64, bw=0.004)
    C(0.03, (x0 + L + 0.03, 0, cz), (x0 + L + 0.045, 0, cz), P_["iron"], g, verts=32)
    C(0.014, (x0 + L + 0.045, 0, cz), (x0 + L + 0.11, 0, cz), P_["chrome"], "shaft", verts=32, bw=0.001)
    BX(x0 + L + 0.06, x0 + L + 0.105, -0.004, 0.004, cz + 0.010, cz + 0.016, P_["steel"], "shaft", bw=0.0005)
    C(R * 0.98, (x0, 0, cz), (x0 - 0.02, 0, cz), P_["motor_paint"], g, verts=64, bw=0.004)
    C(R * 1.02, (x0 - 0.02, 0, cz), (x0 - 0.11, 0, cz), P_["case_black"], "cowl", verts=64, bw=0.004, r2=R * 0.96)
    for k in range(18):
        a = 2 * math.pi * k / 18
        BX(x0 - 0.1105, x0 - 0.110, -0.002, 0.002, 0.02, R * 0.9, P_["case_grey"], "cowl", bw=0)
        o = G["cowl"][-1]
        lib._sel(o)
        o.location = (0, 0, 0)
        bpy.ops.object.transform_apply(location=False)
        o.rotation_euler = (a, 0, 0)
        o.location = (0, 0, cz)
    # nameplate
    BX(x0 + 0.13, x0 + 0.23, -R - 0.012, -R - 0.009, cz - 0.03, cz + 0.02, P_["stainless"], g, bw=0.0005)
    text(g, "3~ MOT  4kW  400V Y / 230V Δ", (x0 + 0.18, -R - 0.0126, cz + 0.008), 0.0055, P_["print_black"])
    text(g, "8.2A / 14.2A  1450 rpm  cosφ 0.82", (x0 + 0.18, -R - 0.0126, cz - 0.004), 0.0052, P_["print_black"])
    text(g, "IP55  50Hz  INS. CL F", (x0 + 0.18, -R - 0.0126, cz - 0.016), 0.0052, P_["print_black"])
    # terminal box on top, open (lid on the floor beside)
    tbx, tby, tbz = x0 + 0.17, 0.0, cz + R - 0.01
    W, Dp, H = 0.13, 0.13, 0.075
    tb = BX(tbx - W / 2, tbx + W / 2, tby - Dp / 2, tby + Dp / 2, tbz, tbz + H, P_["motor_paint"], "tbox", bw=0.004)
    cutbox(tb, tbx - W / 2 + 0.006, tbx + W / 2 - 0.006, tby - Dp / 2 + 0.006, tby + Dp / 2 - 0.006, tbz + 0.012, tbz + H + 0.01)
    BX(0.30, 0.43, -0.55, -0.42, 0.0, 0.012, P_["motor_paint"], "lid", bw=0.003)
    # terminal board: two rows of three brass studs
    bz = tbz + 0.018
    BX(tbx - 0.05, tbx + 0.05, tby - 0.045, tby + 0.045, tbz + 0.012, bz, P_["case_black"], "tboard", bw=0.002)
    studs = {}
    rows = {"top": (tby + 0.022, ["W2", "U2", "V2"]), "bot": (tby - 0.022, ["U1", "V1", "W1"])}
    for row, (yy, names) in rows.items():
        for i, nm in enumerate(names):
            xx = tbx - 0.032 + i * 0.032
            C(0.0042, (xx, yy, bz), (xx, yy, bz + 0.022), P_["brass"], "tboard", verts=24, bw=0.0004)
            C(0.0065, (xx, yy, bz + 0.010), (xx, yy, bz + 0.014), P_["brass"], "tboard", verts=6, bw=0.0004)  # nut
            studs[nm] = (xx, yy, bz + 0.022)
            text("tboard", nm, (xx, yy + (-0.012 if row == "bot" else 0.012), bz + 0.0004), 0.006, P_["print_white"], rot=(0, 0, 0))
    # star links (one bar over W2-U2-V2) and delta links (three bars U1-W2, V1-U2, W1-V2)
    for nm in ("W2", "U2", "V2"):
        pass
    a, b = studs["W2"], studs["V2"]
    BX(a[0] - 0.006, b[0] + 0.006, a[1] - 0.005, a[1] + 0.005, bz + 0.014, bz + 0.0165, P_["copper"], "links_star", bw=0.0006)
    for lo, hi in (("U1", "W2"), ("V1", "U2"), ("W1", "V2")):
        p, q = studs[lo], studs[hi]
        BX(p[0] - 0.005, p[0] + 0.005, p[1] - 0.005, q[1] + 0.005, bz + 0.0165, bz + 0.019, P_["copper"], "links_delta", bw=0.0006)
    # supply cable into the gland on the box's front side, cores to U1 V1 W1 and PE stud
    gl = (tbx, tby - Dp / 2, tbz + 0.035)
    C(0.012, (gl[0], gl[1] - 0.02, gl[2]), (gl[0], gl[1] + 0.003, gl[2]), P_["case_black"], "tbox", verts=6, bw=0.001)
    iso = (-0.75, 0.6, 1.1)
    wire("cable", [(gl[0], gl[1] - 0.02, gl[2]), (gl[0], gl[1] - 0.1, gl[2] - 0.02), (gl[0] - 0.1, -0.35, 0.03), (-0.6, -0.1, 0.02), (-0.75, 0.55, 0.02), (-0.75, 0.62, 0.3), (iso[0], iso[1] + 0.02, iso[2] - 0.12)], 0.0095, P_["sheath"])
    pe_stud = (tbx + 0.05 - 0.004, tby - 0.040, bz + 0.004)
    C(0.0035, (pe_stud[0], pe_stud[1], tbz + 0.012), (pe_stud[0], pe_stud[1], bz + 0.014), P_["brass"], "tboard", verts=16)
    text("tboard", "⏚", (pe_stud[0] - 0.008, pe_stud[1], bz + 0.0004), 0.007, P_["print_white"], rot=(0, 0, 0))
    studs["PE"] = (pe_stud[0], pe_stud[1], bz + 0.014)
    cores = [("U1", P_["w_brown"]), ("V1", P_["w_black"]), ("W1", P_["w_grey"]), ("PE", P_["w_gy"])]
    for i, (nm, m) in enumerate(cores):
        s = studs[nm]
        ring = (s[0], s[1], s[2] - 0.009 if nm != "PE" else s[2] - 0.004)
        wire("tboard", [(gl[0] + (i - 1.5) * 0.004, gl[1] + 0.004, gl[2]), (gl[0] + (i - 1.5) * 0.006, gl[1] + 0.015, gl[2] - 0.005), (ring[0], ring[1] - 0.012, ring[2] + 0.004), ring], 0.0022, m)
        C(0.0058, (ring[0], ring[1], ring[2] - 0.0008), (ring[0], ring[1], ring[2] + 0.0008), P_["copper"], "tboard", verts=24, bw=0)
    # local isolator on the wall
    BX(iso[0] - 0.07, iso[0] + 0.07, iso[1] + 0.3, iso[1] + 0.38, iso[2] - 0.11, iso[2] + 0.11, P_["case_grey"], "isolator", bw=0.01)
    BX(iso[0] - 0.06, iso[0] + 0.06, iso[1] - 0.0, iso[1] + 0.3, iso[2] - 0.1, iso[2] + 0.1, P_["meg_yellow"], "isolator", bw=0.01)
    C(0.03, (iso[0], iso[1], iso[2]), (iso[0], iso[1] - 0.012, iso[2]), P_["meg_yellow"], "isolator", verts=48)
    text("isolator", "0   OFF", (iso[0] - 0.04, iso[1] - 0.0005, iso[2] + 0.06), 0.012, P_["print_black"])
    text("isolator", "I  ON", (iso[0] + 0.045, iso[1] - 0.0005, iso[2] + 0.06), 0.012, P_["print_black"])
    text("isolator", "Q0  M1", (iso[0], iso[1] - 0.0005, iso[2] - 0.08), 0.012, P_["print_black"])
    BX(iso[0] - 0.008, iso[0] + 0.008, iso[1] - 0.04, iso[1] - 0.01, iso[2] - 0.05, iso[2] + 0.05, P_["red"], "tog_iso", bw=0.004)
    C(0.022, (iso[0], iso[1] - 0.012, iso[2]), (iso[0], iso[1] - 0.03, iso[2]), P_["red"], "tog_iso", verts=48, bw=0.003)
    wire("cable", [(iso[0], iso[1] + 0.34, iso[2] + 0.11), (iso[0], iso[1] + 0.34, 2.0)], 0.0095, P_["sheath"])
    # a wooden crate as a bench beside the motor
    BX(-0.82, -0.45, -0.55, -0.25, 0.0, 0.40, P_["wood"], "crate", bw=0.006)
    for z in (0.1, 0.2, 0.3):
        BX(-0.822, -0.448, -0.552, -0.248, z, z + 0.004, P_["cardboard"], "crate", bw=0)
    out = (0, -0.6, 1)
    for nm in ("U1", "V1", "W1", "U2", "V2", "W2", "PE"):
        point("pt_" + nm, studs[nm], out)
    point("pt_BODY", (x0 + 0.06 + 0.03, -0.12, 0.152), (0, -0.7, 1))
    made = finish_nodes({"tog_iso": (iso[0], iso[1] - 0.012, iso[2]), "links_star": (tbx, 0, bz + 0.015), "links_delta": (tbx, 0, bz + 0.018), "shaft": (0, 0, cz)})
    pose("mount_meter", (-0.62, -0.42, 0.40), (-62, 0, 20))
    pose("mount_clamp", (-0.55, -0.32, 0.418), (90, 0, 30))
    pose("mount_box", (-0.64, -0.40, 0.40), (0, 0, 20))
    for k, tgt, cam in (("all", (-0.12, -0.12, 0.35), (-0.55, -1.75, 1.15)),
                        ("tbox", (tbx, 0.0, tbz + 0.04), (tbx - 0.12, -0.34, tbz + 0.32)),
                        ("iso", iso, (iso[0] + 0.25, iso[1] - 0.9, iso[2] + 0.1))):
        point("view_" + k, tgt)
        point("cam_" + k, cam)


MODELS = dict(avo=avo, dmm=dmm, clamp=clamp, megger=megger, watt=watt, leads=leads, board=board, motor=motor)


def render_preview(key):
    """a quick Cycles look at the model (out/inst_<key>.png)"""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    big = key in ("board", "motor")
    c = (lo + hi) / 2
    size = (hi - lo).length
    if big:
        v = os.environ.get("VIEW", "all")
        tgt = bpy.data.objects.get("view_" + v)
        cam = bpy.data.objects.get("cam_" + v)
        c = tgt.location
        dist = (cam.location - tgt.location).length
        el = math.degrees(math.asin((cam.location.z - tgt.location.z) / dist))
        az = math.degrees(math.atan2(-(cam.location.x - c.x), -(cam.location.y - c.y)))
        lib.studio(target=tuple(c), dist=dist, elev=el, azim=az, lens_mm=32, res=(900, 700), samples=24, key=2.0)
    else:
        lib.studio(target=tuple(c), dist=size * 2.6, elev=12, azim=-22, lens_mm=60, res=(700, 800), samples=24)
    bpy.context.scene.render.compositor_device = "CPU"
    lib.render("inst_" + key + ("_" + os.environ["VIEW"] if big and os.environ.get("VIEW") else ""))


def _studio_bg(res, target, dist, elev, azim, lens, transparent):
    lib.studio(target=target, dist=dist, elev=elev, azim=azim, lens_mm=lens, res=res, samples=48, key=2.4,
               bg=(0.035, 0.04, 0.05))
    S = bpy.context.scene
    S.render.film_transparent = transparent
    S.render.compositor_device = "CPU"


def cards(only_all=False):
    """card images for the app: each instrument alone (transparent) and all five together"""
    global P_
    out = []
    for k in () if only_all else ("avo", "dmm", "clamp", "megger", "watt"):
        lib.reset()
        G.clear()
        P_ = mats()
        mc.P_ = P_
        MODELS[k]()
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for o in objs:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        c = (lo + hi) / 2
        size = (hi - lo).length
        _studio_bg((640, 640), tuple(c), size * 2.5, 14, -24, 60, True)
        lib.render("card_" + k)
        out.append("card_" + k)
    # all five on a dark bench
    lib.reset()
    G.clear()
    P_ = mats()
    mc.P_ = P_
    place = {"watt": ((-0.17, 0.12, 0.0), 12), "megger": ((0.15, 0.10, 0.0), -14), "avo": ((-0.10, -0.12, 0.0), 8),
             "dmm": ((0.06, -0.15, 0.0), -6), "clamp": ((0.20, -0.12, 0.0), -18)}
    for k, (off, rz) in place.items():
        before = set(bpy.context.scene.objects)
        G.clear()
        MODELS[k]()
        new = [o for o in bpy.context.scene.objects if o not in before and o.parent is None]
        bpy.ops.object.empty_add(location=(0, 0, 0))
        holder = bpy.context.object
        holder.name = "_hold_" + k
        for o in new:
            mc.parent(o, holder)
        holder.location = off
        holder.rotation_euler = (0, 0, math.radians(rz))
    G.clear()
    BX(-1, 1, -1, 1, -0.01, 0.0, P_["case_black"], "_floor", bw=0)
    mc.nodes({})
    _studio_bg((720, 880), (0.02, -0.02, 0.09), 0.95, 22, -8, 50, False)
    lib.render("card_all")
    return out


def publish_cards():
    """out/card_*.png -> app/assets/images/instruments/<key>.webp and app/assets/images/cards/meters.webp"""
    from PIL import Image
    app = os.path.join(HERE, "..", "app", "assets", "images")
    os.makedirs(os.path.join(app, "instruments"), exist_ok=True)
    for k in ("avo", "dmm", "clamp", "megger", "watt"):
        im = Image.open(os.path.join(lib.OUT, "card_%s.png" % k)).convert("RGBA")
        x0, y0, x1, y1 = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        pad = 18
        im = im.crop((max(0, x0 - pad), max(0, y0 - pad), min(im.width, x1 + pad), min(im.height, y1 + pad)))
        im.thumbnail((480, 480))
        im.save(os.path.join(app, "instruments", k + ".webp"), quality=86, method=6)
    im = Image.open(os.path.join(lib.OUT, "card_all.png")).convert("RGB")
    im.save(os.path.join(app, "cards", "meters.webp"), quality=84, method=6)


def main(keys, do_render):
    global P_
    FACES.update(faces.all_faces())
    for k in keys:
        lib.reset()
        G.clear()
        P_ = mats()
        mc.P_ = P_
        MODELS[k]()
        lib.export("inst_" + k)
        print("inst_%s.glb" % k)
        if do_render:
            render_preview(k)


P_ = None
if __name__ == "__main__":
    if "--cards" in sys.argv:
        FACES.update(faces.all_faces())
        cards(only_all="--all" in sys.argv)
        publish_cards()
    else:
        args = [a for a in sys.argv[1:] if a in MODELS] or list(MODELS)
        main(args, "--render" in sys.argv)
