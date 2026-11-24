"""Residual current circuit breaker (RCCB, IEC 61008-1), 2-pole, 2 modules (36 mm). mm; front -Y."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

W2 = 35.6
XL, XN = -8.8, 8.8   # phase pole (left), neutral pole (right)

PARTS = {
    "housing_left":  ("نص الجسم الشمال", "Housing half (left)", (-46, 0, 0)),
    "housing_right": ("نص الجسم اليمين والطباعة", "Housing half (right) & markings", (46, 0, 0)),
    "handle":        ("ذراع التشغيل", "Operating handle", (0, -44, -8), (XL, -32, -3)),
    "test_button":   ("زرار الاختبار T", "TEST button", (0, -50, 30), (XL, -37, 16)),
    "test_resistor": ("مقاومة دايرة الاختبار", "Test-circuit resistor", (-30, -24, 36)),
    "toroid":        ("محول التيار الحلقي", "Toroidal core (residual-current transformer)", (0, -6, -36), (0, 8, -15)),
    "trip_relay":    ("ريلاي الفصل المستقطب", "Polarised trip relay", (40, -20, 24)),
    "mechanism":     ("آلية الفصل والماسك", "Latch mechanism", (0, -28, 0), (0, -12, 0)),
    "contacts":      ("النقط الرئيسية (فاز ونيوترال)", "Main contacts (L & N)", (0, 26, 26)),
    "line_terminals": ("ترامل الدخول", "Line terminals", (0, 0, 36)),
    "load_terminals": ("ترامل الخروج", "Load terminals", (0, 0, -40)),
}


def build(M):
    body = lib.mat("rc_body", (0.80, 0.80, 0.78), rough=0.45, bump=0.25)
    blue = lib.mat("rc_blue", (0.01, 0.12, 0.55), rough=0.35, coat=0.3)
    orange = lib.mat("rc_orange", (0.95, 0.30, 0.02), rough=0.35, coat=0.3)
    ink = lib.mat("rc_ink", (0.03, 0.03, 0.04), rough=0.6)
    copper = lib.mat("rc_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22)
    silver = lib.mat("rc_ag", (0.93, 0.93, 0.95), metal=1.0, rough=0.18)
    steel = lib.mat("rc_steel", (0.62, 0.63, 0.65), metal=1.0, rough=0.32)
    ferrite = lib.mat("rc_core", (0.10, 0.10, 0.11), metal=0.6, rough=0.4)
    enamel = kit.striped("rc_wire", (0.70, 0.32, 0.12), 1.0, 0.25, "Z", 1600.0, 0.4)
    mech = lib.mat("rc_mech", (0.08, 0.08, 0.09), rough=0.45)
    beige = lib.mat("rc_res", (0.80, 0.68, 0.45), rough=0.5)
    grey = lib.mat("rc_window", (0.55, 0.56, 0.58), rough=0.3)

    # ---------- housing halves (split at x=0), classic modular profile
    for g, x0, x1, inner in (("housing_left", -W2 / 2 + 0.05, 0, (-16.0, 0.1)), ("housing_right", 0, W2 / 2 - 0.05, (-0.1, 16.0))):
        for (y0, y1, z0, z1, cy0, cy1, cz0, cz1) in ((-6, 36.5, -45, 45, -6.2, 34.7, -43.2, 43.2),
                                                       (-14, -6, -45, 45, -12.2, -5.8, -43.2, 43.2),
                                                       (-36.5, -14, -22.5, 22.5, -34.7, -13.8, -20.7, 20.7)):
            o = B(x0, x1, y0, y1, z0, z1, body, g, bw=1.0)
            cut(o, cbox(inner[0], inner[1], cy0, cy1, cz0, cz1))
            for x in (XL, XN):
                for z in (33, -33):
                    cut(o, ccyl(3.4, -16, -4, x, z))
                for z in (46, -46):
                    cut(o, cbox(x - 4.5, x + 4.5, -10, 2, z - 5, z + 5))
            cut(o, cbox(XL - 5.4, XL + 5.4, -38, -30, -19.5, 4.5))     # handle slot
            cut(o, cbox(XL - 4.2, XL + 4.2, -38, -30, 11.8, 20.2))     # test button opening
            cut(o, cbox(XN - 3.0, XN + 3.0, -38, -34, 1.0, 4.0))       # indicator window
    # prints (right half)
    for txt, z, s in (("ERC1-63", 18.5, 2.0), ("63A", 13.6, 3.6), ("IΔn 0.03A", 8.6, 1.8), ("230V~", -2.6, 1.6),
                      ("t < 0.1s", -5.8, 1.5), ("IEC 61008-1", -15.0, 1.3)):
        T(txt, XN + 0.6, -36.56, z, s, ink, "housing_right")
    T("TEST", XL, -36.56, 21.3, 1.3, ink, "housing_left")
    T(lib.BRAND, XN + 0.6, -36.56, -20.2, 1.5, blue, "housing_right")
    B(XN - 2.8, XN + 2.8, -35.0, -34.2, 1.2, 3.8, grey, "mechanism", bw=0.1)          # indicator flag
    # terminal labels on shoulders
    for x, top, bot in ((XL, "1", "2"), (XN, "N", "N")):
        T(top, x + 5.6, -14.06, 39.5, 2.0, ink, "housing_right" if x > 0 else "housing_left")
        T(bot, x + 5.6, -14.06, -39.5, 2.0, ink, "housing_right" if x > 0 else "housing_left")

    # ---------- handle (blue) + tie to neutral pole inside
    hb = B(XL - 5.0, XL + 5.0, -40.5, -27.5, -8.0, 3.5, blue, "handle", bw=1.2)
    hb.rotation_euler = (math.radians(-14), 0, 0)
    T("O-OFF", XL, -40.66, -1.6, 1.4, M["print_white"], "handle").rotation_euler = (math.radians(76), 0, 0)
    CYL(2.2, -27.5, -18, XL, -8, mech, "handle", bw=0.3)
    # ---------- test button + resistor
    B(XL - 4.0, XL + 4.0, -37.6, -26, 12.0, 20.0, orange, "test_button", bw=0.9)
    T("T", XL, -37.66, 16.0, 4.2, M["print_white"], "test_button")
    helix("test_button", (XL, -22, 16), 6, 1.6, 4, 0.3, steel, axis="Y")
    CYL(1.6, -12, -2, -12, 26, beige, "test_resistor", axis="X", bw=0.4)
    for sx in (-14, -2):
        CYL(0.35, sx - 3, sx + 0.1, -7, 26, steel, "test_resistor", axis="X", bw=0.05, verts=12)
    # ---------- mechanism
    B(-14, 14, -20, -4, -10, 8, mech, "mechanism", bw=0.6)
    helix("mechanism", (6, -12, 12), 9, 1.6, 7, 0.32, steel, axis="Z")
    # ---------- toroidal core: both conductors pass through it
    tor = lib.torus(0.0095, 0.0036, 0, ferrite)
    tor.location = (0, 0.008, -0.015)
    kit.G["toroid"].append(tor)
    for k in range(22):                                              # secondary winding (sense coil)
        a = math.radians(200 + k * 6.4)
        o = lib.torus(0.0039, 0.00045, 0, enamel)
        o.rotation_euler = (math.radians(90), 0, a + math.pi / 2)
        o.location = (0.0095 * math.cos(a), 0.008 + 0.0095 * math.sin(a), -0.015)
        kit.G["toroid"].append(o)
    for x in (-4, 4):                                                # primary conductors (L and N)
        B(x - 1.4, x + 1.4, 7, 9, -30, 4, copper, "toroid", bw=0.3)
    # ---------- polarised trip relay (permanent magnet + coil + plunger)
    CYL(5.0, -2, 14, 11, 16, mech, "trip_relay", bw=0.6)
    CYL(5.1, 8, 11, 11, 16, enamel, "trip_relay", bw=0.4)
    CYL(1.4, -9, -2, 11, 16, steel, "trip_relay", bw=0.2)
    for x in (9, 13):
        CYL(0.3, -2, 2, x, 9, copper, "trip_relay", axis="Z", bw=0.05, verts=10)
    # ---------- main contacts (L and N)
    for x in (XL, XN):
        B(x - 2, x + 2, 18, 21, 4, 17, copper, "contacts", bw=0.3)
        CYL(1.8, 17.2, 18.2, x, 6, silver, "contacts", bw=0.2)
        B(x - 1.6, x + 1.6, 9, 16.8, -9, 7.5, copper, "contacts", bw=0.3)
        CYL(1.8, 16.3, 17.2, x, 6, silver, "contacts", bw=0.2)
    # ---------- terminals
    for zc, g in ((33, "line_terminals"), (-33, "load_terminals")):
        for x, lab in ((XL, "1" if zc > 0 else "2"), (XN, "N" if zc > 0 else "N2")):
            o = B(x - 4.6, x + 4.6, -8, 3, zc - 4.6, zc + 4.6, M["zinc"], g, bw=0.4)
            cut(o, cbox(x - 3.6, x + 3.6, -6.5, 1.5, zc - 7, zc + 7))
            screw(x, -9.0, zc, "-Y", M, lab, g, scale=0.9)


if __name__ == "__main__":
    import rccb
    modes = sys.argv[1].split(",") if len(sys.argv) > 1 else ["assembled", "exploded"]
    kit.run("rccb", rccb,
            dict(target=(0, -0.008, 0), dist=0.26, elev=14, azim=-28, lens_mm=60),
            dict(target=(0, -0.004, 0), dist=0.58, elev=16, azim=-54, lens_mm=50), modes)
