"""Synthesise the app's sound effects (no samples, no licences).

    python tool/make_sfx.py   -> assets/sfx/*.wav, intro.mp3
"""
import pathlib
import subprocess
import wave

import numpy as np

SR = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sfx"
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.1):
    e = np.ones(n)
    na, nr = int(SR * a), int(SR * r)
    if na:
        e[:na] = np.linspace(0, 1, na)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def lp(x, k=0.2):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def save(name, x, peak=0.85):
    x = x / (np.abs(x).max() + 1e-9) * peak
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def click():
    tt = t(0.06)
    a = noise(0.06) * np.exp(-tt * 220)
    b = np.sin(2 * np.pi * 2300 * tt) * np.exp(-tt * 160) * 0.6
    tt2 = t(0.05)
    c = np.sin(2 * np.pi * 1500 * tt2) * np.exp(-tt2 * 200) * 0.4
    return np.concatenate([a + b, np.zeros(int(SR * 0.012)), c + noise(0.05) * np.exp(-tt2 * 260) * 0.5])


def trip():
    tt = t(0.25)
    snap = noise(0.25) * np.exp(-tt * 40)
    thud = np.sin(2 * np.pi * 90 * tt) * np.exp(-tt * 18)
    clack = np.sin(2 * np.pi * 900 * tt) * np.exp(-tt * 60) * 0.5
    return snap * 0.7 + thud + clack


def zap():
    d = 0.7
    tt = t(d)
    crackle = noise(d) * (rng.uniform(0, 1, len(tt)) > 0.6)
    buzz = np.sign(np.sin(2 * np.pi * 100 * tt)) * 0.35
    bang = noise(d) * np.exp(-tt * 9)
    return (crackle * np.exp(-tt * 4) + buzz * np.exp(-tt * 5) + bang * 1.3) * env(len(tt), 0.001, 0.15)


def sizzle():
    d = 1.6
    tt = t(d)
    x = noise(d) - lp(noise(d), 0.3)
    pops = (rng.uniform(0, 1, len(tt)) > 0.997) * rng.uniform(-1, 1, len(tt)) * 3
    return (x * 0.6 + pops) * env(len(tt), 0.05, 0.6)


def hum(d=2.0):
    tt = t(d)
    x = sum(np.sin(2 * np.pi * 100 * k * tt) / k for k in (1, 2, 3, 5))
    return x * env(len(tt), 0.02, 0.02)


def bell():
    d = 1.4
    tt = t(d)
    ring = np.sign(np.sin(2 * np.pi * 25 * tt)) * 0.5 + 0.5
    tone = sum(np.sin(2 * np.pi * f * tt) * a for f, a in ((1180, 1), (2950, 0.5), (4300, 0.25)))
    return tone * (0.4 + 0.6 * ring) * env(len(tt), 0.005, 0.1)


def buzzer():
    d = 0.9
    tt = t(d)
    x = np.sign(np.sin(2 * np.pi * 180 * tt)) + 0.5 * np.sin(2 * np.pi * 360 * tt)
    return lp(x, 0.35) * env(len(tt), 0.01, 0.05)


def note(f, d, a=1.0, decay=3.0):
    tt = t(d)
    x = sum(np.sin(2 * np.pi * f * k * tt) / (k * k) for k in (1, 2, 3))
    return x * np.exp(-tt * decay) * env(len(tt), 0.004, 0.05) * a


def success():
    return np.concatenate([note(660, 0.12), note(880, 0.12), note(1320, 0.45, decay=4)])


def fail():
    return np.concatenate([note(330, 0.18, decay=5), note(247, 0.4, decay=4)])


def tap():
    tt = t(0.035)
    return np.sin(2 * np.pi * 1800 * tt) * np.exp(-tt * 180)


def wire():
    tt = t(0.12)
    return (noise(0.12) * 0.4 + np.sin(2 * np.pi * 700 * tt)) * np.exp(-tt * 40)


def beep():
    tt = t(0.25)
    return np.sin(2 * np.pi * 2700 * tt) * env(len(tt), 0.003, 0.02)


def intro():
    """3.2 s: electric riser, a spark, then a warm major chord."""
    d = 3.4
    tt = t(d)
    x = np.zeros(len(tt))
    # rising hum + filtered noise riser (0 -> 1.2 s)
    n = int(SR * 1.2)
    f = np.linspace(60, 220, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    rise = (np.sin(ph) + 0.4 * np.sin(2 * ph)) * np.linspace(0, 1, n) ** 2 * 0.5
    rise += lp(rng.uniform(-1, 1, n), 0.08) * np.linspace(0, 1, n) ** 3 * 1.5
    x[:n] += rise
    # spark at 1.2 s
    s0 = n
    sp = zap()[: int(SR * 0.35)] * 0.6
    x[s0:s0 + len(sp)] += sp
    # chord from 1.25 s (C major add9, bell-like)
    c0 = int(SR * 1.25)
    for fq, a in ((261.6, 1), (329.6, 0.8), (392.0, 0.8), (523.3, 0.6), (587.3, 0.35), (784.0, 0.3)):
        nn = note(fq, d - 1.25, a, decay=1.1)
        x[c0:c0 + len(nn)] += nn
    # shimmer
    sh = np.sin(2 * np.pi * 2093 * t(d - 1.3)) * np.exp(-t(d - 1.3) * 2.5) * 0.15
    x[c0:c0 + len(sh)] += sh
    return x * env(len(x), 0.01, 0.6)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("click", click), ("trip", trip), ("zap", zap), ("sizzle", sizzle), ("hum", hum), ("bell", bell),
                     ("buzzer", buzzer), ("success", success), ("fail", fail), ("tap", tap), ("wire", wire), ("beep", beep)):
        save(f"{name}.wav", fn())
    save("intro.wav", intro(), 0.8)
    wav = OUT / "intro.wav"
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-b:a", "96k", str(OUT / "intro.mp3")], check=True)
        wav.unlink()
    except Exception as e:  # keep the wav when ffmpeg is missing
        print("ffmpeg failed, keeping wav:", e)
    print("done")
