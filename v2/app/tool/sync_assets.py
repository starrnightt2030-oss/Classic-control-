"""Copy the shared v2 assets into the Flutter app before building.

    python tool/sync_assets.py

Sources (single source of truth, not duplicated in git):
  ../assets/models/*.glb      -> assets/models/
  ../content/*.json           -> assets/content/
  ../assets/audio/sfx/*.mp3   -> assets/audio/sfx/
  ../assets/audio/<comp>/*.mp3 (narration, when recorded) -> assets/audio/<comp>/
Also writes the narration folders into pubspec.yaml (Flutter needs every asset
folder listed) between the '# >>> audio' / '# <<< audio' markers.
"""
import pathlib
import re
import shutil

APP = pathlib.Path(__file__).resolve().parent.parent
V2 = APP.parent


def copy_glob(src_dir: pathlib.Path, pattern: str, dst_dir: pathlib.Path) -> int:
    dst_dir.mkdir(parents=True, exist_ok=True)
    n = 0
    for f in sorted(src_dir.glob(pattern)):
        shutil.copy2(f, dst_dir / f.name)
        n += 1
    return n


def main() -> None:
    print("models :", copy_glob(V2 / "assets/models", "*.glb", APP / "assets/models"))
    print("content:", copy_glob(V2 / "content", "*.json", APP / "assets/content"))
    print("sfx    :", copy_glob(V2 / "assets/audio/sfx", "*.mp3", APP / "assets/audio/sfx"))

    voice_dirs = []
    audio_root = V2 / "assets/audio"
    for d in sorted(p for p in audio_root.iterdir() if p.is_dir() and p.name != "sfx"):
        n = copy_glob(d, "*.mp3", APP / "assets/audio" / d.name)
        if n:
            voice_dirs.append(d.name)
            print(f"voice  : {d.name} ({n})")

    pub = APP / "pubspec.yaml"
    text = pub.read_text(encoding="utf-8")
    block = "    # >>> audio\n" + "".join(f"    - assets/audio/{d}/\n" for d in voice_dirs) + "    # <<< audio\n"
    if "# >>> audio" in text:
        text = re.sub(r"    # >>> audio\n.*?    # <<< audio\n", block, text, flags=re.S)
    else:
        text = text.replace("    - assets/audio/sfx/\n", "    - assets/audio/sfx/\n" + block)
    pub.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
