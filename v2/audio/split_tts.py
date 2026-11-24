"""Split one long TTS recording into the named clips listed in a manifest, cutting at the N-1 longest pauses.
Usage: python split_tts.py <long_audio> <manifest_part_XX.json> [--out ../assets/audio] [--noise -35dB] [--min 0.5]"""
import sys, os, json, re, subprocess, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("audio")
ap.add_argument("manifest")
ap.add_argument("--out", default=os.path.join(HERE, "..", "assets", "audio"))
ap.add_argument("--noise", default="-35dB")
ap.add_argument("--min", type=float, default=0.5, help="minimum pause length in seconds")
a = ap.parse_args()

order = json.load(open(a.manifest, encoding="utf8"))["order"]
n = len(order)
log = subprocess.run(["ffmpeg", "-hide_banner", "-i", a.audio, "-af", f"silencedetect=noise={a.noise}:d={a.min}", "-f", "null", "-"],
                     capture_output=True, text=True).stderr
starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
dur = float(re.findall(r"Duration: (\d+):(\d+):([\d.]+)", log)[0][2]) + 60 * int(re.findall(r"Duration: (\d+):(\d+)", log)[0][1]) + 3600 * int(re.findall(r"Duration: (\d+)", log)[0])
sil = [(s, e) for s, e in zip(starts, ends) if s > 0.05 and e < dur - 0.05]
if len(sil) < n - 1:
    sys.exit(f"Found only {len(sil)} pauses but need {n - 1}. Try --noise -30dB or --min 0.35, or record with longer pauses.")
cuts = sorted(sorted(sil, key=lambda p: p[1] - p[0], reverse=True)[: n - 1])
bounds = [0.0] + [(s + e) / 2 for s, e in cuts] + [dur]
for i, name in enumerate(order):
    dst = os.path.join(a.out, name)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    s, e = bounds[i], bounds[i + 1]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", a.audio, "-ss", f"{s:.3f}", "-to", f"{e:.3f}",
                    "-af", "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse",
                    "-ac", "1", "-b:a", "64k", dst], check=True)
    print(f"{i + 1:3d}/{n}  {s:7.2f}-{e:7.2f}s  {name}")
print("done:", n, "clips ->", os.path.abspath(a.out))
