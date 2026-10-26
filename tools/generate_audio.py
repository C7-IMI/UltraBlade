#!/usr/bin/env python3
"""ULTRABLADE -- original procedural audio generator.

Every WAV in game/assets/audio/ is synthesized from scratch in this script with
numpy (additive/subtractive synthesis, noise shaping, FFT convolution).  No
downloaded samples, no generative music models, no third-party IRs.  Output is
44.1 kHz / 16-bit PCM WAV via the Python standard library wave module.

Determinism: each asset seeds a numpy Generator from zlib.crc32(asset name), so a
re-run on the same script version produces bit-identical WAVs (dither included).

Usage (from the repo root):
    C:/Python/python.exe tools/generate_audio.py
    C:/Python/python.exe tools/generate_audio.py --verify-only
    C:/Python/python.exe tools/generate_audio.py --only music_match,slash

Audit artifacts go to artifacts/audio/: manifest.json, audit.json, REPORT.md,
waveforms.png, music_match_spectrogram.png.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import time
import wave
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Sequence

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "game" / "assets" / "audio"
DEFAULT_REPORT = ROOT / "artifacts" / "audio"
BUDGET_BYTES = 25 * 1024 * 1024
PIPELINE_VERSION = "ultrablade-audio-v1"

# --------------------------------------------------------------------------
# small numeric helpers
# --------------------------------------------------------------------------


def db_lin(db: float) -> float:
    return 10.0 ** (db / 20.0)


def lin_db(value: float) -> float:
    return 20.0 * math.log10(max(float(value), 1e-12))


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((float(m) - 69.0) / 12.0)


def nsamp(seconds: float) -> int:
    return int(round(float(seconds) * SR))


def tline(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")) & 0xFFFFFFFF)


def next_pow2(n: int) -> int:
    return 1 << max(1, (max(int(n), 1) - 1).bit_length())


# --------------------------------------------------------------------------
# filters (zero-phase magnitude shaping via FFT)
# --------------------------------------------------------------------------


def _lp_mag(f: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    fl = f / max(float(fc), 1.0)
    return 1.0 / np.sqrt(1.0 + fl ** (2 * order))


def _hp_mag(f: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    fh = np.maximum(f / max(float(fc), 1e-6), 1e-9)
    return 1.0 / np.sqrt(1.0 + 1.0 / (fh ** (2 * order)))


def fft_filter(
    x: np.ndarray,
    highpass: float | None = None,
    lowpass: float | None = None,
    order: int = 2,
    circular: bool = True,
    sr: int = SR,
) -> np.ndarray:
    """Zero-phase Butterworth-magnitude EQ.  circular=True wraps (loop-safe)."""
    x = np.asarray(x, dtype=np.float64)
    squeeze = x.ndim == 1
    xin = x[:, None] if squeeze else x
    n = xin.shape[0]
    if circular:
        nfft, pad = n, 0
    else:
        pad = min(n, nsamp(0.30))
        nfft = n + pad
        xin = np.vstack([xin, np.zeros((pad, xin.shape[1]))])
    f = np.fft.rfftfreq(nfft, 1.0 / sr)
    H = np.ones_like(f)
    if highpass:
        H *= _hp_mag(f, float(highpass), order)
    if lowpass:
        H *= _lp_mag(f, float(lowpass), order)
    y = np.fft.irfft(np.fft.rfft(xin, n=nfft, axis=0) * H[:, None], n=nfft, axis=0)
    if not circular:
        y = y[:n]
    return y[:, 0] if squeeze else y


def time_varying_filter(
    x: np.ndarray,
    highpass_fn: Callable[[float], float] | None = None,
    lowpass_fn: Callable[[float], float] | None = None,
    order: int = 2,
    frame: int = 2048,
    hop: int = 512,
    sr: int = SR,
) -> np.ndarray:
    """Overlap-add piecewise zero-phase EQ; fn(progress 0..1) -> cutoff Hz."""
    squeeze = x.ndim == 1
    xin = x[:, None] if squeeze else np.asarray(x, dtype=np.float64)
    n = xin.shape[0]
    frame = int(min(frame, next_pow2(n)))
    hop = max(64, min(hop, frame // 2))
    win = np.hanning(frame + 2)[1:-1]
    out = np.zeros((n + frame, xin.shape[1]))
    wsum = np.zeros(n + frame)
    f = np.fft.rfftfreq(frame, 1.0 / sr)
    for start in range(0, n, hop):
        seg = xin[start : start + frame]
        if seg.shape[0] < frame:
            seg = np.vstack([seg, np.zeros((frame - seg.shape[0], xin.shape[1]))])
        prog = min(1.0, (start + frame * 0.5) / max(n, 1))
        H = np.ones_like(f)
        if highpass_fn is not None:
            H *= _hp_mag(f, highpass_fn(prog), order)
        if lowpass_fn is not None:
            H *= _lp_mag(f, lowpass_fn(prog), order)
        buf = np.fft.irfft(np.fft.rfft(seg, axis=0) * H[:, None], n=frame, axis=0)
        out[start : start + frame] += buf * win[:, None]
        wsum[start : start + frame] += win
    out /= np.maximum(wsum[:, None], 1e-6)
    out = out[:n]
    return out[:, 0] if squeeze else out


# --------------------------------------------------------------------------
# envelopes and oscillators
# --------------------------------------------------------------------------


def env_exp(n: int, attack: float = 0.002, tau: float = 0.15, sr: int = SR) -> np.ndarray:
    t = tline(n)
    a = np.clip(t / max(attack, 1e-9), 0.0, 1.0)
    return a * np.exp(-np.maximum(t - attack, 0.0) / max(tau, 1e-9))


def env_points(n: int, points: Sequence[tuple[float, float]], sr: int = SR) -> np.ndarray:
    """Piecewise-linear envelope; points are (seconds, value), increasing time."""
    t = tline(n)
    xs = np.array([p[0] for p in points], dtype=np.float64)
    ys = np.array([p[1] for p in points], dtype=np.float64)
    return np.interp(t, xs, ys)


def _polyblep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    dt = np.maximum(dt, 1e-9)
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def polyblep_saw(freq: np.ndarray | float, n: int, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    if np.isscalar(freq):
        dt = np.full(n, float(freq) / sr)
        phase = phase0 + dt * np.arange(n)
    else:
        f = np.asarray(freq, dtype=np.float64)
        dt = f / sr
        phase = phase0 + np.cumsum(dt)
    t = phase % 1.0
    return 2.0 * t - 1.0 - _polyblep(t, dt)


def polyblep_square(freq: np.ndarray | float, n: int, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    if np.isscalar(freq):
        dt = np.full(n, float(freq) / sr)
        phase = phase0 + dt * np.arange(n)
    else:
        f = np.asarray(freq, dtype=np.float64)
        dt = f / sr
        phase = phase0 + np.cumsum(dt)
    t = phase % 1.0
    y = np.where(t < 0.5, 1.0, -1.0)
    y += _polyblep(t, dt)
    y -= _polyblep((t + 0.5) % 1.0, dt)
    return y


def saw_voice(freq: float, n: int, cents: float = 0.0, vib_hz: float = 0.0, vib_cents: float = 0.0, phase: float = 0.0) -> np.ndarray:
    if vib_hz and vib_cents:
        t = tline(n)
        f = freq * 2.0 ** ((cents + vib_cents * np.sin(2.0 * math.pi * vib_hz * t + phase * 6.283)) / 1200.0)
        return polyblep_saw(f, n)
    f = freq * 2.0 ** (cents / 1200.0)
    return polyblep_saw(np.full(n, f), n, phase0=phase)


def pink_noise(rng: np.random.Generator, n: int) -> np.ndarray:
    white = rng.standard_normal(n)
    X = np.fft.rfft(white)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    y = np.fft.irfft(X / np.sqrt(np.maximum(f, 20.0)), n=n)
    return y / (np.std(y) + 1e-12)


def brown_noise(rng: np.random.Generator, n: int) -> np.ndarray:
    white = rng.standard_normal(n)
    X = np.fft.rfft(white)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    y = np.fft.irfft(X / np.maximum(f, 20.0), n=n)
    return y / (np.std(y) + 1e-12)


# --------------------------------------------------------------------------
# reverb (synthetic IRs, circular convolution => seamless loops)
# --------------------------------------------------------------------------


def _make_ir(rng: np.random.Generator, decay: float, damp: float, predelay: float, sr: int = SR) -> np.ndarray:
    n = nsamp(decay)
    t = tline(n)
    noise = rng.standard_normal(n)
    noise = fft_filter(noise, highpass=180.0, lowpass=damp, circular=False)
    ir = np.zeros(n)
    pre = nsamp(predelay)
    if pre < n:
        ir[pre:] = noise[: n - pre]
    ir *= np.exp(-6.9078 * t / max(decay, 1e-6))
    for extra, gain in ((0.013, 0.5), (0.021, 0.34), (0.033, 0.26), (0.047, 0.18), (0.063, 0.13)):
        idx = nsamp(predelay + extra)
        if idx < n:
            ir[idx] += gain * (1.0 if rng.random() > 0.5 else -1.0)
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-12)


def _circ_conv(x: np.ndarray, ir: np.ndarray, n: int) -> np.ndarray:
    return np.fft.irfft(np.fft.rfft(x, n=n) * np.fft.rfft(ir, n=n), n=n)


def _lin_conv(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    n = len(x)
    nfft = next_pow2(n + len(ir) - 1)
    X = np.fft.rfft(np.pad(x, (0, nfft - n)), n=nfft)
    H = np.fft.rfft(np.pad(ir, (0, nfft - len(ir))), n=nfft)
    return np.fft.irfft(X * H, n=nfft)[:n]


def reverb_send(mono: np.ndarray, rng: np.random.Generator, decay: float = 1.8, damp: float = 3800.0, predelay: float = 0.018) -> np.ndarray:
    """Stereo wet signal for a mono send; circular convolution (loop-safe)."""
    n = len(mono)
    wet = np.zeros((n, 2))
    target = np.sqrt(np.mean(np.square(mono))) + 1e-12
    for ch in range(2):
        ir = _make_ir(rng, decay, damp, predelay)
        ir = ir[: max(1, n // 2)]
        y = _circ_conv(mono, ir, n)
        y /= np.sqrt(np.mean(np.square(y))) + 1e-12
        wet[:, ch] = y * target
    return wet


def reverb_stereo(dry: np.ndarray, rng: np.random.Generator, mix: float = 0.22, decay: float = 1.4, damp: float = 4200.0) -> np.ndarray:
    """Add a stereo reverb tail to a one-shot (linear convolution, tail included)."""
    x = np.asarray(dry, dtype=np.float64)
    squeeze = x.ndim == 1
    xin = x[:, None] if squeeze else x
    n = xin.shape[0]
    out = np.zeros((n, 2))
    mono = xin.mean(axis=1)
    target = np.sqrt(np.mean(np.square(mono))) + 1e-12
    for ch in range(2):
        ir = _make_ir(rng, decay, damp, 0.012)
        y = _lin_conv(mono, ir)
        y /= np.sqrt(np.mean(np.square(y))) + 1e-12
        out[:, ch] = y * target
    out = out * mix
    if squeeze:
        return xin[:, 0] * (1.0 - mix * 0.5) + out.mean(axis=1) * 0.5
    return xin * (1.0 - mix) + out


# --------------------------------------------------------------------------
# placement / mixing / mastering / file io
# --------------------------------------------------------------------------


def add_signal(bus: np.ndarray, sig: np.ndarray, at_sec: float = 0.0, gain: float = 1.0, wrap: bool = False, pan: float = 0.0) -> None:
    sig = np.asarray(sig, dtype=np.float64)
    n = bus.shape[0]
    start = int(round(float(at_sec) * SR))
    if sig.ndim == 1:
        if bus.ndim == 2:
            th = (float(pan) + 1.0) * 0.25 * math.pi
            stereo = np.stack([sig * math.cos(th), sig * math.sin(th)], axis=1)
        else:
            stereo = sig
    else:
        stereo = sig
    if stereo.shape[0] > n:
        stereo = stereo[:n]
    length = stereo.shape[0]
    if length == 0:
        return
    if wrap:
        start %= n
        end = start + length
        if end <= n:
            bus[start:end] += stereo * gain
        else:
            k = n - start
            bus[start:n] += stereo[:k] * gain
            bus[: end - n] += stereo[k:] * gain
    else:
        if start >= n:
            return
        if start < 0:
            stereo = stereo[-start:]
            start = 0
        end = min(n, start + stereo.shape[0])
        if end > start:
            bus[start:end] += stereo[: end - start] * gain


def sidechain_env(n: int, times: Sequence[float], depth: float = 0.5, tau: float = 0.13) -> np.ndarray:
    duck = np.ones(n)
    span = nsamp(tau * 6.0)
    for tk in times:
        start = int(round(tk * SR))
        if start >= n:
            start %= n
        length = min(n, span)
        tt = np.arange(length) / SR
        env = 1.0 - depth * np.exp(-tt / max(tau, 1e-6))
        end = start + length
        if end <= n:
            duck[start:end] = np.minimum(duck[start:end], env)
        else:
            k = n - start
            duck[start:] = np.minimum(duck[start:], env[:k])
    return duck


def master(x: np.ndarray, peak_db: float = -1.0, highpass: float | None = 24.0, fade_in: float = 0.002, fade_out: float = 0.02, circular: bool = False) -> np.ndarray:
    squeeze = np.ndim(x) == 1
    x2 = np.asarray(x, dtype=np.float64)
    x2 = x2[:, None] if squeeze else x2.copy()
    if highpass:
        x2 = fft_filter(x2, highpass=highpass, circular=circular)
    n = x2.shape[0]
    fi, fo = nsamp(fade_in), nsamp(fade_out)
    if fi > 1:
        x2[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
    if fo > 1:
        x2[-fo:] *= np.linspace(1.0, 0.0, fo)[:, None]
    peak = float(np.max(np.abs(x2))) if n else 0.0
    if peak > 0.0:
        x2 *= db_lin(peak_db) / peak
    return x2[:, 0] if squeeze else x2


def write_wav(path: Path, samples: np.ndarray, rng: np.random.Generator) -> int:
    samples = np.asarray(samples, dtype=np.float64)
    channels = 1 if samples.ndim == 1 else samples.shape[1]
    x = np.clip(samples, -1.0, 1.0)
    dither = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0
    ints = np.clip(np.round((x + dither) * 32767.0), -32768, 32767).astype("<i2")
    if samples.ndim == 2:
        ints = ints.reshape(-1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(ints.tobytes())
    return path.stat().st_size


# --------------------------------------------------------------------------
# percussion / metal instruments
# --------------------------------------------------------------------------


def kick(rng: np.random.Generator, dur: float = 0.42, f_start: float = 155.0, f_end: float = 47.0, decay: float = 0.13) -> np.ndarray:
    n = nsamp(dur)
    t = tline(n)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.028)
    ph = 2.0 * math.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / decay)
    click = fft_filter(rng.standard_normal(n), highpass=1700.0, circular=False) * np.exp(-t / 0.0025) * 0.8
    sub = np.sin(2.0 * math.pi * f_end * 0.84 * t) * np.exp(-t / (decay * 1.7)) * 0.45
    return np.tanh((body + click + sub) * 1.4)


def snare(rng: np.random.Generator, dur: float = 0.30, tone: float = 185.0) -> np.ndarray:
    n = nsamp(dur)
    t = tline(n)
    noise = fft_filter(rng.standard_normal(n), highpass=850.0, lowpass=7800.0, circular=False)
    noise *= env_exp(n, attack=0.001, tau=0.055)
    body = np.sin(2.0 * math.pi * (tone + 70.0 * np.exp(-t / 0.012)) * t) * np.exp(-t / 0.055) * 0.55
    return np.tanh((noise + body) * 1.2)


def clap(rng: np.random.Generator, dur: float = 0.28) -> np.ndarray:
    n = nsamp(dur)
    out = np.zeros(n)
    for i, off in enumerate((0.0, 0.0085, 0.0175, 0.028)):
        m = n - nsamp(off)
        if m <= 0:
            continue
        t = tline(m)
        burst = fft_filter(rng.standard_normal(m), highpass=1100.0, lowpass=6500.0, circular=False)
        burst *= np.exp(-t / (0.010 + 0.006 * i)) * np.minimum(t / 0.0008, 1.0)
        add_signal(out, burst * (1.0 - 0.15 * i), off)
    t = tline(n)
    tail = fft_filter(rng.standard_normal(n), highpass=900.0, lowpass=5200.0, circular=False) * np.exp(-t / 0.075) * 0.5
    return (out + tail) * 1.1


def hat(rng: np.random.Generator, dur: float = 0.06, tau: float = 0.011) -> np.ndarray:
    n = nsamp(dur)
    noise = fft_filter(rng.standard_normal(n), highpass=7200.0, circular=False)
    return noise * env_exp(n, attack=0.0005, tau=tau) * 0.9


def metallic_partials(rng: np.random.Generator, n: int, base: float = 420.0, decay: float = 0.25, density: float = 1.0) -> np.ndarray:
    t = tline(n)
    sig = np.zeros(n)
    ratios = (1.0, 2.31, 3.87, 5.19, 7.03, 9.17)
    for i, r in enumerate(ratios):
        f = base * r * (1.0 + 0.012 * rng.standard_normal())
        amp = (0.5 / (i + 1)) * density
        sig += np.sin(2.0 * math.pi * f * t + rng.random() * 6.283) * np.exp(-t / (decay / (1.0 + 0.7 * i))) * amp
    return sig


def sub_drop(rng: np.random.Generator, dur: float = 0.9, f_start: float = 95.0, f_end: float = 33.0) -> np.ndarray:
    n = nsamp(dur)
    t = tline(n)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.12)
    sig = np.sin(2.0 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.32)
    return np.tanh(sig * 1.6) * 0.9

# --------------------------------------------------------------------------
# SFX builders (each returns float64 mono or stereo in [-1, 1])
# --------------------------------------------------------------------------


def sfx_skate_loop() -> np.ndarray:
    name, dur = "skate_loop", 2.0
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    hiss = fft_filter(rng.standard_normal(n), highpass=1250.0, lowpass=9500.0, circular=True)
    mod = 0.30 + 0.09 * np.sin(2.0 * math.pi * 1.5 * t + 0.7) + 0.05 * np.sin(2.0 * math.pi * 4.0 * t + 2.1)
    ice = hiss * mod
    scrape_a = fft_filter(rng.standard_normal(nsamp(0.13)), highpass=3200.0, lowpass=11000.0, circular=False)
    scrape_a *= env_exp(nsamp(0.13), attack=0.004, tau=0.030)
    scrape_b = fft_filter(rng.standard_normal(nsamp(0.13)), highpass=2200.0, lowpass=9000.0, circular=False)
    scrape_b *= env_exp(nsamp(0.13), attack=0.006, tau=0.038)
    for i, pos in enumerate((0.06, 0.56, 1.06, 1.56)):
        burst = scrape_a if i % 2 == 0 else scrape_b
        add_signal(ice, burst * (0.9 + 0.1 * rng.random()), pos, wrap=True)
        add_signal(ice, burst * 0.3, pos, wrap=True)
    rumble = fft_filter(brown_noise(rng, n), lowpass=170.0, circular=True) * 0.10
    blade = np.sin(2.0 * math.pi * 2450.0 * t + 0.4 * np.sin(2.0 * math.pi * 1.5 * t)) * 0.012
    blade *= 0.5 + 0.5 * np.sin(2.0 * math.pi * 4.0 * t)
    sig = ice * 0.55 + rumble + blade
    return master(sig, peak_db=-9.0, highpass=90.0, fade_in=0.0, fade_out=0.0, circular=True)


def sfx_turnstile_hum() -> np.ndarray:
    name, dur = "turnstile_hum", 4.0
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    hum = np.zeros(n)
    for f, a in ((60.0, 0.5), (120.0, 0.35), (180.0, 0.2), (240.0, 0.12), (360.0, 0.07)):
        hum += np.sin(2.0 * math.pi * f * t + rng.random()) * a
    hum *= 0.85 + 0.15 * np.sin(2.0 * math.pi * 6.0 * t)
    buzz = polyblep_square(np.full(n, 120.0), n) * 0.06
    buzz = fft_filter(buzz, lowpass=900.0, circular=True)
    whoosh = np.zeros(n)
    sweep = fft_filter(rng.standard_normal(nsamp(0.45)), highpass=180.0, lowpass=2200.0, circular=False)
    sweep *= env_points(nsamp(0.45), [(0.0, 0.0), (0.16, 1.0), (0.45, 0.0)])
    for pos in (0.5, 1.5, 2.5, 3.5):
        add_signal(whoosh, sweep, pos, wrap=True)
    glide = np.sin(2.0 * math.pi * 220.0 * t + 0.9 * np.sin(2.0 * math.pi * 2.0 * t)) * 0.05
    sig = (hum + buzz) * 0.5 + whoosh * 0.35 + glide * 0.5
    return master(sig, peak_db=-9.0, highpass=45.0, fade_in=0.0, fade_out=0.0, circular=True)


def sfx_crowd_loop() -> np.ndarray:
    name, dur = "crowd_loop", 8.0
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        base = fft_filter(pink_noise(rng, n), highpass=170.0, lowpass=3000.0, circular=True) * 0.55
        form = (
            fft_filter(pink_noise(rng, n), highpass=350.0, lowpass=900.0, circular=True) * 0.55
            + fft_filter(pink_noise(rng, n), highpass=900.0, lowpass=1900.0, circular=True) * 0.35
            + fft_filter(pink_noise(rng, n), highpass=2600.0, lowpass=5200.0, circular=True) * 0.16
        )
        bed = base + form
        for k in range(1, 10):
            hz = k / dur
            bed *= 1.0 + (0.20 / (1.0 + 0.6 * k)) * np.sin(2.0 * math.pi * hz * t + rng.random() * 6.283)
        out[:, ch] = bed
    clap_bank = clap(rng, 0.11)
    for _ in range(6):
        add_signal(out, clap_bank * (0.25 + 0.35 * rng.random()), rng.random() * dur, wrap=True, pan=(rng.random() * 2.0 - 1.0) * 0.8)
    return master(out, peak_db=-13.0, highpass=120.0, fade_in=0.0, fade_out=0.0, circular=True)


def sfx_slash() -> np.ndarray:
    name, dur = "slash", 0.45
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    whoosh = time_varying_filter(
        rng.standard_normal(n),
        highpass_fn=lambda p: 2600.0 - 1700.0 * p,
        lowpass_fn=lambda p: 9500.0 - 5600.0 * p,
        frame=1024,
        hop=256,
    )
    whoosh *= env_points(n, [(0.0, 0.0), (0.004, 1.0), (0.11, 0.5), (dur, 0.0)])
    shing = np.sin(2.0 * math.pi * np.cumsum(2100.0 - 1450.0 * np.linspace(0.0, 1.0, n)) / SR)
    shing *= np.exp(-t / 0.05) * 0.30
    metal = metallic_partials(rng, n, base=2680.0, decay=0.085, density=0.35)
    sig = whoosh * 0.9 + shing + metal
    return master(sig, peak_db=-1.5, highpass=180.0, fade_out=0.03)


def sfx_metal_hit() -> np.ndarray:
    name, dur = "metal_hit", 0.80
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    sig = metallic_partials(rng, n, base=430.0, decay=0.30, density=1.0)
    sig += metallic_partials(rng, n, base=1180.0, decay=0.12, density=0.5)
    sig += fft_filter(rng.standard_normal(n), highpass=2400.0, circular=False) * np.exp(-t / 0.006) * 0.9
    sig += np.sin(2.0 * math.pi * 118.0 * t) * np.exp(-t / 0.05) * 0.55
    sig += rng.standard_normal(n) * np.exp(-t / 0.0012) * 0.45
    sig = np.tanh(sig * 1.5) * 0.8
    return master(sig, peak_db=-1.0, highpass=45.0, fade_out=0.05)


def sfx_heavy_hit() -> np.ndarray:
    name, dur = "heavy_hit", 1.00
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    low = metallic_partials(rng, n, base=235.0, decay=0.40, density=1.0)
    high = metallic_partials(rng, n, base=920.0, decay=0.16, density=0.6)
    crunch = fft_filter(rng.standard_normal(n), highpass=600.0, lowpass=6000.0, circular=False)
    crunch *= env_exp(n, attack=0.001, tau=0.05) * 0.8
    thump = np.sin(2.0 * math.pi * 82.0 * t) * np.exp(-t / 0.14) * 0.9
    drop = sub_drop(rng, dur, f_start=70.0, f_end=32.0) * 0.5
    sig = np.tanh((low + high + crunch + thump) * 1.4)
    sig = sig * 0.85 + drop
    return master(sig, peak_db=-1.0, highpass=32.0, fade_out=0.08)


def sfx_body_check() -> np.ndarray:
    name, dur = "body_check", 0.60
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    thud = np.sin(2.0 * math.pi * (105.0 + 40.0 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.10) * 0.9
    crunch = fft_filter(rng.standard_normal(n), highpass=220.0, lowpass=1800.0, circular=False)
    crunch *= env_exp(n, attack=0.001, tau=0.045) * 0.7
    gear = np.zeros(n)
    for _ in range(5):
        at = 0.045 + rng.random() * 0.20
        m = nsamp(0.08)
        tick = fft_filter(rng.standard_normal(m), highpass=2800.0, circular=False)
        tick *= np.exp(-tline(m) / 0.012) * (0.10 + 0.08 * rng.random())
        add_signal(gear, tick, at)
    puff = fft_filter(rng.standard_normal(n), highpass=120.0, lowpass=520.0, circular=False) * np.exp(-t / 0.07) * 0.25
    sig = thud + crunch + gear + puff
    return master(sig, peak_db=-1.2, highpass=38.0, fade_out=0.05)


def sfx_puck_pickup() -> np.ndarray:
    name, dur = "puck_pickup", 0.38
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    snap = fft_filter(rng.standard_normal(n), highpass=2400.0, circular=False) * np.exp(-t / 0.002) * 0.8
    chirp_f = 880.0 + 520.0 * np.clip(t / 0.10, 0.0, 1.0)
    chirp = np.sin(2.0 * math.pi * np.cumsum(chirp_f) / SR) * env_exp(n, attack=0.001, tau=0.09) * 0.55
    bell = np.sin(2.0 * math.pi * 2640.0 * t) * 0.30 + np.sin(2.0 * math.pi * 3520.0 * t) * 0.16
    bell *= env_exp(n, attack=0.002, tau=0.10)
    low = np.sin(2.0 * math.pi * 240.0 * t) * np.exp(-t / 0.035) * 0.25
    sig = snap + chirp + bell + low
    return master(sig, peak_db=-2.5, highpass=70.0, fade_out=0.04)


def sfx_shot() -> np.ndarray:
    name, dur = "shot", 0.55
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    whoosh = time_varying_filter(
        rng.standard_normal(n),
        highpass_fn=lambda p: 3200.0 - 2400.0 * p,
        lowpass_fn=lambda p: 9000.0 - 6800.0 * p,
        frame=1024,
        hop=256,
    )
    whoosh *= env_points(n, [(0.0, 0.0), (0.005, 1.0), (0.10, 0.45), (dur, 0.0)])
    crack = rng.standard_normal(n) * np.exp(-t / 0.0022) * 0.75
    launch_f = 520.0 - 380.0 * np.clip(t / 0.18, 0.0, 1.0)
    launch = np.sin(2.0 * math.pi * np.cumsum(launch_f) / SR) * np.exp(-t / 0.06) * 0.5
    thump = np.sin(2.0 * math.pi * 96.0 * t) * np.exp(-t / 0.055) * 0.55
    tail = fft_filter(rng.standard_normal(n), highpass=700.0, lowpass=4200.0, circular=False) * np.exp(-t / 0.09) * 0.18
    sig = whoosh * 0.8 + crack + launch + thump + tail
    return master(sig, peak_db=-1.5, highpass=40.0, fade_out=0.05)


def sfx_goal_horn() -> np.ndarray:
    name, dur = "goal_horn", 2.20
    rng = rng_for(name)
    n = nsamp(dur)
    out = np.zeros((n, 2))

    def horn_note(midi: float, length: float, amp: float) -> np.ndarray:
        m = nsamp(length)
        env = env_points(m, [(0.0, 0.0), (0.035, 1.0), (length * 0.55, 0.95), (length * 0.82, 0.75), (length, 0.0)])
        f = midi_hz(midi)
        sig = np.zeros(m)
        for cents in (-6.0, 0.0, 6.0):
            sig += saw_voice(f, m, cents=cents, vib_hz=5.2, vib_cents=6.0, phase=rng.random())
        sig += polyblep_square(np.full(m, f), m, phase0=rng.random()) * 0.35
        sig = fft_filter(sig, highpass=60.0, lowpass=3400.0, circular=False)
        return sig * env * amp

    for midi, delay, amp in ((146.83, 0.0, 0.34), (220.0, 0.0, 0.30), (293.66, 0.0, 0.22), (349.23, 0.18, 0.10)):
        note = horn_note(midi, 1.75, amp)
        add_signal(out, note, delay, pan=0.0)
        add_signal(out, note * 0.5, delay + 0.012, pan=-0.45)
        add_signal(out, note * 0.5, delay + 0.024, pan=0.45)
    crowd = fft_filter(pink_noise(rng, n), highpass=250.0, lowpass=2600.0, circular=False)
    crowd *= env_points(n, [(0.0, 0.0), (0.5, 0.35), (1.5, 0.5), (dur, 0.0)]) * 0.35
    out += crowd[:, None]
    out = reverb_stereo(out, rng, mix=0.16, decay=1.2, damp=4500.0)
    return master(out, peak_db=-1.2, highpass=55.0, fade_out=0.12)


def sfx_crowd_swell() -> np.ndarray:
    name, dur = "crowd_swell", 3.20
    rng = rng_for(name)
    n = nsamp(dur)
    out = np.zeros((n, 2))
    for ch in range(2):
        base = fft_filter(pink_noise(rng, n), highpass=180.0, lowpass=2800.0, circular=False)
        form = (
            fft_filter(pink_noise(rng, n), highpass=320.0, lowpass=850.0, circular=False) * 0.6
            + fft_filter(pink_noise(rng, n), highpass=850.0, lowpass=1800.0, circular=False) * 0.4
            + fft_filter(pink_noise(rng, n), highpass=2400.0, lowpass=5400.0, circular=False) * 0.22
        )
        out[:, ch] = base * 0.5 + form
    env = env_points(n, [(0.0, 0.0), (0.85, 0.85), (1.5, 1.0), (2.2, 0.8), (dur, 0.0)])
    out *= env[:, None]
    clap_bank = clap(rng, 0.10)
    for _ in range(14):
        at = rng.random() * dur
        gain = (0.2 + 0.3 * rng.random()) * float(np.interp(at, tline(n), env))
        add_signal(out, clap_bank * gain, at, pan=(rng.random() * 2.0 - 1.0) * 0.9)
    return master(out, peak_db=-3.0, highpass=130.0, fade_out=0.10)


def sfx_ui_click() -> np.ndarray:
    name, dur = "ui_click", 0.16
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    noise = fft_filter(rng.standard_normal(n), highpass=2600.0, circular=False) * np.exp(-t / 0.0018) * 0.6
    f = 1180.0 - 380.0 * np.clip(t / 0.04, 0.0, 1.0)
    tone = polyblep_square(f, n) * np.exp(-t / 0.022) * 0.35
    return master(noise + tone, peak_db=-7.0, highpass=300.0, fade_out=0.01)


def sfx_ui_hover() -> np.ndarray:
    name, dur = "ui_hover", 0.10
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    tone = np.sin(2.0 * math.pi * 2320.0 * t) * env_exp(n, attack=0.001, tau=0.012) * 0.5
    tick = fft_filter(rng.standard_normal(n), highpass=5000.0, circular=False) * np.exp(-t / 0.0012) * 0.25
    return master(tone + tick, peak_db=-12.0, highpass=800.0, fade_out=0.008)


def sfx_ui_back() -> np.ndarray:
    name, dur = "ui_back", 0.22
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    seg1, seg2 = nsamp(0.075), nsamp(0.13)
    s1 = np.sin(2.0 * math.pi * 980.0 * tline(seg1)) * env_exp(seg1, attack=0.001, tau=0.03) * 0.4
    s2 = np.sin(2.0 * math.pi * 640.0 * tline(seg2)) * env_exp(seg2, attack=0.001, tau=0.04) * 0.35
    tick = fft_filter(rng.standard_normal(n), highpass=3500.0, circular=False) * np.exp(-t / 0.0015) * 0.3
    out = np.zeros(n)
    add_signal(out, s1, 0.0)
    add_signal(out, s2, 0.075)
    return master(out + tick, peak_db=-9.0, highpass=300.0, fade_out=0.02)


def sfx_killball_charge() -> np.ndarray:
    name, dur = "killball_charge", 1.60
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    f = 180.0 * (1500.0 / 180.0) ** np.clip(t / dur, 0.0, 1.0)
    ph = 2.0 * math.pi * np.cumsum(f) / SR
    whine = np.sin(ph) * 0.5 + np.sin(2.0 * ph) * 0.22 + np.sin(3.0 * ph) * 0.12
    am = 0.72 + 0.28 * np.sin(2.0 * math.pi * (28.0 + 42.0 * t / dur) * t)
    whine *= am
    crackles = np.zeros(n)
    count = 34
    for i in range(count):
        at = dur * (i / count) ** 0.75 * 0.97
        m = nsamp(0.02)
        burst = fft_filter(rng.standard_normal(m), highpass=4200.0, circular=False)
        burst *= np.exp(-tline(m) / 0.0025) * (0.25 + 0.55 * i / count)
        add_signal(crackles, burst, at)
    amp = env_points(n, [(0.0, 0.0), (0.10, 0.35), (dur * 0.85, 1.0), (dur, 0.15)])
    sig = np.tanh((whine + crackles) * amp * 1.3)
    return master(sig, peak_db=-2.0, highpass=70.0, fade_out=0.012)


def sfx_killball_zap() -> np.ndarray:
    name, dur = "killball_zap", 0.90
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    gate = np.where(np.sin(2.0 * math.pi * 92.0 * t) > -0.2, 1.0, 0.25)
    discharge = fft_filter(rng.standard_normal(n), highpass=380.0, lowpass=12000.0, circular=False)
    discharge *= env_exp(n, attack=0.001, tau=0.10) * gate
    zap_f = 2800.0 - 2500.0 * np.clip(t / 0.16, 0.0, 1.0)
    zap = np.sin(2.0 * math.pi * np.cumsum(zap_f) / SR) * np.exp(-t / 0.06) * 0.55
    boom = sub_drop(rng, dur, f_start=110.0, f_end=30.0) * 0.7
    ring = np.sin(2.0 * math.pi * 2150.0 * t) * np.exp(-t / 0.18) * 0.20
    crackle = np.zeros(n)
    for _ in range(10):
        m = nsamp(0.015)
        b = fft_filter(rng.standard_normal(m), highpass=5200.0, circular=False) * np.exp(-tline(m) / 0.002) * (0.2 + 0.4 * rng.random())
        add_signal(crackle, b, rng.random() * 0.55)
    sig = np.tanh((discharge * 0.9 + zap + ring) * 1.5) * 0.9 + boom + crackle * 0.5
    return master(sig, peak_db=-1.0, highpass=32.0, fade_out=0.08)


def sfx_countdown_beep() -> np.ndarray:
    name, dur = "countdown_beep", 0.22
    n = nsamp(dur)
    t = tline(n)
    env = env_points(n, [(0.0, 0.0), (0.005, 1.0), (0.07, 0.7), (dur, 0.0)])
    sig = (np.sin(2.0 * math.pi * 880.0 * t) * 0.7 + np.sin(2.0 * math.pi * 1760.0 * t) * 0.15) * env
    return master(sig, peak_db=-9.0, highpass=120.0, fade_out=0.02)


def sfx_countdown_go() -> np.ndarray:
    name, dur = "countdown_go", 0.50
    n = nsamp(dur)
    t = tline(n)
    env = env_points(n, [(0.0, 0.0), (0.006, 1.0), (0.14, 0.85), (dur, 0.0)])
    sig = np.zeros(n)
    for f, a in ((1320.0, 0.55), (1980.0, 0.28), (2640.0, 0.12)):
        sig += np.sin(2.0 * math.pi * f * t) * a
    return master(np.tanh(sig * env * 1.2), peak_db=-6.0, highpass=150.0, fade_out=0.04)


def sfx_victory() -> np.ndarray:
    name, dur = "victory", 2.60
    rng = rng_for(name)
    n = nsamp(dur)
    out = np.zeros((n, 2))
    for i, midi in enumerate((62, 65, 69, 74, 77)):
        m = nsamp(0.22)
        blip = polyblep_saw(midi_hz(midi), m) * env_exp(m, attack=0.002, tau=0.05) * 0.22
        add_signal(out, blip, 0.03 + i * 0.075, pan=-0.5 + 0.25 * i)
    for midi, amp, pan in ((50, 0.30, -0.4), (53, 0.22, 0.35), (57, 0.24, -0.2), (62, 0.18, 0.45), (65, 0.10, -0.55)):
        m = nsamp(1.9)
        raw = np.zeros(m)
        for cents in (-7.0, 0.0, 7.0):
            raw += saw_voice(midi_hz(midi), m, cents=cents, vib_hz=4.6, vib_cents=5.0, phase=rng.random())
        raw = fft_filter(raw, highpass=70.0, lowpass=3200.0, circular=False)
        env = env_points(m, [(0.0, 0.0), (0.16, 1.0), (1.2, 0.75), (1.9, 0.0)])
        add_signal(out, raw * env * amp, 0.22, pan=pan)
    impact = kick(rng, 0.7, f_start=140.0, f_end=38.0, decay=0.30) * 0.8
    add_signal(out, impact, 0.22)
    shimmer = fft_filter(rng.standard_normal(n), highpass=4800.0, circular=False)
    shimmer *= env_points(n, [(0.0, 0.0), (0.3, 0.25), (1.4, 0.10), (dur, 0.0)]) * 0.4
    out += shimmer[:, None]
    out = reverb_stereo(out, rng, mix=0.24, decay=1.8, damp=5200.0)
    return master(out, peak_db=-1.2, highpass=50.0, fade_out=0.25)


def sfx_death() -> np.ndarray:
    name, dur = "death", 2.20
    rng = rng_for(name)
    n = nsamp(dur)
    out = np.zeros((n, 2))
    m = nsamp(1.4)
    tt = tline(m)
    f = 300.0 * (58.0 / 300.0) ** np.clip(tt / 1.1, 0.0, 1.0)
    raw = np.zeros(m)
    for cents in (-9.0, 0.0, 9.0):
        raw += polyblep_saw(f * 2.0 ** (cents / 1200.0), m)
    raw = fft_filter(raw, highpass=40.0, lowpass=1800.0, circular=False)
    env = env_points(m, [(0.0, 0.0), (0.03, 1.0), (0.7, 0.6), (1.4, 0.0)])
    add_signal(out, raw * env * 0.5, 0.05)
    rev = fft_filter(rng.standard_normal(nsamp(1.1)), highpass=300.0, lowpass=6000.0, circular=False)
    rev *= env_points(nsamp(1.1), [(0.0, 0.0), (1.05, 0.55), (1.1, 0.0)])
    add_signal(out, rev * 0.5, 0.0, pan=-0.3)
    add_signal(out, sub_drop(rng, 1.2, f_start=80.0, f_end=28.0) * 0.85, 0.05)
    mm = nsamp(0.9)
    creak = metallic_partials(rng, mm, base=180.0, decay=0.30, density=0.5)
    creak *= env_points(mm, [(0.0, 0.0), (0.1, 0.5), (0.9, 0.0)])
    add_signal(out, creak * 0.35, 0.30, pan=0.4)
    out = reverb_stereo(out, rng, mix=0.30, decay=2.2, damp=2600.0)
    out = fft_filter(out, highpass=30.0, circular=False)
    return master(out, peak_db=-1.4, highpass=None, fade_out=0.30)

# --------------------------------------------------------------------------
# extra SFX required by main.gd integration (names the Lead already calls)
# --------------------------------------------------------------------------


def sfx_horn_short() -> np.ndarray:
    name, dur = "horn_short", 1.00
    rng = rng_for(name)
    n = nsamp(dur)
    out = np.zeros((n, 2))
    for midi, amp, pan in ((146.83, 0.34, -0.25), (220.0, 0.30, 0.20), (293.66, 0.20, 0.40)):
        m = nsamp(0.70)
        tt = tline(m)
        env = env_points(m, [(0.0, 0.0), (0.03, 1.0), (0.35, 0.9), (0.55, 0.55), (0.70, 0.0)])
        freq = midi_hz(midi) * (1.0 + 0.03 * np.exp(-tt / 0.04))
        sig = polyblep_saw(freq, m) + polyblep_square(np.full(m, midi_hz(midi)), m) * 0.25
        sig = fft_filter(sig, highpass=80.0, lowpass=3200.0, circular=False)
        add_signal(out, sig * env * amp, 0.0, pan=pan)
    out = reverb_stereo(out, rng, mix=0.10, decay=0.9, damp=5000.0)
    return master(out, peak_db=-2.0, highpass=60.0, fade_out=0.05)


def sfx_crowd_goal() -> np.ndarray:
    name, dur = "crowd_goal", 2.40
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        base = fft_filter(pink_noise(rng, n), highpass=160.0, lowpass=2600.0, circular=False)
        form = (
            fft_filter(pink_noise(rng, n), highpass=300.0, lowpass=800.0, circular=False) * 0.7
            + fft_filter(pink_noise(rng, n), highpass=800.0, lowpass=1700.0, circular=False) * 0.5
            + fft_filter(pink_noise(rng, n), highpass=2300.0, lowpass=5600.0, circular=False) * 0.30
        )
        roar = base * 0.55 + form
        roar *= 0.82 + 0.18 * np.sin(2.0 * math.pi * 2.1 * t + rng.random() * 6.283)
        out[:, ch] = roar
    env = env_points(n, [(0.0, 0.0), (0.10, 0.55), (0.45, 1.0), (1.6, 0.85), (dur, 0.0)])
    out *= env[:, None]
    clap_bank = clap(rng, 0.10)
    for _ in range(22):
        at = rng.random() * 1.9
        gain = (0.25 + 0.35 * rng.random()) * float(np.interp(at, tline(n), env))
        add_signal(out, clap_bank * gain, at, pan=(rng.random() * 2.0 - 1.0) * 0.9)
    return master(out, peak_db=-2.0, highpass=110.0, fade_out=0.20)


def sfx_defeat() -> np.ndarray:
    name, dur = "defeat", 2.40
    rng = rng_for(name)
    n = nsamp(dur)
    out = np.zeros((n, 2))
    m = nsamp(1.5)
    tt = tline(m)
    freq = 146.83 * (0.25 / 1.0) ** np.clip(tt / 1.25, 0.0, 1.0)
    raw = np.zeros(m)
    for cents in (-8.0, 0.0, 8.0):
        raw += polyblep_saw(freq * 2.0 ** (cents / 1200.0), m)
    raw = fft_filter(raw, highpass=35.0, lowpass=1600.0, circular=False)
    env = env_points(m, [(0.0, 0.0), (0.03, 1.0), (0.8, 0.55), (1.5, 0.0)])
    add_signal(out, raw * env * 0.42, 0.04)
    for midi, amp, pan in ((50, 0.22, -0.3), (53, 0.16, 0.3), (57, 0.14, -0.1)):
        m2 = nsamp(1.9)
        pad = np.zeros(m2)
        for cents in (-6.0, 6.0):
            pad += saw_voice(midi_hz(midi), m2, cents=cents, vib_hz=0.3, vib_cents=4.0, phase=rng.random())
        pad = fft_filter(pad, highpass=60.0, lowpass=1400.0, circular=False)
        penv = env_points(m2, [(0.0, 0.0), (0.12, 1.0), (1.2, 0.7), (1.9, 0.0)])
        add_signal(out, pad * penv * amp, 0.10, pan=pan)
    add_signal(out, sub_drop(rng, 1.3, f_start=72.0, f_end=26.0) * 0.8, 0.04)
    rev = fft_filter(rng.standard_normal(nsamp(1.2)), highpass=280.0, lowpass=5200.0, circular=False)
    rev *= env_points(nsamp(1.2), [(0.0, 0.0), (1.15, 0.5), (1.2, 0.0)])
    add_signal(out, rev * 0.4, 0.0, pan=0.2)
    out = reverb_stereo(out, rng, mix=0.28, decay=2.1, damp=2400.0)
    out = fft_filter(out, highpass=28.0, circular=False)
    return master(out, peak_db=-1.5, highpass=None, fade_out=0.35)


def sfx_down() -> np.ndarray:
    name, dur = "down", 0.90
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    fall_f = 230.0 * (70.0 / 230.0) ** np.clip(t / 0.30, 0.0, 1.0)
    fall = np.sin(2.0 * math.pi * np.cumsum(fall_f) / SR) * np.exp(-t / 0.22) * 0.55
    thud = np.sin(2.0 * math.pi * 78.0 * t) * np.exp(-t / 0.11) * 0.9
    skid = fft_filter(rng.standard_normal(n), highpass=1200.0, lowpass=7000.0, circular=False)
    skid *= env_points(n, [(0.0, 0.0), (0.02, 0.5), (0.25, 0.12), (0.6, 0.0)])
    gear = np.zeros(n)
    for _ in range(6):
        mm = nsamp(0.05)
        tick = fft_filter(rng.standard_normal(mm), highpass=3200.0, circular=False) * np.exp(-tline(mm) / 0.008)
        add_signal(gear, tick * (0.10 + 0.08 * rng.random()), 0.04 + rng.random() * 0.25)
    sig = np.tanh((thud + fall + gear) * 1.2) + skid * 0.35
    return master(sig, peak_db=-1.5, highpass=35.0, fade_out=0.06)


def sfx_boost_pad() -> np.ndarray:
    name, dur = "boost_pad", 0.55
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    sweep = time_varying_filter(
        rng.standard_normal(n),
        highpass_fn=lambda p: 500.0 + 2200.0 * p,
        lowpass_fn=lambda p: 1800.0 + 7000.0 * p,
        frame=1024,
        hop=256,
    )
    sweep *= env_points(n, [(0.0, 0.0), (0.03, 0.7), (0.18, 1.0), (dur, 0.0)])
    tone_f = 260.0 * (1300.0 / 260.0) ** np.clip(t / 0.35, 0.0, 1.0)
    tone = np.sin(2.0 * math.pi * np.cumsum(tone_f) / SR) * env_points(n, [(0.0, 0.0), (0.05, 0.8), (0.30, 0.5), (dur, 0.0)])
    ping = np.sin(2.0 * math.pi * 2400.0 * t) * np.exp(-np.maximum(t - 0.18, 0.0) / 0.06) * np.clip((t - 0.18) / 0.01, 0.0, 1.0) * 0.3
    sig = sweep * 0.8 + tone * 0.5 + ping
    return master(sig, peak_db=-2.5, highpass=180.0, fade_out=0.05)


def sfx_save() -> np.ndarray:
    name, dur = "save", 0.70
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    slap = fft_filter(rng.standard_normal(n), highpass=2800.0, circular=False) * np.exp(-t / 0.0035) * 0.9
    leather = np.sin(2.0 * math.pi * 188.0 * t) * np.exp(-t / 0.05) * 0.6
    thock = np.sin(2.0 * math.pi * (470.0 + 120.0 * np.exp(-t / 0.015)) * t) * np.exp(-t / 0.055) * 0.5
    rebound = fft_filter(rng.standard_normal(n), highpass=900.0, lowpass=4200.0, circular=False) * np.exp(-t / 0.07) * 0.25
    gasp = fft_filter(pink_noise(rng, n), highpass=300.0, lowpass=1600.0, circular=False)
    gasp *= env_points(n, [(0.0, 0.0), (0.06, 0.25), (0.18, 0.35), (0.55, 0.0)])
    sig = np.tanh((slap + leather + thock) * 1.3) + rebound * 0.6 + gasp
    return master(sig, peak_db=-1.5, highpass=60.0, fade_out=0.07)


def sfx_hit_rok() -> np.ndarray:
    name, dur = "hit_rok", 0.35
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    metal = metallic_partials(rng, n, base=920.0, decay=0.075, density=0.85)
    knock = np.sin(2.0 * math.pi * 320.0 * t) * np.exp(-t / 0.035) * 0.55
    click = rng.standard_normal(n) * np.exp(-t / 0.0015) * 0.5
    sig = np.tanh((metal + knock + click) * 1.4)
    return master(sig, peak_db=-2.0, highpass=120.0, fade_out=0.03)


def sfx_pass() -> np.ndarray:
    name, dur = "pass", 0.40
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    whoosh = time_varying_filter(
        rng.standard_normal(n),
        highpass_fn=lambda p: 2200.0 - 1400.0 * p,
        lowpass_fn=lambda p: 7200.0 - 4400.0 * p,
        frame=1024,
        hop=256,
    )
    whoosh *= env_points(n, [(0.0, 0.0), (0.006, 0.8), (0.10, 0.35), (dur, 0.0)])
    tap = fft_filter(rng.standard_normal(n), highpass=1800.0, circular=False) * np.exp(-t / 0.004) * 0.5
    body = np.sin(2.0 * math.pi * 240.0 * t) * np.exp(-t / 0.045) * 0.35
    sig = whoosh * 0.9 + tap + body
    return master(sig, peak_db=-3.0, highpass=160.0, fade_out=0.04)


def sfx_killball_throw() -> np.ndarray:
    name, dur = "killball_throw", 0.85
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    whoosh = time_varying_filter(
        rng.standard_normal(n),
        highpass_fn=lambda p: 800.0 + 1500.0 * p,
        lowpass_fn=lambda p: 6000.0 + 4000.0 * p,
        frame=1024,
        hop=256,
    )
    whoosh *= env_points(n, [(0.0, 0.0), (0.01, 0.9), (0.20, 0.6), (dur, 0.0)])
    whine_f = 1800.0 * (420.0 / 1800.0) ** np.clip(t / 0.5, 0.0, 1.0)
    whine = np.sin(2.0 * math.pi * np.cumsum(whine_f) / SR)
    whine *= (0.5 + 0.5 * np.sin(2.0 * math.pi * 62.0 * t)) * np.exp(-t / 0.35) * 0.35
    crackle = np.zeros(n)
    for _ in range(12):
        mm = nsamp(0.018)
        b = fft_filter(rng.standard_normal(mm), highpass=3800.0, circular=False) * np.exp(-tline(mm) / 0.002)
        add_signal(crackle, b * (0.15 + 0.35 * rng.random()), rng.random() * 0.45)
    sig = np.tanh((whoosh * 0.8 + whine) * 1.4) + crackle * 0.6
    return master(sig, peak_db=-1.5, highpass=120.0, fade_out=0.06)


def sfx_slash_hit() -> np.ndarray:
    name, dur = "slash_hit", 0.50
    rng = rng_for(name)
    n = nsamp(dur)
    t = tline(n)
    whoosh = time_varying_filter(
        rng.standard_normal(n),
        highpass_fn=lambda p: 3000.0 - 1800.0 * p,
        lowpass_fn=lambda p: 10000.0 - 5000.0 * p,
        frame=1024,
        hop=256,
    )
    whoosh *= env_points(n, [(0.0, 0.0), (0.004, 0.9), (0.08, 0.4), (dur, 0.0)]) * 0.6
    metal = metallic_partials(rng, n, base=1480.0, decay=0.10, density=0.85)
    thump = np.sin(2.0 * math.pi * 152.0 * t) * np.exp(-t / 0.045) * 0.5
    click = rng.standard_normal(n) * np.exp(-t / 0.0015) * 0.45
    sig = np.tanh((metal + thump + click) * 1.4) * 0.9 + whoosh
    return master(sig, peak_db=-1.0, highpass=70.0, fade_out=0.04)


# --------------------------------------------------------------------------
# match music: 40.0 s seamless dark synthwave / industrial loop
# --------------------------------------------------------------------------

BPM = 120.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BARS = 20
LOOP_SEC = BAR * BARS  # 40.0 exactly
CHORD_CYCLE = ("Dm", "Bb", "Gm", "A")

CHORDS = {
    "Dm": {"root": 38, "pad": (50, 53, 57, 60, 64), "arp": (62, 65, 69, 72, 76, 81)},
    "Bb": {"root": 34, "pad": (46, 50, 53, 57, 62), "arp": (58, 62, 65, 69, 72, 77)},
    "Gm": {"root": 31, "pad": (43, 46, 50, 53, 58), "arp": (55, 58, 62, 65, 69, 74)},
    "A": {"root": 33, "pad": (45, 49, 52, 55, 60), "arp": (57, 61, 64, 69, 72, 76)},
}

SECTION_GAIN = {
    "pad": {"D": 0.60, "C": 0.95, "E": 0.62},
    "bass": {"D": 1.00, "C": 0.16, "E": 0.95},
    "arp": {"D": 0.40, "C": 0.55, "E": 0.38},
}


def section_of_bar(bar: int) -> str:
    if bar < 8:
        return "D"
    if bar < 12:
        return "C"
    return "E"


def _arrangement() -> dict:
    kicks = []
    snares = []
    hats = []
    for bar in range(BARS):
        sec = section_of_bar(bar)
        base = bar * BAR
        for beat in range(4):
            if sec != "C":
                play = True
            elif bar in (8, 9):
                play = beat == 0
            elif bar == 10:
                play = beat in (0, 2)
            else:
                play = True
            if play:
                kicks.append((base + beat * BEAT, 1.0 if beat in (0, 2) else 0.9))
    for bar in range(BARS):
        sec = section_of_bar(bar)
        base = bar * BAR
        if sec in ("D", "E"):
            snares.append((base + BEAT, 0.78))
            snares.append((base + 3.0 * BEAT, 0.90))
        if sec == "C" and bar == 11:
            for i in range(8, 16):
                snares.append((base + i * BEAT / 4.0, 0.30 + 0.05 * (i - 8)))
        if bar == 19:
            for i in range(12, 16):
                snares.append((base + i * BEAT / 4.0, 0.55 + 0.08 * (i - 12)))
    hat_vel = (0.55, 0.22, 0.78, 0.24, 0.50, 0.22, 0.72, 0.26, 0.55, 0.22, 0.78, 0.24, 0.52, 0.22, 0.85, 0.30)
    for bar in range(BARS):
        sec = section_of_bar(bar)
        base = bar * BAR
        if sec in ("D", "E"):
            for i in range(16):
                hats.append((base + i * BEAT / 4.0, hat_vel[i], i in (6, 14)))
        if sec == "C" and bar == 11:
            for i in range(8, 16):
                hats.append((base + i * BEAT / 4.0, 0.32 + 0.05 * (i - 8), False))
    clangs = [(0.0, 0.62), (7 * BAR, 0.40), (8 * BAR, 0.50), (12 * BAR, 0.85), (16 * BAR, 0.50)]
    return {"kicks": kicks, "snares": snares, "hats": hats, "clangs": clangs}


def _music_pad(rng: np.random.Generator) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    left = np.zeros(n)
    right = np.zeros(n)
    for bar in range(BARS):
        chord = CHORDS[CHORD_CYCLE[bar % 4]]
        start = bar * BAR
        sec = section_of_bar(bar)
        duration = BAR + 0.55
        nn = nsamp(duration)
        for note in chord["pad"]:
            env = env_points(nn, [(0.0, 0.0), (0.30, 1.0), (BAR * 0.7, 0.86), (BAR + 0.02, 0.80), (duration, 0.0)])
            for cents, dest in ((-7.0, left), (7.0, right)):
                voice = saw_voice(midi_hz(note), nn, cents=cents, vib_hz=0.19, vib_cents=3.0, phase=rng.random())
                add_signal(dest, voice * env * 0.105 * SECTION_GAIN["pad"][sec], start, wrap=True)
    pad = np.stack([left, right], axis=1)
    table = [0.0, 0.2, 0.4, 0.5, 0.6, 0.8, 1.0]
    values = [1250.0, 1750.0, 2600.0, 2350.0, 2200.0, 2000.0, 1800.0]
    return time_varying_filter(pad, lowpass_fn=lambda p: float(np.interp(p, table, values)), order=2)


def _music_bass(rng: np.random.Generator) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    bus = np.zeros(n)
    pattern = ((0, 1.00, 0), (2, 0.55, 0), (3, 0.82, 12), (6, 0.62, 0), (8, 1.00, 0), (10, 0.58, 0), (11, 0.85, 12), (14, 0.70, 0))
    for bar in range(BARS):
        gain = SECTION_GAIN["bass"][section_of_bar(bar)]
        chord = CHORDS[CHORD_CYCLE[bar % 4]]
        for step, vel, octave in pattern:
            at = bar * BAR + step * BEAT / 4.0
            dur = 0.115 if step in (0, 8) else 0.095
            nn = nsamp(dur + 0.05)
            tt = tline(nn)
            freq = midi_hz(chord["root"] + octave)
            env = env_exp(nn, attack=0.003, tau=0.075)
            sig = saw_voice(freq * 1.0035, nn) * 0.5 + saw_voice(freq * 0.9965, nn) * 0.5
            sig += np.sin(2.0 * math.pi * freq * 0.5 * tt) * 0.40
            sig *= env
            click = fft_filter(rng.standard_normal(nn), highpass=3200.0, circular=False) * np.exp(-tt / 0.0015) * 0.20
            add_signal(bus, (sig + click) * vel * gain * 0.55, at, wrap=True)
    bus = fft_filter(bus, highpass=32.0, lowpass=1500.0, circular=True)
    table = [0.0, 0.2, 0.4, 0.5, 0.6, 0.8, 1.0]
    values = [1300.0, 1200.0, 900.0, 800.0, 1500.0, 1300.0, 1100.0]
    return time_varying_filter(bus, lowpass_fn=lambda p: float(np.interp(p, table, values)), order=2)


def _music_arp(rng: np.random.Generator) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    bus = np.zeros(n)
    pattern = (0, 1, 2, 3, 4, 5, 4, 3, 0, 1, 2, 3, 4, 5, 4, 3)
    for bar in range(0, BARS):
        gain = SECTION_GAIN["arp"][section_of_bar(bar)]
        pool = CHORDS[CHORD_CYCLE[bar % 4]]["arp"]
        for i, idx in enumerate(pattern):
            at = bar * BAR + i * BEAT / 4.0
            nn = nsamp(0.17)
            freq = midi_hz(pool[idx])
            env = env_exp(nn, attack=0.002, tau=0.055)
            voice = saw_voice(freq, nn, cents=2.5) * 0.5 + saw_voice(freq, nn, cents=-2.5) * 0.5
            voice += polyblep_square(np.full(nn, freq * 2.0), nn) * 0.22
            amp = gain * (1.0 if i % 4 == 0 else 0.7)
            add_signal(bus, voice * env * amp, at, wrap=True)
    table = [0.0, 0.2, 0.4, 0.5, 0.6, 0.8, 1.0]
    values = [2200.0, 3200.0, 1400.0, 1100.0, 4200.0, 3600.0, 3000.0]
    bus = time_varying_filter(bus, lowpass_fn=lambda p: float(np.interp(p, table, values)), order=2)
    delay = nsamp(BEAT * 0.75)
    left = bus * 0.78 + np.roll(bus, delay) * 0.20 + np.roll(bus, 3 * delay) * 0.09
    right = bus * 0.78 + np.roll(bus, 2 * delay) * 0.20 + np.roll(bus, 4 * delay) * 0.09
    return np.stack([left, right], axis=1) * 0.9


def _music_lead(rng: np.random.Generator) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    out = np.zeros((n, 2))
    melody = (
        (12, 0, 3, 74), (12, 3, 2, 77), (12, 5, 3, 76), (12, 8, 4, 74), (12, 12, 3, 69),
        (13, 0, 3, 70), (13, 3, 2, 74), (13, 5, 3, 77), (13, 8, 2, 74), (13, 10, 2, 72), (13, 12, 3, 70),
        (14, 0, 3, 67), (14, 3, 2, 70), (14, 5, 3, 74), (14, 8, 3, 77), (14, 11, 2, 76), (14, 13, 2, 74),
        (15, 0, 4, 69), (15, 4, 3, 73), (15, 7, 3, 76), (15, 10, 2, 74), (15, 12, 2, 73), (15, 14, 2, 69),
        (16, 0, 3, 77), (16, 3, 2, 81), (16, 5, 3, 79), (16, 8, 4, 77), (16, 12, 3, 72),
        (17, 0, 3, 74), (17, 3, 2, 77), (17, 5, 3, 79), (17, 8, 2, 77), (17, 10, 2, 76), (17, 12, 3, 74),
        (18, 0, 3, 70), (18, 3, 2, 74), (18, 5, 3, 77), (18, 8, 3, 79), (18, 11, 2, 77), (18, 13, 2, 76),
        (19, 0, 4, 74), (19, 4, 4, 77), (19, 8, 4, 74), (19, 12, 6, 81),
    )
    table = [0.0, 0.2, 0.4, 0.5, 0.6, 0.8, 1.0]
    values = [2000.0, 3000.0, 2600.0, 2500.0, 4200.0, 3800.0, 3400.0]
    for bar, step, length, midi in melody:
        at = bar * BAR + step * BEAT / 4.0
        gate = length * BEAT / 4.0
        nn = nsamp(gate + 0.38)
        tt = tline(nn)
        env = env_points(nn, [(0.0, 0.0), (0.012, 1.0), (gate * 0.8, 0.82), (gate, 0.7), (gate + 0.34, 0.0)])
        mono = np.zeros(nn)
        for cents in (-9.0, 0.0, 9.0):
            mono += saw_voice(midi_hz(midi), nn, cents=cents, vib_hz=5.1, vib_cents=5.0, phase=rng.random())
        mono += np.sin(2.0 * math.pi * midi_hz(midi - 12) * tt) * 0.25
        mono = fft_filter(mono, highpass=120.0, lowpass=4600.0, circular=False)
        mono *= env * 0.16
        add_signal(out, mono, at, pan=-0.12, wrap=True)
        add_signal(out, mono * 0.85, at + 0.012, pan=0.12, wrap=True)
    out = time_varying_filter(out, lowpass_fn=lambda p: float(np.interp(p, table, values)), order=2)
    delay = nsamp(BEAT * 0.75)
    left = out[:, 0] + np.roll(out[:, 0], delay) * 0.16
    right = out[:, 1] + np.roll(out[:, 1], 2 * delay) * 0.16
    return np.stack([left, right], axis=1) * 0.85


def _music_drums(rng: np.random.Generator, arr: dict) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    bus = np.zeros(n)
    for at, vel in arr["kicks"]:
        k = kick(rng, f_start=155.0 + 12.0 * (rng.random() - 0.5), f_end=47.0, decay=0.13)
        add_signal(bus, k * vel * 0.95, at, wrap=True)
    snare_bank = snare(rng)
    clap_bank = clap(rng)
    for at, vel in arr["snares"]:
        add_signal(bus, snare_bank * vel * 0.42, at, wrap=True)
        add_signal(bus, clap_bank * vel * 0.30, at + 0.004, pan=0.1, wrap=True)
    hats_short = hat(rng, 0.05, 0.010)
    hats_long = hat(rng, 0.16, 0.055)
    for at, vel, is_open in arr["hats"]:
        bank = hats_long if is_open else hats_short
        add_signal(bus, bank * vel * 0.16, at, pan=0.18 if is_open else -0.12, wrap=True)
    bus = fft_filter(bus, highpass=32.0, circular=True)
    return np.tanh(bus * 1.15)


def _music_fx(rng: np.random.Generator, arr: dict) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    out = np.zeros((n, 2))
    for at, gain in arr["clangs"]:
        m = nsamp(1.1)
        clang = metallic_partials(rng, m, base=300.0 + 90.0 * rng.random(), decay=0.45, density=0.70)
        clang = fft_filter(clang, highpass=180.0, lowpass=5000.0, circular=False)
        clang *= np.exp(-tline(m) / 0.30) * gain * 0.28
        add_signal(out, clang, at, pan=0.3)
        add_signal(out, clang * 0.7, at, pan=-0.3)
    rise_dur = 4.0
    m = nsamp(rise_dur)
    riser = time_varying_filter(
        rng.standard_normal(m),
        highpass_fn=lambda p: 260.0 + 1400.0 * p,
        lowpass_fn=lambda p: 700.0 + 8600.0 * p,
        frame=2048,
        hop=512,
    )
    riser *= env_points(m, [(0.0, 0.0), (rise_dur * 0.72, 0.35), (rise_dur - 0.02, 1.0), (rise_dur, 0.0)])
    tone_f = 110.0 * (700.0 / 110.0) ** np.clip(tline(m) / rise_dur, 0.0, 1.0)
    riser += np.sin(2.0 * math.pi * np.cumsum(tone_f) / SR)
    riser *= 1.0
    riser *= env_points(m, [(0.0, 0.0), (rise_dur * 0.8, 0.10), (rise_dur, 0.25)])
    add_signal(out, riser * 0.55, 20.0)
    m = nsamp(1.25)
    rev = fft_filter(rng.standard_normal(m), highpass=2600.0, circular=False)
    rev *= env_points(m, [(0.0, 0.0), (1.18, 0.6), (1.25, 0.0)])
    add_signal(out, rev, 22.75, pan=-0.2)
    add_signal(out, kick(rng, 0.9, f_start=130.0, f_end=36.0, decay=0.36) * 0.9, 24.0)
    add_signal(out, sub_drop(rng, 1.1, f_start=105.0, f_end=30.0) * 0.7, 24.0)
    m2 = nsamp(1.6)
    boom = fft_filter(rng.standard_normal(m2), highpass=250.0, lowpass=6500.0, circular=False)
    boom *= np.exp(-tline(m2) / 0.10) * 0.35
    add_signal(out, boom, 24.0)
    m = nsamp(1.4)
    sw = fft_filter(rng.standard_normal(m), highpass=500.0, lowpass=7200.0, circular=False)
    sw *= env_points(m, [(0.0, 0.0), (1.3, 0.5), (1.4, 0.0)])
    add_signal(out, sw, 6.6)
    return out


def _music_bed(rng: np.random.Generator) -> np.ndarray:
    n = nsamp(LOOP_SEC)
    t = tline(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        bed = fft_filter(pink_noise(rng, n), highpass=140.0, lowpass=2400.0, circular=True)
        bed *= 0.7 + 0.3 * np.sin(2.0 * math.pi * 7.0 / LOOP_SEC * t + rng.random() * 6.283)
        out[:, ch] = bed
    return out


def build_music_match() -> np.ndarray:
    rng = rng_for("music_match")
    n = nsamp(LOOP_SEC)
    arr = _arrangement()
    kick_times = [t for t, _v in arr["kicks"]]
    pad = _music_pad(rng) * sidechain_env(n, kick_times, depth=0.22, tau=0.16)[:, None]
    bass = _music_bass(rng) * sidechain_env(n, kick_times, depth=0.52, tau=0.12)
    arp = _music_arp(rng) * sidechain_env(n, kick_times, depth=0.30, tau=0.13)[:, None]
    lead = _music_lead(rng)
    drums = _music_drums(rng, arr)
    fx = _music_fx(rng, arr)
    bed = _music_bed(rng)
    mix = np.zeros((n, 2))
    add_signal(mix, drums, gain=0.80)
    add_signal(mix, bass, gain=0.86)
    add_signal(mix, pad, gain=0.66)
    add_signal(mix, arp, gain=0.54)
    add_signal(mix, lead, gain=0.50)
    add_signal(mix, fx, gain=0.48)
    add_signal(mix, bed, gain=0.030)
    mix = fft_filter(mix, highpass=26.0, circular=True)
    mix = np.tanh(mix * 1.30) / math.tanh(1.30)
    wet = reverb_send(mix.mean(axis=1), rng, decay=2.0, damp=4200.0)
    mix += wet * 0.13
    mix = fft_filter(mix, highpass=28.0, circular=True)
    return master(mix, peak_db=-1.6, highpass=None, fade_in=0.0, fade_out=0.0, circular=True)


# --------------------------------------------------------------------------
# asset registry
# --------------------------------------------------------------------------


@dataclass
class Asset:
    name: str
    channels: int
    loop: bool
    base_db: float
    target_sec: float
    build: Callable[[], np.ndarray]
    purpose: str
    peak_db: float = -1.0
    fade_out: float = 0.02


def build_registry() -> list[Asset]:
    return [
        Asset("skate_loop", 1, True, -14.0, 2.0, sfx_skate_loop,
              "Seamless ice-skate hiss + scrape loop for skater motion (mono, loop).", -9.0, 0.0),
        Asset("slash", 1, False, -3.0, 0.45, sfx_slash,
              "Short jak slash whoosh with metal shing; pitch up for light, down for heavy.", -1.5, 0.03),
        Asset("metal_hit", 1, False, -2.0, 0.80, sfx_metal_hit,
              "Jak-on-jak metal clash: inharmonic partials plus transient.", -1.0, 0.05),
        Asset("heavy_hit", 1, False, -2.0, 1.00, sfx_heavy_hit,
              "Heavy slash impact: low metal ring, crunch and sub drop.", -1.0, 0.08),
        Asset("body_check", 1, False, -3.0, 0.60, sfx_body_check,
              "Body-check thud with gear rattle.", -1.2, 0.05),
        Asset("puck_pickup", 1, False, 0.0, 0.38, sfx_puck_pickup,
              "Rok pickup: magnetic snap plus rising chirp.", -2.5, 0.04),
        Asset("shot", 1, False, -2.5, 0.55, sfx_shot,
              "Charged shot launch: swept whoosh, crack and low thump.", -1.5, 0.05),
        Asset("goal_horn", 2, False, -1.0, 2.20, sfx_goal_horn,
              "Stadium air-horn chord with crowd bed (stereo).", -1.2, 0.12),
        Asset("crowd_swell", 2, False, -4.0, 3.20, sfx_crowd_swell,
              "Crowd roar swell with claps for goals and big hits (stereo).", -3.0, 0.10),
        Asset("crowd_loop", 2, True, -12.0, 8.0, sfx_crowd_loop,
              "Seamless crowd murmur bed for AudioDirector.set_crowd (stereo, loop).", -13.0, 0.0),
        Asset("turnstile_hum", 1, True, -16.0, 4.0, sfx_turnstile_hum,
              "Rotating turnstile hazard hum plus whoosh loop (mono, loop).", -9.0, 0.0),
        Asset("ui_click", 1, False, -12.0, 0.16, sfx_ui_click, "Primary UI click.", -7.0, 0.01),
        Asset("ui_hover", 1, False, -18.0, 0.10, sfx_ui_hover, "Soft UI hover tick.", -12.0, 0.008),
        Asset("ui_back", 1, False, -14.0, 0.22, sfx_ui_back, "UI back/cancel two-tone blip.", -9.0, 0.02),
        Asset("killball_charge", 1, False, -5.0, 1.60, sfx_killball_charge,
              "Killball charger rising electric whine with sparks.", -2.0, 0.012),
        Asset("killball_zap", 1, False, -1.0, 0.90, sfx_killball_zap,
              "Killball electric discharge: gated noise, zap glide, sub boom.", -1.0, 0.08),
        Asset("countdown_beep", 1, False, 2.0, 0.22, sfx_countdown_beep, "Countdown beep (3-2-1).", -9.0, 0.02),
        Asset("countdown_go", 1, False, 2.0, 0.50, sfx_countdown_go, "Countdown GO tone.", -6.0, 0.04),
        Asset("victory", 2, False, -1.0, 2.60, sfx_victory,
              "Victory stinger: rising blips, dark power chord, impact (stereo).", -1.2, 0.25),
        Asset("death", 2, False, -1.0, 2.20, sfx_death,
              "Death stinger: descending detuned saws, reverse swell, sub boom (stereo).", -1.4, 0.30),
        Asset("horn_short", 2, False, 0.0, 1.00, sfx_horn_short,
              "Short period/whistle horn for faceoffs (stereo).", -2.0, 0.05),
        Asset("crowd_goal", 2, False, 0.0, 2.40, sfx_crowd_goal,
              "Big goal crowd roar with claps, layered under the horn (stereo).", -2.0, 0.20),
        Asset("defeat", 2, False, -1.0, 2.40, sfx_defeat,
              "Defeat stinger: descending saws, low minor pad, sub drop (stereo).", -1.5, 0.35),
        Asset("down", 1, False, 0.0, 0.90, sfx_down,
              "Skater knocked down: falling slide tone, thud and gear clatter.", -1.5, 0.06),
        Asset("boost_pad", 1, False, 0.0, 0.55, sfx_boost_pad,
              "Boost pad pickup: rising sweep, tone rise and sparkle.", -2.5, 0.05),
        Asset("save", 1, False, 0.0, 0.70, sfx_save,
              "Goalie save: glove slap, leather thump and crowd gasp.", -1.5, 0.07),
        Asset("hit_rok", 1, False, 0.0, 0.35, sfx_hit_rok,
              "Rok impact: short metal tick plus plastic knock.", -2.0, 0.03),
        Asset("pass", 1, False, 0.0, 0.40, sfx_pass,
              "Quick pass flick whoosh with tap.", -3.0, 0.04),
        Asset("killball_throw", 1, False, 0.0, 0.85, sfx_killball_throw,
              "Killball throw: electric launch whoosh, scanning whine and crackle.", -1.5, 0.06),
        Asset("slash_hit", 1, False, 0.0, 0.50, sfx_slash_hit,
              "Light jak slash impact: whoosh plus bright metal tick and thump.", -1.0, 0.04),
        Asset("music_match", 2, True, -6.0, LOOP_SEC, build_music_match,
              "40.0 s seamless dark synthwave/industrial match loop (stereo, loop).", -1.6, 0.0),
    ]


# --------------------------------------------------------------------------
# verification / auditing
# --------------------------------------------------------------------------


def decode_wav(path: Path) -> tuple:
    with wave.open(str(path), "rb") as w:
        channels = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if channels == 2:
        data = data.reshape(-1, 2)
    return data, {"channels": channels, "sample_width": width, "sample_rate": rate, "frames": frames}


def analyse_spectrum(mono: np.ndarray) -> dict:
    n = len(mono)
    X = np.abs(np.fft.rfft(mono * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, 1.0 / SR)
    total = float(np.sum(X)) + 1e-18
    out = {}
    for lo, hi in ((20.0, 150.0), (150.0, 500.0), (500.0, 2000.0), (2000.0, 6000.0), (6000.0, 16000.0)):
        m = (f >= lo) & (f < hi)
        out["%d-%dHz" % (int(lo), int(hi))] = round(100.0 * float(np.sum(X[m])) / total, 2)
    return {"bands_percent": out, "centroid_hz": round(float(np.sum(f * X) / total), 1)}


def verify_entry(path: Path, entry: dict) -> dict:
    checks = []

    def check(label: str, ok: bool, detail: str = "") -> None:
        checks.append({"check": label, "ok": bool(ok), "detail": detail})

    result = {"name": entry["name"], "file": entry["file"], "checks": checks}
    check("exists", path.exists(), str(path))
    if not path.exists():
        result["status"] = "fail"
        return result
    try:
        data, meta = decode_wav(path)
    except Exception as exc:  # noqa: BLE001
        check("decodable", False, repr(exc))
        result["status"] = "fail"
        return result
    check("decodable", True)
    ch = meta["channels"]
    check("channels", ch == entry["channels"], "%d (expected %d)" % (ch, entry["channels"]))
    check("sample_width_16bit", meta["sample_width"] == 2, "%d-bit" % (meta["sample_width"] * 8))
    check("sample_rate_44100", meta["sample_rate"] == SR, "%d Hz" % meta["sample_rate"])
    frames = meta["frames"]
    duration = frames / float(meta["sample_rate"])
    expect = float(entry["target_sec"])
    tol = max(0.02, expect * 0.02)
    check("duration", abs(duration - expect) <= tol, "%.4f s (expected %.2f s)" % (duration, expect))
    mono = data if data.ndim == 1 else data.mean(axis=1)
    peak = float(np.max(np.abs(data)))
    rms = float(np.sqrt(np.mean(np.square(mono))))
    dc = float(np.mean(data))
    clipped = int(np.sum(np.abs(np.round(data * 32768.0)) >= 32767.0))
    result.update(duration_sec=round(duration, 4), peak_dbfs=round(lin_db(peak), 2),
                  rms_dbfs=round(lin_db(rms), 2), dc_offset=round(dc, 6),
                  clipped_samples=clipped, bytes=path.stat().st_size)
    check("peak_headroom", -24.0 < lin_db(peak) < -0.05, "%.2f dBFS" % lin_db(peak))
    check("audible_rms", -45.0 < lin_db(rms) < -4.0, "%.2f dBFS" % lin_db(rms))
    check("dc_offset", abs(dc) < 0.005, "%.6f" % dc)
    check("no_clipping", clipped == 0, "%d clipped samples" % clipped)
    if entry["loop"]:
        win = min(len(data), nsamp(0.50))
        rms_head = float(np.sqrt(np.mean(np.square(data[:win]))))
        rms_tail = float(np.sqrt(np.mean(np.square(data[-win:]))))
        ratio = rms_head / max(rms_tail, 1e-12)
        step = float(np.max(np.abs(data[0] - data[-1])))
        delta = float(np.max(np.abs(np.diff(data, axis=0))))
        k = min(len(data), nsamp(0.025))
        seam_rms = float(np.sqrt(np.mean(np.square(np.concatenate([data[-k:], data[:k]], axis=0)))))
        loop_rms = float(np.sqrt(np.mean(np.square(data))))
        energy = seam_rms / max(loop_rms, 1e-12)
        check("loop_seam_rms_match", 0.5 <= ratio <= 2.0, "0.5 s head/tail RMS ratio %.3f" % ratio)
        check("loop_seam_step", step <= max(0.05, 0.6 * delta),
              "splice step %.4f vs max in-loop attack delta %.4f" % (step, delta))
        check("loop_seam_energy", 0.2 <= energy <= 3.0, "25 ms seam RMS / loop RMS %.3f" % energy)
        result["loop"] = {"head_tail_rms_ratio": round(ratio, 4), "seam_step": round(step, 5),
                          "max_in_loop_delta": round(delta, 5), "seam_energy_ratio": round(energy, 4)}
    if entry["name"] == "music_match":
        result["spectrum"] = analyse_spectrum(mono)
    result["status"] = "pass" if all(c["ok"] for c in checks) else "fail"
    return result


# --------------------------------------------------------------------------
# reports and images
# --------------------------------------------------------------------------


def write_notice(out_dir: Path, entries: list, total_bytes: int) -> None:
    lines = [
        "# ULTRABLADE audio -- provenance and license",
        "",
        "All WAV files in this directory are original works generated procedurally by this",
        "repository with tools/generate_audio.py (Python 3 + numpy, built-in wave module).",
        "",
        "- No downloaded samples, no sample packs, no field recordings.",
        "- No generative music/AI models were used (no MusicGen, no Stable Audio, etc.).",
        "- Every sound is synthesized from oscillators/noise/envelopes/filters/convolution in code.",
        "- Intended license: CC0-1.0 (public domain dedication) for these generated audio assets.",
        "- Deterministic: each asset seeds a numpy Generator from CRC32(asset name); re-running the",
        "  same tool version reproduces the same audio.",
        "",
        "Generator: tools/generate_audio.py (pipeline %s)." % PIPELINE_VERSION,
        "Format: 44.1 kHz, 16-bit PCM WAV. Mono for positional/impact SFX; stereo for music,",
        "ambience, horn and stingers.",
        "",
        "Generated: %s UTC" % datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "Total: %d files, %.2f MB (budget 25 MB)." % (len(entries), total_bytes / (1024.0 * 1024.0)),
        "",
        "| file | channels | duration | loop | base volume | purpose |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for e in entries:
        lines.append("| %s | %d | %.2f s | %s | %+.1f dB | %s |" % (
            e["file"], e["channels"], e["duration"], "yes" if e["loop"] else "no", e["base_db"], e["purpose"]))
    lines += [
        "",
        "Loop assets (skate_loop, crowd_loop, turnstile_hum, music_match) are built with circular",
        "synthesis/filtering/convolution so the end wraps into the start; verify seams with",
        "python tools/generate_audio.py --verify-only (writes artifacts/audio/audit.json).",
        "",
        "Regenerate: C:/Python/python.exe tools/generate_audio.py",
        "",
    ]
    (out_dir / "NOTICE.md").write_text("\n".join(lines), encoding="utf-8")


def write_report(report_dir: Path, entries: list, results: list, total_bytes: int, elapsed: float, cmd: str) -> None:
    ok = sum(1 for r in results if r["status"] == "pass")
    lines = [
        "# ULTRABLADE audio audit",
        "",
        "- Command: %s" % cmd,
        "- Generated: %s UTC" % datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "- Python: %s | numpy: %s" % (sys.version.split()[0], np.__version__),
        "- Pipeline: %s" % PIPELINE_VERSION,
        "- Files: %d | total %.2f MB (budget 25 MB) | wall %.1f s" % (len(entries), total_bytes / (1024.0 * 1024.0), elapsed),
        "- Verification: %d/%d pass" % (ok, len(results)),
        "",
        "## Assets",
        "",
        "| file | ch | dur | loop | base dB | peak dBFS | rms dBFS | bytes | result |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for e, r in zip(entries, results):
        lines.append("| %s | %s | %.3f s | %s | %+.1f | %s | %s | %s | %s |" % (
            e["file"], e["channels"], e["duration"], "yes" if e["loop"] else "no", e["base_db"],
            r.get("peak_dbfs", "-"), r.get("rms_dbfs", "-"), r.get("bytes", "-"), r["status"].upper()))
    lines += ["", "## Loop seam report", "",
              "| file | 0.5 s head/tail RMS | splice step | max in-loop attack delta | seam energy ratio |",
              "| --- | --- | --- | --- | --- |"]
    for r in results:
        if "loop" in r:
            loops = r["loop"]
            lines.append("| %s | %.3f | %.4f | %.4f | %.3f |" % (
                r["file"], loops["head_tail_rms_ratio"], loops["seam_step"],
                loops["max_in_loop_delta"], loops["seam_energy_ratio"]))
    music = next((r for r in results if r["name"] == "music_match" and "spectrum" in r), None)
    if music:
        lines += ["", "## music_match spectral balance", "", "- centroid: %.1f Hz" % music["spectrum"]["centroid_hz"]]
        for band, pct in music["spectrum"]["bands_percent"].items():
            lines.append("- %s: %.2f%%" % (band, pct))
    lines += ["", "## Failed checks", ""]
    failed_any = False
    for r in results:
        bad = [c for c in r["checks"] if not c["ok"]]
        for c in bad:
            failed_any = True
            lines.append("- %s %s: %s" % (r["file"], c["check"], c["detail"]))
    if not failed_any:
        lines.append("- none")
    lines += [
        "",
        "## Integration notes",
        "",
        "- AudioDirector maps SFX by stem name (no .wav suffix); see game/scripts/audio_director.gd.",
        "- Mono assets suit AudioStreamPlayer3D; stereo assets are UI/ambience/stingers.",
        "- Loops: skate_loop, crowd_loop, turnstile_hum, music_match (loop_mode set at load).",
        "",
    ]
    (report_dir / "REPORT.md").write_text("\n".join(lines), encoding="utf-8")


def write_manifest(path: Path, entries: list, cmd: str) -> None:
    payload = {
        "pipeline": PIPELINE_VERSION,
        "generator": "tools/generate_audio.py",
        "command": cmd,
        "sample_rate": SR,
        "sample_width_bits": 16,
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "assets": entries,
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_waveform_png(path: Path, entries: list, out_dir: Path) -> bool:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except Exception:  # noqa: BLE001
        return False
    row_h = 56
    left = 210
    width = 1360
    top = 26
    height = top + row_h * len(entries) + 8
    img = Image.new("RGB", (width, height), (7, 10, 18))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default()
    except Exception:  # noqa: BLE001
        font = None
    draw.text((12, 8), "ULTRABLADE audio -- waveform overview (%d assets)" % len(entries), fill=(180, 235, 255), font=font)
    plot_w = width - left - 12
    for i, e in enumerate(entries):
        y = top + i * row_h
        mid = y + row_h // 2
        draw.line([(left, mid), (width - 12, mid)], fill=(26, 40, 60))
        data, _meta = decode_wav(out_dir / e["file"])
        mono = data if data.ndim == 1 else data.mean(axis=1)
        cols = plot_w
        chunk = max(1, len(mono) // cols)
        usable = cols * chunk
        view = np.abs(mono[:usable]).reshape(cols, chunk)
        mx = view.max(axis=1)
        scale = (row_h // 2 - 5) * 1.0 / (float(np.max(mx)) + 1e-9)
        color = (255, 176, 32) if e["name"] == "music_match" else ((33, 230, 255) if e["loop"] else (255, 45, 111))
        for c in range(cols):
            amp = mx[c] * scale
            draw.line([(left + c, mid - amp), (left + c, mid + amp)], fill=color)
        draw.text((8, mid - 5), e["file"].replace(".wav", ""), fill=(170, 220, 240), font=font)
        draw.text((8, mid + 5), "%.2f s" % e["duration"], fill=(105, 135, 165), font=font)
    img.save(path)
    return True


def write_spectrogram_png(path: Path, wav_path: Path) -> bool:
    try:
        from PIL import Image
    except Exception:  # noqa: BLE001
        return False
    data, _meta = decode_wav(wav_path)
    mono = data if data.ndim == 1 else data.mean(axis=1)
    frame = 2048
    hop = 512
    win = np.hanning(frame)
    count = 1 + (len(mono) - frame) // hop
    mags = np.empty((count, frame // 2 + 1), dtype=np.float64)
    for i in range(count):
        mags[i] = np.abs(np.fft.rfft(mono[i * hop : i * hop + frame] * win))
    db = 20.0 * np.log10(mags + 1e-9)
    db = np.clip((db + 90.0) / 70.0, 0.0, 1.0)
    keep = int((frame // 2) * (16000.0 / (SR / 2.0)))
    img_arr = db[:, :keep].T[::-1]
    colors = np.array([
        [7, 10, 18], [24, 16, 48], [78, 20, 96], [180, 30, 110],
        [255, 100, 60], [255, 200, 60], [230, 245, 255],
    ], dtype=np.float64)
    pos = np.linspace(0.0, 1.0, len(colors))
    rgb = np.stack([np.interp(img_arr, pos, colors[:, c]) for c in range(3)], axis=-1).astype(np.uint8)
    img = Image.fromarray(rgb, "RGB").resize((1360, 420), Image.Resampling.BILINEAR)
    img.save(path)
    return True


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate ULTRABLADE original procedural audio.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="WAV output directory")
    parser.add_argument("--report-dir", type=Path, default=DEFAULT_REPORT, help="audit artifact directory")
    parser.add_argument("--verify-only", action="store_true", help="skip generation; verify existing WAVs against manifest")
    parser.add_argument("--only", default="", help="comma-separated asset names to generate")
    parser.add_argument("--no-image", action="store_true", help="skip PNG audit images")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    started = time.perf_counter()
    out_dir = args.out.resolve()
    report_dir = args.report_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)
    cmd = "C:/Python/python.exe tools/generate_audio.py" + ((" " + " ".join(argv)) if argv else "")
    registry = build_registry()
    by_name = {a.name: a for a in registry}

    if args.verify_only:
        manifest_path = report_dir / "manifest.json"
        if not manifest_path.exists():
            print("ERROR: --verify-only needs %s (run generation first)" % manifest_path)
            return 2
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        entries = manifest["assets"]
    else:
        selected = registry
        if args.only:
            wanted = [s.strip() for s in args.only.split(",") if s.strip()]
            missing = [w for w in wanted if w not in by_name]
            if missing:
                print("ERROR: unknown asset name(s): %s" % ", ".join(missing))
                return 2
            selected = [by_name[w] for w in wanted]
        entries = []
        for asset in selected:
            t0 = time.perf_counter()
            sig = np.asarray(asset.build(), dtype=np.float64)
            channels = 1 if sig.ndim == 1 else sig.shape[1]
            if channels != asset.channels:
                raise RuntimeError("%s: built %d channels, expected %d" % (asset.name, channels, asset.channels))
            expected_frames = nsamp(asset.target_sec)
            if sig.shape[0] != expected_frames:
                raise RuntimeError("%s: built %d frames, expected %d" % (asset.name, sig.shape[0], expected_frames))
            path = out_dir / (asset.name + ".wav")
            size = write_wav(path, sig, rng_for("dither:" + asset.name))
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            entries.append({
                "name": asset.name,
                "file": asset.name + ".wav",
                "channels": asset.channels,
                "frames": expected_frames,
                "duration": round(expected_frames / float(SR), 6),
                "target_sec": asset.target_sec,
                "loop": asset.loop,
                "base_db": asset.base_db,
                "purpose": asset.purpose,
                "peak_db_target": asset.peak_db,
                "bytes": size,
                "sha256": digest,
                "gen_seconds": round(time.perf_counter() - t0, 3),
            })
            if not args.quiet:
                print("GEN %-16s %6.2f s %8d bytes %s" % (asset.name, expected_frames / float(SR), size, digest[:12]))
        if args.only:
            manifest_path = report_dir / "manifest.json"
            if manifest_path.exists():
                previous = json.loads(manifest_path.read_text(encoding="utf-8"))
                prev_map = {e["name"]: e for e in previous.get("assets", [])}
                for e in entries:
                    prev_map[e["name"]] = e
                entries = [prev_map[name] for name in by_name if name in prev_map]
        write_manifest(report_dir / "manifest.json", entries, cmd)
        write_notice(out_dir, entries, sum(int(e.get("bytes", 0)) for e in entries))

    results = [verify_entry(out_dir / e["file"], e) for e in entries]
    total_bytes = sum(int(e.get("bytes", 0)) for e in entries)
    elapsed = time.perf_counter() - started
    ok = all(r["status"] == "pass" for r in results) and total_bytes < BUDGET_BYTES
    audit = {
        "pipeline": PIPELINE_VERSION,
        "command": cmd,
        "mode": "verify-only" if args.verify_only else "generate",
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "python": sys.version.split()[0],
        "numpy": np.__version__,
        "sample_rate": SR,
        "bits": 16,
        "asset_count": len(entries),
        "total_bytes": total_bytes,
        "budget_bytes": BUDGET_BYTES,
        "within_budget": total_bytes < BUDGET_BYTES,
        "pass_count": sum(1 for r in results if r["status"] == "pass"),
        "fail_count": sum(1 for r in results if r["status"] != "pass"),
        "result": "PASS" if ok else "FAIL",
        "elapsed_seconds": round(elapsed, 3),
        "assets": results,
    }
    (report_dir / "audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    write_report(report_dir, entries, results, total_bytes, elapsed, cmd)
    if not args.no_image:
        write_waveform_png(report_dir / "waveforms.png", entries, out_dir)
        if any(e["name"] == "music_match" for e in entries):
            write_spectrogram_png(report_dir / "music_match_spectrogram.png", out_dir / "music_match.wav")
    if not args.quiet:
        print("")
        print("VERIFY %d assets, %.2f MB, %.1f s -> %s" % (len(entries), total_bytes / (1024.0 * 1024.0), elapsed, audit["result"]))
        for r in results:
            if r["status"] != "pass":
                for c in r["checks"]:
                    if not c["ok"]:
                        print("  FAIL %s: %s (%s)" % (r["file"], c["check"], c["detail"]))
        if total_bytes >= BUDGET_BYTES:
            print("  FAIL total size %.2f MB exceeds 25 MB budget" % (total_bytes / (1024.0 * 1024.0)))
        print("REPORT %s" % (report_dir / "REPORT.md"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
