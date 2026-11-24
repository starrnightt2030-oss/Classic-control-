"""Generic DIN-rail modular housing (EN 60715, 35 mm rail) used by electronic relays, meters, timers, fuse holders.
Profile: rear body (y 0..+depth_back), shoulders (y shoulder_y..0) full height, front escutcheon (y front_y..shoulder_y) 45 mm high."""
import kit, lib
from kit import B, CYL, T, cbox, ccyl, cut, screw

MOD = 17.6


def housing(M, g, n=1, color=(0.82, 0.82, 0.80), front_y=-30.0, shoulder_y=-12.0, back_y=34.0, H=90.0,
            top=(), bot=(), ink=None, top_z=None, two_rows=False):
    """top/bot: list of terminal labels (spread across width). Returns (width, materials)."""
    W = MOD * n - 0.2
    body = lib.mat(f"din_{g}_body", color, rough=0.45, bump=0.25)
    ink = ink or lib.mat(f"din_{g}_ink", (0.03, 0.03, 0.04), rough=0.6)
    h2 = H / 2
    B(-W / 2, W / 2, 0, back_y, -h2, h2, body, g, bw=1.0)
    sh = B(-W / 2, W / 2, shoulder_y, 0.2, -h2, h2, body, g, bw=1.0)
    B(-W / 2, W / 2, front_y, shoulder_y + 0.2, -22.5, 22.5, body, g, bw=1.2)
    B(-W / 2, W / 2, back_y - 2, back_y, 17.5, 21, body, g, bw=0.3)          # rail hook
    B(-4, 4, back_y - 6, back_y, -h2 - 4, -h2 + 2, body, g, bw=0.5)          # clip
    zt = top_z if top_z is not None else h2 - 11
    for labels, z, sgn in ((top, zt, 1), (bot, -zt, -1)):
        k = len(labels)
        for i, lab in enumerate(labels):
            x = (i - (k - 1) / 2) * (W / max(k, 1))
            cut(sh, ccyl(3.0, shoulder_y - 2, shoulder_y + 5, x, z))
            screw(x, shoulder_y + 4.5, z, "-Y", M, lab, g, scale=0.7)
            T(lab, x, shoulder_y - 0.06, z + sgn * 6.0, 2.0, ink, g)
    return W, body, ink
