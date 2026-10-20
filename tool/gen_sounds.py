#!/usr/bin/env python3
"""Generates the alarm sound assets (stdlib only).

    python3 tool/gen_sounds.py

Writes:
  assets/sounds/siren.wav  ~2 s seamless loop, loud two-tone (high/low)
                           alternating siren, 16-bit mono 22050 Hz,
                           normalised to near full scale.
  assets/sounds/chime.wav  ~0.6 s two-note "ding-dong" warning chime.

Square-ish waveforms (fundamental + odd harmonics) are used for the siren
because they are perceived as much louder than a sine at the same peak level
and cut through wind and engine noise; small phone speakers also reproduce
the harmonics better than a low fundamental.
"""

import math
import os
import struct
import wave

RATE = 22050
PEAK = 0.97  # fraction of full scale after normalisation
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_DIR = os.path.join(ROOT, "assets", "sounds")


def write_wav(path, samples):
    peak = max(abs(s) for s in samples) or 1.0
    scale = PEAK * 32767 / peak
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(s * scale)))))
        for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"wrote {path}: {len(samples) / RATE:.2f} s")


def bright_tone(phase):
    """Band-limited square-ish wave: odd harmonics 1..9 (bright, loud)."""
    return sum(math.sin(phase * k) / k for k in (1, 3, 5, 7, 9))


def siren():
    # Two tones alternating every 0.5 s -> 4 segments = 2.0 s loop.
    # Frequencies are chosen so each segment holds a whole number of cycles
    # (960 Hz * 0.5 s = 480, 720 Hz * 0.5 s = 360), so the phase is continuous
    # at segment boundaries and the loop point is click-free.
    seg = int(RATE * 0.5)
    tones = [960.0, 720.0, 960.0, 720.0]
    ramp = int(RATE * 0.004)  # 4 ms crossfade at tone changes
    out = []
    phase = 0.0
    for i, f in enumerate(tones):
        prev_f = tones[i - 1]
        for n in range(seg):
            # Glide the frequency briefly at the boundary to avoid clicks.
            if n < ramp:
                t = n / ramp
                freq = prev_f + (f - prev_f) * t
            else:
                freq = f
            phase += 2 * math.pi * freq / RATE
            out.append(bright_tone(phase))
    return out


def chime():
    # "Ding" (E6) then "dong" (C6), each a bell-like decaying partial mix.
    notes = [(1318.5, 0.0), (1046.5, 0.22)]
    length = int(RATE * 0.6)
    out = [0.0] * length
    for freq, start in notes:
        s0 = int(start * RATE)
        for n in range(length - s0):
            t = n / RATE
            env = math.exp(-t * 7.0)
            attack = min(1.0, n / (RATE * 0.003))
            v = (
                math.sin(2 * math.pi * freq * t)
                + 0.45 * math.sin(2 * math.pi * freq * 2.0 * t) * math.exp(-t * 10)
                + 0.25 * math.sin(2 * math.pi * freq * 3.01 * t) * math.exp(-t * 14)
            )
            out[s0 + n] += v * env * attack
    # Short fade-out so the file ends in silence.
    fade = int(RATE * 0.03)
    for n in range(fade):
        out[length - fade + n] *= 1 - n / fade
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_wav(os.path.join(OUT_DIR, "siren.wav"), siren())
    write_wav(os.path.join(OUT_DIR, "chime.wav"), chime())


if __name__ == "__main__":
    main()
