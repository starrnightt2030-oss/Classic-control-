"""Content-pack manifests for the in-app updater (lib/services/update_service.dart).

    python tool/pack_manifest.py app
        -> assets/pack/manifest.json: sha256 of every lesson, sound, recording and
           3D model bundled in this build, so the app knows what it already has.

    python tool/pack_manifest.py release --build N --sha SHA --repo owner/name --dist DIR --out DIR/update.json
        -> update.json for the release: the build, notes, the APK / Windows downloads
           (and the Windows patch when win_patch.py made one), and every content file
           with its hash, size and path in the repository, so the app downloads only
           what changed straight from the release commit.

Run `app` after tool/sync_assets.py; it reads the same sources.
"""
import argparse
import hashlib
import json
import os
import pathlib

APP = pathlib.Path(__file__).resolve().parent.parent
V2 = APP.parent
ROOT = V2.parent


def sha(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def sources():
    """asset key -> source file, the same mapping as sync_assets.py"""
    out = {}
    for f in sorted((V2 / "content").glob("*.json")):
        out[f"assets/content/{f.name}"] = f
    for f in sorted((V2 / "assets/models").glob("*.glb")):
        out[f"assets/models/{f.name}"] = f
    audio = V2 / "assets/audio"
    for d in sorted(p for p in audio.iterdir() if p.is_dir()):
        for f in sorted(d.glob("*.mp3")):
            out[f"assets/audio/{d.name}/{f.name}"] = f
    return out


def app_manifest() -> None:
    files = {k: sha(f) for k, f in sources().items()}
    dst = APP / "assets/pack/manifest.json"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps({"files": files}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("pack manifest:", len(files), "files ->", dst)


def release(a) -> None:
    dist = pathlib.Path(a.dist)

    def asset(name):
        p = dist / name
        return {"name": name, "size": p.stat().st_size, "sha": sha(p)} if p.exists() else None

    files = {k: {"sha": sha(f), "size": f.stat().st_size, "src": f.relative_to(ROOT).as_posix()} for k, f in sources().items()}
    win = asset("ClassicControl-Windows.zip")
    patch_info = dist / "windows-patch.json"
    if win and patch_info.exists():
        pi = json.loads(patch_info.read_text(encoding="utf-8"))
        p = asset(pi["name"])
        if p:
            p.update({"from": pi["from"], "files": pi["files"]})
            win["patch"] = p
    notes = os.environ.get("NOTES", "").strip()
    # the commit's first paragraph, without trailers
    notes = "\n".join(l for l in notes.split("\n\n")[0].splitlines() if not l.lower().startswith(("co-authored-by", "claude-session")))
    out = {
        "build": a.build,
        "version": a.version,
        "sha": a.sha,
        "repo": a.repo,
        "notes": notes[:600],
        "android": asset("ClassicControl-Android.apk"),
        "windows": win,
        "files": files,
    }
    pathlib.Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print("update.json:", a.build, "·", len(files), "content files")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["app", "release"])
    ap.add_argument("--build", type=int, default=0)
    ap.add_argument("--sha", default="")
    ap.add_argument("--repo", default="")
    ap.add_argument("--version", default="")
    ap.add_argument("--dist", default="dist")
    ap.add_argument("--out", default="dist/update.json")
    a = ap.parse_args()
    app_manifest() if a.mode == "app" else release(a)
