#!/usr/bin/env python3
"""
Playdead / Martin Stig Andersen Acoustic Mastering Pipeline for INSIDE Lab.

Takes the raw CC0 recordings downloaded in `res://assets/audio/raw/`, slices and
layers them into 5 distinct micro-variations per Foley layer, applies:
  1. Zero-Latency Transient Trimming (< 2ms leading silence for Layer 1 strikes).
  2. "Skull-Resonance" & Intimate Proximity EQ (+3.5 dB warm body boost at 280 Hz,
     smooth roll-off above 11 kHz to eliminate digital fizz).
  3. Soft-knee tape saturation and peak normalization (-1.2 dBFS ceiling, zero clipping).
  4. Exports 44.1 kHz, 16-bit Mono PCM .wav for 3D spatialized foley voices and
     44.1 kHz, 16-bit Stereo PCM .wav for ambient beds into `res://assets/audio/foley/`.
"""

import json
import math
import os
import subprocess
import wave
from typing import Dict, List, Tuple
import numpy as np

SAMPLE_RATE = 44100
PROJECT_ROOT = "/home/dashallb/.gemini/antigravity/scratch/inside_lab"
RAW_DIR = os.path.join(PROJECT_ROOT, "assets/audio/raw")
OUT_DIR = os.path.join(PROJECT_ROOT, "assets/audio/foley")


def decode_audio_mono(path: str) -> np.ndarray:
    """Decodes any audio file via ffmpeg into float32 mono at 44.1 kHz."""
    if not os.path.exists(path):
        return np.zeros(0, dtype=np.float32)
    cmd = [
        "ffmpeg", "-v", "error", "-i", path,
        "-f", "s16le", "-acodec", "pcm_s16le",
        "-ar", str(SAMPLE_RATE), "-ac", "1", "-"
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if res.returncode != 0 or len(res.stdout) == 0:
        return np.zeros(0, dtype=np.float32)
    pcm = np.frombuffer(res.stdout, dtype=np.int16).astype(np.float32) / 32768.0
    return pcm


def decode_audio_stereo(path: str, max_sec: float = 12.0) -> np.ndarray:
    """Decodes any audio file via ffmpeg into float32 stereo (N, 2) at 44.1 kHz."""
    if not os.path.exists(path):
        return np.zeros((0, 2), dtype=np.float32)
    cmd = [
        "ffmpeg", "-v", "error", "-t", str(max_sec), "-i", path,
        "-f", "s16le", "-acodec", "pcm_s16le",
        "-ar", str(SAMPLE_RATE), "-ac", "2", "-"
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if res.returncode != 0 or len(res.stdout) == 0:
        return np.zeros((0, 2), dtype=np.float32)
    pcm = np.frombuffer(res.stdout, dtype=np.int16).astype(np.float32) / 32768.0
    return pcm.reshape(-1, 2)


def trim_leading_silence(signal: np.ndarray, threshold_db: float = -42.0, pre_roll_ms: float = 0.8) -> np.ndarray:
    """
    Zero-Latency Transient Trimming: strips leading silence so strikes fire
    within < 2ms (default 0.8ms = 35 samples) of the raycast hit.
    """
    if len(signal) == 0:
        return signal
    peak = float(np.max(np.abs(signal)))
    if peak < 1e-6:
        return signal
    thresh = peak * (10.0 ** (threshold_db / 20.0))
    idx = np.argmax(np.abs(signal) >= thresh)
    pre_samples = int(SAMPLE_RATE * (pre_roll_ms / 1000.0))
    start = max(0, int(idx) - pre_samples)
    trimmed = signal[start:].copy()
    # Micro 0.6ms fade-in to prevent DC click while keeping < 2ms transient onset
    fade_in = min(len(trimmed), int(SAMPLE_RATE * 0.0006))
    if fade_in > 1:
        trimmed[:fade_in] *= np.linspace(0.0, 1.0, fade_in, dtype=np.float32)
    return trimmed


def apply_skull_resonance_eq(
    signal: np.ndarray,
    body_freq_hz: float = 280.0,
    body_gain_db: float = 3.8,
    lowpass_hz: float = 11000.0,
    highpass_hz: float = 32.0,
    extra_tilt_hz: float = 0.0,
    extra_tilt_db: float = 0.0,
) -> np.ndarray:
    """
    Martin Stig Andersen "Skull-Resonance" & Intimate Proximity EQ in FFT domain:
      - High-pass below 32 Hz to remove DC / sub-rumble mud.
      - Warm resonant bell boost centered at 280 Hz (bone conduction warmth).
      - Smooth 2nd-order butterworth-like roll-off above 11 kHz to tame harsh fizz.
      - Optional surface-specific formant tilt.
    """
    n = len(signal)
    if n < 64:
        return signal
    freqs = np.fft.rfftfreq(n, d=1.0 / SAMPLE_RATE)
    spec = np.fft.rfft(signal)

    # 1. Subsonic high-pass (32 Hz)
    hp = (freqs / np.maximum(freqs, 1e-3)) ** 2 / (1.0 + (highpass_hz / np.maximum(freqs, 1e-3)) ** 4) ** 0.5

    # 2. 280 Hz Skull-Resonance bell boost (Gaussian in log-frequency, Q ~ 1.4)
    log_dist = np.log2(np.maximum(freqs, 1.0) / body_freq_hz)
    bell_db = body_gain_db * np.exp(-(log_dist ** 2) / (2.0 * (0.55 ** 2)))
    bell_gain = 10.0 ** (bell_db / 20.0)

    # 3. Optional surface-character formant bell
    if extra_tilt_hz > 0.0 and abs(extra_tilt_db) > 0.01:
        tilt_dist = np.log2(np.maximum(freqs, 1.0) / extra_tilt_hz)
        tilt_db = extra_tilt_db * np.exp(-(tilt_dist ** 2) / (2.0 * (0.65 ** 2)))
        bell_gain = bell_gain * (10.0 ** (tilt_db / 20.0))

    # 4. Smooth 11 kHz low-pass roll-off (eliminates digital fizz)
    lp = 1.0 / np.sqrt(1.0 + (freqs / lowpass_hz) ** 6)

    filtered = np.fft.irfft(spec * hp * bell_gain * lp, n=n).astype(np.float32)
    return filtered


def resample_pitch(signal: np.ndarray, ratio: float) -> np.ndarray:
    """High-quality linear interpolation pitch/time shift for micro-variations."""
    if len(signal) < 4 or abs(ratio - 1.0) < 1e-4:
        return signal.copy()
    new_len = max(4, int(len(signal) / ratio))
    x_old = np.linspace(0.0, 1.0, len(signal), dtype=np.float32)
    x_new = np.linspace(0.0, 1.0, new_len, dtype=np.float32)
    return np.interp(x_new, x_old, signal).astype(np.float32)


def shape_envelope_and_master(
    signal: np.ndarray,
    max_duration_sec: float,
    fade_out_ratio: float = 0.32,
    target_peak_db: float = -1.5,
    trim_silence: bool = True,
    pre_roll_ms: float = 0.8,
) -> np.ndarray:
    """Trims, applies smooth decay tail, soft-knee tape saturation, and normalizes."""
    if trim_silence:
        signal = trim_leading_silence(signal, threshold_db=-38.0, pre_roll_ms=pre_roll_ms)
    max_samples = int(SAMPLE_RATE * max_duration_sec)
    if len(signal) > max_samples:
        signal = signal[:max_samples].copy()
    elif len(signal) < int(SAMPLE_RATE * 0.06):
        pad = np.zeros(int(SAMPLE_RATE * 0.08), dtype=np.float32)
        pad[:len(signal)] = signal
        signal = pad

    # Smooth cosine fade-out on tail
    fade_samples = max(16, int(len(signal) * fade_out_ratio))
    fade_curve = 0.5 * (1.0 + np.cos(np.linspace(0.0, math.pi, fade_samples, dtype=np.float32)))
    signal[-fade_samples:] *= fade_curve

    # Remove DC offset
    signal = signal - float(np.mean(signal))

    # Pre-normalize into soft-knee tanh saturation for warm Playdead transient density
    peak = float(np.max(np.abs(signal)))
    if peak > 1e-6:
        signal = signal / peak
    signal = np.tanh(signal * 1.35).astype(np.float32)
    peak_after = float(np.max(np.abs(signal)))
    target_amp = 10.0 ** (target_peak_db / 20.0)
    if peak_after > 1e-6:
        signal = signal * (target_amp / peak_after)
    return signal


def save_wav_mono(path: str, signal: np.ndarray) -> Dict[str, float]:
    """Writes 44.1 kHz, 16-bit Mono PCM .wav and returns acoustic telemetry."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    clipped = np.clip(signal, -0.999, 0.999)
    pcm16 = (clipped * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm16.tobytes())

    peak_db = 20.0 * math.log10(max(float(np.max(np.abs(clipped))), 1e-7))
    rms_db = 20.0 * math.log10(max(float(np.sqrt(np.mean(clipped ** 2))), 1e-7))
    return {
        "duration_sec": round(len(pcm16) / SAMPLE_RATE, 4),
        "peak_db": round(peak_db, 2),
        "rms_db": round(rms_db, 2),
    }


def save_wav_stereo(path: str, stereo: np.ndarray) -> Dict[str, float]:
    """Writes 44.1 kHz, 16-bit Stereo PCM .wav and returns acoustic telemetry."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    clipped = np.clip(stereo, -0.999, 0.999)
    pcm16 = (clipped * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm16.tobytes())

    peak_db = 20.0 * math.log10(max(float(np.max(np.abs(clipped))), 1e-7))
    rms_db = 20.0 * math.log10(max(float(np.sqrt(np.mean(clipped ** 2))), 1e-7))
    return {
        "duration_sec": round(stereo.shape[0] / SAMPLE_RATE, 4),
        "peak_db": round(peak_db, 2),
        "rms_db": round(rms_db, 2),
    }


def mix_layers(layers: List[Tuple[np.ndarray, float, int]]) -> np.ndarray:
    """Mixes multiple (signal, gain, offset_samples) tuples into a single buffer."""
    max_len = 0
    for sig, _, offset in layers:
        if len(sig) > 0:
            max_len = max(max_len, len(sig) + max(0, offset))
    if max_len == 0:
        return np.zeros(int(SAMPLE_RATE * 0.15), dtype=np.float32)
    out = np.zeros(max_len, dtype=np.float32)
    for sig, gain, offset in layers:
        if len(sig) == 0:
            continue
        off = max(0, offset)
        out[off:off + len(sig)] += sig * gain
    return out


def extract_Active_chunks(signal: np.ndarray, count: int, chunk_sec: float) -> List[np.ndarray]:
    """Slices a longer recording into `count` high-energy windows."""
    chunk_len = int(SAMPLE_RATE * chunk_sec)
    if len(signal) <= chunk_len:
        return [resample_pitch(signal, 0.94 + 0.03 * i) for i in range(count)]

    # Scan with stride to find top non-overlapping energy windows
    stride = max(chunk_len // 2, int(SAMPLE_RATE * 0.08))
    windows = []
    for start in range(0, len(signal) - chunk_len, stride):
        seg = signal[start:start + chunk_len]
        energy = float(np.mean(seg ** 2))
        windows.append((energy, start, seg))
    windows.sort(key=lambda x: x[0], reverse=True)

    chosen: List[np.ndarray] = []
    used_starts: List[int] = []
    for energy, start, seg in windows:
        if all(abs(start - u) >= chunk_len // 2 for u in used_starts):
            chosen.append(seg.copy())
            used_starts.append(start)
            if len(chosen) == count:
                break
    while len(chosen) < count:
        idx = len(chosen)
        base = chosen[idx % len(chosen)] if chosen else signal[:chunk_len]
        chosen.append(resample_pitch(base, 0.95 + 0.025 * idx))
    return chosen


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(1337)

    # Decode raw web CC0 pool
    raw: Dict[str, np.ndarray] = {}
    for fname in sorted(os.listdir(RAW_DIR)):
        if fname.endswith((".wav", ".ogg", ".mp3", ".flac")):
            # Skip huge >3MB ambient files in the mono one-shot dictionary; load separately
            fpath = os.path.join(RAW_DIR, fname)
            if os.path.getsize(fpath) < 2_500_000:
                raw[fname] = trim_leading_silence(decode_audio_mono(fpath), threshold_db=-36.0, pre_roll_ms=0.6)

    print(f"Loaded {len(raw)} raw CC0 one-shot recordings from {RAW_DIR}")

    manifest: Dict[str, Dict[str, float]] = {}

    # =========================================================================
    # 1. CONCRETE BUNKER (Cold, dry, dense sub-bass + mineral grit)
    # =========================================================================
    concrete_pool = [raw[k] for k in ["concrete_0.ogg", "concrete_1.ogg", "concrete_2.ogg", "concrete_3.ogg", "concrete_4.ogg"] if k in raw]
    stone_pool = [raw[k] for k in ["stone_a.wav", "stone_b.wav", "stone_c.wav", "stone_d.wav", "stone_e.wav"] if k in raw]
    rock_pool = [raw[k] for k in ["rock_a.wav", "rock_b.wav", "rock_c.wav"] if k in raw]
    sand_pool = [raw[k] for k in ["sand_a.wav", "sand_b.wav", "sand_c.wav"] if k in raw]
    thud_pool = [raw[k] for k in ["thud_1.wav", "thud_2.wav", "big_thump.wav"] if k in raw]

    for i in range(5):
        # Layer 1A: Concrete Strike Soft (creeping sneaker tap, warm 280Hz skull resonance, muted top)
        c_sig = resample_pitch(concrete_pool[i % len(concrete_pool)], 0.96 + i * 0.022)
        s_sig = resample_pitch(stone_pool[i % len(stone_pool)], 0.93 + i * 0.025)
        mixed = mix_layers([(c_sig, 0.75, 0), (s_sig, 0.35, int(SAMPLE_RATE * 0.002))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=260.0, body_gain_db=4.2, lowpass_hz=6200.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.22, fade_out_ratio=0.45, target_peak_db=-3.0)
        fname = f"concrete_strike_soft_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 1B: Concrete Strike Hard (firm heel strike on bunker slab)
        s_hard = resample_pitch(stone_pool[(i + 2) % len(stone_pool)], 0.97 + i * 0.018)
        r_hard = resample_pitch(rock_pool[i % len(rock_pool)], 0.95 + i * 0.025)
        c_hard = resample_pitch(concrete_pool[(i + 1) % len(concrete_pool)], 1.0 + i * 0.015)
        mixed = mix_layers([(s_hard, 0.70, 0), (c_hard, 0.65, 0), (r_hard, 0.45, int(SAMPLE_RATE * 0.001))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=280.0, body_gain_db=3.8, lowpass_hz=10800.0, extra_tilt_hz=1800.0, extra_tilt_db=2.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.28, fade_out_ratio=0.38, target_peak_db=-1.2)
        fname = f"concrete_strike_hard_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 1C: Concrete Strike Land (heavy sub-thud + boot slap + grit scatter)
        t_land = resample_pitch(thud_pool[i % len(thud_pool)], 0.88 + i * 0.04)
        s_land = resample_pitch(stone_pool[(i + 1) % len(stone_pool)], 0.92 + i * 0.02)
        g_land = resample_pitch(sand_pool[i % len(sand_pool)], 1.05 + i * 0.03)
        mixed = mix_layers([
            (t_land, 0.85, 0),
            (s_land, 0.75, int(SAMPLE_RATE * 0.001)),
            (g_land, 0.35, int(SAMPLE_RATE * 0.018))
        ])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=190.0, body_gain_db=5.0, lowpass_hz=9800.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.42, fade_out_ratio=0.35, target_peak_db=-0.8)
        fname = f"concrete_strike_land_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 2A: Concrete Body Texture (grit compression under sole)
        snd = resample_pitch(sand_pool[i % len(sand_pool)], 0.92 + i * 0.035)
        rk = resample_pitch(rock_pool[(i + 1) % len(rock_pool)], 1.02 + i * 0.025)
        mixed = mix_layers([(snd, 0.65, 0), (rk, 0.45, int(SAMPLE_RATE * 0.008))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=310.0, body_gain_db=3.2, lowpass_hz=8500.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.26, fade_out_ratio=0.42, target_peak_db=-2.5)
        fname = f"concrete_body_grit_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 2B: Concrete Scuff Drag (direction-reversal grit scrape)
        sc1 = resample_pitch(sand_pool[(i + 1) % len(sand_pool)], 0.84 + i * 0.04)
        sc2 = resample_pitch(stone_pool[(i + 3) % len(stone_pool)], 0.89 + i * 0.03)
        mixed = mix_layers([(sc1, 0.80, 0), (sc2, 0.50, int(SAMPLE_RATE * 0.025)), (sc1, 0.45, int(SAMPLE_RATE * 0.065))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=280.0, body_gain_db=3.0, lowpass_hz=9200.0, extra_tilt_hz=2600.0, extra_tilt_db=2.5)
        out = shape_envelope_and_master(eq, max_duration_sec=0.36, fade_out_ratio=0.35, target_peak_db=-1.8)
        fname = f"concrete_scuff_drag_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 3: Concrete Tail Release (subtle pebble roll & sole lift)
        tl1 = resample_pitch(sand_pool[(i + 2) % len(sand_pool)], 1.12 + i * 0.04)
        tl2 = resample_pitch(concrete_pool[(i + 2) % len(concrete_pool)], 1.08 + i * 0.03)
        mixed = mix_layers([(tl1[int(len(tl1)*0.15):], 0.65, 0), (tl2, 0.35, int(SAMPLE_RATE * 0.01))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=300.0, body_gain_db=2.2, lowpass_hz=7800.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.20, fade_out_ratio=0.50, target_peak_db=-4.0)
        fname = f"concrete_tail_release_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

    # =========================================================================
    # 2. SWAMPY MARSH (Thick mud, shallow water slosh, visceral suction squelch)
    # =========================================================================
    step_mud_pool = [raw[k] for k in ["stepfx_mud_a.wav", "stepfx_mud_b.wav", "stepfx_mud_c.wav", "stepfx_mud_d.wav", "stepfx_mud_e.wav"] if k in raw]
    cc0_mud_pool = [raw[k] for k in ["mud_01.ogg", "mud_02.ogg", "mud_03.ogg", "mud_04.ogg", "mud_05.ogg", "mud_06.ogg"] if k in raw]
    puddle_pool = [raw[k] for k in ["puddle_a.wav", "puddle_b.wav", "puddle_c.wav", "puddle_d.wav"] if k in raw]
    water_pool = [raw[k] for k in ["water_a.wav", "water_b.wav", "water_c.wav"] if k in raw]
    slime_pool = [raw[k] for k in ["slime_01.ogg", "slime_02.ogg", "slime_03.ogg", "slime_04.ogg", "slime_05.ogg", "slime_06.ogg"] if k in raw]
    splash_pool = [raw[k] for k in ["splash_01.ogg", "splash_02.ogg", "splash_03.ogg"] if k in raw]

    for i in range(5):
        # Layer 1A: Swamp Strike Soft (gentle mud entry + puddle ripple)
        m_soft = resample_pitch(step_mud_pool[i % len(step_mud_pool)], 0.94 + i * 0.025)
        p_soft = resample_pitch(puddle_pool[i % len(puddle_pool)], 0.96 + i * 0.02)
        mixed = mix_layers([(m_soft, 0.75, 0), (p_soft, 0.55, int(SAMPLE_RATE * 0.004))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=250.0, body_gain_db=4.5, lowpass_hz=5400.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.30, fade_out_ratio=0.40, target_peak_db=-2.2)
        fname = f"swamp_strike_soft_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 1B: Swamp Strike Hard (deep mud plunge + water displace)
        m_hard = resample_pitch(cc0_mud_pool[i % len(cc0_mud_pool)], 0.92 + i * 0.03)
        w_hard = resample_pitch(water_pool[i % len(water_pool)], 0.95 + i * 0.025)
        sm_hard = resample_pitch(step_mud_pool[(i + 2) % len(step_mud_pool)], 0.90 + i * 0.02)
        mixed = mix_layers([(sm_hard, 0.75, 0), (m_hard, 0.70, int(SAMPLE_RATE * 0.002)), (w_hard, 0.55, int(SAMPLE_RATE * 0.008))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=240.0, body_gain_db=4.8, lowpass_hz=7200.0, extra_tilt_hz=950.0, extra_tilt_db=2.2)
        out = shape_envelope_and_master(eq, max_duration_sec=0.36, fade_out_ratio=0.36, target_peak_db=-1.2)
        fname = f"swamp_strike_hard_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 1C: Swamp Strike Land (heavy body impact into mire + splash)
        sp = resample_pitch(splash_pool[i % len(splash_pool)], 0.90 + i * 0.035)
        th = resample_pitch(thud_pool[i % len(thud_pool)], 0.85 + i * 0.03)
        md = resample_pitch(cc0_mud_pool[(i + 1) % len(cc0_mud_pool)], 0.88 + i * 0.03)
        mixed = mix_layers([(th, 0.75, 0), (sp, 0.80, int(SAMPLE_RATE * 0.002)), (md, 0.70, int(SAMPLE_RATE * 0.015))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=180.0, body_gain_db=5.2, lowpass_hz=7800.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.48, fade_out_ratio=0.35, target_peak_db=-0.8)
        fname = f"swamp_strike_land_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 2A: Swamp Body Slosh (thick mud mass & water movement around ankle)
        pd = resample_pitch(puddle_pool[(i + 1) % len(puddle_pool)], 0.92 + i * 0.03)
        md2 = resample_pitch(cc0_mud_pool[(i + 2) % len(cc0_mud_pool)], 0.96 + i * 0.025)
        mixed = mix_layers([(pd, 0.70, 0), (md2, 0.65, int(SAMPLE_RATE * 0.012))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=280.0, body_gain_db=4.0, lowpass_hz=6400.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.34, fade_out_ratio=0.38, target_peak_db=-2.0)
        fname = f"swamp_body_slosh_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 2B: Swamp Scuff Drag (heavy wading drag through thick mud)
        wt = resample_pitch(water_pool[(i + 1) % len(water_pool)], 0.86 + i * 0.03)
        sl = resample_pitch(slime_pool[i % len(slime_pool)], 0.90 + i * 0.035)
        mixed = mix_layers([(wt, 0.75, 0), (sl, 0.65, int(SAMPLE_RATE * 0.020))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=260.0, body_gain_db=4.2, lowpass_hz=6800.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.40, fade_out_ratio=0.35, target_peak_db=-1.6)
        fname = f"swamp_scuff_drag_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 3: Swamp Tail Suction (visceral wet boot pull-out squelch!)
        sl_a = resample_pitch(slime_pool[(i + 1) % len(slime_pool)], 0.94 + i * 0.04)
        md_a = resample_pitch(cc0_mud_pool[(i + 3) % len(cc0_mud_pool)], 1.04 + i * 0.03)
        mixed = mix_layers([(sl_a, 0.85, 0), (md_a, 0.55, int(SAMPLE_RATE * 0.015))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=320.0, body_gain_db=3.6, lowpass_hz=8200.0, extra_tilt_hz=1350.0, extra_tilt_db=3.2)
        out = shape_envelope_and_master(eq, max_duration_sec=0.32, fade_out_ratio=0.42, target_peak_db=-1.8)
        fname = f"swamp_tail_suction_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

    # =========================================================================
    # 3. WINDY GRASS FIELD (Soft earth turf thud + dry tall-grass blade swish)
    # =========================================================================
    grass_pool = [raw[k] for k in ["grass_0.ogg", "grass_1.ogg", "grass_2.ogg", "grass_3.ogg", "grass_4.ogg"] if k in raw]
    forest_pool = [raw[k] for k in ["forest_a.wav", "forest_b.wav", "forest_c.wav", "forest_d.wav", "forest_e.wav"] if k in raw]
    path_pool = [raw[k] for k in ["path_a.wav", "path_b.wav", "path_c.wav"] if k in raw]

    for i in range(5):
        # Layer 1A: Field Strike Soft (soft earth step + quiet grass rustle)
        g_soft = resample_pitch(grass_pool[i % len(grass_pool)], 0.95 + i * 0.02)
        p_soft = resample_pitch(path_pool[i % len(path_pool)], 0.92 + i * 0.025)
        mixed = mix_layers([(p_soft, 0.65, 0), (g_soft, 0.60, int(SAMPLE_RATE * 0.003))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=240.0, body_gain_db=4.4, lowpass_hz=8800.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.25, fade_out_ratio=0.42, target_peak_db=-2.8)
        fname = f"field_strike_soft_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 1B: Field Strike Hard (running turf thud + dry stalk snap)
        f_hard = resample_pitch(forest_pool[i % len(forest_pool)], 0.96 + i * 0.02)
        p_hard = resample_pitch(path_pool[(i + 1) % len(path_pool)], 0.95 + i * 0.02)
        g_hard = resample_pitch(grass_pool[(i + 1) % len(grass_pool)], 0.98 + i * 0.02)
        mixed = mix_layers([(p_hard, 0.75, 0), (f_hard, 0.65, int(SAMPLE_RATE * 0.001)), (g_hard, 0.50, int(SAMPLE_RATE * 0.006))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=260.0, body_gain_db=4.2, lowpass_hz=10500.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.30, fade_out_ratio=0.38, target_peak_db=-1.4)
        fname = f"field_strike_hard_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 1C: Field Strike Land (heavy turf thump + foliage crush)
        th_f = resample_pitch(thud_pool[(i + 1) % len(thud_pool)], 0.90 + i * 0.03)
        fo_f = resample_pitch(forest_pool[(i + 2) % len(forest_pool)], 0.92 + i * 0.025)
        gr_f = resample_pitch(grass_pool[(i + 2) % len(grass_pool)], 0.94 + i * 0.02)
        mixed = mix_layers([(th_f, 0.80, 0), (fo_f, 0.70, int(SAMPLE_RATE * 0.002)), (gr_f, 0.60, int(SAMPLE_RATE * 0.012))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=185.0, body_gain_db=5.0, lowpass_hz=9600.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.42, fade_out_ratio=0.36, target_peak_db=-0.9)
        fname = f"field_strike_land_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 2A: Field Body Turf (fibrous grass & root compression)
        fo_b = resample_pitch(forest_pool[(i + 1) % len(forest_pool)], 1.0 + i * 0.025)
        gr_b = resample_pitch(grass_pool[(i + 3) % len(grass_pool)], 0.95 + i * 0.03)
        mixed = mix_layers([(gr_b, 0.75, 0), (fo_b, 0.55, int(SAMPLE_RATE * 0.010))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=290.0, body_gain_db=3.5, lowpass_hz=9800.0, extra_tilt_hz=3800.0, extra_tilt_db=1.8)
        out = shape_envelope_and_master(eq, max_duration_sec=0.28, fade_out_ratio=0.40, target_peak_db=-2.2)
        fname = f"field_body_turf_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 2B: Field Scuff Drag (sliding boot through tall dry grass & dirt)
        fo_s = resample_pitch(forest_pool[(i + 3) % len(forest_pool)], 0.88 + i * 0.03)
        sn_s = resample_pitch(sand_pool[i % len(sand_pool)], 0.92 + i * 0.03)
        gr_s = resample_pitch(grass_pool[(i + 4) % len(grass_pool)], 0.90 + i * 0.025)
        mixed = mix_layers([(gr_s, 0.75, 0), (fo_s, 0.65, int(SAMPLE_RATE * 0.018)), (sn_s, 0.45, int(SAMPLE_RATE * 0.035))])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=280.0, body_gain_db=3.2, lowpass_hz=10200.0, extra_tilt_hz=4200.0, extra_tilt_db=2.4)
        out = shape_envelope_and_master(eq, max_duration_sec=0.36, fade_out_ratio=0.36, target_peak_db=-1.7)
        fname = f"field_scuff_drag_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

        # Layer 3: Field Tail Swish (grass blades whipping/springing back on foot lift)
        gr_t = resample_pitch(grass_pool[(i + 2) % len(grass_pool)], 1.08 + i * 0.035)
        fo_t = resample_pitch(forest_pool[(i + 4) % len(forest_pool)], 1.12 + i * 0.03)
        # Synthesize a subtle airy blade-whip layer to enrich the real grass recording
        t_len = int(SAMPLE_RATE * 0.22)
        t_axis = np.linspace(0.0, 1.0, t_len, dtype=np.float32)
        air_swish = rng.standard_normal(t_len).astype(np.float32) * (np.maximum(np.sin(t_axis * math.pi), 0.0) ** 1.6) * 0.18
        mixed = mix_layers([(gr_t, 0.75, 0), (fo_t, 0.45, int(SAMPLE_RATE * 0.008)), (air_swish, 0.40, 0)])
        eq = apply_skull_resonance_eq(mixed, body_freq_hz=340.0, body_gain_db=2.0, lowpass_hz=10800.0, highpass_hz=180.0, extra_tilt_hz=4800.0, extra_tilt_db=3.0)
        out = shape_envelope_and_master(eq, max_duration_sec=0.24, fade_out_ratio=0.48, target_peak_db=-3.2)
        fname = f"field_tail_swish_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out)

    # =========================================================================
    # 4. BOY'S VOICE SEQUENCER (Jakob Schmid Architecture: Inhale, Exhale, Recovery)
    # =========================================================================
    hb_full = decode_audio_mono(os.path.join(RAW_DIR, "heavy_breathing.wav"))
    sigh_full = decode_audio_mono(os.path.join(RAW_DIR, "sigh.wav"))
    b1 = raw.get("breath_1.ogg", np.zeros(0, dtype=np.float32))
    b2 = raw.get("breath_2.ogg", np.zeros(0, dtype=np.float32))
    h_clips = [raw[k] for k in ["human_01.ogg", "human_02.ogg", "human_03.ogg", "human_04.ogg", "grunt_01.ogg", "grunt_02.ogg"] if k in raw]

    hb_chunks = extract_Active_chunks(hb_full, 6, 0.34)
    sigh_chunks = extract_Active_chunks(sigh_full, 5, 0.38)

    for i in range(5):
        # Inhale micro-clips (close-mic nasal/chest intake synced to stride)
        base_in = hb_chunks[i % len(hb_chunks)]
        layer_in = resample_pitch(b1 if i % 2 == 0 else b2, 1.06 + i * 0.025)
        mixed_in = mix_layers([(base_in, 0.80, 0), (layer_in, 0.35, int(SAMPLE_RATE * 0.005))])
        eq_in = apply_skull_resonance_eq(mixed_in, body_freq_hz=290.0, body_gain_db=4.0, lowpass_hz=7600.0, highpass_hz=90.0, extra_tilt_hz=1600.0, extra_tilt_db=2.0)
        out_in = shape_envelope_and_master(eq_in, max_duration_sec=0.28, fade_out_ratio=0.40, target_peak_db=-3.5, pre_roll_ms=1.5)
        fname = f"breath_inhale_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out_in)

        # Exhale & heavy strain exertion micro-clips
        base_ex = sigh_chunks[i % len(sigh_chunks)]
        strain_vo = resample_pitch(h_clips[i % len(h_clips)], 0.96 + i * 0.03)
        mixed_ex = mix_layers([(base_ex, 0.75, 0), (strain_vo, 0.45, int(SAMPLE_RATE * 0.004))])
        eq_ex = apply_skull_resonance_eq(mixed_ex, body_freq_hz=260.0, body_gain_db=4.6, lowpass_hz=7200.0, highpass_hz=85.0)
        out_ex = shape_envelope_and_master(eq_ex, max_duration_sec=0.32, fade_out_ratio=0.42, target_peak_db=-2.8, pre_roll_ms=1.5)
        fname = f"breath_exhale_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out_ex)

        # Quiet Idle recovery breaths
        rec_a = resample_pitch(sigh_chunks[(i + 2) % len(sigh_chunks)], 0.92 + i * 0.02)
        rec_b = resample_pitch(hb_chunks[(i + 1) % len(hb_chunks)], 0.95 + i * 0.02)
        mixed_rec = mix_layers([(rec_a, 0.70, 0), (rec_b, 0.50, int(SAMPLE_RATE * 0.015))])
        eq_rec = apply_skull_resonance_eq(mixed_rec, body_freq_hz=275.0, body_gain_db=3.8, lowpass_hz=6400.0, highpass_hz=80.0)
        out_rec = shape_envelope_and_master(eq_rec, max_duration_sec=0.38, fade_out_ratio=0.48, target_peak_db=-5.0, pre_roll_ms=2.0)
        fname = f"breath_recovery_0{i+1}.wav"
        manifest[fname] = save_wav_mono(os.path.join(OUT_DIR, fname), out_rec)

    # =========================================================================
    # 5. STEREO AMBIENT BEDS ("Naked World" inverse-ducked environmental beds)
    # =========================================================================
    vent_st = decode_audio_stereo(os.path.join(RAW_DIR, "air_vent.wav"), max_sec=6.0)
    furnace_st = decode_audio_stereo(os.path.join(RAW_DIR, "furnace_fan.wav"), max_sec=6.0)
    outside_st = decode_audio_stereo(os.path.join(RAW_DIR, "outside_wind.wav"), max_sec=6.0)
    windy_st = decode_audio_stereo(os.path.join(RAW_DIR, "windy.wav"), max_sec=6.0)
    water_st = decode_audio_stereo(os.path.join(RAW_DIR, "loop_water_01.ogg"), max_sec=6.0)
    amb_st = decode_audio_stereo(os.path.join(RAW_DIR, "loop_ambient_01.ogg"), max_sec=6.0)

    bed_len = int(SAMPLE_RATE * 4.5)

    def fit_stereo(arr: np.ndarray, length: int) -> np.ndarray:
        if len(arr) == 0:
            return np.zeros((length, 2), dtype=np.float32)
        if len(arr) < length:
            reps = (length // len(arr)) + 2
            arr = np.tile(arr, (reps, 1))
        seg = arr[:length].copy()
        for ch in range(2):
            seg[:, ch] = apply_skull_resonance_eq(seg[:, ch], body_freq_hz=220.0, body_gain_db=3.0, lowpass_hz=6500.0, highpass_hz=35.0)
        # Crossfade ends for seamless looping
        xf = int(SAMPLE_RATE * 0.25)
        fade = np.linspace(0.0, 1.0, xf, dtype=np.float32)[:, None]
        seg[:xf] = seg[:xf] * fade + seg[-xf:] * (1.0 - fade)
        peak = float(np.max(np.abs(seg)))
        if peak > 1e-6:
            seg = seg * ((10.0 ** (-6.0 / 20.0)) / peak)
        return seg

    bunker_bed = fit_stereo(vent_st * 0.55 + fit_stereo(furnace_st, len(vent_st)) * 0.45 + fit_stereo(amb_st, len(vent_st)) * 0.35, bed_len)
    swamp_bed = fit_stereo(water_st * 0.65 + fit_stereo(vent_st, len(water_st)) * 0.35, bed_len)
    field_bed = fit_stereo(outside_st * 0.65 + fit_stereo(windy_st, len(outside_st)) * 0.45, bed_len)
    hybrid_bed = fit_stereo(bunker_bed * 0.45 + swamp_bed * 0.25 + field_bed * 0.40, bed_len)

    manifest["ambience_bunker_drone.wav"] = save_wav_stereo(os.path.join(OUT_DIR, "ambience_bunker_drone.wav"), bunker_bed)
    manifest["ambience_swamp_murk.wav"] = save_wav_stereo(os.path.join(OUT_DIR, "ambience_swamp_murk.wav"), swamp_bed)
    manifest["ambience_field_wind.wav"] = save_wav_stereo(os.path.join(OUT_DIR, "ambience_field_wind.wav"), field_bed)
    manifest["ambience_master_hybrid.wav"] = save_wav_stereo(os.path.join(OUT_DIR, "ambience_master_hybrid.wav"), hybrid_bed)

    manifest_path = os.path.join(OUT_DIR, "foley_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    print(f"Mastered {len(manifest)} Playdead-grade .wav files into {OUT_DIR}")


if __name__ == "__main__":
    main()
