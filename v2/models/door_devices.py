"""Batch 1: 22 mm door devices. Run: python door_devices.py <name|all> [--norender]"""
import sys, math, bpy
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import lib
from lib import cyl, box, text, screw_terminal, knurl_ring, cut, torus

PANEL_RAL7035 = (0.62, 0.63, 0.6)


def panel_plate(mm):
    """Piece of the door sheet the device is mounted through (grey RAL 7035 powder coat)."""
    m = lib.mat("ral7035", PANEL_RAL7035, rough=0.55, bump=0.6)
    p = box(0.056, 0.056, 0.0015, (0, 0, -0.00075), m, bw=0.0004, name="_plate_vis")
    p.name = "panel_plate"
    hole = cyl(0.0112, 0.01, -0.005, m, bw=0, name="h")
    cut(p, hole)
    return p


def body_rear(mm, depth_to=-0.012):
    """Thread tube + knurled ring nut + mounting base (behind door)."""
    parts = []
    parts.append(cyl(0.0109, -depth_to - 0.0015, depth_to, mm["satin"], verts=64, bw=0.0002, name="thread_tube"))
    for i in range(7):  # thread grooves
        parts.append(torus(0.0109, 0.00028, -0.0055 - i * 0.0009, mm["satin"], name="thread"))
    ring, teeth = knurl_ring(0.0110, 0.0145, 0.0028, -0.0045, mm["satin"])
    parts += [ring, teeth]
    # mounting base with latch + clamp screws
    base = box(0.030, 0.030, 0.0085, (0, 0, depth_to - 0.00425), mm["black"], bw=0.0012, name="base")
    parts.append(base)
    for x in (-0.0105, 0.0105):
        parts.append(cyl(0.0019, 0.001, depth_to + 0.0, mm["zinc"], x=x, y=-0.0105, verts=32, bw=0.0002, name="clamp"))
    parts.append(box(0.010, 0.004, 0.003, (0, -0.0158, depth_to - 0.004), mm["black"], bw=0.0006, name="latch"))
    return parts, depth_to - 0.0085


def contact_block(mm, x, z_top, kind, nums):
    """LA38/XB2-style clip-on contact block. kind NO/NC (green/red marker)."""
    parts, terms = [], []
    W, D, H = 0.0105, 0.030, 0.030
    zc = z_top - H / 2
    b = box(W, D, H, (x, 0, zc), mm["black"], bw=0.0007, name="cblock")
    parts.append(b)
    # moulded ribs on side
    for i in range(3):
        parts.append(box(W + 0.0004, 0.0012, 0.0008, (x, 0.008, zc - 0.006 + i * 0.006), mm["black"], bw=0.0002, name="rib"))
    # colour marker (green NO / red NC)
    col = mm["green"] if kind == "NO" else mm["red"]
    parts.append(box(0.0062, 0.0004, 0.0042, (x, -D / 2 - 0.0001, zc + 0.0005), col, bw=0.0001, name="marker"))
    parts.append(text(kind, 0.0023, (x, -D / 2 - 0.00035, zc + 0.0005), mm["print_white"], rot=(90, 0, 0)))
    # terminals: top and bottom on the front face, recessed
    for (zt, n) in ((z_top - 0.0055, nums[0]), (z_top - H + 0.0055, nums[1])):
        recess = box(0.0078, 0.004, 0.0078, (x, -D / 2, zt), mm["black"], bw=0, name="rc")
        cut(b, recess)
        p, e = screw_terminal((x, -D / 2 + 0.0015, zt), "-Y", mm, label=n)
        parts += p
        terms.append(e)
        parts.append(text(n, 0.0026, (x, -D / 2 - 0.0001, zt + (0.0052 if zt > zc else -0.0052)), mm["print_white"], rot=(90, 0, 0)))
    return parts, terms


def bezel_chrome(mm, r_out=0.0148, h=0.0058):
    o = cyl(r_out, h, 0.0, mm["chrome"], verts=96, bw=0.0018, name="bezel")
    hole = cyl(r_out - 0.0026, h * 3, -h, mm["chrome"], bw=0, name="h")
    cut(o, hole)
    return o


def rear_and_blocks(mm, blocks):
    parts, z_bottom = body_rear(mm)
    terms = []
    n = len(blocks)
    xs = [0] if n == 1 else [-0.0056, 0.0056]
    for x, (kind, nums) in zip(xs, blocks):
        p, t = contact_block(mm, x, z_bottom - 0.0002, kind, nums)
        parts += p
        terms += t
    return parts, terms


# ------------------------------------------------------------------ devices
def pushbutton(color="green", pressed=False):
    mm = lib.M()
    parts = [bezel_chrome(mm)]
    travel = 0.0018 if pressed else 0.0
    cap = cyl(0.0118, 0.0052, 0.0012 - travel, mm[color], verts=96, bw=0.0016, name="cap")
    parts.append(cap)
    # dark gap ring between cap and bezel
    parts.append(cyl(0.0122, 0.004, 0.0004, mm["black"], verts=96, bw=0.0002, name="gap"))
    kind = ("NO", ("13", "14")) if color == "green" else ("NC", ("11", "12"))
    p, t = rear_and_blocks(mm, [kind])
    return parts + p, t


def estop(pressed=False):
    mm = lib.M()
    parts = []
    # yellow legend plate (Ø60 ring) printed EMERGENCY STOP
    yp = cyl(0.030, 0.0012, 0.0, mm["yellow"], verts=128, bw=0.0003, name="legend_plate")
    parts.append(yp)
    for i, ch in enumerate("EMERGENCY STOP"):
        a = math.radians(210 + i * (120 / 13))
        r = 0.0245
        parts.append(text(ch, 0.0034, (r * math.cos(a), r * math.sin(a), 0.00125), mm["print_black"],
                          rot=(0, 0, math.degrees(a) + 90), depth=0.00004))
    parts.append(cyl(0.0165, 0.007, 0.0012, mm["black"], verts=96, bw=0.0016, name="collar"))
    dz = -0.004 if pressed else 0.0
    # mushroom head Ø40
    head = cyl(0.020, 0.010, 0.0080 + dz, mm["red"], verts=128, bw=0.0045, name="mushroom")
    parts.append(head)
    parts.append(cyl(0.010, 0.004, 0.0060 + dz, mm["red"], verts=64, bw=0.0008, name="stem"))
    p, t = rear_and_blocks(mm, [("NC", ("11", "12"))])
    return parts + p, t


def selector(pos=0):
    mm = lib.M()
    parts = [bezel_chrome(mm)]
    parts.append(cyl(0.0122, 0.0048, 0.0006, mm["black"], verts=96, bw=0.0012, name="knob_base"))
    lever = box(0.0075, 0.0225, 0.0098, (0, 0, 0.0095), mm["black_gloss"], bw=0.0025, name="lever")
    lever.rotation_euler = (0, 0, math.radians(-45 if pos == 0 else 45))
    parts.append(lever)
    a = math.radians(-45 if pos == 0 else 45)
    line = box(0.0011, 0.008, 0.0004, (-0.0062 * math.sin(a), 0.0062 * math.cos(a), 0.0146), mm["print_white"], bw=0.0001, name="mark")
    line.rotation_euler = (0, 0, a)
    parts.append(line)
    p, t = rear_and_blocks(mm, [("NO", ("13", "14")), ("NO", ("23", "24"))])
    return parts + p, t


def pilot_lamp(color=(0.02, 0.9, 0.08), on=False):
    """AD16-22 style monoblock LED indicator."""
    mm = lib.M()
    parts = []
    parts.append(cyl(0.0140, 0.0040, 0.0, mm["black"], verts=96, bw=0.0012, name="bezel"))
    L = lib.lens(color, on)
    parts.append(cyl(0.0118, 0.0042, 0.0022, L, verts=96, bw=0.0016, name="lens"))
    # inner LED reflector visible through lens
    parts.append(cyl(0.008, 0.001, 0.0015, mm["satin"], verts=48, bw=0.0002, name="reflector"))
    parts.append(cyl(0.0109, 0.022, -0.0235, mm["black"], verts=64, bw=0.0008, name="body"))
    ring, teeth = knurl_ring(0.0110, 0.0140, 0.0026, -0.0042, mm["black"])
    parts += [ring, teeth]
    # rear terminal cap with two screws facing -Y
    rc = box(0.018, 0.016, 0.010, (0, 0, -0.0285), mm["black"], bw=0.0012, name="rearcap")
    parts.append(rc)
    terms = []
    for x, n in ((-0.0045, "X1"), (0.0045, "X2")):
        rec = box(0.0068, 0.004, 0.0068, (x, -0.008, -0.0285), mm["black"], bw=0, name="r")
        cut(rc, rec)
        p, e = screw_terminal((x, -0.0068, -0.0285), "-Y", mm, label=n)
        parts += p
        terms.append(e)
        parts.append(text(n, 0.0022, (x, -0.0081, -0.0350), mm["print_white"], rot=(90, 0, 0)))
    parts.append(text("230V AC", 0.0021, (0, -0.0110, -0.0165), mm["print_white"], rot=(90, 0, 0)))
    if on:
        bpy.ops.object.light_add(type="POINT", location=(0, 0, 0.012))
        l = bpy.context.object
        l.name = "_glow"
        l.data.energy = 0.15
        l.data.color = color
        l.data.shadow_soft_size = 0.008
    return parts, terms


DEVICES = {
    "pb_green": lambda: pushbutton("green"),
    "pb_red": lambda: pushbutton("red"),
    "pb_green_pressed": lambda: pushbutton("green", pressed=True),
    "estop": lambda: estop(),
    "selector": lambda: selector(0),
    "lamp_green_on": lambda: pilot_lamp((0.02, 0.9, 0.08), True),
    "lamp_red_on": lambda: pilot_lamp((1.0, 0.04, 0.02), True),
    "lamp_amber_off": lambda: pilot_lamp((1.0, 0.45, 0.0), False),
}


def build(name, do_render=True):
    lib.reset()
    parts, terms = DEVICES[name]()
    cam = lib.studio(target=(0, 0, -0.012), dist=0.165, elev=22, azim=-35, lens_mm=60, samples=48, res=(900, 900))
    if do_render:
        lib.render(name)
    lib.export(name)
    print("BUILT", name, "terminals:", [t.name for t in terms])


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "pb_green"
    names = list(DEVICES) if arg == "all" else arg.split(",")
    for n in names:
        build(n, "--norender" not in sys.argv)
