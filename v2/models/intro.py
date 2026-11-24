"""Animated app intro (rendered to frames): cables grow into a contactor's
terminals, sparks at each connection, the circuit energises (cyan glow), the
camera pulls back. The logo/text are composited in the app over these frames.

    python intro.py [first_frame] [last_frame] [--res 720] [--samples 16]
    -> out/intro/f_0001.png ...
"""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lib  # noqa: E402

ASSETS = os.path.join(HERE, "..", "assets", "models") + os.sep
OUT = os.path.join(HERE, "out", "intro") + os.sep
os.makedirs(OUT, exist_ok=True)

args = [a for a in sys.argv[1:]]
RES = int(args[args.index("--res") + 1]) if "--res" in args else 720
SAMPLES = int(args[args.index("--samples") + 1]) if "--samples" in args else 16
nums = [int(a) for a in args if a.isdigit()]
F0, F1 = (nums + [1, 144])[:2] if len(nums) >= 2 else (1, 144)

FPS, N = 24, 144
lib.reset()
S = bpy.context.scene
S.render.fps = FPS
S.frame_start, S.frame_end = 1, N


def imp(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=ASSETS + name + ".glb")
    new = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new(name + "_root", None)
    S.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    bpy.context.view_layer.update()
    return root, new


def bbox(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


# ---------------- components on a rail ----------------
row = ["mcb_3p", "contactor", "mpcb", "relay_my4"]
groups = {}
x = 0.0
for name in row:
    root, objs = imp(name)
    mn, mx = bbox(objs)
    # back face on y=0, vertically centred on z=0, left edge at x
    root.location = Vector((x - mn.x, -mx.y, -(mn.z + mx.z) / 2))
    bpy.context.view_layer.update()
    mn, mx = bbox(objs)
    groups[name] = (root, objs, mn, mx)
    x = mx.x + 0.004
total_w = x
shift = -total_w / 2
for name, (root, objs, mn, mx) in groups.items():
    root.location.x += shift
bpy.context.view_layer.update()
for name in groups:
    root, objs, _, _ = groups[name]
    groups[name] = (root, objs) + bbox(objs)

rail_root, rail_objs = imp("din_rail")
rmn, rmx = bbox(rail_objs)
rail_root.scale = (max(1.0, (total_w + 0.06) / max(rmx.x - rmn.x, 1e-3)), 1, 1)
bpy.context.view_layer.update()
rmn, rmx = bbox(rail_objs)
rail_root.location += Vector((-(rmn.x + rmx.x) / 2, 0.002 - rmn.y, -(rmn.z + rmx.z) / 2))

# back plate (galvanised mounting plate look)
plate_m = lib.mat("plate", (0.05, 0.065, 0.085), metal=0.5, rough=0.55)
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.012, 0), rotation=(math.pi / 2, 0, 0))
plate = bpy.context.object
plate.scale = (1.4, 0.9, 1)
plate.data.materials.append(plate_m)

# ---------------- cables into the contactor's line terminals ----------------
cont_objs = groups["contactor"][1]
terms = {o.name.split("_")[1] + "_" + o.name.split("_")[2] if o.name.count("_") >= 2 else o.name: o
         for o in cont_objs if o.name.startswith("TERM_")}
bpy.context.view_layer.update()


def term_pos(prefix):
    for o in cont_objs:
        if o.name.startswith(prefix):
            return o.matrix_world.translation.copy()
    return None


cable_specs = [
    ("TERM_1_L1", (0.16, 0.07, 0.03), 8),    # brown
    ("TERM_3_L2", (0.03, 0.03, 0.035), 16),  # black
    ("TERM_5_L3", (0.16, 0.17, 0.18), 24),   # grey
]
cables = []
for i, (tname, col, start) in enumerate(cable_specs):
    p = term_pos(tname)
    if p is None:
        continue
    m = lib.mat(f"cable{i}", col, rough=0.38)
    m.node_tree.nodes.get("Principled BSDF").inputs["Emission Color"].default_value = (0.25, 0.85, 0.95, 1)
    em = m.node_tree.nodes.get("Principled BSDF").inputs["Emission Strength"]
    em.default_value = 0.0
    em.keyframe_insert("default_value", frame=62 + i * 3)
    em.default_value = 0.45
    em.keyframe_insert("default_value", frame=74 + i * 3)
    em.default_value = 0.18
    em.keyframe_insert("default_value", frame=96)

    cu = bpy.data.curves.new(f"cable{i}", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.0017
    cu.bevel_resolution = 4
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(2)
    top = p + Vector((0, -0.002, 0.004))
    pts = [Vector((p.x + (i - 1) * 0.03 - 0.05, -0.09, p.z + 0.16)), Vector((p.x - 0.01 + (i - 1) * 0.008, -0.03, p.z + 0.06)), top]
    for bp, co in zip(sp.bezier_points, pts):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(f"cable{i}", cu)
    S.collection.objects.link(ob)
    ob.data.materials.append(m)
    cu.bevel_factor_end = 0.0
    cu.keyframe_insert("bevel_factor_end", frame=start)
    cu.bevel_factor_end = 1.0
    cu.keyframe_insert("bevel_factor_end", frame=start + 26)
    # ferrule (copper sleeve) appears at the end
    cables.append((ob, p, start + 26))

# sparks at each connection
spark_m = lib.mat("spark", (1, 0.85, 0.5), emit=((1.0, 0.82, 0.45), 40))
for i, (ob, p, f_hit) in enumerate(cables):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.0018, subdivisions=2, location=p + Vector((0, -0.004, 0.006)))
    s = bpy.context.object
    s.data.materials.append(spark_m)
    for f, sc in ((f_hit - 1, 0.0), (f_hit, 1.6), (f_hit + 2, 0.6), (f_hit + 4, 1.0), (f_hit + 6, 0.0)):
        s.scale = (sc, sc, sc)
        s.keyframe_insert("scale", frame=f)
    bpy.ops.object.light_add(type="POINT", location=p + Vector((0, -0.01, 0.01)))
    L = bpy.context.object
    L.data.color = (1.0, 0.8, 0.45)
    L.data.shadow_soft_size = 0.002
    for f, e in ((f_hit - 1, 0), (f_hit, 0.9), (f_hit + 1, 0.25), (f_hit + 3, 0.6), (f_hit + 6, 0)):
        L.data.energy = e
        L.data.keyframe_insert("energy", frame=f)

# ---------------- lights / world / camera ----------------
w = bpy.data.worlds.new("w")
S.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.006, 0.012, 0.028, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0


def area(loc, energy, size, color):
    bpy.ops.object.light_add(type="AREA", location=loc)
    L = bpy.context.object
    L.data.energy = energy
    L.data.size = size
    L.data.color = color
    tr = L.constraints.new("TRACK_TO")
    tr.target = tgt
    return L


bpy.ops.object.empty_add(location=(0, 0, 0))
tgt = bpy.context.object
tgt.name = "cam_target"
area((0.25, -0.30, 0.32), 1.9, 0.30, (1.0, 0.86, 0.62))        # warm gold key
area((-0.35, -0.12, 0.05), 0.7, 0.35, (0.55, 0.75, 1.0))     # cool fill
rim = area((-0.10, 0.20, 0.30), 2.5, 0.20, (0.25, 0.85, 1.0))  # cyan rim
for f, e in ((60, 2.5), (78, 7), (110, 4)):
    rim.data.energy = e
    rim.data.keyframe_insert("energy", frame=f)

cont_mn, cont_mx = groups["contactor"][2], groups["contactor"][3]
c_top = Vector(((cont_mn.x + cont_mx.x) / 2, cont_mn.y, cont_mx.z - 0.01))
bpy.ops.object.camera_add()
cam = bpy.context.object
S.camera = cam
cam.data.lens = 50
cam.constraints.new("TRACK_TO").target = tgt
keys = [
    (1, c_top + Vector((0.035, -0.11, 0.07)), c_top + Vector((0, 0, -0.005))),
    (40, c_top + Vector((0.015, -0.13, 0.06)), c_top + Vector((0, 0, -0.012))),
    (84, Vector((0.05, -0.30, 0.10)), Vector((0, 0, 0.0))),
    (144, Vector((-0.07, -0.40, 0.06)), Vector((0, 0, -0.01))),
]
for f, loc, t in keys:
    cam.location = loc
    cam.keyframe_insert("location", frame=f)
    tgt.location = t
    tgt.keyframe_insert("location", frame=f)
cam.data.dof.use_dof = True
cam.data.dof.focus_object = tgt
cam.data.dof.aperture_fstop = 11

# ---------------- render ----------------
S.render.engine = "CYCLES"
S.cycles.samples = SAMPLES
S.cycles.use_denoising = True
S.render.resolution_x = S.render.resolution_y = RES
S.view_settings.view_transform = "AgX"
S.view_settings.look = "AgX - Medium High Contrast"
S.render.image_settings.file_format = "PNG"

# bloom for sparks / glowing cables (Blender 5 compositor node group)
try:
    ng = bpy.data.node_groups.new("intro_comp", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = ng.nodes.new("CompositorNodeRLayers")
    glare = ng.nodes.new("CompositorNodeGlare")
    out = ng.nodes.new("NodeGroupOutput")
    for key, val in (("Type", "Fog Glow"), ("Glare Type", "Fog Glow"), ("Quality", "Medium"), ("Threshold", 0.9), ("Strength", 0.8)):
        if key in glare.inputs:
            try:
                glare.inputs[key].default_value = val
            except Exception as e:
                print("glare", key, e)
    ng.links.new(rl.outputs["Image"], glare.inputs["Image"])
    ng.links.new(glare.outputs["Image"], out.inputs[0])
    S.compositing_node_group = ng
    print("bloom on", [i.name for i in glare.inputs])
except Exception as e:
    print("bloom off:", e)

for f in range(F0, F1 + 1):
    S.frame_set(f)
    S.render.filepath = OUT + f"f_{f:04d}.png"
    bpy.ops.render.render(write_still=True)
    print("FRAME", f, flush=True)
