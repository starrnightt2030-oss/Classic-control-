"""Thermal overload relay (mounts directly under the contactor). X width, Y depth (front -Y), Z height. mm."""
import sys, math
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

POLES = [-16.5, -5.5, 5.5]

PARTS = {
    "front_cover":   ("الغطاء الأمامي ولوحة الضبط", "Front cover & setting panel", (0, -70, 0)),
    "setting_dial":  ("قرص ضبط التيار", "Current-setting dial", (0, -48, 22), (-12, -33, 9)),
    "test_button":   ("زرار الاختبار TEST", "TEST button", (0, -55, 42), (0, -32, 17)),
    "reset_button":  ("زرار إعادة الضبط RESET", "RESET button (H/A)", (18, -55, 30), (0, -32, 8)),
    "trip_flag":     ("مبين الفصل", "Trip indicator flag", (30, -40, 12), (0, -29, 1)),
    "contactor_pins": ("أصابع التوصيل بالكونتاكتور", "Contactor connection pins", (0, 0, 34)),
    "bimetal_heaters": ("البايميتال وملفات التسخين", "Bimetal strips & heaters", (0, -20, -12)),
    "differential":  ("مسطرة الفرق (حماية فقد الفاز)", "Differential trip slides", (0, -12, 40)),
    "compensation":  ("بايميتال تعويض الحرارة", "Ambient-compensation bimetal", (72, -14, 2)),
    "trip_mechanism": ("آلية الفصل والسوستة", "Trip latch & snap spring", (78, -30, 34)),
    "aux_contacts":  ("النقط المساعدة المفتوحة والمقفولة", "Aux contacts 95-96 (NC) / 97-98 (NO)", (66, -46, -30)),
    "base_housing":  ("الجسم وترامل الخروج", "Housing & load terminals", (0, 62, -8)),
}


def build(M):
    body = lib.mat("ol_body", (0.70, 0.70, 0.68), rough=0.5, bump=0.2)
    panel = lib.mat("ol_panel", (0.20, 0.21, 0.23), rough=0.45, bump=0.15)
    blue = lib.mat("ol_blue", (0.02, 0.10, 0.45), rough=0.35, coat=0.4)
    red = M["red"]
    orange = lib.mat("flag_orange", (0.9, 0.25, 0.0), rough=0.4)
    green = lib.mat("flag_green", (0.02, 0.35, 0.06), rough=0.4)
    copper = lib.mat("copper_ol", (0.93, 0.52, 0.36), metal=1.0, rough=0.22)
    steelb = lib.mat("bimetal_steel", (0.55, 0.56, 0.58), metal=1.0, rough=0.35)
    brassb = lib.mat("bimetal_brass", (0.78, 0.62, 0.30), metal=1.0, rough=0.3)
    plastic_y = lib.mat("slide_plastic", (0.75, 0.55, 0.12), rough=0.45)
    white = M["print_white"]
    steel = lib.mat("spring_steel_ol", (0.72, 0.72, 0.74), metal=1.0, rough=0.3)
    silver = lib.mat("silver_ol", (0.93, 0.93, 0.95), metal=1.0, rough=0.18)

    # ---------- base housing (+ load terminals 2/T1 4/T2 6/T3)
    base = B(-22.5, 22.5, -22, 36, -26, 25, body, "base_housing", bw=1.2)
    cut(base, cbox(-19, 19, -18, 32, -2, 22))                     # cavity for the mechanism
    for x in POLES:
        cut(base, ccyl(4.2, -27, -16, x, -15))
        screw(x, -16, -15, "-Y", M, ["2_T1", "4_T2", "6_T3"][POLES.index(x)], "base_housing")
    for x, lab in zip(POLES, ["2/T1", "4/T2", "6/T3"]):
        T(lab, x, -22.06, -22.5, 2.4, lib.mat("ol_print_dark", (0.03, 0.03, 0.05), rough=0.6), "base_housing")
    for x in (-11, 0):
        B(x - 0.8, x + 0.8, -25, -21.5, -26, -6, body, "base_housing", bw=0.3)  # barriers
    B(-12, 12, 30, 38, -30, -24, body, "base_housing", bw=0.8)                 # rear support foot

    # ---------- front cover with setting panel and aux terminals
    cov = B(-22.5, 22.5, -30, -22, -5, 25, body, "front_cover", bw=1.0)
    cut(cov, ccyl(7.6, -32, -20, -12, 9))                     # dial opening
    cut(cov, cbox(-3.2, 3.2, -32, -20, 15, 19.2))             # test opening
    cut(cov, cbox(-3.6, 3.6, -32, -20, 4.3, 11.7))            # reset opening
    cut(cov, cbox(-2.5, 2.5, -32, -27, -0.8, 2.8))            # flag window
    B(-21, 5, -30.35, -29.9, -4, 23.5, panel, "front_cover", bw=0.2)
    for x, z, lab in ((10, 17, "97"), (18, 17, "98"), (10, 3, "95"), (18, 3, "96")):
        cut(cov, ccyl(3.2, -32, -25.5, x, z))
        screw(x, -25.5, z, "-Y", M, lab, "front_cover", scale=0.8)
        T(lab, x, -30.06, z + (5.0 if z > 10 else -5.0), 2.2, lib.mat("ol_print_dark2", (0.03, 0.03, 0.05), rough=0.6), "front_cover")
    T("NO", 14, -30.06, 21.3 + 1.2, 1.6, lib.mat("ol_print_dark3", (0.03, 0.03, 0.05), rough=0.6), "front_cover")
    T("NC", 14, -30.06, -3.0, 1.6, lib.mat("ol_print_dark4", (0.03, 0.03, 0.05), rough=0.6), "front_cover")
    # dial scale (setting range 7-10 A)
    for i, v in enumerate(["7", "8", "9", "10"]):
        a = math.radians(210 - i * 80)
        T(v, -12 + 10.6 * math.cos(a), -30.45, 9 + 10.6 * math.sin(a), 2.2, white, "front_cover")
    T("A", -19.5, -30.45, 20.5, 2.4, white, "front_cover")
    T("TEST", 0, -30.45, 21.4, 1.6, white, "front_cover")
    T("RESET", 0, -30.45, 13.2, 1.4, white, "front_cover")
    T(lib.BRAND, -21, -30.45, -2.3, 1.7, white, "front_cover", align="LEFT")
    T("EOL-D10", 22, -22.06, -3.0, 1.6, lib.mat("ol_print_dark5", (0.03, 0.03, 0.05), rough=0.6), "front_cover", align="RIGHT")

    # ---------- controls
    CYL(7.2, -33.5, -26, -12, 9, blue, "setting_dial", bw=0.8, verts=64)
    B(-12.6, -11.4, -33.8, -33.2, 4, 14, white, "setting_dial", bw=0.2)          # pointer slot line
    CYL(4.0, -26, -8, -12, 9, plastic_y, "setting_dial", bw=0.3)                 # shaft
    CYL(6.0, -8, -5, -10.5, 9, plastic_y, "setting_dial", bw=0.3)                # eccentric cam
    B(-3.0, 3.0, -32.5, -18, 15.2, 19.0, red, "test_button", bw=0.8)
    B(-3.4, 3.4, -33.0, -16, 4.5, 11.5, blue, "reset_button", bw=1.0)
    T("R", 0, -33.06, 8.0, 3.0, white, "reset_button")
    B(-2.3, 2.3, -28.5, -27.6, -0.6, 2.6, green, "trip_flag", bw=0.2)            # green = normal
    B(-0.6, 0.6, -27.6, -14, 0.4, 1.6, panel, "trip_flag", bw=0.1)

    # ---------- pins (copper rods that plug into contactor terminals 2/T1 4/T2 6/T3)
    for x in POLES:
        CYL(1.7, 18, 46, x, -15, copper, "contactor_pins", axis="Z", bw=0.4, verts=24)
        B(x - 2.5, x + 2.5, -16.5, -8, 16, 19, copper, "contactor_pins", bw=0.3)

    # ---------- bimetals with heater windings (one per pole)
    for x in POLES:
        B(x - 2.2, x + 2.2, 4.0, 4.9, -10, 17, steelb, "bimetal_heaters", bw=0.15)
        B(x - 2.2, x + 2.2, 4.9, 5.8, -10, 17, brassb, "bimetal_heaters", bw=0.15)
        helix("bimetal_heaters", (x, 4.9, 3), 16, 3.4, 9, 0.45, copper, axis="Z")
        B(x - 2.0, x + 2.0, -8, 4, -12, -9, copper, "bimetal_heaters", bw=0.3)         # link to load terminal
        B(x - 2.0, x + 2.0, -8, 4, 15.5, 18, copper, "bimetal_heaters", bw=0.3)        # link from pin

    # ---------- differential slides (upper/lower) — detect overload AND phase loss
    B(-21, 12, 6.2, 7.6, 18.5, 20.0, plastic_y, "differential", bw=0.3)
    B(-21, 12, 6.2, 7.6, 15.6, 17.1, plastic_y, "differential", bw=0.3)
    for x in POLES:
        B(x - 0.7, x + 0.7, 5.8, 7.6, 17.1, 18.5, plastic_y, "differential", bw=0.1)

    # ---------- ambient compensation bimetal + adjusting lever
    B(13, 15, 4.0, 4.9, -4, 20, steelb, "compensation", bw=0.15)
    B(13, 15, 4.9, 5.8, -4, 20, brassb, "compensation", bw=0.15)
    B(11, 16, 4, 10, 19, 21, plastic_y, "compensation", bw=0.3)

    # ---------- trip latch + snap spring
    B(14, 18, 8, 12, 4, 20, plastic_y, "trip_mechanism", bw=0.4)
    B(12, 19, 8, 9.5, 19, 22, steel, "trip_mechanism", bw=0.2)
    helix("trip_mechanism", (16, 13.5, 12), 9, 1.4, 6, 0.3, steel, axis="Z")

    # ---------- aux contacts (NC 95-96, NO 97-98)
    for z, kind in ((3, "NC"), (17, "NO")):
        B(8, 20, -20, -18.8, z - 1.5, z + 1.5, copper, "aux_contacts", bw=0.25)
        for x in (10, 18):
            CYL(1.1, -18.8, -18.2, x, z, silver, "aux_contacts", bw=0.15)
        helix("aux_contacts", (14, -16, z), 4, 1.2, 4, 0.22, steel)


def post(parts):
    pass


if __name__ == "__main__":
    import overload
    modes = sys.argv[1].split(",") if len(sys.argv) > 1 else ["assembled", "exploded"]
    kit.run("overload", overload,
            dict(target=(0, -0.006, 0.004), dist=0.21, elev=16, azim=-32, lens_mm=60),
            dict(target=(0.008, -0.020, 0.006), dist=0.52, elev=20, azim=-44, lens_mm=50), modes)
