"""Split a long narration recording into the manifest's named clips using a speech-recognition
transcript (word timestamps) aligned to the recording script.

    python asr_split.py <recording.wav> <part> <asr.json> [--out ../assets/audio] [--report r.json] [--dry]

asr.json: [{"s":..,"e":..,"t":..,"w":[[start,end,word],...]}, ...]   (faster-whisper output)

How it works
1. Normalise Arabic in script and transcript (hamza/alef/ya/ta-marbuta forms, diacritics, punctuation).
2. Align the two word sequences (difflib matching blocks) → each script word gets a time where matched.
3. A clip runs from its first matched word to its last; the cut between two clips is placed in the
   silence between them (pause detection), so no word is clipped.
4. Clips the recording doesn't fully contain (the studio stopped early) are not written; the
   report lists them so they can be re-recorded.
Each clip: trimmed, 120 ms padding, EBU R128 loudness -16 LUFS, mono MP3 64 kb/s 44.1 kHz.
"""
import argparse
import difflib
import json
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REC = os.path.join(HERE, "..", "content", "recording")
MARK = "\n\n.\n\n"

_DIAC = re.compile(r"[ً-ْٰـ]")
_PUNCT = re.compile(r"[^\w\s]|_", re.UNICODE)
_LAT = {"0": "صفر", "1": "واحد", "2": "اتنين", "3": "تلاتة", "4": "اربعة", "5": "خمسة", "6": "ستة", "7": "سبعة", "8": "تمانية", "9": "تسعة"}


def norm_word(w):
    w = _DIAC.sub("", w)
    w = w.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا").replace("ٱ", "ا")
    w = w.replace("ى", "ي").replace("ة", "ه").replace("ؤ", "و").replace("ئ", "ي")
    w = _PUNCT.sub(" ", w.lower())
    return w.split()


def words_of(text):
    out = []
    for raw in text.split():
        out.extend(norm_word(raw))
    return out


def pauses(path, noise="-40dB", d=0.15):
    log = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", f"silencedetect=noise={noise}:d={d}", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    st = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", log)]
    en = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    h, m, s = re.findall(r"Duration: (\d+):(\d+):([\d.]+)", log)[0]
    return [(max(a, 0.0), b) for a, b in zip(st, en)], int(h) * 3600 + int(m) * 60 + float(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("audio")
    ap.add_argument("part", help="part number (tts_part_XX) or rr_XX for a re-record file")
    ap.add_argument("asr")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "assets", "audio"))
    ap.add_argument("--report")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--min-match", type=float, default=0.55)
    a = ap.parse_args()

    if a.part.startswith("rr_"):
        man = json.load(open(os.path.join(REC, "rerecord", f"manifest_{a.part}.json"), encoding="utf8"))
        text = open(os.path.join(REC, "rerecord", f"{a.part}.txt"), encoding="utf8").read()
    else:
        n = int(a.part)
        man = json.load(open(os.path.join(REC, f"manifest_part_{n:02d}.json"), encoding="utf8"))
        text = open(os.path.join(REC, f"tts_part_{n:02d}.txt"), encoding="utf8").read()
    clips = [s.strip() for s in text.split(MARK) if s.strip()]
    order = man["order"]
    assert len(clips) == len(order), (len(clips), len(order))

    # script words with clip index
    sw, sclip = [], []
    for ci, c in enumerate(clips):
        ws = words_of(c)
        sw += ws
        sclip += [ci] * len(ws)
    # transcript words with times
    asr = json.load(open(a.asr, encoding="utf8"))
    aw, at = [], []
    for seg in asr:
        for ws, we, w in seg["w"]:
            for piece in norm_word(w):
                aw.append(piece)
                at.append((ws, we))

    sm = difflib.SequenceMatcher(None, sw, aw, autojunk=False)
    t_of = [None] * len(sw)
    for blk in sm.get_matching_blocks():
        if blk.size < 2:          # single-word matches are mostly coincidences (و، في، ده…)
            continue
        for k in range(blk.size):
            t_of[blk.a + k] = at[blk.b + k]

    pz, dur = pauses(a.audio)
    last_t = at[-1][1] if at else 0.0

    info = []
    for ci in range(len(clips)):
        idx = [i for i, c in enumerate(sclip) if c == ci]
        matched = [t_of[i] for i in idx if t_of[i] is not None]
        frac = len(matched) / max(1, len(idx))
        # is the clip's ending inside the recording? (last 25 % of its words matched somewhere)
        # the clip is complete only if its closing words were actually spoken
        tail = idx[-5:]
        tail_ok = sum(t_of[i] is not None for i in tail) >= 2
        first = min(m[0] for m in matched) if matched else None
        lastw = max(m[1] for m in matched) if matched else None
        info.append({"clip": order[ci], "words": len(idx), "matched": round(frac, 2), "t0": first, "t1": lastw, "tail_ok": tail_ok})

    # A clip is usable when the narrator really read it: enough of its words were recognised,
    # including its opening and its closing words, in the right time order.
    head_ok = []
    for ci in range(len(clips)):
        idx = [i for i, c in enumerate(sclip) if c == ci]
        head_ok.append(sum(t_of[i] is not None for i in idx[:5]) >= 2)
    ok = []
    prev_end = -1.0
    for ci, r in enumerate(info):
        expd = len(clips[ci]) / 11.0
        good = (r["matched"] >= a.min_match and r["tail_ok"] and head_ok[ci] and r["t0"] is not None
                and 0.6 * expd - 1 <= r["t1"] - r["t0"] <= 1.5 * expd + 2 and r["t0"] >= prev_end - 0.05)
        r["ratio"] = round((r["t1"] - r["t0"]) / expd, 2) if r["t0"] is not None else None
        ok.append(good)
        if good:
            prev_end = r["t1"]

    def longest_gap(lo, hi):
        """midpoint of the longest pause inside [lo, hi] (the '.' separator pause)"""
        best = None
        for s_, e_ in pz:
            a_, b_ = max(s_, lo), min(e_, hi)
            if b_ - a_ <= 0.05:
                continue
            if best is None or (b_ - a_) > best[0]:
                best = (b_ - a_, (a_ + b_) / 2)
        return best[1] if best else None

    def snap_before(ci):
        t0 = info[ci]["t0"]
        prev = info[ci - 1]["t1"] if ci > 0 else None
        lo = prev if prev is not None and prev < t0 else t0 - 2.5
        c = longest_gap(max(lo, 0.0), t0 + 0.05)
        return max(0.0, c if c is not None else t0 - 0.3)

    def snap_after(ci):
        t1 = info[ci]["t1"]
        nxt = info[ci + 1]["t0"] if ci + 1 < len(info) else None
        hi = nxt if nxt is not None and nxt > t1 else t1 + 2.5
        c = longest_gap(t1 - 0.05, min(hi, dur))
        return min(dur, c if c is not None else t1 + 0.4)

    bounds = {}
    last_end = 0.0
    for ci, r in enumerate(info):
        if ok[ci]:
            st = max(snap_before(ci), last_end)
            en = snap_after(ci)
            bounds[ci] = (st, en)
            last_end = en
    n_ok = len(bounds)

    report = {
        "part": a.part, "recording_seconds": round(dur, 1), "transcript_end": round(last_t, 1),
        "clips_in_part": len(order), "clips_written": n_ok,
        "missing": [r["clip"] for ci, r in enumerate(info) if ci not in bounds],
        "clips": [dict(r, ok=ci in bounds, start=round(bounds[ci][0], 2) if ci in bounds else None,
                       end=round(bounds[ci][1], 2) if ci in bounds else None) for ci, r in enumerate(info)],
    }
    print(f"part {a.part}: {n_ok}/{len(order)} clips usable; recording {dur:.0f}s")
    if a.report:
        json.dump(report, open(a.report, "w", encoding="utf8"), ensure_ascii=False, indent=1)
    if a.dry:
        return
    for ci, (s, e) in bounds.items():
        r = info[ci]
        dst = os.path.join(a.out, r["clip"])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        af = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
              "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
              "adelay=120:all=1,apad=pad_dur=0.15,afade=t=in:d=0.015,"
              "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{s:.3f}", "-to", f"{e:.3f}", "-i", a.audio,
                        "-af", af, "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "64k", dst], check=True)


if __name__ == "__main__":
    main()
