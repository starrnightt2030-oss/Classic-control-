"""Windows patch for the in-app updater: only the program files that changed.

    python tool/win_patch.py <Release folder> --repo owner/name --out DIR

Writes DIR/windows-files.json (sha256 of every file in the Release folder). When the
newest earlier `v2-app-build-N` release has its windows-files.json, also writes
DIR/ClassicControl-Windows-patch.zip with the changed and new files (same layout as
the full zip) and DIR/windows-patch.json {name, from, fromCode, files}. A PC on build N,
or on any build with the same program (code hash) as N, then downloads only the patch;
any other PC gets the full zip.
Uses GH_TOKEN for the GitHub API when it is set.
"""
import argparse
import hashlib
import json
import os
import pathlib
import urllib.request
import zipfile

PREFIX = "v2-app-build-"


def sha(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def get(url: str, api: bool = False) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "ControlAcademy-CI"})
    if api:
        req.add_header("Accept", "application/vnd.github+json")
    tok = os.environ.get("GH_TOKEN")
    if tok and api:
        req.add_header("Authorization", f"Bearer {tok}")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def previous(repo: str):
    """(build, files, code) of the newest earlier release that has windows-files.json"""
    rels = json.loads(get(f"https://api.github.com/repos/{repo}/releases?per_page=20", api=True))
    best = None
    for r in rels:
        tag = r.get("tag_name", "")
        if not tag.startswith(PREFIX) or not tag[len(PREFIX):].isdigit():
            continue
        a = next((x for x in r.get("assets", []) if x["name"] == "windows-files.json"), None)
        u = next((x for x in r.get("assets", []) if x["name"] == "update.json"), None)
        if a and (best is None or int(tag[len(PREFIX):]) > best[0]):
            best = (int(tag[len(PREFIX):]), a["browser_download_url"], u and u["browser_download_url"])
    if not best:
        return None
    code = ""
    if best[2]:
        try:
            code = json.loads(get(best[2])).get("code", "")
        except Exception:
            code = ""
    return best[0], json.loads(get(best[1])), code


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("release")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", default=".")
    a = ap.parse_args()
    rel, out = pathlib.Path(a.release), pathlib.Path(a.out)
    files = {p.relative_to(rel).as_posix(): sha(p) for p in sorted(rel.rglob("*")) if p.is_file()}
    (out / "windows-files.json").write_text(json.dumps(files, indent=0), encoding="utf-8")
    print("windows files:", len(files))
    try:
        prev = previous(a.repo)
    except Exception as e:  # no network or no releases yet: full zip only
        print("no previous release:", e)
        prev = None
    if not prev:
        return
    build, old, code = prev
    changed = [k for k, h in files.items() if old.get(k) != h]
    name = "ClassicControl-Windows-patch.zip"
    with zipfile.ZipFile(out / name, "w", zipfile.ZIP_DEFLATED) as z:
        for k in changed:
            z.write(rel / k, k)
    (out / "windows-patch.json").write_text(json.dumps({"name": name, "from": build, "fromCode": code, "files": len(changed)}), encoding="utf-8")
    size = (out / name).stat().st_size
    print(f"patch from build {build}: {len(changed)} of {len(files)} files, {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
