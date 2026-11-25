"""Realistic sound effects for the app, synthesised from physical models.

Mechanical parts (contactors, relays, breakers, buttons) are modal impacts: a short
excitation (noise burst) driving a bank of damped, inharmonic resonances of the
housing and the metal parts, with contact bounces a few milliseconds apart and a small
room reverb. Motors are an induction-motor model: magnetic hum at twice the line
frequency with its harmonics, rotor-slot whine tied to the speed, fan blade-pass tone
and turbulent air rising with the speed squared. The siren is a rotating-disc wail.
The intro theme is a short power-up: charge, a contactor closing, an opening chord.

Run: python sfx_real.py [id ...]  ->  ../assets/audio/sfx/<id>.mp3   (synced into the app in CI)
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio", "sfx")
rng = np.random.default_rng(11)


# ----------------------------------------------------------------- helpers
def n_(d):
    return int(SR * d)


def t(d):
    return np.arange(n_(d)) / SR


def noise(d):
    return rng.standard_normal(n_(d))


def filt(x, kind, f, o=2):
    f = np.atleast_1d(f) / (SR / 2)
    b, a = butter(o, f if len(f) > 1 else f[0], btype=kind)
    return lfilter(b, a, x)


def lp(x, f, o=2):
    return filt(x, "low", f, o)


def hp(x, f, o=2):
    return filt(x, "high", f, o)


def bp(x, lo, hi, o=2):
    return filt(x, "band", [lo, hi], o)


def place(dst, x, sec, g=1.0):
    i = n_(sec)
    m = min(len(x), len(dst) - i)
    if m > 0:
        dst[i:i + m] += x[:m] * g
    return dst


def silence(d):
    return np.zeros(n_(d))


def room(x, size=0.25, mix=0.18, damp=6000):
    """small room: exponentially decaying filtered noise impulse response"""
    ir = noise(size) * np.exp(-t(size) / (size / 5))
    ir = lp(ir, damp)
    ir[0] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = fftconvolve(x, ir)[: len(x)]
    return x * (1 - mix) + wet * mix * 1.6


def modal(freqs, decays, amps, d, excite=0.0015):
    """damped resonances excited by a short noise burst"""
    x = t(d)
    y = np.zeros_like(x)
    for f, dc, a in zip(freqs, decays, amps):
        ph = rng.uniform(0, 2 * np.pi)
        y += a * np.sin(2 * np.pi * f * x + ph) * np.exp(-x / dc)
    exc = noise(excite) * np.hanning(n_(excite))
    return fftconvolve(y, exc)[: len(y)] * 30 + y * 0.15


def impact(d, body, metal, hard=1.0):
    """one mechanical hit: housing body + metal parts + click transient"""
    bf, bdec = body
    y = modal([bf, bf * 1.73, bf * 2.41], [bdec * 0.5, bdec * 0.3, bdec * 0.2], [1, 0.5, 0.3], d)
    y += modal(metal, [0.005 + 0.009 * rng.random() for _ in metal], [0.5 + 0.5 * rng.random() for _ in metal], d) * 0.6
    tr = bp(noise(0.004), 2000, 12000) * np.hanning(n_(0.004)) * hard
    y[: len(tr)] += tr * 2
    return y


def bounce(hits, d):
    """several impacts (contact bounce): [(time, gain, body, metal)]"""
    y = silence(d)
    for sec, g, body, metal in hits:
        place(y, impact(d - sec, body, metal), sec, g)
    return y


def norm(y, peak=0.89):
    return y / (np.max(np.abs(y)) + 1e-9) * peak


def fade(y, a=0.002, b=0.01):
    y = y.copy()
    na, nb = n_(a), n_(b)
    if na:
        y[:na] *= np.linspace(0, 1, na)
    if nb:
        y[-nb:] *= np.linspace(1, 0, nb)
    return y


def loopable(y, xf=0.4):
    """crossfade the tail into the head so the clip loops without a seam"""
    k = n_(xf)
    head, body, tail = y[:k], y[k:-k], y[-k:]
    w = np.linspace(0, 1, k)
    return np.concatenate([body[:-0] if False else body, tail * (1 - w) + head * w])


# ----------------------------------------------------------------- mechanical
def contactor_pull():
    d = 0.35
    y = bounce([
        (0.000, 1.00, (95, 0.05), [1850, 2960, 4420, 6900]),   # armature hits the core
        (0.0045, 0.55, (140, 0.03), [2300, 3700, 5600]),      # contacts close
        (0.0085, 0.30, (140, 0.02), [2500, 4100]),            # bounce
    ], d)
    # magnetic buzz while the armature seats
    hum = sum(np.sin(2 * np.pi * 100 * k * t(0.08)) / k for k in range(1, 6)) * np.exp(-t(0.08) / 0.03)
    place(y, hum, 0, 0.08)
    return room(y, 0.3, 0.16)


def contactor_drop():
    d = 0.3
    y = bounce([
        (0.000, 0.75, (120, 0.03), [2100, 3400, 5200]),
        (0.006, 0.35, (160, 0.02), [2800, 4600]),
    ], d)
    # return springs ring
    place(y, np.sin(2 * np.pi * 3900 * t(0.15)) * np.exp(-t(0.15) / 0.04), 0.004, 0.05)
    return room(y, 0.28, 0.15)


def relay_click():
    d = 0.18
    y = bounce([(0, 1.0, (300, 0.01), [3300, 5100, 7600]), (0.003, 0.4, (300, 0.008), [4200, 6800])], d)
    return room(y, 0.2, 0.12)


def mcb(on=True):
    d = 0.35
    if on:
        y = bounce([(0, 1.0, (180, 0.04), [1500, 2650, 4100]), (0.018, 0.7, (210, 0.03), [2200, 3500, 5600])], d)
    else:
        # trip: spring-loaded snap, sharper and louder
        y = bounce([(0, 1.0, (150, 0.05), [1300, 2400, 3900, 6300]), (0.006, 0.6, (230, 0.03), [3100, 5300])], d)
        place(y, np.sin(2 * np.pi * 2700 * t(0.2)) * np.exp(-t(0.2) / 0.05), 0.002, 0.08)
    return room(y, 0.3, 0.15)


def pushbutton():
    d = 0.32
    y = bounce([(0, 1.0, (420, 0.015), [2600, 4400, 6600]), (0.004, 0.5, (520, 0.01), [3500, 5800])], d)
    place(y, impact(0.12, (480, 0.012), [3000, 5200]), 0.17, 0.55)  # release
    return room(y, 0.22, 0.14)


def selector():
    d = 0.2
    y = bounce([(0, 1.0, (360, 0.02), [2200, 3600, 5900]), (0.03, 0.6, (400, 0.015), [2900, 4700])], d)
    return room(y, 0.2, 0.14)


def estop():
    d = 0.4
    y = bounce([(0, 1.3, (110, 0.06), [900, 1700, 2900]), (0.012, 0.7, (260, 0.03), [2400, 4300, 6100])], d)
    return room(y, 0.3, 0.18)


def overload_trip():
    d = 0.25
    y = bounce([(0, 1.0, (240, 0.02), [2700, 4400, 6900]), (0.012, 0.6, (300, 0.015), [3600, 5900])], d)
    return room(y, 0.22, 0.14)


def din_click():
    d = 0.22
    y = bounce([(0, 1.0, (260, 0.02), [1900, 3300, 5100]), (0.025, 0.8, (300, 0.015), [2600, 4200])], d)
    return room(y, 0.2, 0.12)


def solenoid():
    d = 0.6
    y = bounce([(0, 1.3, (70, 0.08), [800, 1500, 2600]), (0.01, 0.5, (150, 0.04), [1900, 3100])], d)
    place(y, sum(np.sin(2 * np.pi * 100 * k * t(0.5)) / k for k in range(1, 5)) * 0.05, 0.02)
    return room(y, 0.3, 0.18)


def screw():
    d = 0.9
    y = silence(d)
    for k in range(9):
        place(y, bp(noise(0.04), 1800, 7000) * np.hanning(n_(0.04)) * (0.4 + 0.3 * rng.random()), k * 0.075)
    place(y, impact(0.15, (500, 0.01), [3000, 5000]), 0.72, 0.8)
    return room(y, 0.2, 0.1)


# ----------------------------------------------------------------- motor model
def motor(speed, d, inrush=None, strain=False):
    """speed: array 0..1 of nominal speed (1450 rpm), line 50 Hz"""
    x = t(d)
    rps = speed * 1450 / 60.0
    ph_rot = 2 * np.pi * np.cumsum(rps) / SR
    # magnetic hum at 100 Hz + harmonics; louder at standstill (inrush) and under strain
    load = inrush if inrush is not None else np.zeros_like(x)
    hum_amp = 0.3 + 0.6 * load + (0.7 if strain else 0)
    hum = (np.sin(2 * np.pi * 100 * x) + 0.55 * np.sin(2 * np.pi * 200 * x + 0.3) + 0.3 * np.sin(2 * np.pi * 300 * x + 1.1)
           + 0.18 * np.sin(2 * np.pi * 600 * x)) * hum_amp
    if strain:
        hum *= 1 + 0.25 * np.sin(2 * np.pi * 6 * x)
        hum += bp(noise(d), 150, 900) * 0.25
    # rotor slot whine (28 slots) with ±100 Hz sidebands
    slot = np.sin(28 * ph_rot) + 0.5 * np.sin(28 * ph_rot + 2 * np.pi * 100 * x) + 0.5 * np.sin(28 * ph_rot - 2 * np.pi * 100 * x)
    whine = slot * 0.2 * speed ** 1.5
    # fan: 9 blades, blade-pass tone + turbulent air
    bpf = np.sin(9 * ph_rot) * 0.3 * speed ** 2
    air = lp(bp(noise(d), 150, 1800, 3), 2200, 4) * 0.09 * speed ** 2 + lp(noise(d), 300, 3) * 0.12 * speed ** 2
    # rotation rumble (unbalance at 1×) and bearing hiss
    rumble = np.sin(ph_rot) * 0.2 * speed + bp(noise(d), 3000, 6000) * 0.006 * speed
    y = hum + whine + bpf + air + rumble
    return room(lp(y, 6000, 4), 0.35, 0.18, 4000)


def motor_start():
    d = 3.0
    x = t(d)
    sp = 1 - np.exp(-np.maximum(0, x - 0.05) * 2.2)
    inrush = np.exp(-np.maximum(0, x - 0.05) * 2.0) * (x > 0.04)
    y = motor(sp, d, inrush)
    place(y, contactor_pull() * 0.35, 0)
    return y


def motor_run():
    d = 6.0
    y = motor(np.full(n_(d), 1.0), d)
    return loopable(y, 0.6)


def motor_stop():
    d = 3.5
    x = t(d)
    sp = np.exp(-x * 1.1)
    y = motor(sp, d)
    y[: n_(0.02)] *= np.linspace(0.6, 1, n_(0.02))
    hum_cut = np.exp(-x / 0.05)  # the field collapses at once
    y = y - (np.sin(2 * np.pi * 100 * x) * 0.22) * (1 - hum_cut)
    place(y, contactor_drop() * 0.3, 0)
    return y


def motor_strain():
    d = 2.5
    return motor(np.full(n_(d), 0.02), d, np.full(n_(d), 1.0), strain=True)


def coil_hum(loud=False):
    d = 2.0
    x = t(d)
    y = sum(np.sin(2 * np.pi * 100 * k * x + k) / k ** (0.7 if loud else 1.4) for k in range(1, 9))
    if loud:
        y *= 1 + 0.3 * np.sign(np.sin(2 * np.pi * 50 * x)) * 0.3
        y += bp(noise(d), 300, 2500) * 0.3
    return loopable(room(y * 0.5, 0.2, 0.12), 0.3)


# ----------------------------------------------------------------- alarms
def siren():
    """rotating-disc siren: wail up and down, rich harmonics, loopable"""
    d = 3.0
    x = t(d)
    f = 520 + 640 * (0.5 - 0.5 * np.cos(2 * np.pi * x / d))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = sum(np.sin(k * ph) / k ** 0.9 for k in range(1, 9))
    y = lp(y, 5000) + bp(noise(d), 800, 4000) * 0.05
    y *= 1 + 0.04 * np.sin(2 * np.pi * 9 * x)
    return room(y * 0.5, 0.5, 0.22)


def buzzer():
    d = 2.0
    x = t(d)
    y = np.sign(np.sin(2 * np.pi * 400 * x)) * 0.5 + np.sin(2 * np.pi * 800 * x) * 0.3
    y = lp(y, 4000) * (0.5 + 0.5 * (np.sin(2 * np.pi * 2 * x) > 0))
    return room(y * 0.5, 0.2, 0.1)


# ----------------------------------------------------------------- electrical faults
def arc(d=1.5):
    y = silence(d)
    for _ in range(int(d * 70)):
        sec = rng.uniform(0, d - 0.02)
        g = rng.uniform(0.2, 1.0)
        place(y, bp(noise(0.012), 1500, 12000) * np.exp(-t(0.012) / 0.003), sec, g)
    y += np.sign(np.sin(2 * np.pi * 100 * t(d))) * bp(noise(d), 100, 1200) * 0.08
    return room(y, 0.3, 0.2)


def short_bang():
    d = 1.4
    y = silence(d)
    boom = lp(noise(0.9), 2500) * np.exp(-t(0.9) / 0.12) * 2.2 + np.sin(2 * np.pi * 55 * t(0.9)) * np.exp(-t(0.9) / 0.15) * 1.2
    place(y, boom, 0)
    place(y, arc(0.25) * 1.2, 0)
    place(y, mcb(False) * 1.3, 0.03)
    return room(y, 0.6, 0.25)


# ----------------------------------------------------------------- UI / music
def bell(f, d, dec=0.6, bright=1.0):
    x = t(d)
    partials = [(1, 1), (2.0, 0.4 * bright), (3.01, 0.2 * bright), (4.2, 0.12 * bright), (5.43, 0.06 * bright)]
    return sum(a * np.sin(2 * np.pi * f * k * x) * np.exp(-x / (dec / k ** 0.6)) for k, a in partials) * np.minimum(1, x / 0.003)


def pad(freqs, d, cutoff=(400, 3000), detune=0.006):
    x = t(d)
    y = np.zeros_like(x)
    for f in freqs:
        for dt in (-detune, 0, detune):
            ph = rng.uniform(0, 1)
            y += 2 * ((x * f * (1 + dt) + ph) % 1) - 1
    # opening low-pass sweep (frame-wise)
    out = np.zeros_like(y)
    st = 1024
    for i in range(0, len(y), st):
        k = i / len(y)
        fc = cutoff[0] + (cutoff[1] - cutoff[0]) * min(1, k * 2.2)
        out[i:i + st] = lp(y[max(0, i - 2048):i + st], fc)[-len(y[i:i + st]):]
    return out / (len(freqs) * 3)


def chime(notes, step=0.12, dec=0.6, bright=1.0):
    d = step * len(notes) + dec * 2
    y = silence(d)
    for i, f in enumerate(notes):
        place(y, bell(f, dec * 2, dec, bright), i * step)
    return room(y, 0.8, 0.28, 9000)


def whoosh(d=0.45, up=True):
    x = t(d)
    nz = noise(d)
    out = np.zeros_like(nz)
    st = 1024
    for i in range(0, len(nz), st):
        k = i / len(nz)
        f = 300 * (16 ** (k if up else 1 - k))
        out[i:i + st] = bp(nz[max(0, i - 2048):i + st], max(f * 0.6, 60), min(f * 1.6, 18000))[-len(nz[i:i + st]):]
    return out * np.sin(np.pi * x / d) ** 2


def intro_theme():
    """soundtrack of the intro (lib/ui/intro_page.dart, 8 s):
    0–1.9 s the schematic draws itself (charge rising on a 100 Hz bed),
    1.9 s S1 pressed, 2.1 s the contactor pulls in, 2.15–3.6 s the motor runs up,
    3.7 s the logo hits: sub, opening chord, bells, shimmer tail"""
    d = 8.0
    y = silence(d)
    x = t(d)
    # pen strokes: soft filtered scratches while the lines are drawn
    for k in range(14):
        sc = bp(noise(0.09), 2500, 7000) * np.hanning(n_(0.09)) * (0.05 + 0.04 * rng.random())
        place(y, sc, 0.1 + k * 0.125)
    rise = np.sin(2 * np.pi * np.cumsum(np.linspace(70, 520, n_(1.9))) / SR) * np.linspace(0, 0.22, n_(1.9)) ** 2
    place(y, rise + whoosh(1.9, True) * 0.25, 0)
    bed = (np.sin(2 * np.pi * 100 * x) + 0.4 * np.sin(2 * np.pi * 200 * x)) * 0.05 * np.minimum(1, x / 1.6) * np.exp(-np.maximum(0, x - 3.6) / 0.3)
    y += bed
    place(y, pushbutton() * 0.9, 1.9)
    place(y, contactor_pull() * 1.3, 2.1)
    md = 1.6
    mx = t(md)
    sp = 1 - np.exp(-mx * 2.4)
    inr = np.exp(-mx * 2.2)
    mot = motor(sp, md, inr) * np.minimum(1, (md - mx) / 0.25) * 0.55
    place(y, mot, 2.15)
    place(y, whoosh(0.5, True) * 0.4, 3.2)
    # 3.7 s: the hit
    sub = np.sin(2 * np.pi * 41.2 * t(1.8)) * np.exp(-t(1.8) / 0.5) * 1.0
    place(y, sub, 3.7)
    place(y, arc(0.16) * 0.3, 3.7)
    chord = pad([82.41, 123.47, 164.81, 207.65, 246.94, 369.99], 4.2, (300, 5200)) * 1.1
    chord *= np.minimum(1, t(4.2) / 0.06) * np.exp(-t(4.2) / 2.0)
    place(y, chord, 3.72)
    for i, f in enumerate([659.25, 987.77, 1244.5, 1318.5, 1975.5]):
        place(y, bell(f, 2.5, 0.9, 0.7) * (0.3 - i * 0.03), 3.8 + i * 0.11)
    place(y, hp(noise(2.4), 7000) * np.exp(-t(2.4) / 0.7) * 0.06, 3.75)
    y *= np.minimum(1, (d - x) / 0.6)
    return room(y, 1.6, 0.3, 8000)


# ----------------------------------------------------------------- machines
def conveyor_run():
    """small geared belt drive: gearbox whine, rollers ticking under the belt, belt rub"""
    d = 4.0
    x = t(d)
    y = motor(np.full(n_(d), 1.0), d) * 0.35
    y += np.sin(2 * np.pi * 410 * x) * 0.03 * (1 + 0.2 * np.sin(2 * np.pi * 3 * x))  # gear mesh
    for k in range(int(d * 11)):
        place(y, impact(0.05, (220, 0.008), [1400, 2300]) * (0.05 + 0.04 * rng.random()), k / 11 + rng.uniform(0, 0.01))
    y += lp(noise(d), 700) * 0.08
    return loopable(room(y, 0.4, 0.2), 0.4)


def air_extend():
    """valve opens: solenoid clunk, compressed air rushing in, piston hits its end stop"""
    d = 0.8
    y = silence(d)
    place(y, solenoid() * 0.6, 0)
    rush = bp(noise(0.45), 900, 6500) * np.minimum(1, t(0.45) / 0.01) * np.exp(-t(0.45) / 0.15) * 0.5
    place(y, rush, 0.015)
    place(y, impact(0.3, (85, 0.05), [900, 1700, 2600]) * 0.8, 0.28)
    return room(y, 0.35, 0.2)


def air_exhaust():
    """valve drops: exhaust blast through the silencer, spring return, soft end stop"""
    d = 0.9
    y = silence(d)
    place(y, relay_click() * 0.4, 0)
    hiss = hp(bp(noise(0.6), 2200, 11000), 1800) * np.minimum(1, t(0.6) / 0.004) * np.exp(-t(0.6) / 0.18) * 0.6
    place(y, hiss, 0.008)
    place(y, impact(0.25, (120, 0.04), [1200, 2100]) * 0.5, 0.38)
    return room(y, 0.35, 0.2)


def press_stamp():
    """the ram lands on the part: heavy body, ringing steel, a little air"""
    d = 1.2
    y = bounce([(0, 1.4, (55, 0.12), [420, 760, 1310, 2210, 3480]), (0.012, 0.5, (90, 0.06), [980, 1800])], d)
    place(y, np.sin(2 * np.pi * 36 * t(0.6)) * np.exp(-t(0.6) / 0.12) * 0.8, 0)
    return room(y, 0.6, 0.25)


def lift_ding():
    y = silence(1.8)
    place(y, bell(1318.5, 1.6, 0.7, 0.5) * 0.5, 0)
    place(y, bell(1046.5, 1.6, 0.8, 0.5) * 0.5, 0.32)
    return room(y, 0.8, 0.3, 9000)


def door_slide():
    d = 1.0
    x = t(d)
    env_ = np.sin(np.pi * x / d) ** 1.5
    y = lp(noise(d), 900) * env_ * 0.4 + bp(noise(d), 2000, 5000) * env_ * 0.03
    y += np.sin(2 * np.pi * 52 * x) * env_ * 0.1
    place(y, impact(0.2, (160, 0.03), [1200, 2400]) * 0.35, d - 0.2)
    return room(y, 0.3, 0.15)


def horn():
    """electromechanical diaphragm horn, loopable"""
    d = 2.0
    x = t(d)
    y = np.sign(np.sin(2 * np.pi * 345 * x)) * 0.6 + np.sign(np.sin(2 * np.pi * 690 * x + 0.4)) * 0.2
    y = bp(y, 300, 3200) + bp(y, 1200, 1800) * 0.8  # bell-mouth formant
    y *= 1 + 0.03 * np.sin(2 * np.pi * 50 * x)
    return loopable(room(y * 0.5, 0.4, 0.2), 0.3)


def bottle_clink():
    y = silence(0.7)
    place(y, modal([2650, 4310, 6020, 7900], [0.12, 0.08, 0.05, 0.03], [1, 0.6, 0.4, 0.2], 0.6) * 0.5, 0)
    place(y, modal([2900, 4700, 6600], [0.1, 0.06, 0.04], [0.8, 0.5, 0.3], 0.5) * 0.3, 0.06)
    return room(y, 0.3, 0.15)


def box_drop():
    d = 0.6
    y = bounce([(0, 1.0, (110, 0.05), [520, 940, 1500]), (0.09, 0.35, (130, 0.03), [700, 1300])], d)
    place(y, lp(noise(0.2), 1500) * np.exp(-t(0.2) / 0.05) * 0.4, 0)
    return room(y, 0.3, 0.18)


def intro_jingle():
    y = silence(2.4)
    place(y, contactor_pull(), 0)
    place(y, chime([659.25, 987.77, 1318.5], 0.11, 0.7, 0.7), 0.08)
    return y


def sfx():
    S = {}
    S["contactor_pull_in"] = contactor_pull()
    S["contactor_drop_out"] = contactor_drop()
    S["relay_click"] = relay_click()
    S["mcb_on"] = mcb(True)
    S["mcb_trip"] = mcb(False)
    S["pushbutton_click"] = pushbutton()
    S["selector_detent"] = selector()
    S["estop_latch"] = estop()
    S["overload_trip"] = overload_trip()
    S["din_rail_click"] = din_click()
    S["solenoid_clunk"] = solenoid()
    S["screw_tighten"] = screw()
    S["motor_start"] = motor_start()
    S["motor_run"] = motor_run()
    S["motor_stop"] = motor_stop()
    S["motor_strain"] = motor_strain()
    S["coil_hum"] = coil_hum(False)
    S["coil_hum_loud"] = coil_hum(True)
    S["alarm_siren"] = siren()
    S["buzzer"] = buzzer()
    S["arc_crackle"] = arc()
    S["short_circuit_bang"] = short_bang()
    S["ui_tap"] = room(impact(0.08, (900, 0.006), [4200, 6800]) * 0.6, 0.1, 0.08)
    S["ui_whoosh"] = whoosh(0.35)
    S["explode_whoosh"] = whoosh(0.6) + np.pad(impact(0.1, (400, 0.01), [2600]) * 0.3, (n_(0.05), n_(0.45)))[: n_(0.6)]
    S["assemble_snap"] = np.concatenate([whoosh(0.35, False) * 0.6, din_click()])
    S["part_select"] = chime([1318.5], 0.1, 0.25, 0.6)
    S["success_chime"] = chime([987.77, 1318.5], 0.1, 0.5, 0.7)
    S["success_fanfare"] = chime([659.25, 830.61, 987.77, 1318.5, 987.77, 1318.5, 1661.2], 0.11, 0.7, 0.7)
    S["soft_fail"] = chime([392.0, 311.13], 0.18, 0.5, 0.3)
    S["error_buzz"] = room(lp(np.sign(np.sin(2 * np.pi * 150 * t(0.35))), 2000) * np.exp(-t(0.35) / 0.25) * 0.4, 0.1, 0.1)
    S["warning_alert"] = chime([880, 659.25], 0.2, 0.35, 0.5)
    S["timer_tick"] = np.concatenate([np.pad(relay_click() * 0.35, (0, n_(0.5) - n_(0.18))) for _ in range(4)])
    S["meter_beep"] = room(np.sin(2 * np.pi * 2730 * t(0.45)) * np.minimum(1, t(0.45) / 0.004) * np.minimum(1, (0.45 - t(0.45)) / 0.01) * 0.4, 0.1, 0.05)
    S["water_flow"] = loopable(lp(noise(4.0), 1600) * 0.4 + bp(noise(4.0), 1800, 5200) * 0.06 * (1 + 0.5 * np.sin(2 * np.pi * 1.3 * t(4.0))), 0.4)
    S["stage_sting"] = chime([659.25, 987.77], 0.12, 0.6, 0.7)
    S["outro_sting"] = chime([1318.5, 987.77, 659.25], 0.16, 0.8, 0.7)
    S["intro_jingle"] = intro_jingle()
    S["intro_theme"] = intro_theme()
    S["conveyor_run"] = conveyor_run()
    S["air_extend"] = air_extend()
    S["air_exhaust"] = air_exhaust()
    S["press_stamp"] = press_stamp()
    S["lift_ding"] = lift_ding()
    S["door_slide"] = door_slide()
    S["horn"] = horn()
    S["bottle_clink"] = bottle_clink()
    S["box_drop"] = box_drop()
    return S


LOOPS = {"motor_run", "coil_hum", "coil_hum_loud", "alarm_siren", "buzzer", "water_flow", "conveyor_run", "horn"}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    import sys

    S = sfx()
    only = set(sys.argv[1:])  # e.g. python sfx_real.py intro_theme horn: write just these
    for k, y in S.items():
        if only and k not in only:
            continue
        y = norm(np.asarray(y, dtype=float), 0.89 if k != "intro_theme" else 0.95)
        if k not in LOOPS:
            y = fade(y, 0.0005, 0.02)
        tmp = os.path.join(tempfile.gettempdir(), k + ".wav")
        wavfile.write(tmp, SR, (y * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-ac", "1", "-c:a", "libmp3lame", "-b:a", "128k", os.path.join(OUT, k + ".mp3")], check=True)
    print(len(S), "sfx written to", os.path.abspath(OUT))
