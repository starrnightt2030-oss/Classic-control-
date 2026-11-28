"""Home banner: the real devices in a row on a board, rendered wide.

    python3 banner.py   ->  out/banner.png
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "v2", "models"))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import lib  # noqa: E402

GLB = os.path.join(HERE, "..", "app", "assets", "models")
ROW = ["kwh_meter", "rccb", "mcb_2p", "mcb_1p", "mcb_1p", "mcb_1p", None, "socket", "sw2_1", "swd_11", None, "lamp_1"]
GAP = 0.006


def bounds(objs):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


lib.reset()
x = 0.0
for name in ROW:
    if name is None:
        x += 0.03
        continue
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(GLB, name + ".glb"))
    new = [o for o in bpy.context.scene.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    lo, hi = bounds([o for o in new if o.type == "MESH"])
    zc = 0.05 if name == "lamp_1" else 0.0
    d = Vector((x - lo.x, -hi.y, zc - (lo.z + hi.z) / 2))
    for r in roots:
        r.location += d
    x += (hi.x - lo.x) + GAP
    bpy.context.view_layer.update()

lo, hi = bounds([o for o in bpy.context.scene.objects if o.type == "MESH"])
# back board
bpy.ops.mesh.primitive_plane_add(size=1, location=((lo.x + hi.x) / 2, 0.001, 0), rotation=(math.pi / 2, 0, 0))
b = bpy.context.object
b.scale = (6, 2, 1)
b.data.materials.append(lib.mat("board_bg", (0.16, 0.20, 0.27), rough=0.5))
c = (lo + hi) / 2
span = hi.x - lo.x
cam = lib.studio(target=(c.x + span * 0.42, c.y, c.z), dist=span * 2.7, elev=10, azim=-14, lens_mm=50, res=(2400, 760),
                 bg=(0.035, 0.07, 0.16), key=2.4, samples=64)
lib.OUT = os.path.join(HERE, "out") + os.sep
lib.render("banner")
