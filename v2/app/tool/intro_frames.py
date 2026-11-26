"""Pack the rendered 3D intro frames (v2/models/intro3d.py) into the animated WebP the
app plays (lib/ui/intro_page.dart, IntroFilm): 24 frames a second, square.

    python3 tool/intro_frames.py [--size 720] [--quality 78]
"""
import glob
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "models", "out", "intro3d")
OUT = os.path.join(HERE, "..", "assets", "intro", "intro3d.webp")


def main():
    a = sys.argv[1:]
    size = int(a[a.index("--size") + 1]) if "--size" in a else 720
    q = int(a[a.index("--quality") + 1]) if "--quality" in a else 78
    files = sorted(glob.glob(os.path.join(SRC, "f_*.png")))
    if not files:
        sys.exit("no frames in " + SRC)
    frames = [Image.open(f).convert("RGB").resize((size, size), Image.LANCZOS) for f in files]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    frames[0].save(OUT, save_all=True, append_images=frames[1:], duration=round(1000 / 24), loop=1, quality=q, method=5)
    print(len(frames), "frames →", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
