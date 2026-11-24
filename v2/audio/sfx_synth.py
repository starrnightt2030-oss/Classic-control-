"""Synthesised placeholder sound effects (replace with real workshop recordings using the same file names).
Run: python sfx_synth.py  -> ../assets/audio/sfx/<id>.ogg"""
import os, json, subprocess, tempfile
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.002, d=0.1):
    x = np.arange(n) / SR
    return np.minimum(1, x / max(a, 1e-4)) * np.exp(-x / d)
def bp(x, lo, hi, o=2):
    b, a = butter(o, [lo / (SR / 2), hi / (SR / 2)], btype="band"); return lfilter(b, a, x)
def lp(x, f, o=2):
    b, a = butter(o, f / (SR / 2)); return lfilter(b, a, x)
def hp(x, f, o=2):
    b, a = butter(o, f / (SR / 2), btype="high"); return lfilter(b, a, x)
def noise(d): return rng.standard_normal(int(SR * d))
def tone(f, d, shape="sine"):
    x = t(d)
    if shape == "sine": return np.sin(2 * np.pi * f * x)
    if shape == "saw": return 2 * ((x * f) % 1) - 1
    if shape == "square": return np.sign(np.sin(2 * np.pi * f * x))
def pad(x, d): return np.concatenate([x, np.zeros(int(SR * d))])
def mix(*parts):
    n = max(len(p) for p in parts); y = np.zeros(n)
    for p in parts: y[:len(p)] += p
    return y
def at(x, sec, total):
    y = np.zeros(int(SR * total)); i = int(SR * sec); y[i:i + len(x)] += x[:len(y) - i]; return y


def click(f_lo=800, f_hi=6000, d=0.06, dec=0.012, body=None):
    c = bp(noise(d), f_lo, f_hi) * env(int(SR * d), 0.0005, dec)
    if body:
        c = mix(c, tone(body, d) * env(int(SR * d), 0.001, dec * 3) * 0.6)
    return c


def contactor(pull=True):
    a = click(300, 4000, 0.12, 0.018, body=180 if pull else 140)
    b = click(1200, 8000, 0.05, 0.006) * 0.6
    return mix(a, at(b, 0.012 if pull else 0.02, 0.15))


def hum(d=2.0, loud=False):
    x = t(d)
    y = sum(np.sin(2 * np.pi * 100 * k * x) / k ** (0.8 if loud else 1.3) for k in range(1, 8))
    if loud:
        y = y * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 7 * x)))
        y += bp(noise(d), 200, 1500) * 0.3
    return y * 0.4


def motor(kind="start"):
    d = {"start": 3.0, "run": 4.0, "stop": 3.0, "strain": 2.5}[kind]
    x = t(d)
    if kind == "start": f = 25 * (1 - np.exp(-x * 2.5))
    elif kind == "stop": f = 25 * np.exp(-x * 1.2)
    else: f = np.full_like(x, 25.0 if kind == "run" else 6.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = 0.5 * np.sin(2 * ph * 2) + 0.25 * np.sin(2 * ph * 24) + 0.15 * np.sin(2 * np.pi * 100 * x)
    wind = bp(noise(d), 300, 3000) * (f / 25) * 0.25
    y = y * (f / 25 + 0.05) + wind
    if kind == "strain":
        y = 0.6 * hum(d, loud=True) + 0.2 * np.sin(2 * np.pi * 50 * x)
    if kind == "start":
        y[: int(SR * 0.08)] += contactor()[: int(SR * 0.08)]
    return y


def chime(notes, dur=0.18, dec=0.5, shape="sine"):
    total = dur * len(notes) + dec * 1.5
    y = np.zeros(int(SR * total))
    for i, f in enumerate(notes):
        n = tone(f, dec * 2, shape) * env(int(SR * dec * 2), 0.005, dec) + 0.3 * tone(f * 2, dec * 2) * env(int(SR * dec * 2), 0.005, dec / 2)
        y += at(n, i * dur, total)
    return y


def whoosh(d=0.45, up=True):
    x = t(d); n = noise(d)
    fc = np.linspace(400, 4000, len(x)) if up else np.linspace(4000, 400, len(x))
    out = np.zeros_like(n); st = 2048
    for i in range(0, len(n), st):
        seg = n[i:i + st]; f = fc[min(i, len(fc) - 1)]
        out[i:i + st] = bp(seg, max(f * 0.6, 50), min(f * 1.4, 20000))
    return out * np.sin(np.pi * x / d) ** 2 * 0.8


def siren(d=3.0):
    x = t(d); f = 600 + 500 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.6 * x))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.6 + 0.2 * np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR))


def sfx():
    S = {}
    S["intro_jingle"] = mix(chime([392, 523.3, 659.3, 784], 0.16, 0.7), at(whoosh(0.5) * 0.4, 0.0, 2.2), at(contactor() * 0.8, 0.66, 2.2))
    S["outro_sting"] = chime([784, 659.3, 523.3], 0.18, 0.8)
    S["stage_sting"] = mix(chime([523.3, 784], 0.14, 0.6), whoosh(0.4) * 0.3)
    S["ui_tap"] = click(1500, 9000, 0.03, 0.004) * 0.6
    S["ui_whoosh"] = whoosh(0.35)
    S["explode_whoosh"] = mix(whoosh(0.6), at(click(400, 5000, 0.06, 0.01) * 0.5, 0.05, 0.7))
    S["assemble_snap"] = mix(whoosh(0.4, up=False) * 0.6, at(contactor() * 0.9, 0.38, 0.6))
    S["part_select"] = chime([1046.5], 0.1, 0.25)
    S["success_chime"] = chime([659.3, 880], 0.12, 0.45)
    S["success_fanfare"] = chime([523.3, 659.3, 784, 1046.5, 784, 1046.5], 0.14, 0.6)
    S["soft_fail"] = chime([392, 349.2, 311.1], 0.22, 0.6)
    S["error_buzz"] = tone(140, 0.35, "square") * env(int(SR * 0.35), 0.005, 0.25) * 0.35
    S["warning_alert"] = np.concatenate([tone(880, 0.22) * env(int(SR * 0.22), 0.005, 0.3), tone(660, 0.3) * env(int(SR * 0.3), 0.005, 0.35)]) * 0.7
    S["alarm_siren"] = siren(3.0)
    S["buzzer"] = tone(420, 1.5, "square") * 0.25 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 3 * t(1.5))))
    S["contactor_pull_in"] = contactor(True)
    S["contactor_drop_out"] = contactor(False)
    S["coil_hum"] = hum(2.0) * 0.5
    S["coil_hum_loud"] = hum(2.0, loud=True)
    S["relay_click"] = mix(click(1500, 9000, 0.04, 0.004), at(click(2500, 10000, 0.03, 0.003) * 0.5, 0.006, 0.05))
    S["overload_trip"] = mix(click(600, 7000, 0.1, 0.01, body=320), at(click(2000, 9000, 0.04, 0.004), 0.015, 0.12))
    S["mcb_on"] = mix(click(400, 4000, 0.12, 0.02, body=220), at(click(1500, 8000, 0.05, 0.005), 0.03, 0.15))
    S["mcb_trip"] = mix(click(300, 6000, 0.15, 0.03, body=260) * 1.2, at(bp(noise(0.06), 2000, 9000) * env(int(SR * 0.06), 0.0005, 0.01), 0.0, 0.2))
    S["pushbutton_click"] = mix(click(1000, 7000, 0.05, 0.006), at(click(1200, 7000, 0.04, 0.005) * 0.7, 0.14, 0.2))
    S["estop_latch"] = mix(click(300, 4000, 0.14, 0.025, body=150) * 1.3, at(click(2000, 9000, 0.05, 0.004), 0.02, 0.2))
    S["selector_detent"] = mix(click(800, 6000, 0.05, 0.006), at(click(1500, 8000, 0.04, 0.004) * 0.6, 0.05, 0.1))
    S["timer_tick"] = np.concatenate([pad(click(2500, 9000, 0.02, 0.002) * 0.4, 0.48) for _ in range(4)])
    S["solenoid_clunk"] = mix(click(150, 2500, 0.15, 0.03, body=90) * 1.3, at(hum(0.4) * 0.15, 0.05, 0.5))
    S["water_flow"] = lp(noise(3.0), 1800) * 0.4 + bp(noise(3.0), 2000, 5000) * 0.05
    S["motor_start"] = motor("start")
    S["motor_run"] = motor("run")
    S["motor_stop"] = motor("stop")
    S["motor_strain"] = motor("strain")
    bang = lp(noise(0.6), 3000) * env(int(SR * 0.6), 0.001, 0.12) * 1.5
    S["short_circuit_bang"] = mix(bang, at(bp(noise(0.3), 2000, 10000) * env(int(SR * 0.3), 0.001, 0.05), 0.0, 0.7), at(S["mcb_trip"], 0.04, 0.7))
    cr = np.zeros(int(SR * 1.5))
    for _ in range(60):
        i = rng.integers(0, len(cr) - 2000); cr[i:i + 600] += bp(noise(0.015), 2000, 12000)[:600] * rng.uniform(0.3, 1.0) * env(600, 0.0002, 0.003)
    S["arc_crackle"] = cr + hp(noise(1.5), 4000) * 0.05
    S["din_rail_click"] = mix(click(600, 6000, 0.06, 0.008, body=400), at(click(2000, 9000, 0.04, 0.004), 0.03, 0.1))
    sc = np.zeros(int(SR * 0.8))
    for k in range(8):
        sc += at(bp(noise(0.05), 1500, 6000) * env(int(SR * 0.05), 0.002, 0.02) * 0.4, k * 0.08, 0.8)
    S["screw_tighten"] = sc + at(click(800, 5000, 0.05, 0.008), 0.68, 0.8)
    S["meter_beep"] = tone(2700, 0.6) * 0.35 * env(int(SR * 0.6), 0.003, 5)
    return S


if __name__ == "__main__":
    ids = [s["id"] for s in json.load(open(os.path.join(HERE, "..", "content", "audio_cues.json"), encoding="utf8"))["sfx"]]
    S = sfx()
    missing = [i for i in ids if i not in S]
    assert not missing, missing
    for k, y in S.items():
        y = np.asarray(y, dtype=float)
        y = y / (np.max(np.abs(y)) + 1e-9) * 0.85
        fade = min(len(y), int(SR * 0.01)); y[-fade:] *= np.linspace(1, 0, fade)
        tmp = os.path.join(tempfile.gettempdir(), k + ".wav")
        wavfile.write(tmp, SR, (y * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, k + ".ogg")], check=True)
    print(len(S), "sfx written to", OUT)
