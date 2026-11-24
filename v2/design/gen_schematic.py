"""Generate a classic (IEC 60617 / EN 81346) control-circuit schematic as inline SVG
and patch it into the canvas artboards. Vertical current paths between L (top) and N (bottom)."""
import re, pathlib

LIVE, DEAD = "#3FD5E8", "#55636F"


def ln(x1, y1, x2, y2, c, w=2.2, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<path d="M{x1} {y1}L{x2} {y2}" stroke="{c}" stroke-width="{w}" fill="none" stroke-linecap="round"{d}></path>'


def txt(x, y, s, cls="tn", anchor="start"):
    return f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">{s}</text>'


def contact(x, ya, yb, kind, c, tag, t1, t2, act=None, ac=None):
    """kind NO|NC between terminal ends ya (top) and yb (bottom). act: None|push|thermal."""
    ac = ac or c
    o = []
    if kind == "NO":
        o.append(ln(x, yb, x - 10, ya + 3, c))           # open blade
        mx, my = x - 5, (ya + yb) / 2 + 1.5
    else:
        o.append(ln(x, ya, x + 14, ya, c))              # fixed stub
        o.append(ln(x, yb, x + 12, ya - 3, c))          # blade resting across stub
        mx, my = x + 5, (ya + yb) / 2 + 1
    if act:
        ex = x - 26
        o.append(ln(mx, my, ex, my, ac, 1.4, "3 3"))
        if act == "push":   # push-button actuator  E-[
            o.append(f'<path d="M{ex+3} {my-7}H{ex}V{my+7}H{ex+3}" stroke="{ac}" stroke-width="1.8" fill="none" stroke-linecap="round"></path>')
        else:               # thermal (bimetal) actuator
            o.append(f'<path d="M{ex} {my}h-4v-6h-6v12h-6v-6h-2" stroke="{ac}" stroke-width="1.8" fill="none" stroke-linejoin="round"></path>')
    o.append(txt(x - 5, ya + 2, t1, "tn", "end") if not act else txt(x + 4, ya - 5, t1))
    o.append(txt(x - 5, yb + 2, t2, "tn", "end") if not act else txt(x + 4, yb + 12, t2))
    o.append(txt(x + 20, (ya + yb) / 2 + 4, tag, "tg"))
    return "".join(o)


def coil(x, yc, c, tag, fill):
    return (f'<rect x="{x-15}" y="{yc-10}" width="30" height="20" rx="1" fill="{fill}" stroke="{c}" stroke-width="2.2"></rect>'
            + txt(x + 19, yc - 13, "A1") + txt(x + 19, yc + 21, "A2") + txt(x - 20, yc + 4, tag, "tg", "end"))


def lamp(x, yc, c, tag, fill, colour):
    r = 12
    return (f'<circle cx="{x}" cy="{yc}" r="{r}" fill="{fill}" stroke="{c}" stroke-width="2.2"></circle>'
            + ln(x - 8.5, yc - 8.5, x + 8.5, yc + 8.5, c, 1.8) + ln(x + 8.5, yc - 8.5, x - 8.5, yc + 8.5, c, 1.8)
            + txt(x + 17, yc - 12, "X1") + txt(x + 17, yc + 21, "X2") + txt(x - 18, yc + 4, tag, "tg", "end")
            + txt(x - 18, yc + 17, colour, "tn", "end"))


def closed(x, ya, yb, c=LIVE):
    """NO contact shown actuated (closed): blade reaches the upper terminal."""
    return ln(x, yb, x - 5, ya, c) + ln(x - 5, ya, x, ya, c)


def dot(x, y, c):
    return f'<circle cx="{x}" cy="{y}" r="3.2" fill="{c}"></circle>'


def schematic():
    L, N = 52, 452          # rail y
    X0, X1 = 26, 350        # rail x extent
    p1, p2, p3, p4 = 92, 160, 236, 312
    o = ['<rect x="0" y="0" width="368" height="520" fill="none"></rect>']
    # current-path numbers (Strompfad)
    for i, x in enumerate((p1, p3, p4), start=1):
        o.append(txt(x, 18, str(i), "tg", "middle"))
    o.append(ln(X0, 26, X1, 26, "#26323C", 1))
    # rails
    o.append(ln(X0, L, X1, L, LIVE, 2.6)); o.append(txt(X0 - 6, L + 4, "L", "tg", "end"))
    o.append(ln(X0, N, X1, N, LIVE, 2.6)); o.append(txt(X0 - 6, N + 4, "N", "tg", "end"))
    for x in (p1, p3, p4):
        o.append(dot(x, L, LIVE)); o.append(dot(x, N, LIVE))
    # path 1: F2 95-96 -> S0 -> [S1 || KM1 13-14] -> KM1 coil
    o.append(ln(p1, L, p1, 76, LIVE))
    o.append(contact(p1, 76, 106, "NC", LIVE, "-F2", "95", "96", "thermal"))
    o.append(ln(p1, 106, p1, 136, LIVE))
    o.append(contact(p1, 136, 166, "NC", LIVE, "-S0", "11", "12", "push"))
    o.append(ln(p1, 166, p1, 196, LIVE)); o.append(dot(p1, 196, LIVE))
    o.append(contact(p1, 214, 244, "NO", DEAD, "-S1", "13", "14", "push"))
    o.append(ln(p1, 196, p1, 214, LIVE)); o.append(ln(p1, 244, p1, 262, LIVE))
    # seal-in branch
    o.append(ln(p1, 196, p2, 196, LIVE)); o.append(ln(p2, 196, p2, 214, LIVE))
    o.append(closed(p2, 214, 244))                 # KM1 energised -> contact closed
    o.append(txt(p2 - 6, 216, "13", "tn", "end")); o.append(txt(p2 - 6, 246, "14", "tn", "end"))
    o.append(txt(p2 + 10, 233, "-KM1", "tg"))
    o.append(ln(p2, 244, p2, 262, LIVE)); o.append(ln(p2, 262, p1, 262, LIVE)); o.append(dot(p1, 262, LIVE))
    o.append(ln(p1, 262, p1, 330, LIVE))
    o.append(coil(p1, 340, LIVE, "-KM1", "rgba(63,213,232,.16)"))
    o.append(ln(p1, 350, p1, N, LIVE))
    # path 2: KM1 23-24 -> H1 (green, run)
    o.append(ln(p3, L, p3, 170, LIVE))
    o.append(closed(p3, 170, 200))
    o.append(txt(p3 - 8, 172, "23", "tn", "end")); o.append(txt(p3 - 8, 202, "24", "tn", "end")); o.append(txt(p3 + 10, 189, "-KM1", "tg"))
    o.append(ln(p3, 200, p3, 328, LIVE))
    o.append(lamp(p3, 340, "#3DDC84", "-H1", "rgba(61,220,132,.25)", "أخضر"))
    o.append(ln(p3, 352, p3, N, LIVE))
    # path 3: F2 97-98 -> H2 (trip)
    o.append(ln(p4, L, p4, 76, LIVE))
    o.append(contact(p4, 76, 106, "NO", DEAD, "-F2", "97", "98"))
    o.append(ln(p4, 106, p4, 328, DEAD))
    o.append(lamp(p4, 340, DEAD, "-H2", "none", "أصفر"))
    o.append(ln(p4, 352, p4, N, DEAD))
    # contact mirror (cross reference) under KM1
    o.append(ln(p1 - 20, 470, p1 + 20, 470, "#33414C", 1)); o.append(ln(p1, 466, p1, 512, "#33414C", 1))
    o.append(txt(p1 - 4, 484, "1-2", "tn", "end")); o.append(txt(p1 - 4, 496, "3-4", "tn", "end")); o.append(txt(p1 - 4, 508, "5-6", "tn", "end"))
    o.append(txt(p1 + 4, 484, "13-14 ›1")); o.append(txt(p1 + 4, 496, "23-24 ›2"))
    o.append(txt(p1 - 22, 466, "NO", "tn", "end"))
    o.append(txt(360, 492, "النقط الرئيسية في مخطط القوى ›", "tn", "end"))
    return "".join(x for x in o if x)


SVG_BODY = schematic()


def power():
    xs = (122, 172, 222)
    bus = (40, 56, 72)
    PE = 88
    G = "#2BB24C"
    o = ['<rect x="0" y="0" width="368" height="520" fill="none"></rect>']
    for i, (x, y) in enumerate(zip(xs, bus)):
        o.append(ln(20, y, 348, y, LIVE, 2.4)); o.append(txt(14, y + 4, f"L{i+1}", "tg", "end"))
        o.append(dot(x, y, LIVE)); o.append(ln(x, y, x, 112, LIVE))
    o.append(ln(20, PE, 348, PE, G, 2.4)); o.append(ln(20, PE, 348, PE, "#F2D21B", 2.4, "6 6"))
    o.append(txt(14, PE + 4, "PE", "tg", "end"))
    o.append(txt(348, 24, "3~ 400 V 50 Hz", "tn", "end"))
    nums = (("1", "2"), ("3", "4"), ("5", "6"))
    # -Q1 motor protection breaker (closed), x-mark = circuit-breaker function
    for x, (a, b) in zip(xs, nums):
        o.append(closed(x, 112, 142))
        o.append(ln(x - 3.5, 108.5, x + 3.5, 115.5, LIVE, 1.8)); o.append(ln(x + 3.5, 108.5, x - 3.5, 115.5, LIVE, 1.8))
        o.append(txt(x - 8, 116, a, "tn", "end")); o.append(txt(x - 8, 146, b, "tn", "end"))
        o.append(ln(x, 142, x, 192, LIVE))
    o.append(ln(xs[0] - 2.5, 127, xs[2] + 22, 127, LIVE, 1.3, "3 3"))
    o.append(f'<path d="M{xs[2]+22} 121h4v12h-4" stroke="{LIVE}" stroke-width="1.6" fill="none"></path>')
    o.append(txt(xs[2] + 32, 131, "-Q1", "tg"))
    # -KM1 main contacts (closed), half-circle = contactor function
    for x, (a, b) in zip(xs, nums):
        o.append(closed(x, 192, 222))
        o.append(f'<path d="M{x-4} 192a4 4 0 0 0 8 0" stroke="{LIVE}" stroke-width="1.8" fill="none"></path>')
        o.append(txt(x - 8, 196, a, "tn", "end")); o.append(txt(x - 8, 226, b, "tn", "end"))
        o.append(ln(x, 222, x, 266, LIVE))
    o.append(ln(xs[0] - 2.5, 207, xs[2] + 26, 207, LIVE, 1.3, "3 3"))
    o.append(txt(xs[2] + 32, 211, "-KM1", "tg"))
    # -F2 thermal overload heaters
    for x, (a, b) in zip(xs, nums):
        o.append(f'<path d="M{x} 266v7h8v14h-8v9" stroke="{LIVE}" stroke-width="2.2" fill="none" stroke-linejoin="round"></path>')
        o.append(txt(x - 8, 270, a, "tn", "end")); o.append(txt(x - 8, 300, b, "tn", "end"))
    o.append(ln(xs[0] + 8, 280, xs[2] + 26, 280, LIVE, 1.3, "3 3"))
    o.append(txt(xs[2] + 32, 284, "-F2", "tg"))
    # -M1 three-phase motor
    cx, cy, r = 172, 410, 34
    o.append(ln(xs[0], 296, xs[0], 352, LIVE)); o.append(ln(xs[0], 352, cx - 20, cy - 27.5, LIVE))
    o.append(ln(xs[1], 296, xs[1], cy - r, LIVE))
    o.append(ln(xs[2], 296, xs[2], 352, LIVE)); o.append(ln(xs[2], 352, cx + 20, cy - 27.5, LIVE))
    o.append(txt(cx - 30, 362, "U1", "tn", "end")); o.append(txt(cx + 5, 366, "V1")); o.append(txt(cx + 30, 362, "W1"))
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="rgba(63,213,232,.10)" stroke="{LIVE}" stroke-width="2.4"></circle>')
    o.append(f'<text x="{cx}" y="{cy+2}" class="tg" text-anchor="middle" style="font-size: 20px">M</text>')
    o.append(f'<text x="{cx}" y="{cy+20}" class="tg" text-anchor="middle">3~</text>')
    o.append(txt(cx - r - 10, cy + 4, "-M1", "tg", "end"))
    # PE to motor frame
    o.append(dot(300, PE, G)); o.append(ln(300, PE, 300, cy, G)); o.append(ln(300, cy, cx + r, cy, G))
    o.append(ln(300, PE, 300, cy, "#F2D21B", 2.2, "6 6")); o.append(ln(300, cy, cx + r, cy, "#F2D21B", 2.2, "6 6"))
    o.append(txt(304, cy - 6, "PE", "tn"))
    # cross reference
    o.append(txt(20, 480, "-KM1 كويل ‹ مخطط التحكم، مسار 1", "tn"))
    o.append(txt(20, 496, "-F2 95-96 ‹ مخطط التحكم، مسار 1", "tn"))
    return "".join(o)


POWER_BODY = power()


def patch(path, start_marker, end_marker, new):
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    i = s.index(start_marker); j = s.index(end_marker, i) + len(end_marker)
    p.write_text(s[:i] + new + s[j:], encoding="utf-8")


PALETTE = [
    ("نقطة مفتوحة", "NO", '<path d="M14 2v8M14 26v-8M14 18l-6-7"></path>'),
    ("نقطة مقفولة", "NC", '<path d="M14 2v8M14 26v-8M14 10h5M14 18l7-9"></path>'),
    ("ضاغط", "زرار", '<path d="M14 2v8M14 26v-8M14 18l-6-7"></path><path d="M11 14.5H4" stroke-dasharray="2 2"></path><path d="M6 10.5H3.5v8H6"></path>'),
    ("كويل", "كويل", '<path d="M14 2v6M14 26v-6"></path><rect x="7" y="8" width="14" height="12" rx="1"></rect>'),
    ("كويل تايمر تأخير", "تايمر", '<path d="M14 2v6M14 26v-6"></path><rect x="7" y="8" width="14" height="12" rx="1"></rect><rect x="21" y="8" width="5" height="12"></rect><path d="M21 8l5 12M26 8l-5 12"></path>'),
    ("لمبة إشارة", "لمبة", '<path d="M14 2v6M14 26v-6"></path><circle cx="14" cy="14" r="6"></circle><path d="M9.8 9.8l8.4 8.4M18.2 9.8l-8.4 8.4"></path>'),
]


def palette_html():
    btn = ('<button aria-label="{a}" style="flex: 1; height: 62px; border-radius: 12px; border: 1px solid #26323C; background: #131A1F; color: #E8EEF2; '
           'display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; font-size: 10.5px; padding: 0">'
           '<svg class="ic" width="28" height="28" viewBox="0 0 28 28" aria-hidden="true">{p}</svg>{l}</button>')
    items = "\n      ".join(btn.format(a=a, l=l, p=p) for a, l, p in PALETTE)
    return ('<section aria-label="الرموز" style="flex: none; padding: 10px 14px 14px; display: flex; flex-direction: column; gap: 8px">\n'
            '    <span style="font-size: 12px; color: #93A3AF">رموز التحكم — IEC 60617</span>\n'
            '    <div style="display: flex; gap: 6px">\n      ' + items + '\n    </div>\n  </section>')


ARIA = "مخطط تحكم كلاسيك لتشغيل موتور مباشر بزرار تشغيل وزرار إيقاف ونقطة مسك ولمبات بيان"

if __name__ == "__main__":
    P = "project/"
    patch(P + "Ladder.dc.html", '<svg role="img" aria-label="مخطط تحكم كلاسيك', "</svg>",
          f'<svg role="img" aria-label="{ARIA}" viewBox="0 0 368 520" style="position: absolute; top: 10px; left: 0; width: 368px; height: 446px" dir="ltr">{SVG_BODY}</svg>')
    patch(P + "Ladder.dc.html", '<section aria-label="الرموز"', "</section>", palette_html())
    patch(P + "DesktopLab.dc.html", '<svg role="img" aria-label="مخطط تحكم كلاسيك', "</svg>",
          f'<svg role="img" aria-label="{ARIA}" viewBox="0 0 368 520" style="position: absolute; top: 52px; left: 6%; width: 88%; height: auto" dir="ltr">{SVG_BODY}</svg>')
    print("ok", len(SVG_BODY))


# ---------- standalone SVG files for the Flutter app (flutter_svg: no CSS) ----------
def standalone(body: str, label: str) -> str:
    import re as _re
    ar = _re.compile(r"[؀-ۿ]")

    def text_attrs(m):
        cls, rest, content = m.group(1), m.group(2), m.group(3)
        fam = "Cairo" if ar.search(content) else "JetBrainsMono"
        if cls == "tg":
            a = f'font-family="{fam}" font-size="12" font-weight="700" fill="#E8EEF2"'
        else:
            a = f'font-family="{fam}" font-size="{10 if fam == "Cairo" else 9.5}" fill="#93A3AF"'
        rest = rest.replace(' style="font-size: 20px"', ' font-size="20"')
        if 'font-size="20"' in rest:
            a = a.replace('font-size="12"', '')
        return f"<text {a}{rest}>{content}</text>"

    body = _re.sub(r'<text class="(tg|tn)"([^>]*)>(.*?)</text>', lambda m: text_attrs(m), body)
    body = _re.sub(r'<text x="([^"]+)" y="([^"]+)" class="(tg|tn)"([^>]*)>(.*?)</text>',
                   lambda m: text_attrs(type("M", (), {"group": lambda s, i: [None, m.group(3), f' x="{m.group(1)}" y="{m.group(2)}"' + m.group(4), m.group(5)][i]})()), body)

    def rgba(m):
        r, g, b, a = m.group(1).split(",")
        return f'fill="#{int(r):02X}{int(g):02X}{int(b):02X}" fill-opacity="{a.strip()}"'
    body = _re.sub(r'fill="rgba\(([^)]+)\)"', rgba, body)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 368 520" width="368" height="520">'
            f'<title>{label}</title>{body}</svg>')


def write_app_svgs(out_dir: str) -> None:
    p = pathlib.Path(out_dir)
    p.mkdir(parents=True, exist_ok=True)
    (p / "dol_control.svg").write_text(standalone(SVG_BODY, "DOL control circuit"), encoding="utf-8")
    (p / "dol_power.svg").write_text(standalone(POWER_BODY, "DOL power circuit"), encoding="utf-8")
