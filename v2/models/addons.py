"""Front-mount add-ons for the contactor: 4-pole auxiliary contact block and pneumatic time-delay block.
Run: python addons.py aux|timer [assembled,exploded]"""
import sys, math
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

COLS = [-15, -5, 5, 15]


def _mats(M):
    return dict(
        body=lib.mat("add_body", (0.06, 0.062, 0.066), rough=0.5, bump=0.25),
        print=lib.mat("add_print", (0.85, 0.85, 0.85), rough=0.6),
        copper=lib.mat("add_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22),
        silver=lib.mat("add_ag", (0.93, 0.93, 0.95), metal=1.0, rough=0.18),
        steel=lib.mat("add_steel", (0.72, 0.72, 0.74), metal=1.0, rough=0.3),
        slide=lib.mat("add_slide", (0.62, 0.62, 0.60), rough=0.4),
        green=lib.mat("add_green", (0.05, 0.55, 0.12), rough=0.4),
        orange=lib.mat("add_orange", (0.95, 0.45, 0.02), rough=0.4),
        rubber=lib.mat("add_rubber", (0.02, 0.02, 0.02), rough=0.8),
        felt=lib.mat("add_felt", (0.85, 0.83, 0.78), rough=0.95, bump=1.0),
        brass=lib.mat("add_brass", (0.82, 0.68, 0.38), metal=1.0, rough=0.25),
        white=lib.mat("add_white", (0.85, 0.85, 0.83), rough=0.45),
    )


def contact_set(C, M, specs, z_top, z_bot, y_fixed, y_bridge, g_fixed, g_bridge, g_cover, cover_y, labels_on):
    """specs: list of (x, kind 'NO'|'NC', top_label, bottom_label)."""
    for x, kind, lt, lb in specs:
        for z, lab in ((z_top, lt), (z_bot, lb)):
            s = 1 if z > 0 else -1
            screw(x, cover_y + 5, z, "-Y", M, lab, g_cover, scale=0.75)
            B(x - 2.6, x + 2.6, cover_y + 5, cover_y + 6.2, z - 3, z + 3, C["copper"], g_fixed, bw=0.2)
            z0, z1 = sorted((s * 5.5, z))
            B(x - 1.6, x + 1.6, y_fixed, y_fixed + 1.2, z0, z1, C["copper"], g_fixed, bw=0.2)
            B(x - 1.6, x + 1.6, cover_y + 6.2, y_fixed, z - 1, z + 1, C["copper"], g_fixed, bw=0.2)
            CYL(1.2, y_fixed - (0.7 if kind == "NO" else -1.2), y_fixed + (0 if kind == "NO" else 1.9), x, s * 7, C["silver"], g_fixed, bw=0.15)
            if labels_on:
                T(lab, x, cover_y - 0.06, z + s * 5.6, 2.0, C["print"], g_cover)
        # bridge: NO sits in front of fixed contacts (closes when pulled back); NC sits behind (opens)
        yb = y_bridge if kind == "NO" else y_fixed + 2.0
        B(x - 2.0, x + 2.0, yb, yb + 1.0, -9, 9, C["copper"], g_bridge, bw=0.25)
        for z in (7, -7):
            CYL(1.2, yb + (1.0 if kind == "NO" else -0.6), yb + (1.6 if kind == "NO" else 0.0), x, z, C["silver"], g_bridge, bw=0.15)
        if labels_on:
            T(kind, x, cover_y - 0.06, 0.0, 1.7, C["print"], g_cover)


# =============================================================== AUX CONTACT BLOCK (2 NO + 2 NC)
AUX_PARTS = {
    "cover":     ("الغطاء الأمامي والترامل", "Front cover & terminals", (0, -60, 0)),
    "fixed":     ("النقط الثابتة", "Fixed contacts", (0, -36, 0)),
    "bridges":   ("الكباري المتحركة NO و NC", "Moving bridges (NO & NC)", (0, -20, 0)),
    "slide":     ("المنزلق (حامل الكباري)", "Contact slide (carrier)", (0, -4, 0)),
    "spring":    ("سوستة الإرجاع", "Return spring", (0, 10, -30)),
    "plunger":   ("ذراع التعشيق مع الكونتاكتور", "Coupling plunger", (0, 26, 0)),
    "clip":      ("كلبس التثبيت وزرار الفك", "Mounting clip & release latch", (0, 24, 34)),
    "base":      ("الجسم الخلفي", "Rear housing", (0, 48, 0)),
}


def build_aux(M):
    C = _mats(M)
    base = B(-21, 21, -2, 18, -24, 24, C["body"], "base", bw=1.0)
    cut(base, cbox(-18, 18, -3, 14, -21, 21))
    cut(base, cbox(-5, 5, 13, 19, -6, 6))                       # plunger opening
    cov = B(-21, 21, -16, -2, -24, 24, C["body"], "cover", bw=1.0)
    for x in COLS:
        for z in (16.5, -16.5):
            cut(cov, ccyl(3.4, -18, -10, x, z))
    for x in (-10, 0, 10):
        B(x - 0.6, x + 0.6, -19, -15.5, 10.5, 24, C["body"], "cover", bw=0.2)
        B(x - 0.6, x + 0.6, -19, -15.5, -24, -10.5, C["body"], "cover", bw=0.2)
    specs = [(-15, "NO", "53", "54"), (-5, "NC", "61", "62"), (5, "NC", "71", "72"), (15, "NO", "83", "84")]
    contact_set(C, M, specs, 16.5, -16.5, -5.5, -8.2, "fixed", "bridges", "cover", -16, True)
    B(-4, 4, -16.6, -15.8, -10.5, -4.5, C["orange"], "cover", bw=0.2)
    T(lib.BRAND, -19.5, -16.06, 6.8, 1.8, C["print"], "cover", align="LEFT")
    T("EAX-22", 19.5, -16.06, 6.8, 1.8, C["print"], "cover", align="RIGHT")
    # slide carrying the bridges
    B(-19, 19, -10.2, -7.2, -11, 11, C["slide"], "slide", bw=0.4)
    for x in COLS:
        for s in (-1, 1):
            B(x + s * 2.7 - 0.4, x + s * 2.7 + 0.4, -7.2, -3.5, -11, 11, C["slide"], "slide", bw=0.1)
    B(-4, 4, -7.2, 13, -4, 4, C["slide"], "slide", bw=0.4)
    helix("spring", (0, 4, -14.5), 12, 2.0, 6, 0.35, C["steel"], axis="Y")
    B(-4.5, 4.5, 13, 22, -4.5, 4.5, C["slide"], "plunger", bw=0.6)
    B(-6, 6, 21, 23, -2, 2, C["slide"], "plunger", bw=0.3)
    # top clip + green release latch + rear hooks
    B(-6, 6, 8, 16, 24, 28, C["green"], "clip", bw=0.6)
    for x in (-15, 15):
        B(x - 3, x + 3, 18, 22, 20, 24, C["body"], "clip", bw=0.4)
        B(x - 3, x + 3, 18, 22, -24, -20, C["body"], "clip", bw=0.4)


# =============================================================== PNEUMATIC TIMER BLOCK (on-delay)
TMR_PARTS = {
    "dial":        ("قرص ضبط الزمن", "Time-setting dial", (0, -78, 0)),
    "cover":       ("الغطاء والترامل", "Cover & terminals", (0, -50, 0)),
    "needle":      ("صمام الإبرة (ضبط سريان الهوا)", "Needle valve (air-flow adjustment)", (0, -30, 34)),
    "filter":      ("فلتر الهوا", "Air filter", (34, -30, 30)),
    "bellows":     ("الرق المطاطي (غرفة الهوا)", "Rubber diaphragm / air chamber", (0, -26, 0)),
    "spring":      ("سوستة التوقيت", "Timing spring", (0, -6, -34)),
    "fixed":       ("النقط الثابتة المؤجلة", "Delayed fixed contacts", (-44, -30, 0)),
    "bridges":     ("كباري النقط المؤجلة", "Delayed contact bridges", (-44, -14, 0)),
    "plunger":     ("ذراع التعشيق مع الكونتاكتور", "Coupling plunger", (0, 22, 0)),
    "base":        ("الجسم الخلفي", "Rear housing", (0, 46, 0)),
}


def build_timer(M):
    C = _mats(M)
    body = C["white"]
    base = B(-21, 21, -2, 22, -24, 24, body, "base", bw=1.0)
    cut(base, cbox(-18, 18, -3, 18, -21, 21))
    cut(base, cbox(-5, 5, 17, 23, -6, 6))
    cov = B(-21, 21, -18, -2, -24, 24, body, "cover", bw=1.0)
    cut(cov, ccyl(14.6, -20, -10, 0, 0, verts=96))
    for x, z in ((-16, 16.5), (-16, -16.5), (16, 16.5), (16, -16.5)):
        cut(cov, ccyl(3.0, -20, -12, x, z))
    ink = lib.mat("tmr_ink", (0.03, 0.03, 0.04), rough=0.6)
    for x, zt, zb, lt, lb, kind in ((-16, 16.5, -16.5, "55", "56", "NC"), (16, 16.5, -16.5, "67", "68", "NO")):
        for z, lab in ((zt, lt), (zb, lb)):
            screw(x, -13, z, "-Y", M, lab, "cover", scale=0.72)
            T(lab, x + (-3.3 if x < 0 else 3.3), -18.06, z + (5.2 if z > 0 else -5.2), 2.0, ink, "cover")
            s = 1 if z > 0 else -1
            B(x - 2.2, x + 2.2, -13, -11.8, z - 2.8, z + 2.8, C["copper"], "fixed", bw=0.2)
            z0, z1 = sorted((s * 5.0, z))
            B(x - 1.4, x + 1.4, -11.8, -10.6, z0, z1, C["copper"], "fixed", bw=0.2)
            CYL(1.1, -12.4 if kind == "NO" else -10.6, -11.8 if kind == "NO" else -10.0, x, s * 6.5, C["silver"], "fixed", bw=0.12)
        T(kind, x + (-4.6 if x < 0 else 4.6), -18.06, 0, 1.7, ink, "cover")
        yb = -14.4 if kind == "NO" else -10.0
        B(x - 1.8, x + 1.8, yb, yb + 0.9, -8.5, 8.5, C["copper"], "bridges", bw=0.2)
    # arrows "- +" scale on cover top
    T("-", -11, -18.06, 20.5, 3.0, ink, "cover")
    T("+", 11, -18.06, 20.5, 3.0, ink, "cover")
    T(lib.BRAND, 0, -18.06, -21.2, 1.8, ink, "cover")
    # dial: knurled black ring + white face with scale
    CYL(13.6, -27.5, -18.5, 0, 0, C["body"], "dial", bw=0.8, verts=96)
    for i in range(56):
        a = 2 * math.pi * i / 56
        o = B(-0.55, 0.55, -27.2, -18.8, 13.3, 14.4, C["body"], "dial", bw=0.15)
        import bpy
        lib._sel(o)
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        o.rotation_euler = (0, a, 0)
    CYL(11.4, -28.4, -18.5, 0, 0, C["white"], "dial", bw=0.6, verts=96)
    for v, a in (("1", 220), ("3", 175), ("10", 120), ("30", 60)):
        r = math.radians(a)
        T(v, 8.0 * math.cos(r), -28.46, 8.0 * math.sin(r), 2.0, ink, "dial")
    T("ON-DELAY", 0, -28.46, -1.0, 1.9, ink, "dial")
    T("1-30 s", 0, -28.46, -4.4, 1.9, ink, "dial")
    B(-0.6, 0.6, -28.9, -28.3, 3, 10.5, lib.mat("tmr_ptr", (0.6, 0.6, 0.62), rough=0.5), "dial", bw=0.1)
    # needle valve + adjusting screw (driven by dial)
    CYL(1.6, -18.5, -6, 0, 0, C["brass"], "needle", bw=0.2, verts=24)
    CYL(1.6, -6, -2, 0, 0, C["brass"], "needle", bw=0.2, verts=24, r2=0.3)
    # air filter (felt disc)
    CYL(4.5, -10, -7.5, 9, 12, C["felt"], "filter", bw=0.5)
    # rubber diaphragm / bellows chamber
    CYL(12, -2, 6, 0, 0, C["rubber"], "bellows", bw=1.5, verts=64)
    for i in range(3):
        o = lib.torus(0.0125, 0.0009, 0, C["rubber"])
        o.rotation_euler = (math.radians(90), 0, 0)
        o.location = (0, (-0.5 + i * 2.6) * 0.001, 0)
        kit.G["bellows"].append(o)
    helix("spring", (0, 9, 0), 10, 6.5, 6, 0.55, C["steel"], axis="Y")
    B(-4.5, 4.5, 14, 26, -4.5, 4.5, C["slide"], "plunger", bw=0.6)
    B(-14, 14, 13, 15, -4, 4, C["slide"], "plunger", bw=0.4)


def bpy_last():
    import bpy
    return bpy.context.object


class _Mod:
    pass


def module(kind):
    m = _Mod()
    if kind == "aux":
        m.PARTS, m.build = AUX_PARTS, build_aux
    else:
        m.PARTS, m.build = TMR_PARTS, build_timer
    return m


if __name__ == "__main__":
    kind = sys.argv[1]
    modes = sys.argv[2].split(",") if len(sys.argv) > 2 else ["assembled", "exploded"]
    name = "aux_block" if kind == "aux" else "pneumatic_timer"
    kit.run(name, module(kind),
            dict(target=(0, -0.004, 0), dist=0.16, elev=16, azim=-30, lens_mm=60),
            dict(target=(-0.004, -0.014, 0), dist=0.42, elev=20, azim=-44, lens_mm=50), modes)
