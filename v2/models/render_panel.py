"""Front-view sprites for the Panel Lab.

For every component GLB: orthographic camera looking at the front (−Y → +Y), transparent
background, soft studio light, fixed scale (PPM pixels per millimetre) so all parts match
each other on the mounting plate. Terminal empties (TERM_*) are projected to pixel
coordinates and written next to the image.

    bvenv/bin/python render_panel.py [names...]
Output: v2/app/assets/panel/<name>.webp + v2/app/assets/panel/panel_sprites.json
"""
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "app", "assets", "models")
OUT = os.path.join(HERE, "..", "app", "assets", "panel")
TMP = "/tmp/panel_render"
PPM = 8.0          # pixels per millimetre in the sprite (UI scales it)
SS = 2             # supersampling factor of the render
SAMPLES = 32

# name -> (glb, front axis). Most models face −Y; a few are modelled facing up (+Z).
PARTS = {
    "terminal_strip": "-Y", "mcb_1p": "-Y", "mcb_2p": "-Y", "mcb_3p": "-Y", "mcb_4p": "-Y",
    "mpcb": "-Y", "rccb": "-Y", "fuse_holder": "-Y", "main_isolator": "-Y",
    "contactor": "-Y", "aux_block": "-Y", "pneumatic_timer": "-Y", "overload": "-Y",
    "relay_my4": "-Y", "timer_din": "-Y", "timer_star_delta": "-Y", "phase_relay": "-Y",
    "pb_green_metal": "-Y", "pb_red_plastic": "-Y", "pb_double": "-Y", "estop": "-Y", "selector": "-Y",
    "lamp_green": "-Y", "lamp_red": "-Y", "lamp_amber": "-Y",
    "limit_roller": "-Y", "power_supply_24v": "-Y", "control_transformer": "-Y",
    "voltmeter": "-Y", "ammeter": "-Y", "kwh_meter": "-Y", "terminal_block": "-Y",
    "din_rail": "-Y", "wire_duct": "-Y", "motor": "-Y", "signal_tower": "-Y", "siren": "-Y",
    # door devices seen face-on (the lab draws their terminals left and right)
    "pb_green_metal_face": "+Z", "pb_red_plastic_face": "+Z", "estop_face": "+Z", "selector_face": "+Z",
    "lamp_green_face": "+Z", "lamp_red_face": "+Z", "lamp_amber_face": "+Z",
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def light(loc, energy, size, target):
    bpy.ops.object.light_add(type="AREA", location=loc)
    L = bpy.context.object
    L.data.energy = energy
    L.data.size = size
    d = Vector(target) - Vector(loc)
    L.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def render_one(name, front):
    reset()
    glb = name[:-5] if name.endswith("_face") else name
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, glb + ".glb"))
    S = bpy.context.scene
    meshes = [o for o in S.objects if o.type == "MESH"]
    if front == "+Z":  # rotate a top-facing model so its face points −Y
        R = Matrix.Rotation(math.radians(90), 4, "X")  # +Z → −Y (towards the camera)
        for o in S.objects:
            if o.parent is None:
                o.matrix_world = R @ o.matrix_world
        bpy.context.view_layer.update()
    lo, hi = world_bounds(meshes)
    size = hi - lo
    cx, cz = (lo.x + hi.x) / 2, (lo.z + hi.z) / 2
    pad = 1.5e-3
    w_mm, h_mm = (size.x + 2 * pad) * 1000, (size.z + 2 * pad) * 1000
    rx, ry = max(8, round(w_mm * PPM)), max(8, round(h_mm * PPM))
    # camera
    bpy.ops.object.camera_add(location=(cx, lo.y - 0.5, cz))
    cam = bpy.context.object
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.type = "ORTHO"
    if rx >= ry:
        cam.data.ortho_scale = size.x + 2 * pad
    else:
        cam.data.ortho_scale = size.z + 2 * pad
    cam.data.clip_end = 5
    S.camera = cam
    # light: key upper-left-front, fill right, rim top-back; tuned for small parts (metres)
    span = max(size.x, size.z, 0.04)
    t = (cx, (lo.y + hi.y) / 2, cz)
    def L(dx, dy, dz, rel, size_k):
        loc = (cx + span * dx, lo.y - span * dy if dy > 0 else hi.y - span * dy, cz + span * dz)
        d2 = sum((a - b) ** 2 for a, b in zip(loc, t))
        light(loc, 29 * d2 * rel, span * size_k, t)
    L(-1.1, 2.0, 1.3, 1.0, 1.2)    # key: upper-left front
    L(1.6, 1.4, 0.1, 0.38, 1.8)    # fill: right
    L(0.0, -1.2, 1.9, 0.7, 1.2)    # rim: top back
    w = bpy.data.worlds.new("w")
    S.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.20, 0.22, 0.25, 1)
    bg.inputs["Strength"].default_value = 0.35
    S.render.engine = "CYCLES"
    S.cycles.samples = SAMPLES
    S.cycles.use_denoising = True
    S.render.film_transparent = True
    S.render.resolution_x, S.render.resolution_y = rx * SS, ry * SS
    S.render.image_settings.file_format = "PNG"
    S.render.image_settings.color_mode = "RGBA"
    S.view_settings.view_transform = "AgX"
    S.view_settings.look = "AgX - Medium High Contrast"
    os.makedirs(TMP, exist_ok=True)
    png = os.path.join(TMP, name + ".png")
    S.render.filepath = png
    bpy.ops.render.render(write_still=True)
    # terminals → pixels (sprite space, origin top-left)
    o_s = cam.data.ortho_scale
    hx, vy = (o_s, o_s * ry / rx) if rx >= ry else (o_s * rx / ry, o_s)
    left, top = cx - hx / 2, cz + vy / 2
    k = rx / hx
    terms = {}
    for o in S.objects:
        if o.type == "EMPTY" and o.name.startswith("TERM_"):
            p = o.matrix_world.translation
            terms[o.name[5:]] = [round((p.x - left) * k, 1), round((top - p.z) * k, 1)]
    os.makedirs(OUT, exist_ok=True)
    webp = os.path.join(OUT, name + ".webp")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", png, "-vf", f"scale={rx}:{ry}:flags=lanczos",
                    "-c:v", "libwebp", "-lossless", "0", "-quality", "92", "-pix_fmt", "yuva420p", webp], check=True)
    return {"w": rx, "h": ry, "mm": [round(w_mm, 1), round(h_mm, 1)], "terms": terms}


def main():
    names = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else []
    names = names or list(PARTS)
    jf = os.path.join(OUT, "panel_sprites.json")
    data = json.load(open(jf)) if os.path.exists(jf) else {}
    data["_ppm"] = PPM
    for n in names:
        print("render", n, flush=True)
        data[n] = render_one(n, PARTS.get(n, "-Y"))
        print("  ", data[n]["w"], "x", data[n]["h"], len(data[n]["terms"]), "terms", flush=True)
    json.dump(data, open(jf, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
