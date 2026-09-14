#!/usr/bin/env python3
"""Render Cuelume 0.2.2's Success recipe using only the Python standard library.

Ported from src/sounds/recipes.ts and src/audio/engine.ts in
https://github.com/Danilaa1/cuelume (Copyright 2026 Daniel Belyi, MIT).
See Boop/Resources/Cuelume-LICENSE.txt for the full license.

The WAV preserves the notes, exponential envelopes, gain, and filtered echo.
Boop applies its quieter playback volume in CompletionSound.swift.
"""

import math
from pathlib import Path
import struct
import wave


SAMPLE_RATE = 48_000
# frequency, offset, attack, decay, peak
NOTES = (
    (880.0, 0.0, 0.004, 0.09, 0.06),
    (1108.73, 0.06, 0.004, 0.1, 0.06),
    (1318.51, 0.12, 0.004, 0.18, 0.07),
)
MASTER_GAIN = 0.5
OUTPUT_GAIN = 4.0
DELAY = 0.1
FEEDBACK = 0.22
WET = 0.16
LOWPASS = 4500.0
FLOOR = 0.0001
SOURCE_PADDING = 0.05
CLEANUP_MARGIN = 0.05


def render():
    source_end = max(offset + attack + decay + SOURCE_PADDING
                     for _, offset, attack, decay, _ in NOTES)
    tail = DELAY * (1 + math.ceil(math.log(0.001) / math.log(FEEDBACK)))
    count = math.ceil((source_end + tail + CLEANUP_MARGIN) * SAMPLE_RATE)
    dry = [0.0] * count

    for frequency, offset, attack, decay, peak in NOTES:
        start = round(offset * SAMPLE_RATE)
        length = round((attack + decay + SOURCE_PADDING) * SAMPLE_RATE)
        for index in range(length):
            time = index / SAMPLE_RATE
            if time < attack:
                gain = FLOOR * (peak / FLOOR) ** (time / attack)
            elif time < attack + decay:
                gain = peak * (FLOOR / peak) ** ((time - attack) / decay)
            else:
                gain = FLOOR
            dry[start + index] += (
                math.sin(2 * math.pi * frequency * time) * gain * MASTER_GAIN
            )

    # Web Audio's lowpass biquad defaults to Q = 1 dB.
    omega = 2 * math.pi * LOWPASS / SAMPLE_RATE
    alpha = math.sin(omega) / (2 * 10 ** (1 / 20))
    cosine = math.cos(omega)
    a0 = 1 + alpha
    b0 = (1 - cosine) / (2 * a0)
    b1 = (1 - cosine) / a0
    b2 = b0
    a1 = -2 * cosine / a0
    a2 = (1 - alpha) / a0
    delay = [0.0] * round(DELAY * SAMPLE_RATE)
    x1 = x2 = y1 = y2 = 0.0
    samples = []
    for index, sample in enumerate(dry):
        position = index % len(delay)
        x = delay[position]
        filtered = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, filtered
        delay[position] = sample + filtered * FEEDBACK
        samples.append((sample + filtered * WET) * OUTPUT_GAIN)

    # This recipe stays below the original limiter's -11 dB knee onset,
    # so no compression is needed. Do not normalize away its gentle level.
    peak = max(abs(sample) for sample in samples)
    assert 0 < peak < 10 ** (-11 / 20), peak
    assert all(math.isfinite(sample) for sample in samples)
    return samples


if __name__ == "__main__":
    samples = render()
    destination = Path(__file__).resolve().parents[1] / "Boop/Resources/Success.wav"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(b"".join(struct.pack("<h", round(sample * 32767))
                                   for sample in samples))
    peak_db = 20 * math.log10(max(abs(sample) for sample in samples))
    print(f"Rendered {destination}: {len(samples) / SAMPLE_RATE:.3f}s, peak {peak_db:.1f} dBFS")
