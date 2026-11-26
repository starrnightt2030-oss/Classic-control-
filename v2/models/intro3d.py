"""The app's 3D intro, on the timeline of assets/audio/sfx/intro_theme.mp3
(IntroTimes in lib/ui/intro_page.dart): a control panel in the dark, a close look at
the green start button; at 1.9 s it is pressed and its lamp lights, at 2.1 s the
contactor pulls in and current glows along the cables, the motor runs up while the
camera pulls back over the whole panel, and at 3.7 s a flash (the hit) hands over to
the logo, which the app draws over the last frame.

Built from the same component models as the rest of the app (v2/assets/models).

    python3.13 intro3d.py [--res 960] [--samples 16] [--frames 1-96]
    -> v2/models/out/intro3d/f_0001.png …, then tool/intro_frames.py packs them
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
OUT = os.path.join(HERE, "out", "intro3d") + os.sep
os.makedirs(OUT, exist_ok=True)

args = sys.argv[1:]
RES = int(args[args.index("--res") + 1]) if "--res" in args else 960
SAMPLES = int(args[args.index("--samples") + 1]) if "--samples" in args else 16
FR = args[args.index("--frames") + 1] if "--frames" in args else "1-96"
F0, F1 = (int(v) for v in FR.split("-"))

FPS = 24
T_PRESS, T_PULL, T_HIT = 1.9, 2.1, 3.7
f_press, f_pull, f_hit = round(T_PRESS * FPS) + 1, round(T_PULL * FPS) + 1, round(T_HIT * FPS) + 1
N = 96

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


def find(objs, name):
    for o in objs:
        if o.name == name or o.name.startswith(name + "."):
            return o
    return None


def place(root, objs, x=None, y=None, z=None):
    """move so the part's left edge / back face / vertical centre land on x, y, z"""
    mn, mx = bbox(objs)
    d = Vector((0, 0, 0))
    if x is not None:
        d.x = x - mn.x
    if y is not None:
        d.y = y - mx.y
    if z is not None:
        d.z = z - (mn.z + mx.z) / 2
    root.location += d
    bpy.context.view_layer.update()
    return bbox(objs)


# ---------------- the panel: rail with breaker, contactor, relay, timer ----------------
row = ["mcb_3p", "contactor", "relay_my4", "timer_din", "mcb_1p"]
parts = {}
x = 0.0
for name in row:
    root, objs = imp(name)
    mn, mx = place(root, objs, x=x, y=0.0, z=0.0)
    parts[name] = (root, objs)
    x = mx.x + 0.006
W = x
for name, (root, objs) in parts.items():
    root.location.x -= W / 2
bpy.context.view_layer.update()

rail_root, rail_objs = imp("din_rail")
rmn, rmx = bbox(rail_objs)
rail_root.scale = ((W + 0.12) / max(rmx.x - rmn.x, 1e-3), 1, 1)
bpy.context.view_layer.update()
rmn, rmx = bbox(rail_objs)
rail_root.location += Vector((-(rmn.x + rmx.x) / 2, 0.003 - rmn.y, -(rmn.z + rmx.z) / 2))

# overload under the contactor, a terminal strip and a wire duct
c_root, c_objs = parts["contactor"]
cmn, cmx = bbox(c_objs)
ol_root, ol_objs = imp("overload")
omn, omx = bbox(ol_objs)
ol_root.location += Vector(((cmn.x + cmx.x) / 2 - (omn.x + omx.x) / 2, cmx.y - omx.y - 0.004, cmn.z - omx.z + 0.006))
bpy.context.view_layer.update()
duct_root, duct_objs = imp("wire_duct")
dmn, dmx = bbox(duct_objs)
sx = (W + 0.12) / max(dmx.x - dmn.x, 1e-3)
duct_root.scale = (sx, 1, 1)
bpy.context.view_layer.update()
dmn, dmx = bbox(duct_objs)
duct_root.location += Vector((-(dmn.x + dmx.x) / 2, 0.0 - dmx.y, cmx.z + 0.03 - dmn.z))
bpy.context.view_layer.update()

plate_m = lib.mat("plate", (0.10, 0.11, 0.12), metal=0.6, rough=0.42)
bpy.ops.mesh.primitive_plane_add(size=1, location=(0.06, 0.006, -0.03), rotation=(math.pi / 2, 0, 0))
plate = bpy.context.object
plate.scale = (W + 0.6, 0.55, 1)
plate.data.materials.append(plate_m)

# ---------------- door devices: start (green), stop (red), run lamp, in front-left ----------------
door = {}
dx = -W / 2 - 0.12
for i, name in enumerate(["pb_green_metal", "pb_red_plastic", "lamp_green"]):
    root, objs = imp(name)
    root.rotation_euler.x = math.radians(90)  # modelled facing up: turn the face to the camera
    bpy.context.view_layer.update()
    mn, mx = bbox(objs)
    root.location += Vector((dx - (mn.x + mx.x) / 2, -0.11 - mn.y, 0.035 - i * 0.05 - (mn.z + mx.z) / 2))
    bpy.context.view_layer.update()
    door[name] = (root, objs)
door_m = lib.mat("door", (0.16, 0.17, 0.19), metal=0.3, rough=0.45)
gmn, gmx = bbox(door["pb_green_metal"][1])
bpy.ops.mesh.primitive_plane_add(size=1, location=(dx, -0.11 + (gmx.y - gmn.y) * 0.62, -0.015), rotation=(math.pi / 2, 0, 0))
dp = bpy.context.object
dp.scale = (0.11, 0.2, 1)
dp.data.materials.append(door_m)

# ---------------- motor on the right ----------------
m_root, m_objs = imp("motor")
mmn, mmx = bbox(m_objs)
m_root.location += Vector((0.05 - (mmn.x + mmx.x) / 2, -0.2 - (mmn.y + mmx.y) / 2, -0.17 - mmn.z - 0.12))
bpy.context.view_layer.update()
mmn, mmx = bbox(m_objs)
floor_m = lib.mat("floor", (0.03, 0.035, 0.045), metal=0.2, rough=0.6)
bpy.ops.mesh.primitive_plane_add(size=4, location=(0, -0.5, mmn.z))
floor = bpy.context.object
floor.data.materials.append(floor_m)

# ---------------- animation ----------------
# start button pressed and released
cap = find(door["pb_green_metal"][1], "cap")
if cap:
    p0 = cap.location.copy()
    # the cap moves along the button's axis (towards the plate, +Y in world)
    ax = cap.matrix_world.inverted().to_3x3() @ Vector((0, 1, 0))
    for f, k in ((f_press - 2, 0), (f_press, 1), (f_press + 5, 1), (f_press + 9, 0)):
        cap.location = p0 + ax.normalized() * 0.004 * k
        cap.keyframe_insert("location", frame=f)

# the run lamp lights with the contactor
lamp_objs = door["lamp_green"][1]
glow = lib.mat("run_glow", (0.2, 1.0, 0.45), emit=((0.25, 1.0, 0.45), 0.0))
lens_obj = max((o for o in lamp_objs if o.type == "MESH"), key=lambda o: o.matrix_world.translation.y * -1, default=None)
for o in lamp_objs:
    if o.type == "MESH" and any(m and ("lens" in m.name.lower() or "green" in m.name.lower()) for m in o.data.materials):
        lens_obj = o
if lens_obj is not None:
    lens_obj.data.materials.clear()
    lens_obj.data.materials.append(glow)
    em = glow.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
    for f, e in ((f_pull, 0.0), (f_pull + 2, 9.0), (f_pull + 6, 6.0)):
        em.default_value = e
        em.keyframe_insert("default_value", frame=f)

# contactor armature pulls in
arm = find(c_objs, "armature")
if arm:
    a0 = arm.location.copy()
    ax = arm.matrix_world.inverted().to_3x3() @ Vector((0, 1, 0))
    for f, k in ((f_pull - 1, 0), (f_pull + 1, 1)):
        arm.location = a0 + ax.normalized() * 0.003 * k
        arm.keyframe_insert("location", frame=f)
        for fc in (arm.animation_data.action.fcurves if hasattr(arm.animation_data.action, "fcurves") else []):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"

# motor shaft and fan run up. Both are imported turned 90° about Y, so their own axis
# is local Z: with Euler order ZXY the Z turn is applied first, about that axis.
sh = find(m_objs, "shaft")
if sh:
    # a keyway on the shaft end, so the turning can be seen
    bpy.ops.mesh.primitive_cube_add(size=1)
    key = bpy.context.object
    key.name = "shaft_key"
    key.scale = (0.0045, 0.007, 0.04)
    key.data.materials.append(lib.mat("key", (0.05, 0.05, 0.06), metal=0.8, rough=0.35))
    key.parent = sh
    key.matrix_parent_inverse.identity()
    key.location = (0.0115, 0, -0.118)
for nm in ("shaft", "fan"):
    o = find(m_objs, nm)
    if not o:
        continue
    o.rotation_mode = "ZXY"
    base = o.rotation_euler.z
    for f in range(f_pull, N + 1):
        t = (f - f_pull) / FPS
        # up to about 1.6 turns a second: fast enough to read as running, slow enough
        # that the frames don't strobe
        total = 6.0 * t * t if t < 0.85 else 6.0 * 0.7225 + 10.2 * (t - 0.85)
        o.rotation_euler.z = base + total
        o.keyframe_insert("rotation_euler", index=2, frame=f)
    if o.animation_data and o.animation_data.action and hasattr(o.animation_data.action, "fcurves"):
        for fc in o.animation_data.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"

# cables: breaker → contactor → overload, and on to the motor; current glows at the pull-in
b_objs = parts["mcb_3p"][1]


def term(objs, prefix):
    for o in objs:
        if o.type == "EMPTY" and o.name.startswith("TERM_" + prefix):
            return o.matrix_world.translation.copy()
    return None


cols = [(0.16, 0.07, 0.03), (0.02, 0.02, 0.025), (0.15, 0.16, 0.17)]
routes = []
for i, (bt, ct) in enumerate((("2", "1_L1"), ("4", "3_L2"), ("6", "5_L3"))):
    a, b = term(b_objs, bt), term(c_objs, ct)
    if a and b:
        routes.append((i, [a + Vector((0, -0.003, -0.002)), a + Vector((0, -0.02, -0.03)), b + Vector((0, -0.02, 0.04)), b + Vector((0, -0.003, 0.003))]))
mtop = Vector(((mmn.x + mmx.x) / 2, (mmn.y + mmx.y) / 2, mmx.z))
for i, ot in enumerate(("2_T1", "4_T2", "6_T3")):
    a = term(ol_objs, ot)
    if a:
        routes.append((i, [a + Vector((0, -0.003, -0.003)), a + Vector((0, -0.03, -0.06)), mtop + Vector((-0.08 + i * 0.012, -0.03, 0.12)), mtop + Vector((-0.02 + i * 0.012, 0, -0.005))]))
for k, (i, pts) in enumerate(routes):
    m = lib.mat(f"cable{k}", cols[i], rough=0.38)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (0.2, 0.85, 1.0, 1)
    em = bsdf.inputs["Emission Strength"]
    for f, e in ((f_pull, 0.0), (f_pull + 3 + k, 0.9), (f_pull + 14, 0.18), (f_hit - 2, 0.3), (f_hit, 2.0)):
        em.default_value = e
        em.keyframe_insert("default_value", frame=f)
    cu = bpy.data.curves.new(f"cable{k}", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.0019
    cu.bevel_resolution = 4
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for bp, co in zip(sp.bezier_points, pts):
        bp.co = co
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(f"cable{k}", cu)
    S.collection.objects.link(ob)
    ob.data.materials.append(m)

# ---------------- light, world, camera ----------------
w = bpy.data.worlds.new("w")
S.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.009, 0.022, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

bpy.ops.object.empty_add(location=(0, 0, 0))
tgt = bpy.context.object


def area(loc, energy, size, color):
    bpy.ops.object.light_add(type="AREA", location=loc)
    L = bpy.context.object
    L.data.energy = energy
    L.data.size = size
    L.data.color = color
    tr = L.constraints.new("TRACK_TO")
    tr.target = tgt
    return L


key = area((0.25, -0.45, 0.4), 14, 0.4, (1.0, 0.86, 0.66))      # warm key
fill = area((-0.5, -0.3, 0.05), 4, 0.5, (0.55, 0.72, 1.0))      # cool fill
rim = area((0.0, 0.3, 0.35), 8, 0.4, (0.25, 0.85, 1.0))         # cyan rim behind
for f, e in ((1, 8), (f_pull, 8), (f_pull + 4, 24), (f_hit - 6, 14), (f_hit, 60), (N, 30)):
    rim.data.energy = e
    rim.data.keyframe_insert("energy", frame=f)
for f, e in ((1, 9), (f_pull + 8, 14), (f_hit, 30), (N, 18)):
    key.data.energy = e
    key.data.keyframe_insert("energy", frame=f)

gb = bbox(door["pb_green_metal"][1])
g_c = (gb[0] + gb[1]) / 2
c_c = (cmn + cmx) / 2
wide_c = Vector((0.0, -0.08, -0.10))
bpy.ops.object.camera_add()
cam = bpy.context.object
S.camera = cam
cam.data.lens = 50
cam.data.sensor_width = 36
cam.constraints.new("TRACK_TO").target = tgt
shots = [
    (1, g_c + Vector((0.07, -0.16, 0.05)), g_c + Vector((0, 0, -0.005))),
    (f_press - 4, g_c + Vector((0.10, -0.20, 0.055)), g_c + Vector((0.02, 0, -0.01))),
    (f_pull + 10, c_c + Vector((-0.05, -0.30, 0.08)), c_c + Vector((-0.02, 0, -0.01))),
    (f_hit, wide_c + Vector((0.16, -0.78, 0.30)), wide_c),
    (N, wide_c + Vector((0.18, -0.86, 0.32)), wide_c),
]
for f, loc, t in shots:
    cam.location = loc
    cam.keyframe_insert("location", frame=f)
    tgt.location = t
    tgt.keyframe_insert("location", frame=f)
cam.data.dof.use_dof = True
cam.data.dof.focus_object = tgt
for f, st in ((1, 2.2), (f_press, 3.0), (f_pull + 10, 5.6), (f_hit, 9.0)):
    cam.data.dof.aperture_fstop = st
    cam.data.dof.keyframe_insert("aperture_fstop", frame=f)

# ---------------- render ----------------
S.render.engine = "CYCLES"
S.cycles.samples = SAMPLES
S.cycles.use_denoising = True
S.render.resolution_x = S.render.resolution_y = RES
S.view_settings.view_transform = "AgX"
S.view_settings.look = "AgX - Medium High Contrast"
S.render.image_settings.file_format = "PNG"
S.render.use_motion_blur = False

try:  # bloom for the glow and the flash
    ng = bpy.data.node_groups.new("intro_comp", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = ng.nodes.new("CompositorNodeRLayers")
    glare = ng.nodes.new("CompositorNodeGlare")
    out = ng.nodes.new("NodeGroupOutput")
    for k_, v_ in (("Type", "Fog Glow"), ("Glare Type", "Fog Glow"), ("Quality", "Medium"), ("Threshold", 0.8), ("Strength", 0.9)):
        if k_ in glare.inputs:
            try:
                glare.inputs[k_].default_value = v_
            except Exception:
                pass
    ng.links.new(rl.outputs["Image"], glare.inputs["Image"])
    ng.links.new(glare.outputs["Image"], out.inputs[0])
    S.compositing_node_group = ng
    if hasattr(S.render, "compositor_device"):
        S.render.compositor_device = "CPU"
except Exception as e:
    print("bloom off:", e)

for f in range(F0, F1 + 1):
    S.frame_set(f)
    S.render.filepath = OUT + f"f_{f:04d}.png"
    bpy.ops.render.render(write_still=True)
    print("FRAME", f, flush=True)
