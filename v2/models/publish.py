"""Copy finished outputs from models/out to assets/: GLB as-is, renders converted to JPG.
Usage: python publish.py rccb mpcb ...   (component names = output file prefixes)"""
import os, sys, glob, shutil
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
A = os.path.join(HERE, "..", "assets")

for name in sys.argv[1:]:
    for f in glob.glob(os.path.join(OUT, name + "*.glb")):
        shutil.copy(f, os.path.join(A, "models"))
        print("glb  ", os.path.basename(f))
    for f in glob.glob(os.path.join(OUT, name + "*_assembled.png")) + glob.glob(os.path.join(OUT, name + "*_labeled.jpg")):
        dst = os.path.join(A, "renders", os.path.splitext(os.path.basename(f))[0] + ".jpg")
        Image.open(f).convert("RGB").save(dst, quality=88)
        print("img  ", os.path.basename(dst))
