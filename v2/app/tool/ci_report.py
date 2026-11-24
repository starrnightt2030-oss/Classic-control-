"""Turn Flutter analyzer / build output into GitHub annotations, so failures are
readable from the public check-runs API (logs need a login).

    python tool/ci_report.py analyze.txt
    python tool/ci_report.py build.txt --tail
"""
import re
import sys


def esc(s: str) -> str:
    return s.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def analyze(lines):
    n = 0
    pat = re.compile(r"^\s*(error|warning)\s+•\s+(.*?)\s+•\s+(\S+?):(\d+):(\d+)\s+•\s+(\S+)")
    for ln in lines:
        m = pat.match(ln)
        if not m:
            continue
        kind, msg, path, line, col, code = m.groups()
        level = "error" if kind == "error" else "warning"
        print(f"::{level} file=v2/app/{path},line={line},col={col}::{esc(code + ': ' + msg)}")
        n += 1
    print(f"{n} analyzer error/warning lines")


def tail(lines):
    interesting = [l for l in lines if re.search(r"error|Error|FAILURE|failed|Exception|What went wrong|\.dart:\d+", l)]
    chunk = (interesting[-60:] if interesting else lines[-60:])
    # GitHub keeps 10 error annotations per step: pack into a few big ones
    for i in range(0, len(chunk), 15):
        print("::error title=build log::" + esc("\n".join(chunk[i:i + 15])[:3800]))


if __name__ == "__main__":
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
    if "--tail" in sys.argv:
        tail(text)
    else:
        analyze(text)
