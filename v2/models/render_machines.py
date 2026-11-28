"""Sprites of the machines for the Panel Lab, from the same Blender models as the 3D view.

Every machine GLB (v2/assets/models/machine_*.glb, made by machines.py) is rendered
from a fixed three-quarter view (orthographic, like the 3D page's starting view) in
layers: the still machine, and each moving part on its own (the cart, the hook, the
lift car with closed and open doors, the pusher, the ram, boxes and bottles). The lab
draws the still layer and moves the others by the machine's state, so the machine on
the bench looks like the Blender model and still runs with the circuit.

For each machine the JSON gives the image size, the 2×4 matrix that projects a
Blender world point (metres) to image pixels, each layer's crop offset, and the pixel
position of each lamp (sensor / valve indicators the lab lights up).

    python3.13 render_machines.py [cart hoist …]   (pip install bpy)
Output: v2/app/assets/panel/mach_<kind>_<layer>.webp + v2/app/assets/panel/machine_sprites.json
"""
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "assets", "models")
OUT = os.path.join(HERE, "..", "app", "assets", "panel")
TMP = "/tmp/machine_render"
WIDTH = 1100        # image width in pixels (height follows the machine)
SS = 2              # supersampling
SAMPLES = int(os.environ.get("SAMPLES", 24))

# moving parts by machine: layer → (objects shown, extra setup)
LAYERS = {
    "cart": {"cart": ["cart"]},
    "hoist": {"hook": ["hook"]},
    "lift": {"car": ["car"], "car_open": ["car"], "cw": ["cw"]},
    "sort": {"rod": ["rod"], "metal": ["proto_metal"], "plastic": ["proto_plastic"]},
    "press": {"ram": ["ram"], "part_raw": ["part_raw"], "part_pressed": ["part_pressed"]},
    "fill": {"bottle": ["proto_bottle"], "bottle_full": ["proto_bottle"], "stream": ["stream"]},
    "belt": {"box": ["proto_box"]},
    "fan": {"blades%d" % i: ["blades"] for i in range(6)},   # 0°, 15° … 75°
    "gate": {"leaf": ["leaf"]},
    "crusher": {"fly%d" % i: ["fly"] for i in range(6)},     # 0°, 10° … 50° (six spokes)
    "crane": {"bridge": ["bridge"], "trolley": ["trolley"], "hook": ["hook"]},
    "oven": {"glow": ["glow"], **{"fan%d" % i: ["fan"] for i in range(6)}},   # 0°, 15° … 75°
    "mixer": {"hook%d" % i: ["hook"] for i in range(6)},     # 0°, 30° … 150° (two arms)
    "tank2": {"water": ["water"]},
    "washer": {"wash": ["wash"], "rinse": ["rinse"], "air": ["air"]},
    "hpress": {"ram": ["ram"]},
    "line3": {"box": ["proto_box"]},
}
# layers that are one node turned: prefix → (node, axis, degrees per frame)
ROT = {"blades": ("blades", 1, 15), "fly": ("fly", 1, 10), "fan": ("fan", 2, 15), "hook": ("hook", 2, 30)}
# never in the still layer (moving, or drawn by the lab: ropes)
MOVING = {
    "cart": ["cart"],
    "hoist": ["hook", "rope"],
    "lift": ["car", "cw", "rope_car"],
    "sort": ["rod", "proto_metal", "proto_plastic"],
    "press": ["ram", "part_raw", "part_pressed"],
    "fill": ["proto_bottle", "stream"],
    "belt": ["proto_box"],
    "fan": ["blades"],
    "gate": ["leaf"],
    "crusher": ["fly"],
    "crane": ["bridge", "trolley", "hook"],
    "oven": ["glow", "fan"],
    "mixer": ["hook"],
    "tank2": ["water"],
    "washer": ["wash", "rinse", "air"],
    "hpress": ["ram"],
    "line3": ["proto_box"],
}


def tree(o):
    out = [o]
    for c in o.children:
        out += tree(c)
    return out


def world_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def light(S, loc, energy, size, target, kind="AREA"):
    d = bpy.data.lights.new("L", kind)
    d.energy = energy
    if kind == "AREA":
        d.size = size
    o = bpy.data.objects.new("L", d)
    S.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()


def materials(S):
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        if m.name.startswith("glass"):
            bsdf.inputs["Alpha"].default_value = 0.28
        if m.name.startswith("water"):
            bsdf.inputs["Alpha"].default_value = 0.8
    # lamp lenses dark (the lab lights them when on)
    for o in S.objects:
        if o.type == "MESH" and o.name.startswith("lamp_") and o.active_material:
            m = o.active_material.copy()
            o.active_material = m
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if m.use_nodes else None
            if bsdf is not None:
                c = bsdf.inputs["Base Color"].default_value
                bsdf.inputs["Base Color"].default_value = (c[0] * 0.25, c[1] * 0.25, c[2] * 0.25, 1)
                if "Emission Strength" in bsdf.inputs:
                    bsdf.inputs["Emission Strength"].default_value = 0


def render(S, png):
    S.render.filepath = png
    bpy.ops.render.render(write_still=True)


def webp(png, out, w, h, crop=True):
    """scale down, crop to the visible pixels; returns (x, y, w, h) in image pixels"""
    from PIL import Image
    im = Image.open(png).convert("RGBA").resize((w, h), Image.LANCZOS)
    box = im.getchannel("A").point(lambda a: 255 if a > 6 else 0).getbbox() if crop else (0, 0, w, h)
    if box is None:
        box = (0, 0, 1, 1)
    box = (max(0, box[0] - 2), max(0, box[1] - 2), min(w, box[2] + 2), min(h, box[3] + 2))
    im = im.crop(box)
    tmp = png[:-4] + "_c.png"
    im.save(tmp)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:v", "libwebp", "-lossless", "0", "-quality", "88",
                    "-pix_fmt", "yuva420p", out], check=True)
    return [box[0], box[1], box[2] - box[0], box[3] - box[1]]


def render_machine(kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, f"machine_{kind}.glb"))
    S = bpy.context.scene
    N = {o.name: o for o in S.objects}
    materials(S)
    protos = [n for n in N if n.startswith("proto_")]
    still_hidden = set()
    for n in MOVING[kind]:
        if n in N:
            still_hidden.update(o.name for o in tree(N[n]))
    everything = [o for o in S.objects if o.type == "MESH"]
    # the machine as the student first sees it (moving parts at rest, no protos)
    view = [o for o in everything if not any(o.name in [x.name for x in tree(N[p])] for p in protos)]
    lo, hi = world_bounds(view)
    if kind == "lift":  # the car travels the whole shaft
        lo.z = min(lo.z, 0)
    c = (lo + hi) / 2
    # camera: three.js start view dir (0.55, 0.5, 1) → Blender (0.55, −1, 0.5)
    d = Vector((0.55, -1.0, 0.5 if kind != "lift" else 0.25)).normalized()
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d)
    S.collection.objects.link(cam)
    r = (hi - lo).length
    cam.location = c + d * r * 3
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam_d.clip_end = r * 10
    S.camera = cam
    bpy.context.view_layer.update()
    # fit: project the bounding box corners on the camera plane
    M = cam.matrix_world.inverted()
    pts = [M @ Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    pad = 0.04 * max(x1 - x0, y1 - y0)
    x0, x1, y0, y1 = x0 - pad, x1 + pad, y0 - pad, y1 + pad
    # centre the camera on that box
    cam.location = cam.matrix_world @ Vector(((x0 + x1) / 2, (y0 + y1) / 2, 0))
    bpy.context.view_layer.update()
    wv, hv = x1 - x0, y1 - y0
    W = WIDTH
    H = round(W * hv / wv)
    if H > 1400:  # tall lift
        H = 1400
        W = round(H * wv / hv)
    cam_d.ortho_scale = max(wv, hv)
    S.render.resolution_x, S.render.resolution_y = W * SS, H * SS
    # projection world → image pixels (top-left origin)
    Mi = cam.matrix_world.inverted()
    k = W / wv
    A = []
    for row, sgn in ((0, 1), (1, -1)):
        coef = [Mi[row][j] * k * sgn for j in range(4)]
        coef[3] += W / 2 if row == 0 else H / 2
        A.append([round(v, 4) for v in coef])

    def px(p):
        return [round(A[i][0] * p.x + A[i][1] * p.y + A[i][2] * p.z + A[i][3], 1) for i in range(2)]

    # light: sun + soft area key + fill, studio world
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.2
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("sun", sun)
    S.collection.objects.link(so)
    so.rotation_euler = Vector((-0.6, 0.9, -1.5)).normalized().to_track_quat("-Z", "Y").to_euler()
    light(S, c + Vector((-1.2, -1.6, 1.4)) * r, 60 * r * r, r * 0.8, c)
    light(S, c + Vector((1.4, -0.8, 0.6)) * r, 20 * r * r, r * 0.8, c)
    w = bpy.data.worlds.new("w")
    S.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.6, 0.7, 1)
    bg.inputs["Strength"].default_value = 0.3
    S.render.engine = "CYCLES"
    S.cycles.samples = SAMPLES
    S.cycles.use_denoising = True
    S.render.film_transparent = True
    S.render.image_settings.file_format = "PNG"
    S.render.image_settings.color_mode = "RGBA"
    S.view_settings.view_transform = "AgX"
    S.view_settings.look = "AgX - Medium High Contrast"
    os.makedirs(TMP, exist_ok=True)

    def show_only(names):
        keep = set()
        for n in names:
            keep.update(o.name for o in tree(N[n]))
        for o in S.objects:
            if o.type == "MESH":
                o.hide_render = o.name not in keep

    out = {"w": W, "h": H, "A": A, "layers": {}, "lamps": {}, "points": {}}
    # still layer
    for o in S.objects:
        if o.type == "MESH":
            o.hide_render = o.name in still_hidden or any(o.name in [x.name for x in tree(N[p])] for p in protos)
    png = os.path.join(TMP, f"{kind}_base.png")
    render(S, png)
    out["layers"]["base"] = webp(png, os.path.join(OUT, f"mach_{kind}_base.webp"), W, H)
    for layer, names in LAYERS[kind].items():
        if any(n not in N for n in names):
            continue
        show_only(names)
        if layer == "car_open":
            N["door_l"].location.x -= 0.38
            N["door_r"].location.x += 0.38
        rot = next(((p, r) for p, r in ROT.items() if layer.startswith(p) and layer[len(p):].isdigit()), None)
        if rot:
            node, axis, step = rot[1]
            # imported glTF nodes rotate by quaternion: switch to Euler or the angle is ignored
            N[node].rotation_mode = "XYZ"
            N[node].rotation_euler[axis] = math.radians(step * int(layer[len(rot[0]):]))
        if layer == "bottle":
            for o in tree(N["proto_liquid"]):
                o.hide_render = True
        bpy.context.view_layer.update()
        png = os.path.join(TMP, f"{kind}_{layer}.png")
        render(S, png)
        out["layers"][layer] = webp(png, os.path.join(OUT, f"mach_{kind}_{layer}.webp"), W, H)
        if rot:
            N[rot[1][0]].rotation_euler[rot[1][1]] = 0
            bpy.context.view_layer.update()
        if layer == "car_open":
            N["door_l"].location.x += 0.38
            N["door_r"].location.x -= 0.38
            bpy.context.view_layer.update()
    for n, o in N.items():
        if n.startswith("lamp_"):
            out["lamps"][n[5:]] = px(o.matrix_world @ Vector(o.bound_box[0]).lerp(Vector(o.bound_box[6]), 0.5))
        if n in ("cart", "hook", "rope", "rope_car", "car", "cw", "rod", "ram", "proto_metal", "proto_plastic", "proto_bottle", "proto_liquid", "stream", "drum", "sheave", "proto_box", "leaf", "blades", "bridge", "trolley", "water", "fly", "fan", "glow"):
            out["points"][n] = [round(v, 4) for v in o.matrix_world.translation]
    if "water" in N:
        wlo, whi = world_bounds(tree(N["water"]))
        out["points"]["water_lo"] = [round(v, 4) for v in wlo]
        out["points"]["water_hi"] = [round(v, 4) for v in whi]
    if "proto_liquid" in N:
        llo, lhi = world_bounds(tree(N["proto_liquid"]))
        out["points"]["liquid_lo"] = [round(v, 4) for v in llo]
        out["points"]["liquid_hi"] = [round(v, 4) for v in lhi]
    return out


def main():
    kinds = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [a for a in sys.argv[1:]]
    kinds = kinds or list(LAYERS)
    jf = os.path.join(OUT, "machine_sprites.json")
    data = json.load(open(jf)) if os.path.exists(jf) else {}
    for k in kinds:
        print("render", k, flush=True)
        data[k] = render_machine(k)
        json.dump(data, open(jf, "w"), indent=1, sort_keys=True)
        print("  ", data[k]["w"], "x", data[k]["h"], list(data[k]["layers"]), flush=True)


if __name__ == "__main__":
    main()
