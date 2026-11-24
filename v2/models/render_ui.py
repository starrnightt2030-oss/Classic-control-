"""Transparent PNG renders of library GLBs for UI design (auto-framed). Optional exploded view from GLB extras.
Run: python render_ui.py name[:exploded] ...  -> out/ui/<name>.png"""
import sys, os, math, bpy
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "assets", "models")
OUT = os.path.join(HERE, "out", "ui")
os.makedirs(OUT, exist_ok=True)

for arg in sys.argv[1:]:
    name, _, mode = arg.partition(":")
    lib.reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(ASSETS, name + ".glb"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if mode == "exploded":
        for o in bpy.context.scene.objects:
            if "explode_mm" in o.keys():
                d = o["explode_mm"]
                o.location = o.location + Vector((d[0], -d[2], d[1])) * 0.001 if False else o.location
        bpy.context.view_layer.update()
        for o in bpy.context.scene.objects:
            if "explode_mm" in o.keys():
                d = list(o["explode_mm"])
                # glTF import converts Y-up back to Z-up on the root; parts keep Blender axes: apply in world space
                o.matrix_world.translation += Vector(d) * 0.001
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr = (mn + mx) / 2
    size = (mx - mn).length
    lib.studio(target=tuple(ctr), dist=size * (2.0 if mode != "exploded" else 1.55), elev=18, azim=-34 if mode != "exploded" else -46,
               lens_mm=60, samples=48, res=(900, 900) if mode != "exploded" else (1400, 900), key=2.6)
    S = bpy.context.scene
    S.render.film_transparent = True
    S.render.image_settings.color_mode = "RGBA"
    S.render.filepath = os.path.join(OUT, name + ("_exploded" if mode else "") + ".png")
    bpy.ops.render.render(write_still=True)
    print("DONE", arg)
