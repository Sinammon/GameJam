#!/usr/bin/env python3
"""Bunker 7 audio synthesizer: writes every sound in bunker-7/audio/ as 16-bit mono WAV.

Pure Python standard library (no numpy, no pip, no downloads). Deterministic: every sound has a fixed
random seed, so running it twice gives byte-identical files.

    python3 bunker-7/tools/synth_audio.py                 # everything
    python3 bunker-7/tools/synth_audio.py --only ui_click,music_menu
    python3 bunker-7/tools/synth_audio.py --list          # names
    python3 bunker-7/tools/synth_audio.py --report        # no files written, only the sanity report

Sound effects are 22.05 kHz, music and ambient loops 16 kHz (keeps the web build small; the music is
deliberately a bit "old radio"). Loops carry a WAV `smpl` loop chunk, and are built so the last sample
flows into the first (events wrap around the end, filters and reverbs run over two passes).
After writing, the report prints per file: duration, peak, rms, DC offset, loop seam and an ASCII envelope.

Add a sound: write a function that returns a list of floats (-1..1) and register it in SOUNDS below
(see AUDIO_NOTES.md).
"""
import argparse
import math
import os
import random
import struct
import sys

SFX_SR = 22050
MUS_SR = 16000
SR = SFX_SR
TAU = 2.0 * math.pi


def use_sr(sr):
    global SR
    SR = sr


def n_of(sec):
    return max(1, int(round(sec * SR)))


# ------------------------------------------------------------------ basic signals

def zeros(n):
    return [0.0] * n


def white(n, rnd):
    r = rnd.random
    return [r() * 2.0 - 1.0 for _ in range(n)]


def hz(name):
    """'A4' -> 440.0, 'F#3', 'Bb2'."""
    letters = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semi = letters[name[0]]
    i = 1
    if name[i] == "#":
        semi += 1
        i += 1
    elif name[i] == "b":
        semi -= 1
        i += 1
    octave = int(name[i:])
    midi = 12 * (octave + 1) + semi
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def loopf(f, total_s):
    """Snaps a frequency so a whole number of cycles fits in the loop (keeps a sine seamless)."""
    return max(1.0, round(f * total_s)) / total_s


def const(f, n):
    return [f] * n


def sweep(f0, f1, n):
    """Exponential frequency sweep."""
    if n <= 1:
        return [f0]
    r = f1 / f0
    return [f0 * r ** (i / (n - 1)) for i in range(n)]


def osc_sine(freqs, phase=0.0):
    k = TAU / SR
    out = []
    p = phase
    for f in freqs:
        out.append(math.sin(p))
        p += f * k
    return out


def osc_saw(freqs, phase=0.0):
    out = []
    p = phase
    for f in freqs:
        out.append(2.0 * p - 1.0)
        p += f / SR
        p -= math.floor(p)
    return out


def osc_square(freqs, duty=0.5):
    out = []
    p = 0.0
    for f in freqs:
        out.append(1.0 if p < duty else -1.0)
        p += f / SR
        p -= math.floor(p)
    return out


def osc_tri(freqs):
    out = []
    p = 0.0
    for f in freqs:
        out.append(4.0 * abs(p - 0.5) - 1.0)
        p += f / SR
        p -= math.floor(p)
    return out


def exp_env(n, tau, attack=0.002):
    """Linear attack then exponential decay (tau in seconds)."""
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        v = math.exp(-(i / SR) / tau)
        if i < a:
            v *= i / a
        out.append(v)
    return out


def ar_env(n, atk, rel):
    """Smooth attack / sustain / release (raised cosine), times in seconds."""
    a = max(1, int(atk * SR))
    r = max(1, int(rel * SR))
    out = []
    for i in range(n):
        v = 1.0
        if i < a:
            v = 0.5 - 0.5 * math.cos(math.pi * i / a)
        j = n - 1 - i
        if j < r:
            v = min(v, 0.5 - 0.5 * math.cos(math.pi * j / r))
        out.append(v)
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def mix_into(dst, src, start=0, gain=1.0):
    n = len(dst)
    for i, v in enumerate(src):
        j = start + i
        if 0 <= j < n:
            dst[j] += v * gain


def scaled(a, g):
    return [x * g for x in a]


def summed(*sigs):
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, v in enumerate(s):
            out[i] += v
    return out


def pad_to(a, n):
    return a + [0.0] * (n - len(a)) if len(a) < n else a[:n]


# ------------------------------------------------------------------ filters

def svf(x, fc, q=0.707, mode="lp"):
    """Zavalishin TPT state-variable filter. fc: Hz or a per-sample list. mode: lp, hp, bp (unity peak), notch."""
    out = [0.0] * len(x)
    s1 = s2 = 0.0
    k = 1.0 / q
    lim = SR * 0.45
    is_list = isinstance(fc, (list, tuple))
    if not is_list:
        g = math.tan(math.pi * min(fc, lim) / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    for i, v in enumerate(x):
        if is_list:
            g = math.tan(math.pi * min(fc[i], lim) / SR)
            a1 = 1.0 / (1.0 + g * (g + k))
            a2 = g * a1
            a3 = g * a2
        v3 = v - s2
        v1 = a1 * s1 + a2 * v3
        v2 = s2 + a2 * s1 + a3 * v3
        s1 = 2.0 * v1 - s1
        s2 = 2.0 * v2 - s2
        if mode == "lp":
            out[i] = v2
        elif mode == "bp":
            out[i] = k * v1
        elif mode == "hp":
            out[i] = v - k * v1 - v2
        else:
            out[i] = v - k * v1
    return out


def lowpass(x, fc, q=0.707):
    return svf(x, fc, q, "lp")


def highpass(x, fc, q=0.707):
    return svf(x, fc, q, "hp")


def bandpass(x, fc, q=2.0):
    return svf(x, fc, q, "bp")


def loop_filter(fn, x):
    """Runs a filter function over two copies and keeps the second: the result wraps seamlessly."""
    n = len(x)
    return fn(x + x)[n:]


# ------------------------------------------------------------------ effects

def echo(x, delay_s, fb, mix, loop=False, taps=7):
    n = len(x)
    d = max(1, int(delay_s * SR))
    out = list(x)
    for k in range(1, taps + 1):
        g = mix * (fb ** (k - 1))
        if g < 0.004:
            break
        off = d * k
        for i in range(n):
            j = i - off
            if loop:
                out[i] += x[j % n] * g
            elif j >= 0:
                out[i] += x[j] * g
    return out


def reverb(x, rt=2.0, mix=0.3, damp=0.35, loop=False):
    """Small Schroeder/Freeverb style mono reverb. loop=True runs two passes so the tail wraps around."""
    n = len(x)
    src = x + x if loop else x + [0.0] * int(rt * SR)
    comb_ms = [29.7, 37.1, 41.1, 43.7, 50.3]
    combs = []
    for ms in comb_ms:
        d = max(2, int(ms * 0.001 * SR))
        g = 10.0 ** (-3.0 * (ms * 0.001) / rt)
        combs.append([[0.0] * d, 0, g, 0.0])
    ap_state = [[[0.0] * max(2, int(5.0 * 0.001 * SR)), 0], [[0.0] * max(2, int(1.7 * 0.001 * SR)), 0]]
    wet = [0.0] * len(src)
    for i, v in enumerate(src):
        acc = 0.0
        for c in combs:
            buf, pos, g, lp = c
            y = buf[pos]
            lp = y * (1.0 - damp) + lp * damp
            c[3] = lp
            buf[pos] = v * 0.2 + lp * g
            c[1] = pos + 1 if pos + 1 < len(buf) else 0
            acc += y
        for st in ap_state:
            buf, pos = st
            b = buf[pos]
            out = -acc + b
            buf[pos] = acc + b * 0.5
            st[1] = pos + 1 if pos + 1 < len(buf) else 0
            acc = out
        wet[i] = acc
    if loop:
        wet = wet[n:]
        src = src[n:]
    out = [0.0] * len(wet)
    for i in range(len(wet)):
        dry = src[i] if i < len(src) else 0.0
        out[i] = dry + wet[i] * mix
    return out


def soft_clip(x, drive=1.0):
    return [math.tanh(v * drive) for v in x]


# ------------------------------------------------------------------ mixing helper

class Mix:
    def __init__(self, dur, loop=True):
        self.n = n_of(dur)
        self.buf = [0.0] * self.n
        self.loop = loop

    def add(self, t, sig, gain=1.0):
        s = int(round(t * SR))
        n = self.n
        b = self.buf
        if self.loop:
            for i, v in enumerate(sig):
                b[(s + i) % n] += v * gain
        else:
            for i, v in enumerate(sig):
                j = s + i
                if j >= n:
                    break
                if j >= 0:
                    b[j] += v * gain


def peak_of(x):
    return max((abs(v) for v in x), default=0.0)


def normalize(x, peak):
    p = peak_of(x)
    if p < 1e-9:
        return x
    g = peak / p
    return [v * g for v in x]


def fade_edges(x, fade_in=0.001, fade_out=0.004):
    n = len(x)
    a = int(fade_in * SR)
    b = int(fade_out * SR)
    out = list(x)
    for i in range(min(a, n)):
        out[i] *= i / a
    for i in range(min(b, n)):
        out[n - 1 - i] *= i / b
    return out


# ------------------------------------------------------------------ instruments

def pad_chord(freqs, dur, atk, rel, cutoff, rnd, detune_cents=(-8.0, 0.0, 7.0), sub=True):
    """Soft pad: detuned saws per note + a sine an octave down, one lowpass, raised-cosine envelope."""
    n = n_of(dur + rel)
    acc = [0.0] * n
    for f in freqs:
        for c in detune_cents:
            ff = f * 2.0 ** (c / 1200.0)
            p = rnd.random()
            inc = ff / SR
            for i in range(n):
                acc[i] += 2.0 * p - 1.0
                p += inc
                if p >= 1.0:
                    p -= 1.0
        if sub:
            k = TAU * f * 0.5 / SR
            for i in range(n):
                acc[i] += 1.4 * math.sin(k * i)
    acc = lowpass(acc, cutoff, 0.8)
    env = ar_env(n, atk, rel)
    norm = 1.0 / (len(freqs) * (len(detune_cents) + 1))
    return [a * e * norm for a, e in zip(acc, env)]


def sine_note(freq, dur, atk, rel, harm=0.0):
    n = n_of(dur + rel)
    k = TAU * freq / SR
    env = ar_env(n, atk, rel)
    return [(math.sin(k * i) + harm * math.sin(2 * k * i)) * env[i] for i in range(n)]


BELL_PARTIALS = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.55), (2.76, 0.32, 0.4), (4.07, 0.16, 0.25), (5.4, 0.1, 0.18)]


def bell(freq, dur, bright=1.0):
    """Music-box / glass bell: inharmonic partials, higher ones fade faster."""
    n = n_of(dur)
    out = [0.0] * n
    for ratio, amp, dec in BELL_PARTIALS:
        f = freq * ratio
        if f > SR * 0.45:
            continue
        a = amp * (bright if ratio > 1.5 else 1.0)
        tau = dur * 0.35 * dec
        k = TAU * f / SR
        for i in range(n):
            t = i / SR
            at = min(1.0, t / 0.004)
            out[i] += a * at * math.exp(-t / tau) * math.sin(k * i)
    return out


def pluck(freq, dur, rnd, decay=0.996, bright=0.5):
    """Karplus-Strong string."""
    n = n_of(dur)
    period = max(2, int(round(SR / freq)))
    buf = [(rnd.random() * 2 - 1) for _ in range(period)]
    # soften the initial noise burst
    for i in range(1, period):
        buf[i] = buf[i] * bright + buf[i - 1] * (1 - bright)
    out = [0.0] * n
    pos = 0
    for i in range(n):
        v = buf[pos]
        nxt = buf[(pos + 1) % period]
        buf[pos] = (v + nxt) * 0.5 * decay
        out[i] = v
        pos = (pos + 1) % period
    return out


def kick(dur=0.35, f0=95.0, f1=38.0, tau=0.12):
    n = n_of(dur)
    k = TAU / SR
    p = 0.0
    out = []
    for i in range(n):
        t = i / SR
        f = f1 + (f0 - f1) * math.exp(-t / 0.025)
        p += f * k
        out.append(math.sin(p) * math.exp(-t / tau) * min(1.0, t / 0.002))
    return out


def noise_burst(dur, tau, rnd, lo=None, hi=None, q=None, band=None):
    n = n_of(dur)
    x = white(n, rnd)
    if band is not None:
        x = bandpass(x, band, q or 1.5)
    if lo is not None:
        x = highpass(x, lo)
    if hi is not None:
        x = lowpass(x, hi)
    env = exp_env(n, tau, 0.0008)
    return [a * b for a, b in zip(x, env)]


def thump(dur, f0, f1, tau, drop=0.03):
    n = n_of(dur)
    k = TAU / SR
    p = 0.0
    out = []
    for i in range(n):
        t = i / SR
        f = f1 + (f0 - f1) * math.exp(-t / drop)
        p += f * k
        out.append(math.sin(p) * math.exp(-t / tau) * min(1.0, t / 0.001))
    return out


def metal_ring(freq, dur, rnd, ratios=(1.0, 2.32, 4.18, 6.7, 9.1), amps=(1.0, 0.7, 0.5, 0.35, 0.22), tau=0.25, jitter=0.01):
    n = n_of(dur)
    out = [0.0] * n
    for r, a in zip(ratios, amps):
        f = freq * r * (1.0 + rnd.uniform(-jitter, jitter))
        if f > SR * 0.45:
            continue
        k = TAU * f / SR
        t_p = tau / (0.6 + 0.4 * r)
        for i in range(n):
            t = i / SR
            out[i] += a * math.exp(-t / t_p) * math.sin(k * i)
    return out


def creak(dur, rnd, f0=300.0, f1=800.0, rate0=30.0, rate1=75.0, q=14.0, wobble=0.25):
    """Stick-slip creak: an irregular impulse train through a swept, very resonant bandpass."""
    n = n_of(dur)
    pulses = [0.0] * n
    phase = 0.0
    jit = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        jit += (rnd.random() - 0.5) * 0.6
        jit *= 0.98
        r = (rate0 + (rate1 - rate0) * t) * (1.0 + wobble * jit)
        phase += max(5.0, r) / SR
        if phase >= 1.0:
            phase -= 1.0
            pulses[i] = rnd.uniform(0.5, 1.0)
    fc = []
    drift = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        drift += (rnd.random() - 0.5) * 0.04
        drift *= 0.995
        fc.append((f0 + (f1 - f0) * t) * (1.0 + 0.25 * drift))
    y = bandpass(pulses, fc, q)
    env = ar_env(n, dur * 0.2, dur * 0.35)
    return [a * b * 6.0 for a, b in zip(y, env)]


FORMANTS = {
    "aa": [(700.0, 6.0, 1.0), (1100.0, 6.0, 0.6), (2500.0, 6.0, 0.15)],
    "oh": [(500.0, 6.0, 1.0), (850.0, 6.0, 0.7), (2300.0, 6.0, 0.12)],
    "uu": [(330.0, 6.0, 1.0), (700.0, 6.0, 0.5), (2200.0, 6.0, 0.1)],
    "ah": [(800.0, 5.0, 1.0), (1250.0, 5.0, 0.55), (2600.0, 6.0, 0.15)],
}


def vocal(f0_curve, vowel, rnd, rasp=0.0, breath=0.0, shift=1.0, vowel_to=None):
    """Voiced sound: a jittery glottal saw through formant bandpasses. f0_curve is a per-sample list in Hz."""
    n = len(f0_curve)
    src = []
    p = 0.0
    for i in range(n):
        f = f0_curve[i] * (1.0 + 0.012 * (rnd.random() - 0.5) * 2.0)
        src.append(2.0 * p - 1.0)
        p += f / SR
        p -= math.floor(p)
    if rasp > 0:
        k = TAU * 31.0 / SR
        src = [s * (1.0 - rasp * (0.5 + 0.5 * math.sin(k * i))) for i, s in enumerate(src)]
    if breath > 0:
        src = [s + breath * (rnd.random() * 2 - 1) for s in src]
    out = [0.0] * n
    f_a = FORMANTS[vowel]
    f_b = FORMANTS[vowel_to] if vowel_to else f_a
    for (fa, q, amp), (fb, _, _) in zip(f_a, f_b):
        fc = [(fa + (fb - fa) * i / max(1, n - 1)) * shift for i in range(n)]
        y = bandpass(src, fc, q)
        for i in range(n):
            out[i] += y[i] * amp
    return out


def crackle(total_s, rnd, count, gain):
    """Sparse radio crackle, circular."""
    n = n_of(total_s)
    out = [0.0] * n
    for _ in range(count):
        ln = int(rnd.uniform(0.003, 0.02) * SR)
        start = rnd.randrange(n)
        amp = gain * rnd.uniform(0.2, 1.0)
        prev = 0.0
        for j in range(ln):
            v = (rnd.random() * 2 - 1)
            hp = v - prev
            prev = v
            out[(start + j) % n] += hp * amp * (1.0 - j / ln) ** 2
    return out


def wind_noise(total_s, rnd, level=1.0, low=250.0, high=900.0, cycles=(2, 5), gust_cycles=3, whistle=0.0):
    """Looping wind: noise through a slowly swept bandpass with gusts (all LFOs fit the loop length)."""
    n = n_of(total_s)
    x = white(n, rnd)
    xx = x + x
    fc = []
    amp = []
    for i in range(2 * n):
        t = (i % n) / n
        f = (low + high) * 0.5 + (high - low) * 0.5 * (0.6 * math.sin(TAU * cycles[0] * t) + 0.4 * math.sin(TAU * cycles[1] * t + 1.3))
        fc.append(f)
        g = 0.5 + 0.5 * math.sin(TAU * gust_cycles * t - 1.0)
        amp.append(0.25 + 0.75 * g * g)
    y = bandpass(xx, fc, 1.4)
    y = lowpass(y, 2200.0)
    y = [a * b for a, b in zip(y, amp)]
    if whistle > 0:
        wf = [900.0 + 260.0 * math.sin(TAU * 2 * (i % n) / n + 0.7) + 120.0 * math.sin(TAU * 7 * (i % n) / n) for i in range(2 * n)]
        w = bandpass(xx, wf, 40.0)
        wamp = [max(0.0, math.sin(TAU * 1 * (i % n) / n - 0.4)) ** 2 for i in range(2 * n)]
        y = [a + whistle * b * c * 14.0 for a, b, c in zip(y, w, wamp)]
    return [v * level for v in y[n:]]


# ------------------------------------------------------------------ music

def music_menu():
    use_sr(MUS_SR)
    rnd = random.Random(101)
    beat = 0.875
    bar = 4 * beat
    total = 8 * bar   # 28 s
    pads = Mix(total)
    chords = [("A2", "E3", "A3", "C4"), ("F2", "C3", "F3", "A3"), ("C3", "G3", "C4", "E4"), ("E2", "B2", "E3", "G3")]
    for ci, ch in enumerate(chords):
        t0 = ci * 2 * bar
        pads.add(t0, pad_chord([hz(x) for x in ch], 2 * bar, 2.2, 3.2, 700.0, rnd), 0.55)
    bass = Mix(total)
    for ci, ch in enumerate(chords):
        bass.add(ci * 2 * bar, sine_note(hz(ch[0]), 2 * bar - 0.5, 1.4, 2.0, harm=0.45), 0.5)
    bells = Mix(total)
    melody = [(1, "A4", 3), (3, "C5", 3), (5.5, "E5", 3.5), (7, "D5", 3), (9, "C5", 3), (11, "A4", 3), (12.5, "F4", 3),
              (14.5, "A4", 3.5), (17, "E5", 3), (19, "G5", 3), (21, "E5", 3), (23, "D5", 3.5), (25, "B4", 3), (27, "G4", 3.5),
              (29, "E5", 3), (31, "B4", 4)]
    for b, nm, ln in melody:
        bells.add(b * beat, bell(hz(nm), ln, 0.8), 0.5)
    bell_sig = echo(bells.buf, beat * 1.5, 0.45, 0.55, loop=True)
    body = [a + b for a, b in zip(pads.buf, bell_sig)]
    body = reverb(body, rt=2.6, mix=0.35, damp=0.45, loop=True)
    cr = crackle(total, rnd, 55, 0.05)
    out = [b + c + d * 1.0 for b, c, d in zip(body, bass.buf, cr)]
    return normalize(out, 0.8), True


def music_bunker():
    use_sr(MUS_SR)
    rnd = random.Random(202)
    total = 28.0
    n = n_of(total)
    # drone: D1 with its octave and fifth, slow breathing
    drone = [0.0] * n
    f = loopf(hz("D2"), total)
    k1 = TAU * loopf(f * 0.5, total) / SR
    k2 = TAU * f / SR
    k3 = TAU * loopf(f * 1.5, total) / SR
    for i in range(n):
        t = i / n
        breath = 0.65 + 0.35 * math.sin(TAU * 2 * t)
        drone[i] = (math.sin(k1 * i) * 0.9 + math.sin(k2 * i + 0.4 * math.sin(TAU * 1 * t)) * 0.5 + math.sin(k3 * i) * 0.12) * breath
    pads = Mix(total)
    pads.add(0.0, pad_chord([hz(x) for x in ("D3", "F3", "A3", "E4")], 11.0, 5.0, 5.5, 520.0, rnd), 0.6)
    pads.add(14.0, pad_chord([hz(x) for x in ("Bb2", "D3", "F3", "A3")], 11.0, 5.0, 5.5, 480.0, rnd), 0.6)
    # electrical hum with slow tremolo
    hum = [0.0] * n
    for i in range(n):
        t = i / SR
        trem = 0.75 + 0.25 * math.sin(TAU * 4.0 * t / total * 1.0)
        hum[i] = (math.sin(TAU * 100.0 * t) * 0.5 + math.sin(TAU * 200.0 * t) * 0.25 + math.sin(TAU * 300.0 * t) * 0.1) * trem
    room = loop_filter(lambda s: lowpass(s, 380.0), white(n, rnd))
    fx = Mix(total)
    fx.add(9.2, creak(1.7, rnd, 260.0, 620.0, 28.0, 55.0, 12.0), 0.16)
    fx.add(21.4, creak(2.2, rnd, 380.0, 220.0, 62.0, 30.0, 10.0), 0.13)
    for t in (4.1, 16.8, 25.3):
        d = [math.sin(TAU * 1850.0 * (i / SR)) * math.exp(-(i / SR) / 0.03) for i in range(n_of(0.25))]
        fx.add(t, d, 0.07)
    fxb = Mix(total)
    fxb.add(12.0, bell(hz("A3"), 4.5, 0.4), 0.18)
    fxb.add(25.0, bell(hz("D4"), 3.5, 0.4), 0.14)
    wet = [a + b + c for a, b, c in zip(pads.buf, fx.buf, fxb.buf)]
    wet = reverb(wet, rt=3.0, mix=0.4, damp=0.5, loop=True)
    out = [w + d * 0.5 + h * 0.035 + r * 0.05 for w, d, h, r in zip(wet, drone, hum, room)]
    return normalize(out, 0.75), True


def music_expedition():
    use_sr(MUS_SR)
    rnd = random.Random(303)
    total = 28.0
    n = n_of(total)
    drone = [0.0] * n
    k1 = TAU * loopf(hz("E2"), total) / SR
    k2 = TAU * loopf(hz("E1"), total) / SR
    for i in range(n):
        t = i / n
        sw = 0.5 + 0.5 * math.sin(TAU * t - 1.2)
        drone[i] = (math.sin(k2 * i) * 0.9 + math.sin(k1 * i) * 0.45 * sw)
    pads = Mix(total)
    pads.add(2.0, pad_chord([hz(x) for x in ("E3", "B3", "F4")], 12.0, 6.0, 6.0, 420.0, rnd), 0.35)
    pads.add(15.0, pad_chord([hz(x) for x in ("E3", "G3", "B3")], 11.0, 5.0, 6.0, 450.0, rnd), 0.35)
    plucks = Mix(total)
    notes = [(1.0, "E3"), (5.5, "B3"), (9.0, "F3"), (11.6, "E3"), (17.0, "G3"), (20.5, "B2"), (24.0, "F3"), (26.2, "E3")]
    for t, nm in notes:
        p = pluck(hz(nm), 3.2, rnd, 0.9965, 0.35)
        plucks.add(t, lowpass(p, 1400.0), 0.55)
    whistle = Mix(total)
    wn = n_of(6.0)
    wf = [hz("B4") * (1.0 + 0.012 * math.sin(TAU * 5.0 * i / SR)) * (1.0 - 0.02 * i / wn) for i in range(wn)]
    wh = mul(osc_sine(wf), ar_env(wn, 2.5, 2.5))
    whistle.add(14.0, wh, 0.05)
    thuds = Mix(total)
    thuds.add(7.4, metal_ring(180.0, 2.5, rnd, tau=0.7), 0.12)
    thuds.add(22.1, metal_ring(130.0, 2.5, rnd, tau=0.9), 0.1)
    wet = [a + b + c + d for a, b, c, d in zip(pads.buf, plucks.buf, whistle.buf, thuds.buf)]
    wet = reverb(wet, rt=3.4, mix=0.45, damp=0.5, loop=True)
    out = [w + d * 0.4 for w, d in zip(wet, drone)]
    return normalize(out, 0.75), True


def music_danger():
    use_sr(MUS_SR)
    rnd = random.Random(404)
    total = 16.0
    n = n_of(total)
    beat = 60.0 / 90.0   # 24 beats in 16 s
    kicks = Mix(total)
    for b in range(24):
        kicks.add(b * beat, kick(0.4, 100.0, 40.0, 0.14), 0.9 if b % 2 == 0 else 0.55)
    # dissonant string cluster: E3 + F3 + Bb3 with a 6 Hz tremolo and a swell that fits the loop
    cluster = [0.0] * n
    for f in (hz("E3"), hz("F3"), hz("Bb3")):
        p = rnd.random()
        for i in range(n):
            cluster[i] += 2.0 * p - 1.0
            p += f / SR
            p -= math.floor(p)
    cluster = loop_filter(lambda s: lowpass(s, 1100.0, 1.2), cluster)
    cl = []
    for i, v in enumerate(cluster):
        t = i / n
        swell = 0.35 + 0.65 * (0.5 - 0.5 * math.cos(TAU * t))
        trem = 0.7 + 0.3 * math.sin(TAU * 6.0 * i / SR)
        cl.append(v * swell * trem)
    # riser: noise through a rising band, amplitude fades to nothing at both ends so the loop is clean
    x = white(n, rnd)
    fc = [400.0 + 2600.0 * (i / n) ** 2 for i in range(n)]
    ris = bandpass(x, fc, 2.5)
    ris = [v * math.sin(math.pi * (i / n)) ** 2 for i, v in enumerate(ris)]
    out = [k * 1.0 + c * 0.35 + r * 0.5 for k, c, r in zip(kicks.buf, cl, ris)]
    out = reverb(out, rt=1.6, mix=0.2, damp=0.5, loop=True)
    return normalize(out, 0.8), True


def music_gameover():
    use_sr(MUS_SR)
    rnd = random.Random(505)
    total = 6.0
    n = n_of(total)
    m = Mix(total, loop=False)
    boom = thump(3.0, 70.0, 28.0, 1.1, 0.12)
    m.add(0.0, boom, 1.0)
    # a chord that closes: D minor, filter sweeping down
    acc = [0.0] * n
    for f in (hz("D2"), hz("A2"), hz("D3"), hz("F3")):
        for c in (-9.0, 0.0, 8.0):
            ff = f * 2.0 ** (c / 1200.0)
            p = rnd.random()
            for i in range(n):
                acc[i] += 2.0 * p - 1.0
                p += ff / SR
                p -= math.floor(p)
    fc = [2200.0 * (0.07 ** (i / n)) + 120.0 for i in range(n)]
    acc = lowpass(acc, fc, 0.9)
    env = [min(1.0, (i / SR) / 0.04) * math.exp(-(i / SR) / 1.8) for i in range(n)]
    m.add(0.0, [a * e * 0.08 for a, e in zip(acc, env)], 1.0)
    # falling bell phrase
    for t, nm, ln in ((0.5, "E5", 3.0), (1.6, "C5", 3.0), (2.9, "A4", 3.0)):
        m.add(t, bell(hz(nm), ln, 0.5), 0.3)
    m.add(0.0, noise_burst(1.5, 0.5, rnd, hi=500.0), 0.5)
    out = reverb(m.buf, rt=2.6, mix=0.45, damp=0.5, loop=False)[:n]
    # fade to silence at the very end
    f_n = int(0.9 * SR)
    for i in range(f_n):
        out[n - 1 - i] *= i / f_n
    return normalize(out, 0.8), False


def music_ending():
    use_sr(MUS_SR)
    rnd = random.Random(606)
    beat = 1.25
    bar = 4 * beat
    total = 4 * bar   # 20 s
    pads = Mix(total)
    chords = [("C3", "G3", "C4", "E4"), ("G2", "D3", "G3", "B3"), ("A2", "E3", "A3", "C4"), ("F2", "C3", "F3", "A3")]
    for ci, ch in enumerate(chords):
        pads.add(ci * bar, pad_chord([hz(x) for x in ch], bar, 1.6, 2.4, 1500.0, rnd), 0.6)
    bass = Mix(total)
    for ci, ch in enumerate(chords):
        bass.add(ci * bar, sine_note(hz(ch[0]), bar - 0.6, 0.4, 1.0, harm=0.5), 0.5)
    bells = Mix(total)
    mel = [(0, "E5", 2), (1.5, "G5", 2), (2.5, "E5", 2.5), (3.5, "D5", 2.5),
           (4, "D5", 2), (5, "G5", 2), (6, "B5", 2.5), (7.5, "A5", 2.5),
           (8, "C5", 2), (9, "E5", 2), (10, "A5", 2.5), (11.5, "G5", 2.5),
           (12, "A5", 2), (13.5, "G5", 2), (14.5, "F5", 2), (15.5, "E5", 3)]
    for b, nm, ln in mel:
        bells.add(b * beat, bell(hz(nm), ln, 0.9), 0.4)
    arp = Mix(total)
    arp_notes = {0: ("C4", "E4", "G4", "C5"), 1: ("G3", "B3", "D4", "G4"), 2: ("A3", "C4", "E4", "A4"), 3: ("F3", "A3", "C4", "F4")}
    for ci in range(4):
        for k in range(8):
            nm = arp_notes[ci][[0, 1, 2, 3, 2, 1, 2, 3][k]]
            arp.add(ci * bar + k * beat * 0.5, bell(hz(nm), 1.4, 0.5), 0.12)
    bell_sig = echo([a + b for a, b in zip(bells.buf, arp.buf)], beat * 0.75, 0.4, 0.45, loop=True)
    body = [a + b for a, b in zip(pads.buf, bell_sig)]
    body = reverb(body, rt=2.4, mix=0.3, damp=0.4, loop=True)
    out = [b + c for b, c in zip(body, bass.buf)]
    return normalize(out, 0.8), True


def amb_wind():
    use_sr(MUS_SR)
    rnd = random.Random(707)
    out = wind_noise(12.0, rnd, 1.0, 260.0, 950.0, (2, 5), 3, whistle=0.35)
    return normalize(out, 0.7), True


# ------------------------------------------------------------------ sound effects

def sfx_footstep(variant):
    use_sr(SFX_SR)
    rnd = random.Random(10 + variant)
    n = n_of(0.16)
    cut = (850.0, 1250.0)[variant - 1]
    x = lowpass(white(n, rnd), cut)
    env = exp_env(n, 0.03 if variant == 1 else 0.022, 0.001)
    body = thump(0.14, 95.0 if variant == 1 else 120.0, 52.0, 0.04)
    grit = noise_burst(0.05, 0.012, rnd, lo=1800.0)
    out = [a * b * 1.4 for a, b in zip(x, env)]
    mix_into(out, body, 0, 0.9)
    mix_into(out, grit, 0, 0.25)
    return out


def sfx_jump():
    use_sr(SFX_SR)
    rnd = random.Random(20)
    n = n_of(0.2)
    x = white(n, rnd)
    fc = sweep(350.0, 1100.0, n)
    y = bandpass(x, fc, 1.1)
    env = [math.sin(math.pi * (i / n)) ** 0.8 for i in range(n)]
    out = [a * b for a, b in zip(y, env)]
    mix_into(out, thump(0.1, 190.0, 120.0, 0.05), 0, 0.5)
    return out


def sfx_land():
    use_sr(SFX_SR)
    rnd = random.Random(21)
    out = thump(0.22, 120.0, 45.0, 0.07)
    mix_into(out, noise_burst(0.12, 0.03, rnd, hi=900.0), 0, 0.8)
    mix_into(out, noise_burst(0.04, 0.01, rnd, lo=2000.0), 0, 0.15)
    return out


def sfx_ui_click():
    use_sr(SFX_SR)
    rnd = random.Random(30)
    out = noise_burst(0.02, 0.004, rnd, band=2600.0, q=1.2)
    tone = [math.sin(TAU * 880.0 * i / SR) * math.exp(-(i / SR) / 0.02) for i in range(n_of(0.08))]
    out = pad_to(out, n_of(0.08))
    mix_into(out, tone, 0, 0.8)
    return out


def sfx_ui_hover():
    use_sr(SFX_SR)
    n = n_of(0.05)
    return [math.sin(TAU * 1500.0 * i / SR) * math.sin(math.pi * i / n) ** 2 * 0.8 for i in range(n)]


def sfx_ui_back():
    use_sr(SFX_SR)
    rnd = random.Random(32)
    n = n_of(0.22)
    out = [0.0] * n
    for t, f in ((0.0, 720.0), (0.08, 500.0)):
        s = [math.sin(TAU * f * i / SR) * math.exp(-(i / SR) / 0.05) for i in range(n_of(0.14))]
        mix_into(out, s, int(t * SR), 0.8)
    mix_into(out, noise_burst(0.015, 0.003, rnd, band=2400.0), 0, 0.5)
    return out


def sfx_ui_confirm():
    use_sr(SFX_SR)
    rnd = random.Random(33)
    n = n_of(0.34)
    out = [0.0] * n
    for t, f in ((0.0, 600.0), (0.09, 900.0)):
        s = osc_tri(const(f, n_of(0.22)))
        e = exp_env(len(s), 0.07, 0.003)
        mix_into(out, mul(s, e), int(t * SR), 0.7)
    mix_into(out, noise_burst(0.015, 0.003, rnd, band=3000.0), 0, 0.35)
    return out


def sfx_pickup():
    use_sr(SFX_SR)
    rnd = random.Random(34)
    n = n_of(0.3)
    out = [0.0] * n
    for t, f in ((0.0, 880.0), (0.07, 1320.0)):
        s = bell(f, 0.22, 0.3)
        mix_into(out, s, int(t * SR), 0.7)
    mix_into(out, noise_burst(0.05, 0.015, rnd, lo=3000.0), 0, 0.15)
    return out


def sfx_drop():
    use_sr(SFX_SR)
    rnd = random.Random(35)
    out = thump(0.16, 200.0, 85.0, 0.05)
    mix_into(out, noise_burst(0.1, 0.02, rnd, hi=1100.0), 0, 0.5)
    return out


def sfx_axe_chop():
    use_sr(SFX_SR)
    rnd = random.Random(36)
    n = n_of(0.3)
    out = thump(0.2, 230.0, 120.0, 0.06, 0.01)
    out = pad_to(out, n)
    mix_into(out, noise_burst(0.1, 0.012, rnd, band=1300.0, q=1.2), 0, 1.0)
    ring = bandpass(white(n, rnd), 560.0, 14.0)
    env = exp_env(n, 0.07, 0.001)
    mix_into(out, [a * b * 4.0 for a, b in zip(ring, env)], 0, 0.6)
    mix_into(out, noise_burst(0.03, 0.006, rnd, lo=2500.0), 0, 0.4)
    return out


def sfx_tree_fall():
    use_sr(SFX_SR)
    rnd = random.Random(37)
    total = 2.0
    m = Mix(total, loop=False)
    m.add(0.0, creak(0.7, rnd, 320.0, 700.0, 22.0, 60.0, 16.0), 0.7)
    n = n_of(0.9)
    wh = bandpass(white(n, rnd), sweep(300.0, 1400.0, n), 1.0)
    m.add(0.0, [v * (i / n) ** 2 for i, v in enumerate(wh)], 0.6)
    m.add(0.62, thump(0.7, 90.0, 28.0, 0.22, 0.06), 1.4)
    m.add(0.62, noise_burst(0.5, 0.12, rnd, hi=700.0), 0.9)
    leaves = noise_burst(0.8, 0.2, rnd, lo=3000.0)
    m.add(0.66, leaves, 0.35)
    m.add(1.0, noise_burst(0.3, 0.06, rnd, band=1200.0), 0.2)
    return m.buf


def sfx_pickaxe_hit():
    use_sr(SFX_SR)
    rnd = random.Random(38)
    out = metal_ring(1500.0, 0.4, rnd, ratios=(1.0, 2.43, 4.1, 5.9), amps=(1.0, 0.6, 0.35, 0.2), tau=0.08)
    mix_into(out, noise_burst(0.03, 0.006, rnd, lo=1500.0), 0, 0.8)
    mix_into(out, thump(0.1, 160.0, 90.0, 0.03), 0, 0.7)
    mix_into(out, noise_burst(0.12, 0.03, rnd, band=900.0, q=1.0), 0, 0.5)
    return out


def sfx_rock_break():
    use_sr(SFX_SR)
    rnd = random.Random(39)
    m = Mix(0.8, loop=False)
    m.add(0.0, thump(0.5, 110.0, 38.0, 0.16), 0.9)
    m.add(0.0, noise_burst(0.35, 0.09, rnd, hi=1500.0), 0.8)
    for _ in range(14):
        t = rnd.uniform(0.02, 0.5)
        f = rnd.uniform(700.0, 3200.0)
        m.add(t, noise_burst(0.07, rnd.uniform(0.01, 0.03), rnd, band=f, q=2.0), rnd.uniform(0.2, 0.55))
    return m.buf


def sfx_zombie_growl(variant):
    use_sr(SFX_SR)
    rnd = random.Random(40 + variant)
    dur = 1.05 if variant == 1 else 0.85
    n = n_of(dur)
    f0 = 72.0 if variant == 1 else 98.0
    curve = []
    for i in range(n):
        t = i / n
        curve.append(f0 * (1.0 + 0.25 * math.sin(math.pi * t) - 0.35 * t) + 3.0 * math.sin(TAU * 6.0 * i / SR))
    vow = ("uu", "aa") if variant == 1 else ("oh", "ah")
    y = vocal(curve, vow[0], rnd, rasp=0.55, breath=0.35, shift=0.95, vowel_to=vow[1])
    env = [math.sin(math.pi * min(1.0, (i / n) ** 0.7)) ** 1.2 for i in range(n)]
    out = [a * b for a, b in zip(y, env)]
    return soft_clip(out, 1.5)


def sfx_zombie_hit():
    use_sr(SFX_SR)
    rnd = random.Random(42)
    out = thump(0.25, 130.0, 55.0, 0.08)
    n = n_of(0.25)
    sq = bandpass(white(n, rnd), sweep(1100.0, 300.0, n), 3.0)
    mix_into(out, [a * b for a, b in zip(sq, exp_env(n, 0.07, 0.002))], 0, 1.2)
    mix_into(out, noise_burst(0.1, 0.02, rnd, hi=1200.0), 0, 0.6)
    return out


def sfx_zombie_death():
    use_sr(SFX_SR)
    rnd = random.Random(43)
    m = Mix(1.7, loop=False)
    n = n_of(1.1)
    curve = [95.0 * math.exp(-1.0 * i / n) for i in range(n)]
    y = vocal(curve, "aa", rnd, rasp=0.6, breath=0.4, vowel_to="uu")
    env = [min(1.0, i / (0.05 * SR)) * (1.0 - i / n) ** 1.5 for i in range(n)]
    m.add(0.0, [a * b for a, b in zip(y, env)], 1.0)
    m.add(0.95, thump(0.5, 100.0, 35.0, 0.15), 1.0)
    m.add(0.95, noise_burst(0.35, 0.07, rnd, hi=900.0), 0.7)
    m.add(1.1, noise_burst(0.4, 0.15, rnd, lo=2500.0), 0.12)
    return soft_clip(m.buf, 1.3)


def sfx_player_hurt():
    use_sr(SFX_SR)
    rnd = random.Random(44)
    n = n_of(0.3)
    curve = [210.0 - 70.0 * (i / n) for i in range(n)]
    y = vocal(curve, "oh", rnd, rasp=0.2, breath=0.12, shift=1.0, vowel_to="uu")
    env = [min(1.0, i / (0.01 * SR)) * math.exp(-(i / SR) / 0.11) for i in range(n)]
    out = [a * b for a, b in zip(y, env)]
    mix_into(out, thump(0.12, 150.0, 70.0, 0.04), 0, 0.5)
    mix_into(out, noise_burst(0.05, 0.01, rnd, band=1500.0), 0, 0.3)
    return out


def sfx_player_death():
    use_sr(SFX_SR)
    rnd = random.Random(45)
    m = Mix(1.6, loop=False)
    n = n_of(1.0)
    curve = [190.0 * math.exp(-0.9 * i / n) for i in range(n)]
    y = vocal(curve, "aa", rnd, rasp=0.15, breath=0.2, vowel_to="uu")
    env = [min(1.0, i / (0.03 * SR)) * (1.0 - i / n) ** 1.2 for i in range(n)]
    m.add(0.0, [a * b for a, b in zip(y, env)], 0.9)
    m.add(0.85, thump(0.6, 95.0, 32.0, 0.18), 1.1)
    m.add(0.85, noise_burst(0.3, 0.06, rnd, hi=800.0), 0.6)
    return m.buf


def sfx_hatch_open():
    use_sr(SFX_SR)
    rnd = random.Random(46)
    m = Mix(1.2, loop=False)
    m.add(0.0, thump(0.2, 140.0, 60.0, 0.05), 0.9)
    m.add(0.0, noise_burst(0.1, 0.02, rnd, band=500.0, q=1.2), 0.8)
    m.add(0.15, creak(0.6, rnd, 220.0, 520.0, 24.0, 48.0, 13.0), 0.8)
    n = n_of(0.8)
    hiss = highpass(white(n, rnd), 3000.0)
    m.add(0.2, [v * math.sin(math.pi * i / n) ** 1.5 for i, v in enumerate(hiss)], 0.3)
    m.add(0.85, metal_ring(260.0, 0.35, rnd, tau=0.12), 0.35)
    m.add(0.85, thump(0.2, 110.0, 55.0, 0.06), 0.8)
    return m.buf


def sfx_hatch_close():
    use_sr(SFX_SR)
    rnd = random.Random(47)
    m = Mix(1.1, loop=False)
    m.add(0.0, creak(0.3, rnd, 500.0, 250.0, 50.0, 25.0, 12.0), 0.6)
    m.add(0.28, metal_ring(190.0, 0.8, rnd, tau=0.3), 0.9)
    m.add(0.28, thump(0.4, 120.0, 40.0, 0.12), 1.1)
    m.add(0.28, noise_burst(0.15, 0.03, rnd, band=900.0, q=1.0), 0.8)
    return m.buf


def sfx_ladder_climb():
    use_sr(SFX_SR)
    rnd = random.Random(48)
    total = 0.8
    m = Mix(total, loop=True)
    for t, f in ((0.0, 880.0), (0.4, 780.0)):
        m.add(t, metal_ring(f, 0.3, rnd, ratios=(1.0, 2.76, 5.4), amps=(1.0, 0.5, 0.3), tau=0.06), 0.7)
        m.add(t, noise_burst(0.05, 0.01, rnd, band=1800.0, q=1.0), 0.5)
        m.add(t + 0.02, thump(0.08, 140.0, 80.0, 0.03), 0.4)
    for t in (0.16, 0.56):
        m.add(t, noise_burst(0.08, 0.02, rnd, band=700.0, q=1.0), 0.18)
    return m.buf


def sfx_door_open():
    use_sr(SFX_SR)
    rnd = random.Random(49)
    m = Mix(1.1, loop=False)
    m.add(0.0, noise_burst(0.05, 0.01, rnd, band=900.0), 0.7)
    m.add(0.05, creak(0.8, rnd, 280.0, 640.0, 26.0, 52.0, 13.0), 0.9)
    n = n_of(0.7)
    w = bandpass(white(n, rnd), sweep(400.0, 900.0, n), 1.0)
    m.add(0.2, [v * math.sin(math.pi * i / n) for i, v in enumerate(w)], 0.25)
    m.add(0.9, thump(0.15, 120.0, 70.0, 0.04), 0.5)
    return m.buf


def sfx_build_ok():
    use_sr(SFX_SR)
    rnd = random.Random(50)
    m = Mix(1.2, loop=False)
    for t in (0.0, 0.16):
        m.add(t, metal_ring(1100.0, 0.18, rnd, ratios=(1.0, 2.5, 4.3), amps=(1.0, 0.5, 0.3), tau=0.04), 0.5)
        m.add(t, thump(0.08, 180.0, 100.0, 0.025), 0.6)
        m.add(t, noise_burst(0.03, 0.005, rnd, lo=2000.0), 0.4)
    for t, nm in ((0.36, "C5"), (0.5, "E5"), (0.64, "G5")):
        m.add(t, bell(hz(nm), 0.7, 0.5), 0.45)
    return m.buf


def sfx_build_fail():
    use_sr(SFX_SR)
    m = Mix(0.4, loop=False)
    for t in (0.0, 0.17):
        n = n_of(0.13)
        s = osc_square(const(110.0, n))
        s2 = osc_square(const(117.0, n))
        e = ar_env(n, 0.005, 0.03)
        m.add(t, [(a + b) * c * 0.4 for a, b, c in zip(s, s2, e)], 1.0)
    return lowpass(m.buf, 1400.0)


def sfx_eat():
    use_sr(SFX_SR)
    rnd = random.Random(52)
    m = Mix(0.8, loop=False)
    for t in (0.0, 0.22, 0.45):
        n = n_of(0.16)
        x = white(n, rnd)
        # crunch: many tiny clicks gated by a decaying envelope
        gate = [1.0 if rnd.random() < 0.18 else 0.0 for _ in range(n)]
        y = highpass(lowpass([a * b for a, b in zip(x, gate)], 5000.0), 1200.0)
        env = exp_env(n, 0.05, 0.002)
        m.add(t, [a * b * 3.0 for a, b in zip(y, env)], 0.8)
        m.add(t, thump(0.08, 150.0, 90.0, 0.03), 0.35)
    return m.buf


def sfx_drink():
    use_sr(SFX_SR)
    rnd = random.Random(53)
    m = Mix(0.9, loop=False)
    for t in (0.0, 0.32):
        n = n_of(0.22)
        f = sweep(360.0, 150.0, n)
        s = osc_sine(f)
        e = [math.sin(math.pi * i / n) ** 1.3 for i in range(n)]
        m.add(t, [a * b for a, b in zip(s, e)], 0.7)
    for _ in range(9):
        t = rnd.uniform(0.0, 0.6)
        n = n_of(0.05)
        f0 = rnd.uniform(500.0, 900.0)
        s = osc_sine(sweep(f0, f0 * 1.6, n))
        m.add(t, [a * math.exp(-(i / SR) / 0.015) for i, a in enumerate(s)], 0.18)
    m.add(0.0, noise_burst(0.5, 0.15, rnd, band=2200.0, q=0.8), 0.05)
    return m.buf


def sfx_sleep():
    use_sr(SFX_SR)
    rnd = random.Random(54)
    m = Mix(2.4, loop=False)
    for t, nm in ((0.0, "E5"), (0.45, "C5"), (0.95, "A4")):
        m.add(t, bell(hz(nm), 1.4, 0.3), 0.6)
    n = n_of(1.8)
    pad = pad_chord([hz("A2"), hz("E3"), hz("A3")], 1.0, 0.4, 1.0, 500.0, rnd)
    m.add(0.0, pad, 0.9)
    br = lowpass(white(n_of(1.4), rnd), 600.0)
    m.add(0.9, [v * math.sin(math.pi * i / len(br)) ** 2 * 0.5 for i, v in enumerate(br)], 0.3)
    return reverb(m.buf, rt=1.4, mix=0.3, loop=False)[:n_of(2.4)]


def sfx_flashlight_toggle():
    use_sr(SFX_SR)
    rnd = random.Random(55)
    out = pad_to(noise_burst(0.01, 0.0025, rnd, band=3200.0, q=1.0), n_of(0.09))
    mix_into(out, thump(0.04, 260.0, 150.0, 0.015), 0, 0.8)
    mix_into(out, noise_burst(0.02, 0.004, rnd, band=2000.0), int(0.035 * SR), 0.6)
    return out


def sfx_heartbeat():
    use_sr(SFX_SR)
    m = Mix(0.8, loop=False)
    m.add(0.0, thump(0.25, 70.0, 42.0, 0.07, 0.03), 1.0)
    m.add(0.2, thump(0.25, 62.0, 40.0, 0.06, 0.03), 0.7)
    return lowpass(m.buf, 200.0)


def sfx_rad_warning():
    use_sr(SFX_SR)
    n1 = n_of(0.1)
    m = Mix(0.55, loop=False)
    for k in range(3):
        s = osc_sine(const(1500.0, n1))
        s3 = osc_sine(const(4500.0, n1))
        e = ar_env(n1, 0.005, 0.02)
        m.add(k * 0.17, [(a + 0.15 * b) * c for a, b, c in zip(s, s3, e)], 0.8)
    return m.buf


def sfx_popup_open():
    use_sr(SFX_SR)
    rnd = random.Random(57)
    n = n_of(0.2)
    w = bandpass(white(n, rnd), sweep(400.0, 1600.0, n), 1.2)
    out = [v * math.sin(math.pi * i / n) ** 2 for i, v in enumerate(w)]
    tick = [math.sin(TAU * 520.0 * i / SR) * math.exp(-(i / SR) / 0.025) for i in range(n_of(0.1))]
    mix_into(out, tick, int(0.08 * SR), 0.7)
    return out


def sfx_popup_close():
    use_sr(SFX_SR)
    rnd = random.Random(58)
    n = n_of(0.18)
    w = bandpass(white(n, rnd), sweep(1500.0, 380.0, n), 1.2)
    out = [v * math.sin(math.pi * i / n) ** 2 for i, v in enumerate(w)]
    tick = [math.sin(TAU * 400.0 * i / SR) * math.exp(-(i / SR) / 0.02) for i in range(n_of(0.08))]
    mix_into(out, tick, 0, 0.6)
    return out


def sfx_day_start():
    use_sr(SFX_SR)
    rnd = random.Random(59)
    m = Mix(2.6, loop=False)
    for t, nm in ((0.0, "A4"), (0.22, "C5"), (0.44, "E5"), (0.7, "A5")):
        m.add(t, bell(hz(nm), 1.6, 0.6), 0.55)
    m.add(0.0, pad_chord([hz("A3"), hz("E4"), hz("C5")], 1.2, 0.3, 1.2, 1400.0, rnd), 0.7)
    return reverb(m.buf, rt=1.8, mix=0.3, loop=False)[:n_of(2.6)]


def sfx_slot_select():
    use_sr(SFX_SR)
    rnd = random.Random(60)
    out = pad_to([math.sin(TAU * 720.0 * i / SR) * math.exp(-(i / SR) / 0.012) for i in range(n_of(0.04))], n_of(0.07))
    mix_into(out, noise_burst(0.01, 0.002, rnd, band=2800.0), 0, 0.4)
    return out


def sfx_geiger(variant):
    use_sr(SFX_SR)
    rnd = random.Random(70 + variant)
    out = noise_burst(0.012, 0.0018, rnd, lo=1200.0)
    f = (2300.0, 3100.0, 2700.0)[variant - 1]
    ring = [math.sin(TAU * f * i / SR) * math.exp(-(i / SR) / 0.004) for i in range(n_of(0.03))]
    out = pad_to(out, n_of(0.04))
    mix_into(out, ring, 0, 0.5)
    return out


def sfx_swing():
    use_sr(SFX_SR)
    rnd = random.Random(61)
    n = n_of(0.22)
    w = bandpass(white(n, rnd), sweep(1800.0, 500.0, n), 1.0)
    return [v * math.sin(math.pi * (i / n) ** 0.7) ** 2 for i, v in enumerate(w)]


# name -> (function, peak level 0..1, kind). kind: "sfx", "music" (functions return (samples, loop)).
SOUNDS = {
    # music + ambience (16 kHz, looping unless noted)
    "music_menu": (music_menu, 0.8, "music"),
    "music_bunker": (music_bunker, 0.75, "music"),
    "music_expedition": (music_expedition, 0.75, "music"),
    "music_danger": (music_danger, 0.8, "music"),
    "music_gameover": (music_gameover, 0.85, "music"),
    "music_ending": (music_ending, 0.8, "music"),
    "amb_wind": (amb_wind, 0.7, "music"),
    # sound effects (22.05 kHz)
    "footstep_1": (lambda: sfx_footstep(1), 0.55, "sfx"),
    "footstep_2": (lambda: sfx_footstep(2), 0.55, "sfx"),
    "jump": (sfx_jump, 0.6, "sfx"),
    "land": (sfx_land, 0.7, "sfx"),
    "ui_click": (sfx_ui_click, 0.55, "sfx"),
    "ui_hover": (sfx_ui_hover, 0.35, "sfx"),
    "ui_back": (sfx_ui_back, 0.55, "sfx"),
    "ui_confirm": (sfx_ui_confirm, 0.6, "sfx"),
    "pickup": (sfx_pickup, 0.6, "sfx"),
    "drop": (sfx_drop, 0.6, "sfx"),
    "axe_chop": (sfx_axe_chop, 0.85, "sfx"),
    "tree_fall": (sfx_tree_fall, 0.9, "sfx"),
    "pickaxe_hit": (sfx_pickaxe_hit, 0.8, "sfx"),
    "rock_break": (sfx_rock_break, 0.85, "sfx"),
    "swing": (sfx_swing, 0.4, "sfx"),
    "zombie_growl_1": (lambda: sfx_zombie_growl(1), 0.75, "sfx"),
    "zombie_growl_2": (lambda: sfx_zombie_growl(2), 0.75, "sfx"),
    "zombie_hit": (sfx_zombie_hit, 0.8, "sfx"),
    "zombie_death": (sfx_zombie_death, 0.8, "sfx"),
    "player_hurt": (sfx_player_hurt, 0.75, "sfx"),
    "player_death": (sfx_player_death, 0.85, "sfx"),
    "hatch_open": (sfx_hatch_open, 0.8, "sfx"),
    "hatch_close": (sfx_hatch_close, 0.85, "sfx"),
    "ladder_climb": (sfx_ladder_climb, 0.6, "sfx_loop"),
    "door_open": (sfx_door_open, 0.75, "sfx"),
    "build_ok": (sfx_build_ok, 0.75, "sfx"),
    "build_fail": (sfx_build_fail, 0.6, "sfx"),
    "eat": (sfx_eat, 0.65, "sfx"),
    "drink": (sfx_drink, 0.6, "sfx"),
    "sleep": (sfx_sleep, 0.7, "sfx"),
    "flashlight_toggle": (sfx_flashlight_toggle, 0.55, "sfx"),
    "heartbeat": (sfx_heartbeat, 0.85, "sfx"),
    "rad_warning": (sfx_rad_warning, 0.6, "sfx"),
    "popup_open": (sfx_popup_open, 0.5, "sfx"),
    "popup_close": (sfx_popup_close, 0.5, "sfx"),
    "day_start": (sfx_day_start, 0.7, "sfx"),
    "slot_select": (sfx_slot_select, 0.45, "sfx"),
    "geiger_1": (lambda: sfx_geiger(1), 0.55, "sfx"),
    "geiger_2": (lambda: sfx_geiger(2), 0.5, "sfx"),
    "geiger_3": (lambda: sfx_geiger(3), 0.6, "sfx"),
}


# ------------------------------------------------------------------ output

def dc_block(x, fc=18.0):
    return highpass(x, fc, 0.707)


def to_int16(x):
    out = bytearray()
    for v in x:
        i = int(round(max(-1.0, min(1.0, v)) * 32767))
        out += struct.pack("<h", i)
    return bytes(out)


def write_wav(path, samples, sr, loop):
    data = to_int16(samples)
    fmt = struct.pack("<HHIIHH", 1, 1, sr, sr * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if loop:
        n = len(samples)
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    chunks += b"data" + struct.pack("<I", len(data)) + data
    blob = b"WAVE" + chunks
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(blob)) + blob)


def analyze(name, samples, sr, loop):
    n = len(samples)
    peak = max(abs(v) for v in samples)
    rms = math.sqrt(sum(v * v for v in samples) / n)
    dc = sum(samples) / n
    diffs = [abs(samples[i + 1] - samples[i]) for i in range(0, n - 1)]
    mean_step = sum(diffs) / len(diffs)
    seam = abs(samples[0] - samples[-1])
    thr = peak * 0.01
    lead = next((i for i, v in enumerate(samples) if abs(v) > thr), n)
    trail = next((i for i, v in enumerate(reversed(samples)) if abs(v) > thr), n)
    cols = 40
    step = max(1, n // cols)
    env = ""
    for c in range(cols):
        seg = samples[c * step:(c + 1) * step]
        if not seg:
            break
        p = max(abs(v) for v in seg)
        db = 20 * math.log10(max(p, 1e-6) / max(peak, 1e-6))
        k = int(max(0, min(9, 9 + db / 6.0)))
        env += " .:-=+*#%@"[k]
    return {
        "name": name, "dur": n / sr, "peak_db": 20 * math.log10(max(peak, 1e-9)), "rms_db": 20 * math.log10(max(rms, 1e-9)),
        "dc": dc, "seam": seam, "seam_vs_step": seam / max(mean_step, 1e-9), "lead_ms": lead / sr * 1000, "trail_ms": trail / sr * 1000,
        "env": env, "bytes": n * 2, "loop": loop,
    }


def render(name):
    fn, level, kind = SOUNDS[name]
    use_sr(MUS_SR if kind == "music" else SFX_SR)
    res = fn()
    loop = kind == "sfx_loop"
    if kind == "music":
        samples, loop = res
    else:
        samples = res
    sr = SR
    if loop:
        # a loop must already be seamless; only remove DC by subtracting the mean (a filter would break the seam)
        mean = sum(samples) / len(samples)
        samples = [v - mean for v in samples]
    else:
        samples = dc_block(samples) if kind == "sfx" else samples
        samples = fade_edges(samples, 0.001, 0.006 if kind == "sfx" else 0.002)
    samples = normalize(samples, level)
    return samples, sr, loop


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))
    ap.add_argument("--only", default="")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--report", action="store_true", help="analyze only, write nothing")
    args = ap.parse_args()
    names = list(SOUNDS)
    if args.list:
        print("\n".join(names))
        return 0
    if args.only:
        wanted = [s.strip() for s in args.only.split(",") if s.strip()]
        for w in wanted:
            if w not in SOUNDS:
                print("unknown sound: " + w)
                return 1
        names = wanted
    os.makedirs(args.out, exist_ok=True)
    total_bytes = 0
    rows = []
    for name in names:
        samples, sr, loop = render(name)
        info = analyze(name, samples, sr, loop)
        rows.append(info)
        total_bytes += info["bytes"]
        if not args.report:
            write_wav(os.path.join(args.out, name + ".wav"), samples, sr, loop)
        print("%-18s %5.2fs peak %6.1f dB rms %6.1f dB dc %+.4f  seam %.4f (%.1fx step)%s  [%s]" % (
            name, info["dur"], info["peak_db"], info["rms_db"], info["dc"], info["seam"], info["seam_vs_step"],
            " LOOP" if loop else "", info["env"]))
        sys.stdout.flush()
    print("total audio data: %.2f MB (%d files)" % (total_bytes / 1e6, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
