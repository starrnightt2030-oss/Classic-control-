"""Shared helpers for procedural electrical component models (units: metres, Z = button axis / up)."""
import bpy, bmesh, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out") + os.sep
os.makedirs(OUT, exist_ok=True)
BRAND = "ELDAWLY"


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear()


def _sel(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


# ---------------------------------------------------------------- materials
_MATS = {}


def mat(name, color, metal=0.0, rough=0.45, coat=0.0, trans=0.0, emit=None, bump=0.0, ior=1.45, alpha=1.0):
    key = (name, color, metal, rough, coat, trans, emit, bump)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Transmission Weight"].default_value = trans
    b.inputs["IOR"].default_value = ior
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
    if emit:
        b.inputs["Emission Color"].default_value = (*emit[0], 1)
        b.inputs["Emission Strength"].default_value = emit[1]
    if bump:
        # fine moulded-plastic micro texture
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = 4000.0
        n.inputs["Detail"].default_value = 4.0
        bm = nt.nodes.new("ShaderNodeBump")
        bm.inputs["Strength"].default_value = bump
        bm.inputs["Distance"].default_value = 0.00002
        nt.links.new(n.outputs["Fac"], bm.inputs["Height"])
        nt.links.new(bm.outputs["Normal"], b.inputs["Normal"])
    _MATS[key] = m
    return m


def M():
    """Standard palette (linear colours)."""
    return dict(
        black=mat("pa_black", (0.018, 0.018, 0.02), rough=0.42, bump=0.25),
        black_gloss=mat("pa_black_gloss", (0.012, 0.012, 0.014), rough=0.18, coat=0.6),
        grey=mat("pa_grey", (0.22, 0.225, 0.23), rough=0.5, bump=0.2),
        white=mat("pa_white", (0.78, 0.78, 0.75), rough=0.45, bump=0.2),
        chrome=mat("chrome", (0.92, 0.92, 0.94), metal=1.0, rough=0.08),
        satin=mat("satin_steel", (0.75, 0.75, 0.77), metal=1.0, rough=0.28),
        zinc=mat("zinc", (0.78, 0.8, 0.82), metal=1.0, rough=0.32),
        brass=mat("brass", (0.82, 0.68, 0.38), metal=1.0, rough=0.22),
        copper=mat("copper", (0.93, 0.55, 0.38), metal=1.0, rough=0.2),
        print_white=mat("print_white", (0.85, 0.85, 0.85), rough=0.6),
        print_black=mat("print_black", (0.01, 0.01, 0.01), rough=0.6),
        green=mat("cap_green", (0.0, 0.16, 0.035), rough=0.22, coat=0.8),
        red=mat("cap_red", (0.42, 0.006, 0.006), rough=0.22, coat=0.8),
        yellow=mat("pa_yellow", (0.75, 0.48, 0.0), rough=0.4, bump=0.2),
        yzinc=mat("yellow_zinc", (0.80, 0.62, 0.32), metal=1.0, rough=0.28),
        blue=mat("pa_blue", (0.005, 0.06, 0.3), rough=0.35),
    )


def lens(color, on):
    if on:
        return mat("lens_on_%s" % (color,), color, rough=0.25, trans=0.3, emit=(color, 18.0))
    dim = tuple(c * 0.55 for c in color)
    return mat("lens_off_%s" % (color,), dim, rough=0.12, trans=0.55, coat=1.0, ior=1.5)


# ---------------------------------------------------------------- geometry
def finish(o, bw=0.0005, seg=3, smooth=True, mats=None):
    if mats:
        for m in mats:
            o.data.materials.append(m)
    if bw:
        md = o.modifiers.new("bev", "BEVEL")
        md.width = bw
        md.segments = seg
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(40)
        md.harden_normals = True
    _sel(o)
    if smooth:
        bpy.ops.object.shade_smooth()
    o.modifiers.new("wn", "WEIGHTED_NORMAL").keep_sharp = True
    return o


def cyl(r, h, z0, m, x=0, y=0, verts=64, bw=0.0004, name="cyl", r2=None, axis="Z"):
    """Cylinder from z0 to z0+h (along axis). r2 => cone/taper."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, vertices=verts)
    o = bpy.context.object
    o.name = name
    if axis == "Z":
        o.location = (x, y, z0 + h / 2)
    elif axis == "Y":
        o.rotation_euler = (math.radians(-90), 0, 0)
        o.location = (x, z0 + h / 2, y)
    elif axis == "X":
        o.rotation_euler = (0, math.radians(90), 0)
        o.location = (z0 + h / 2, x, y)
    return finish(o, bw, mats=[m])


def box(sx, sy, sz, center, m, bw=0.0006, name="box", seg=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = bpy.context.object
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    o.name = name
    return finish(o, bw, seg, mats=[m])


def torus(R, r, z, m, name="torus"):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=(0, 0, z), major_segments=72, minor_segments=16)
    o = bpy.context.object
    o.name = name
    return finish(o, 0, mats=[m])


def knurl_ring(r_in, r_out, h, z0, m, teeth=48, name="knurl"):
    """Ring nut with knurled outer edge."""
    o = cyl(r_out - 0.0004, h, z0, m, verts=96, bw=0.0003, name=name)
    bpy.ops.mesh.primitive_cube_add(size=1)
    t = bpy.context.object
    t.scale = (0.0007, 0.0007, h * 0.8)
    t.location = (r_out - 0.0002, 0, z0 + h / 2)
    bpy.ops.object.transform_apply(scale=True)
    t.rotation_euler = (0, 0, math.radians(45))
    bpy.ops.object.transform_apply(rotation=True, location=False)
    a = t.modifiers.new("arr", "ARRAY")
    bpy.ops.object.empty_add(location=(0, 0, 0))
    e = bpy.context.object
    e.rotation_euler = (0, 0, 2 * math.pi / teeth)
    a.use_relative_offset = False
    a.use_object_offset = True
    a.offset_object = e
    a.count = teeth
    t.location = (0, 0, 0)
    t.data.materials.append(m)
    _sel(t)
    bpy.ops.object.modifier_apply(modifier="arr")
    bpy.data.objects.remove(e)
    hole = cyl(r_in, h * 3, z0 - h, m, name="hole", bw=0)
    for target in (o,):
        bo = target.modifiers.new("hole", "BOOLEAN")
        bo.object = hole
        bo.operation = "DIFFERENCE"
        target.modifiers.move(target.modifiers.find("hole"), 0)
        _sel(target)
        bpy.ops.object.modifier_apply(modifier="hole")
    bpy.data.objects.remove(hole)
    return o, t


def cut(target, cutter, keep=False):
    bo = target.modifiers.new("cut", "BOOLEAN")
    bo.object = cutter
    bo.operation = "DIFFERENCE"
    bo.solver = "EXACT"
    target.modifiers.move(target.modifiers.find("cut"), 0)
    _sel(target)
    bpy.ops.object.modifier_apply(modifier="cut")
    if not keep:
        bpy.data.objects.remove(cutter)


def text(body, size, loc, m, rot=(0, 0, 0), depth=0.00006, align="CENTER", bold=False):
    c = bpy.data.curves.new("txt", "FONT")
    c.body = body
    c.size = size
    c.extrude = depth
    c.align_x = align
    c.align_y = "CENTER"
    o = bpy.data.objects.new("txt_" + body, c)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = tuple(math.radians(a) for a in rot)
    _sel(o)
    bpy.ops.object.convert(target="MESH")
    o.data.materials.append(m)
    return o


def screw_terminal(loc, normal, mats, label=None, name="T", metal="zinc"):
    """Captive screw + square washer + label. normal: '+X','-X','+Y','-Y','+Z','-Z' (direction screw head faces)."""
    rots = {"+Z": (0, 0, 0), "-Z": (180, 0, 0), "+Y": (-90, 0, 0), "-Y": (90, 0, 0), "+X": (0, 90, 0), "-X": (0, -90, 0)}
    rot = rots[normal]
    parts = []
    # build at origin pointing +Z then rotate
    w = box(0.0058, 0.0058, 0.0007, (0, 0, 0.00035), mats[metal], bw=0.0002, name="washer")
    h = cyl(0.0027, 0.0016, 0.0007, mats["zinc"], verts=48, bw=0.0007, name="screwhead")
    slot = box(0.0062, 0.0009, 0.0020, (0, 0, 0.0029), mats["zinc"], bw=0, name="slot")
    cut(h, slot)
    slot2 = box(0.0009, 0.0044, 0.0020, (0, 0, 0.0029), mats["zinc"], bw=0, name="slot2")
    cut(h, slot2)  # pozidriv-like cross
    parts = [w, h]
    for p in parts:
        _sel(p)
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        p.rotation_euler = tuple(math.radians(a) for a in rot)
        p.location = loc
    # connection point empty (wire attaches here)
    bpy.ops.object.empty_add(type="SPHERE", radius=0.002, location=loc)
    e = bpy.context.object
    e.name = "TERM_" + (label or name)
    e.rotation_euler = tuple(math.radians(a) for a in rot)
    return parts, e


def join(objs, name):
    objs = [o for o in objs if o and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        _sel_add(o)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        _sel(o) if False else None
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")  # apply modifiers
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o


def _sel_add(o):
    o.select_set(True)


# ---------------------------------------------------------------- studio
def studio(target=(0, 0, 0), dist=0.16, elev=24, azim=-38, lens_mm=70, res=(1000, 1000), floor_z=None,
           bg=(0.055, 0.058, 0.062), key=2.6, samples=64):
    S = bpy.context.scene
    tx, ty, tz = target
    el, az = math.radians(elev), math.radians(azim)
    cam_loc = (tx + dist * math.cos(el) * math.sin(az) * -1, ty - dist * math.cos(el) * math.cos(az), tz + dist * math.sin(el))
    bpy.ops.object.camera_add(location=cam_loc)
    cam = bpy.context.object
    S.camera = cam
    cam.data.lens = lens_mm
    bpy.ops.object.empty_add(location=target)
    tgt = bpy.context.object
    tgt.name = "cam_target"
    cam.constraints.new("TRACK_TO").target = tgt
    k = dist / 0.16
    for loc, e, size in [((0.20, -0.16, 0.24), key, 0.22), ((-0.22, -0.10, 0.08), key * 0.35, 0.35),
                         ((0.02, 0.22, 0.20), key * 0.9, 0.25)]:
        bpy.ops.object.light_add(type="AREA", location=(tx + loc[0] * k, ty + loc[1] * k, tz + loc[2] * k))
        L = bpy.context.object
        L.data.energy = e * k * k
        L.data.size = size * k
        L.constraints.new("TRACK_TO").target = tgt
    if floor_z is not None:
        bpy.ops.mesh.primitive_plane_add(size=3, location=(0, 0, floor_z))
        f = bpy.context.object
        f.data.materials.append(mat("floor", bg, rough=0.6))
        f.name = "_floor"
    w = bpy.data.worlds.new("w")
    S.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (*bg, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    S.render.engine = "CYCLES"
    S.cycles.samples = samples
    S.cycles.use_denoising = True
    S.render.resolution_x, S.render.resolution_y = res
    S.view_settings.view_transform = "AgX"
    S.view_settings.look = "AgX - Medium High Contrast"
    return cam


def render(name):
    S = bpy.context.scene
    S.render.filepath = OUT + name + ".png"
    bpy.ops.render.render(write_still=True)


def export(name):
    """Export only the component (no camera/lights/floor) as GLB with terminal empties."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.context.scene.objects:
        if o.type in ("MESH", "EMPTY") and not o.name.startswith("_") and o.name != "cam_target":
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT + name + ".glb", use_selection=True, export_apply=True,
                              export_extras=True)
