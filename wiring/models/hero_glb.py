"""Studio renders of imported GLBs (the v2 devices and tools) in the same look as residential.py --hero.

    python3 hero_glb.py mcb_1p rccb ...   ->  out/<name>.png
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "v2", "models"))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import lib  # noqa: E402

GLB = os.path.join(HERE, "..", "app", "assets", "models")
REN = os.path.join(HERE, "out")

for name in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]):
    lib.reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(GLB, name + ".glb"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    c = (lo + hi) / 2
    span = max(hi - lo)
    lib.studio(target=tuple(c), dist=span * 2.6, elev=18, azim=-28, lens_mm=60, res=(900, 900), bg=(0.035, 0.07, 0.16), key=2.6, samples=48)
    lib.OUT = REN + os.sep
    lib.render(name)
