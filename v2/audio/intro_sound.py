"""Soundtrack for the animated intro (synced to models/intro.py, 24 fps, 144 frames = 6 s).
Run: python intro_sound.py -> ../assets/audio/sfx/intro_theme.mp3"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile

import sfx_synth as s

SR = s.SR
TOTAL = 7.0


def arc(d=0.35):
    """electric arc / spark: crackly broadband bursts on a 50 Hz buzz"""
    n = s.noise(d)
    crack = s.bp(n, 1800, 9000) * (s.rng.random(len(n)) > 0.82)
    buzz = 0.35 * np.sign(np.sin(2 * np.pi * 50 * s.t(d))) * s.bp(s.noise(d), 100, 600)
    return (crack * 1.4 + buzz) * s.env(len(n), 0.001, d / 3)


def drone(d):
    x = s.t(d)
    sub = 0.5 * np.sin(2 * np.pi * 55 * x) + 0.25 * np.sin(2 * np.pi * 82.5 * x)
    air = s.lp(s.noise(d), 900) * 0.25
    swell = np.minimum(1, x / (d * 0.6))
    return (sub + air) * swell * 0.5


def boom(d=1.6):
    x = s.t(d)
    f = 70 * np.exp(-x * 2.2) + 32
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * s.env(len(x), 0.004, 0.55)
    return y + s.lp(s.noise(d), 300) * s.env(len(x), 0.001, 0.12) * 0.6


def main():
    y = np.zeros(int(SR * TOTAL))
    y += s.at(drone(3.6), 0.0, TOTAL) * 0.8
    for k, start in enumerate((8, 16, 24)):            # cables start growing (frames)
        y += s.at(s.whoosh(0.9, up=True) * 0.35, start / 24, TOTAL)
    for start in (34, 42, 50):                          # terminal hit + spark
        tsec = start / 24
        y += s.at(s.click(300, 5000, 0.1, 0.02, body=220) * 0.9, tsec, TOTAL)
        y += s.at(arc(0.32) * 0.8, tsec + 0.01, TOTAL)
    e = 62 / 24                                         # energise
    y += s.at(s.contactor(True) * 1.2, e, TOTAL)
    y += s.at(arc(0.6) * 0.9, e + 0.02, TOTAL)
    h = s.hum(3.6) * np.linspace(0.2, 0.7, int(SR * 3.6))
    y += s.at(h * 0.6, e + 0.05, TOTAL)
    y += s.at(s.whoosh(1.1, up=True) * 0.6, 3.25, TOTAL)
    y += s.at(boom() * 1.1, 4.05, TOTAL)
    y += s.at(s.chime([523.25, 659.25, 783.99, 1046.5], dur=0.11, dec=0.9) * 0.45, 4.1, TOTAL)
    # fade out tail
    fade = np.ones_like(y)
    n = int(SR * 1.2)
    fade[-n:] = np.linspace(1, 0, n)
    y *= fade
    y = y / (np.max(np.abs(y)) + 1e-9) * 0.89

    out = os.path.join(s.OUT, "intro_theme.mp3")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, (y * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", f.name, "-codec:a", "libmp3lame", "-q:a", "3", out], check=True)
    print("wrote", out)


if __name__ == "__main__":
    main()
