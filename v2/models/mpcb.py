"""Motor protection circuit breaker (MPCB, IEC 60947-2 / -4-1), rotary handle, 3 poles. mm; front -Y."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, helix, screw

POLES = [-14.5, 0.0, 14.5]

PARTS = {
    "front_cover":   ("الغطاء الأمامي والترامل", "Front cover & terminals", (0, -78, 0)),
    "rotary_knob":   ("المقبض الدوار I / O", "Rotary handle (I / O)", (0, -112, 0)),
    "setting_dial":  ("قرص ضبط تيار الموتور", "Motor-current setting dial", (-34, -96, 26), (-12, -37, 17)),
    "test_pusher":   ("ذراع الاختبار Test", "Test pusher", (34, -96, 26), (12, -37, 17)),
    "mechanism":     ("الآلية الدوارة وسوستة الطقة", "Rotary toggle mechanism", (0, -48, 0)),
    "trip_bar":      ("مسطرة الفصل المشتركة", "Common trip bar (differential)", (0, -24, 46)),
    "bimetals":      ("البايميتال (حماية زيادة الحمل)", "Bimetals (thermal overload)", (0, -10, 30)),
    "magnetic":      ("الملفات المغناطيسية (حماية القصر)", "Magnetic trip coils (short-circuit)", (0, -12, -14), (0, 10, -6)),
    "contacts":      ("النقط والكباري (فتح مزدوج)", "Contacts & bridges (double break)", (0, 20, -40)),
    "arc_chambers":  ("غرف إطفاء الشرارة", "Arc chambers", (0, 48, -56)),
    "base":          ("القاعدة وكلبس الدين ريل", "Base & DIN-rail clip", (0, 80, 0)),
}


def build(M):
    body = lib.mat("mp_body", (0.80, 0.80, 0.78), rough=0.45, bump=0.25)
    dark = lib.mat("mp_dark", (0.05, 0.052, 0.056), rough=0.45, bump=0.2)
    ink = lib.mat("mp_ink", (0.03, 0.03, 0.04), rough=0.6)
    red = lib.mat("mp_red", (0.6, 0.02, 0.02), rough=0.4)
    white = M["print_white"]
    copper = lib.mat("mp_cu", (0.93, 0.52, 0.36), metal=1.0, rough=0.22)
    silver = lib.mat("mp_ag", (0.93, 0.93, 0.95), metal=1.0, rough=0.18)
    steel = lib.mat("mp_steel", (0.62, 0.63, 0.65), metal=1.0, rough=0.32)
    steelb = lib.mat("mp_bi_a", (0.55, 0.56, 0.58), metal=1.0, rough=0.35)
    brassb = lib.mat("mp_bi_b", (0.78, 0.62, 0.30), metal=1.0, rough=0.3)
    mech = lib.mat("mp_mech", (0.62, 0.62, 0.60), rough=0.4)
    yellow = lib.mat("mp_slide", (0.75, 0.55, 0.12), rough=0.45)

    # ---------- base (rear) + DIN clip
    base = B(-22.5, 22.5, -10, 45, -44.5, 44.5, body, "base", bw=1.2)
    cut(base, cbox(-19.5, 19.5, -11, 42, -41.5, 41.5))
    B(-7, 7, 38, 45, -49, -43, body, "base", bw=0.6)
    B(-22.5, 22.5, 43, 45, 17.5, 20.5, body, "base", bw=0.3)
    # ---------- front cover (stepped: terminal tiers + central face)
    top = B(-22.5, 22.5, -25, -10, 24, 44.5, body, "front_cover", bw=1.0)
    bot = B(-22.5, 22.5, -25, -10, -44.5, -24, body, "front_cover", bw=1.0)
    mid = B(-22.5, 22.5, -35, -10, -24, 24, body, "front_cover", bw=1.2)
    cut(mid, ccyl(13.6, -37, -30, 0, -2, verts=96))                  # knob recess
    cut(mid, ccyl(5.4, -37, -32, -12, 17))                           # dial recess
    cut(mid, cbox(9.5, 14.5, -37, -32, 15.5, 18.5))                  # test slot
    labels_top = ["1/L1", "3/L2", "5/L3"]
    labels_bot = ["2/T1", "4/T2", "6/T3"]
    for x, lt, lb in zip(POLES, labels_top, labels_bot):
        cut(top, ccyl(4.2, -27, -18, x, 34))
        cut(bot, ccyl(4.2, -27, -18, x, -34))
        screw(x, -18.5, 34, "-Y", M, lt.replace("/", "_"), "front_cover")
        screw(x, -18.5, -34, "-Y", M, lb.replace("/", "_"), "front_cover")
        T(lt, x, -25.06, 41.6, 2.2, ink, "front_cover")
        T(lb, x, -25.06, -41.6, 2.2, ink, "front_cover")
    for x in (-7.25, 7.25):
        B(x - 0.7, x + 0.7, -28, -24.5, 25, 44.5, body, "front_cover", bw=0.3)
        B(x - 0.7, x + 0.7, -28, -24.5, -44.5, -25, body, "front_cover", bw=0.3)
    # prints on central face
    T(lib.BRAND, -21, -35.06, 21.6, 1.8, ink, "front_cover", align="LEFT")
    T("EMS2-25", 21, -35.06, 21.6, 1.8, ink, "front_cover", align="RIGHT")
    T("20-25A", -12, -35.06, 9.6, 1.9, ink, "front_cover")
    T("Test", 12, -35.06, 13.4, 1.5, red, "front_cover")
    T("I", 0, -35.06, 14.0, 2.6, ink, "front_cover")
    T("O", -14.5, -35.06, -2.0, 2.6, ink, "front_cover")
    T("Trip", 15.2, -35.06, 6.0, 1.5, ink, "front_cover")
    T("Ie: 0.1-32A  Icu 50kA@400V", 0, -35.06, -21.2, 1.25, ink, "front_cover")
    # ---------- rotary knob (shown ON = vertical)
    CYL(12.6, -41, -33, 0, -2, dark, "rotary_knob", bw=1.4, verts=96)
    B(-4.2, 4.2, -47, -40, -15.5, 11.5, dark, "rotary_knob", bw=1.8)
    B(-0.6, 0.6, -47.1, -46.8, 3, 10, white, "rotary_knob", bw=0.1)
    CYL(3.0, -33, -14, 0, -2, mech, "rotary_knob", bw=0.3)
    # ---------- setting dial (blue scale ring)
    CYL(5.0, -37.5, -31, -12, 17, lib.mat("mp_dial", (0.02, 0.10, 0.45), rough=0.35), "setting_dial", bw=0.5)
    B(-12.4, -11.6, -37.7, -37.3, 14, 20, white, "setting_dial", bw=0.1)
    CYL(2.0, -31, -8, -12, 17, yellow, "setting_dial", bw=0.2)
    CYL(4.0, -8, -5.5, -11, 17, yellow, "setting_dial", bw=0.2)                 # eccentric cam
    for v, a in (("20", 210), ("22", 150), ("25", 90)):
        r = math.radians(a)
        T(v, -12 + 7.6 * math.cos(r), -35.06, 17 + 7.6 * math.sin(r), 1.6, ink, "setting_dial")
    # ---------- test pusher
    B(10.0, 14.0, -36, -16, 15.8, 18.2, red, "test_pusher", bw=0.4)
    # ---------- rotary toggle mechanism
    CYL(9.0, -14, -8, 0, -2, mech, "mechanism", bw=0.6)
    B(-12, 12, -10, 2, -14, 10, mech, "mechanism", bw=0.6)
    helix("mechanism", (8, -4, 12), 9, 1.8, 7, 0.4, steel, axis="Z")
    helix("mechanism", (-8, -4, 12), 9, 1.8, 7, 0.4, steel, axis="Z")
    # ---------- per pole: bimetal+heater, magnetic coil, contacts, arc chamber
    for x in POLES:
        B(x - 2.4, x + 2.4, 18.0, 19.0, 4, 26, steelb, "bimetals", bw=0.15)
        B(x - 2.4, x + 2.4, 19.0, 20.0, 4, 26, brassb, "bimetals", bw=0.15)
        helix("bimetals", (x, 19, 14), 18, 3.6, 8, 0.5, copper, axis="Z")
        CYL(3.0, 4, 16, x, -6, mech, "magnetic", bw=0.3)
        helix("magnetic", (x, 10, -6), 11, 4.0, 6, 0.8, copper, axis="Y")
        CYL(1.8, -2, 18, x, -6, steel, "magnetic", bw=0.2)
        # double-break bridge + fixed contacts
        B(x - 2.4, x + 2.4, 27, 28.4, -27, -13, copper, "contacts", bw=0.3)
        for z in (-15, -25):
            CYL(1.6, 28.4, 29.2, x, z, silver, "contacts", bw=0.15)
            B(x - 2.2, x + 2.2, 30.0, 31.4, z - 3, z + 3, copper, "contacts", bw=0.3)
            CYL(1.6, 29.2, 30.0, x, z, silver, "contacts", bw=0.15)
        helix("contacts", (x, 24.5, -20), 5, 1.7, 4, 0.35, steel, axis="Y")
        for k in range(7):
            B(x - 5.6, x + 5.6, 32 + k * 1.4, 32.5 + k * 1.4, -31, -9, steel, "arc_chambers", bw=0.08)
        B(x - 6.3, x - 5.6, 31.5, 42, -31, -9, dark, "arc_chambers", bw=0.1)
        B(x + 5.6, x + 6.3, 31.5, 42, -31, -9, dark, "arc_chambers", bw=0.1)
    # common trip bar (two slides) across bimetal tips
    B(-20, 20, 20.5, 22, 26.5, 28, yellow, "trip_bar", bw=0.3)
    B(-20, 20, 20.5, 22, 29, 30.5, yellow, "trip_bar", bw=0.3)


if __name__ == "__main__":
    import mpcb
    modes = sys.argv[1].split(",") if len(sys.argv) > 1 else ["assembled", "exploded"]
    kit.run("mpcb", mpcb,
            dict(target=(0, -0.010, 0), dist=0.27, elev=14, azim=-30, lens_mm=60),
            dict(target=(0, -0.020, -0.004), dist=0.66, elev=18, azim=-50, lens_mm=50), modes)
