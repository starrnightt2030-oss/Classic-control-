"""Generate the missing narration clips with the Gemini TTS API — one request per clip, so
every clip is read exactly as written and saved under the name the app expects.

    GEMINI_API_KEY=... python gemini_tts.py [--voice Charon] [--model auto] [--max 400] [--verify]

* Missing = listed in content/recording/manifest_part_XX.json but not present in assets/audio/.
* Each clip: Gemini TTS (24 kHz PCM) → trimmed, 120 ms padding, EBU R128 -16 LUFS, mono MP3 64 kb/s.
* --verify: transcribe the clip (faster-whisper small) and compare with the script; a clip that
  doesn't match is regenerated once, then left out and reported.
* Stops cleanly on quota errors; run again later and it continues where it stopped.
Status: audio/reports/gemini_tts_status.json
"""
import argparse
import base64
import difflib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
V2 = HERE.parent
REC = V2 / "content" / "recording"
AUDIO = V2 / "assets" / "audio"
STATUS = HERE / "reports" / "gemini_tts_status.json"
MARK = "\n\n.\n\n"
API = "https://generativelanguage.googleapis.com/v1beta"

sys.path.insert(0, str(HERE))
from asr_split import words_of  # noqa: E402

# Style goes in the system instruction; the spoken content is the script text only
# (this TTS model reads any instruction placed in the content aloud).
STYLE = ("You are a text-to-speech narrator. Speak the user's text exactly, word for word, in Egyptian Arabic, "
         "with a calm, clear, warm teacher voice. Do not add, skip, translate or explain anything.")
_USE_SYSTEM = [True]


def all_clips():
    out = []
    for part in range(1, 100):
        tts = REC / f"tts_part_{part:02d}.txt"
        if not tts.exists():
            break
        order = json.loads((REC / f"manifest_part_{part:02d}.json").read_text(encoding="utf8"))["order"]
        texts = [s.strip() for s in tts.read_text(encoding="utf8").split(MARK) if s.strip()]
        out += list(zip(order, texts))
    return out


def text_hash(t):
    import hashlib
    return hashlib.sha1(t.encode("utf8")).hexdigest()[:12]


def missing_clips():
    out = []
    for part in range(1, 100):
        tts = REC / f"tts_part_{part:02d}.txt"
        if not tts.exists():
            break
        order = json.loads((REC / f"manifest_part_{part:02d}.json").read_text(encoding="utf8"))["order"]
        texts = [s.strip() for s in tts.read_text(encoding="utf8").split(MARK) if s.strip()]
        for name, text in zip(order, texts):
            if not (AUDIO / name).exists():
                out.append((name, text))
    return out


def http(method, url, body=None, timeout=180):
    data = json.dumps(body).encode("utf8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf8"))


def pick_model(key, wanted):
    if wanted and wanted != "auto":
        return wanted
    models = http("GET", f"{API}/models?key={key}&pageSize=200").get("models", [])
    names = [m["name"].split("/", 1)[1] for m in models if "tts" in m["name"].lower()]
    if not names:
        raise SystemExit("No TTS model available for this API key.")
    # prefer the newest flash TTS model, then pro
    names.sort(key=lambda n: (("flash" not in n), n), reverse=False)
    flash = [n for n in names if "flash" in n]
    return sorted(flash)[-1] if flash else sorted(names)[-1]


def synth(key, model, voice, text):
    body = {
        "contents": [{"role": "user", "parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}},
        },
    }
    if _USE_SYSTEM[0]:
        body["systemInstruction"] = {"parts": [{"text": STYLE}]}
    try:
        res = http("POST", f"{API}/models/{model}:generateContent?key={key}", body)
    except urllib.error.HTTPError as e:
        if e.code == 400 and _USE_SYSTEM[0]:
            print("  model rejects systemInstruction; sending the text only", flush=True)
            _USE_SYSTEM[0] = False
            body.pop("systemInstruction", None)
            res = http("POST", f"{API}/models/{model}:generateContent?key={key}", body)
        else:
            raise
    for part in res["candidates"][0]["content"]["parts"]:
        inline = part.get("inlineData") or part.get("inline_data")
        if inline and inline.get("data"):
            return base64.b64decode(inline["data"]), inline.get("mimeType", "audio/L16;rate=24000")
    raise RuntimeError("no audio in response")


def synth_azure(key, region, voice, text, rate="-4%"):
    from xml.sax.saxutils import escape
    ssml = (f"<speak version='1.0' xml:lang='ar-EG' xmlns='http://www.w3.org/2001/10/synthesis'>"
            f"<voice name='{voice}'><prosody rate='{rate}'>{escape(text)}</prosody></voice></speak>")
    req = urllib.request.Request(
        f"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1", data=ssml.encode("utf8"), method="POST",
        headers={"Ocp-Apim-Subscription-Key": key, "Content-Type": "application/ssml+xml",
                 "X-Microsoft-OutputFormat": "raw-24khz-16bit-mono-pcm", "User-Agent": "control-academy"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read(), "audio/L16;rate=24000"


def to_mp3(pcm, mime, dst):
    rate = 24000
    if "rate=" in mime:
        rate = int(mime.split("rate=")[1].split(";")[0])
    dst.parent.mkdir(parents=True, exist_ok=True)
    af = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
          "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
          "adelay=120:all=1,apad=pad_dur=0.15,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", "pipe:0",
                    "-af", af, "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "64k", str(dst)], input=pcm, check=True)


class Verifier:
    def __init__(self):
        from faster_whisper import WhisperModel
        self.m = WhisperModel("small", device="cpu", compute_type="int8")

    def score(self, path, text):
        import numpy as np
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                             capture_output=True).stdout
        segs, _ = self.m.transcribe(np.frombuffer(raw, np.float32), language="ar", beam_size=1, condition_on_previous_text=False)
        hyp, ref = words_of(" ".join(s.text for s in segs)), words_of(text)
        sm = difflib.SequenceMatcher(None, ref, hyp, autojunk=False)
        hit = sum(b.size for b in sm.get_matching_blocks())
        self.last = " ".join(s.text for s in segs)[:160] if False else " ".join(hyp)[:160]
        return hit / max(1, len(ref)), hit / max(1, len(hyp)), len(hyp) / max(1, len(ref))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default="gemini", choices=["gemini", "azure"])
    ap.add_argument("--voice", default="")
    ap.add_argument("--only", default="", help="comma-separated clip names (also regenerates existing ones)")
    ap.add_argument("--out", default="", help="write here instead of assets/audio (samples)")
    ap.add_argument("--model", default="auto")
    ap.add_argument("--max", type=int, default=400)
    ap.add_argument("--delay", type=float, default=7.0, help="seconds between requests (free-tier rate limits)")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--all", action="store_true",
                    help="regenerate every clip whose current audio was not made with this voice from this exact text")
    a = ap.parse_args()
    if a.engine == "azure":
        key = os.environ.get("AZURE_SPEECH_KEY", "").strip()
        region = os.environ.get("AZURE_SPEECH_REGION", "").strip()
        if not key or not region:
            raise SystemExit("AZURE_SPEECH_KEY / AZURE_SPEECH_REGION are not set (repository secrets).")
        a.voice = a.voice or "ar-EG-ShakirNeural"
        model = "azure-neural"
        a.delay = min(a.delay, 3.2)          # F0 tier: 20 requests / minute
        tts = lambda text: synth_azure(key, region, a.voice, text)
    else:
        key = os.environ.get("GEMINI_API_KEY", "").strip()
        if not key:
            raise SystemExit("GEMINI_API_KEY is not set (add it as a repository secret).")
        a.voice = a.voice or "Charon"
        model = pick_model(key, a.model)
        tts = lambda text: synth(key, model, a.voice, text)
    out_root = pathlib.Path(a.out) if a.out else AUDIO
    if a.only:
        want = [x.strip() for x in a.only.split(",") if x.strip()]
        allc = dict(all_clips())
        todo = [(n, allc[n]) for n in want if n in allc]
    status = json.loads(STATUS.read_text(encoding="utf8")) if STATUS.exists() else {}
    if a.only:
        pass
    elif a.all:
        todo = [(n, t) for n, t in all_clips()
                if not (status.get(n, {}).get("ok") and status[n].get("voice") == a.voice and status[n].get("h") == text_hash(t)
                        and (out_root / n).exists())][: a.max]
    else:
        todo = missing_clips()[: a.max]
    print(f"model={model} voice={a.voice} todo={len(todo)}", flush=True)
    ver = Verifier() if a.verify else None
    quota_hits = 0
    done = 0
    for i, (name, text) in enumerate(todo, 1):
        final = out_root / name
        dst = final.with_suffix(".new.mp3")
        ok = False
        for attempt in (1, 2):
            try:
                pcm, mime = tts(text)
                quota_hits = 0
            except urllib.error.HTTPError as e:
                msg = e.read().decode("utf8", "replace")[:300]
                if e.code == 429:
                    quota_hits += 1
                    wait = 60 * quota_hits
                    print(f"::warning::429 quota/rate limit ({quota_hits}) — waiting {wait}s: {msg[:200]}", flush=True)
                    if quota_hits >= 4:
                        print(f"::warning::stopping: quota exhausted for now after {done} clips; re-run later to continue", flush=True)
                        STATUS.write_text(json.dumps(status, ensure_ascii=False, indent=1), encoding="utf8")
                        return
                    time.sleep(wait)
                    continue
                print(f"::warning::HTTP {e.code} for {name}: {msg[:200]}", flush=True)
                break
            except Exception as e:  # network / malformed response
                print(f"  error for {name}: {e}", flush=True)
                time.sleep(a.delay)
                continue
            to_mp3(pcm, mime, dst)
            if ver:
                rec, prec, ratio = ver.score(dst, text)
                good = rec >= 0.5 and prec >= 0.4 and ratio <= 1.5
                status[name] = {"recall": round(rec, 2), "precision": round(prec, 2), "attempt": attempt, "ok": good, "voice": a.voice,
                                "model": model, "h": text_hash(text), "heard": ver.last}
                if not good:
                    dst.unlink(missing_ok=True)
                    print(f"  ✗ {name} rec={rec:.2f} prec={prec:.2f} (attempt {attempt})", flush=True)
                    time.sleep(a.delay)
                    continue
            else:
                status[name] = {"ok": True, "voice": a.voice, "model": model, "h": text_hash(text)}
            dst.replace(final)
            ok = True
            break
        done += ok
        print(f"[{i}/{len(todo)}] {'✓' if ok else '—'} {name}", flush=True)
        if i % 10 == 0:
            STATUS.write_text(json.dumps(status, ensure_ascii=False, indent=1), encoding="utf8")
        time.sleep(a.delay)
    STATUS.write_text(json.dumps(status, ensure_ascii=False, indent=1), encoding="utf8")
    print(f"::notice::generated {done}/{len(todo)} with {model}/{a.voice}", flush=True)


if __name__ == "__main__":
    main()
