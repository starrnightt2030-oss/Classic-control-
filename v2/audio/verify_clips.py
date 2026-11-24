"""Re-transcribe every cut clip and compare with its script text; delete clips that don't match."""
import json, os, subprocess, sys, difflib, numpy as np
sys.path.insert(0, '/home/claude/classic-control-/v2/audio')
from asr_split import words_of, MARK
from faster_whisper import WhisperModel
REC = '/home/claude/classic-control-/v2/content/recording/'
A = '/home/claude/classic-control-/v2/assets/audio/'
m = WhisperModel("/tmp/whisper_small", device="cpu", compute_type="int8", cpu_threads=2)
script = {}
for p in range(1, 9):
    order = json.load(open(REC + f'manifest_part_{p:02d}.json'))['order']
    clips = [s.strip() for s in open(REC + f'tts_part_{p:02d}.txt', encoding='utf8').read().split(MARK) if s.strip()]
    script.update(dict(zip(order, clips)))
res = []
for root, _, files in os.walk(A):
    for f in files:
        if not f.endswith('.mp3') or '/sfx' in root:
            continue
        rel = os.path.relpath(os.path.join(root, f), A)
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(root, f), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"], capture_output=True).stdout
        a = np.frombuffer(raw, np.float32)
        segs, _ = m.transcribe(a, language="ar", beam_size=1, condition_on_previous_text=False)
        hyp = words_of(' '.join(s.text for s in segs))
        ref = words_of(script[rel])
        sm = difflib.SequenceMatcher(None, ref, hyp, autojunk=False)
        matched = sum(b.size for b in sm.get_matching_blocks())
        recall = matched / max(1, len(ref))         # how much of the script is in the clip
        precision = matched / max(1, len(hyp))      # how much of the clip is the script
        # the first and last few script words should be present (no clipped start/end)
        head = difflib.SequenceMatcher(None, ref[:4], hyp[:8], autojunk=False).find_longest_match(0, len(ref[:4]), 0, len(hyp[:8])).size
        tail = difflib.SequenceMatcher(None, ref[-4:], hyp[-8:], autojunk=False).find_longest_match(0, len(ref[-4:]), 0, len(hyp[-8:])).size
        short = len(ref) <= 6
        ok = recall >= 0.5 and precision >= (0.6 if short else 0.5) and (head >= 1 or short) and (tail >= 1 or short) and len(hyp) <= len(ref) * 1.4 + 1
        res.append({"clip": rel, "ok": ok, "recall": round(recall, 2), "precision": round(precision, 2), "head": head, "tail": tail, "ref_words": len(ref), "hyp_words": len(hyp), "secs": round(len(a) / 16000, 1)})
        print(('OK ' if ok else 'BAD'), rel, round(recall, 2), round(precision, 2), head, tail, flush=True)
json.dump(res, open('verify.json', 'w', encoding='utf8'), ensure_ascii=False, indent=1)
print('ok', sum(r['ok'] for r in res), 'bad', sum(not r['ok'] for r in res))
