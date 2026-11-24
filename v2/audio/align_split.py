"""Split a long narration recording into the manifest's clips by *aligning durations*.

The TTS reads each clip's text, so a clip's length is ~proportional to its character
count. We list every pause in the recording, then pick, with dynamic programming,
the cut points whose segment lengths best match the expected lengths (and prefer
the longer pauses the '.' separators produce). Works when the recording stops
early (studio length limit): only the clips that are complete get written.

    python align_split.py <recording.wav> <part_number> [--out ../assets/audio] [--report report.json]

Each clip: trimmed, 120 ms padding, loudness-normalised (EBU R128, -16 LUFS), mono MP3 64 kb/s.
"""
import argparse
import json
import math
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REC = os.path.join(HERE, "..", "content", "recording")
MARK = "\n\n.\n\n"


def pauses(path, noise="-38dB", d=0.22):
    log = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", f"silencedetect=noise={noise}:d={d}", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    st = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", log)]
    en = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    h, m, s = re.findall(r"Duration: (\d+):(\d+):([\d.]+)", log)[0]
    dur = int(h) * 3600 + int(m) * 60 + float(s)
    return [(max(a, 0.0), b) for a, b in zip(st, en)], dur


def align(chars, pz, dur, rate, lead):
    """returns (cost, bounds list) for the best prefix alignment"""
    # candidate cut times (pause mid) with pause length; speech starts after the leading silence
    cand = [(0.5 * (a + b), b - a) for a, b in pz if a > lead + 0.3 and b < dur - 0.05]
    times = [lead] + [c[0] for c in cand]
    plen = [1.5] + [c[1] for c in cand]
    m = len(times)
    exp = [c / rate for c in chars]
    INF = float("inf")
    # best[k][j]: min cost having placed k clips with the k-th ending at cut j
    best = [[INF] * m for _ in range(len(chars) + 1)]
    back = [[-1] * m for _ in range(len(chars) + 1)]
    best[0][0] = 0.0
    for k in range(1, len(chars) + 1):
        e = exp[k - 1]
        lo, hi = 0.55 * e - 0.4, 1.6 * e + 1.2
        row_prev, row = best[k - 1], best[k]
        for i in range(m):
            if row_prev[i] == INF:
                continue
            t0 = times[i]
            for j in range(i + 1, m):
                d = times[j] - t0
                if d < lo:
                    continue
                if d > hi:
                    break
                err = (d - e) / (e + 1.0)
                c = row_prev[i] + err * err * 4 - 0.25 * min(plen[j], 1.6)
                if c < row[j]:
                    row[j] = c
                    back[k][j] = i
    # choose the deepest k reachable; the remainder after the last cut is the (possibly cut-off) next clip
    for k in range(len(chars), 0, -1):
        j = min(range(m), key=lambda x: best[k][x])
        if best[k][j] < INF:
            tail = dur - times[j]
            # complete recording: the last clip ends at the file end
            if k == len(chars) - 1 and 0.6 * exp[-1] < tail < 1.7 * exp[-1] + 1.5:
                path = [j]
                kk = k
                while kk > 0:
                    path.append(back[kk][path[-1]])
                    kk -= 1
                bounds = [times[x] for x in reversed(path)] + [dur]
                return best[k][j] / len(chars), bounds, True
            path = [j]
            kk = k
            while kk > 0:
                path.append(back[kk][path[-1]])
                kk -= 1
            bounds = [times[x] for x in reversed(path)]
            return best[k][j] / k, bounds, False
    return INF, [], False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("part", type=int)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "assets", "audio"))
    ap.add_argument("--report", default=None)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()

    man = json.load(open(os.path.join(REC, f"manifest_part_{a.part:02d}.json"), encoding="utf8"))
    text = open(os.path.join(REC, f"tts_part_{a.part:02d}.txt"), encoding="utf8").read()
    segs = [s.strip() for s in text.split(MARK) if s.strip()]
    order = man["order"]
    assert len(segs) == len(order), (len(segs), len(order))
    chars = [len(s) for s in segs]

    pz, dur = pauses(a.audio)
    lead = pz[0][1] if pz and pz[0][0] < 0.05 else 0.0
    best = None
    # the narrator's articulation rate is the same in every session (~11 chars/s incl. pauses);
    # search a narrow band and keep the best-fitting rate
    for r100 in range(980, 1261, 10):
        cost, bounds, complete = align(chars, pz, dur, r100 / 100, lead)
        if bounds and (best is None or cost < best[0]):
            best = (cost, bounds, complete, r100 / 100)
    cost, bounds, complete, rate = best
    n = len(bounds) - 1
    rows = []
    for i in range(n):
        s, e = bounds[i], bounds[i + 1]
        expd = chars[i] / rate
        rows.append({"clip": order[i], "start": round(s, 2), "end": round(e, 2), "dur": round(e - s, 2),
                     "expected": round(expd, 2), "ratio": round((e - s) / expd, 2), "chars": chars[i]})
    flagged = [r for r in rows if not 0.72 <= r["ratio"] <= 1.38]
    rep = {"part": a.part, "recording_seconds": round(dur, 1), "rate_chars_per_s": rate, "fit_cost": round(cost, 4),
           "complete": complete, "clips_written": n, "clips_in_part": len(order),
           "missing_from": order[n] if n < len(order) else None, "flagged": [r["clip"] for r in flagged], "clips": rows}
    print(f"part {a.part}: {n}/{len(order)} clips, rate {rate} ch/s, cost {cost:.4f}, complete={complete}, flagged={len(flagged)}")
    if a.report:
        json.dump(rep, open(a.report, "w", encoding="utf8"), ensure_ascii=False, indent=1)
    if a.dry:
        return
    for r in rows:
        dst = os.path.join(a.out, r["clip"])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        af = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
              "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
              "adelay=120:all=1,apad=pad_dur=0.12,"
              "afade=t=in:d=0.02,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", a.audio, "-ss", f"{r['start']:.3f}", "-to", f"{r['end']:.3f}",
                        "-af", af, "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "64k", dst], check=True)


if __name__ == "__main__":
    main()
