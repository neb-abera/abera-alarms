#!/usr/bin/env python3
"""Writes the five alarm sounds in App/Sounds as 16-bit mono WAV, 28 s each
(AlarmKit plays a bundled sound of up to 30 s and repeats it). Standard
library only, and original, so there is no licence to track. Converted to
CAF by tools/make-sounds.sh: python3 tools/make-sounds.py && tools/make-sounds.sh"""
import math, struct, wave, pathlib

RATE, SECONDS = 44100, 28
OUT = pathlib.Path(__file__).resolve().parent.parent / "App/Sounds"

def tone(freq, t):
    # A sine with its third harmonic, so it carries on a phone speaker.
    return math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * 3 * freq * t)

def envelope(t, start, length, attack=0.01, release=0.04):
    x = t - start
    if x < 0 or x > length: return 0.0
    return min(1.0, x / attack, (length - x) / release)

def pulse(t):
    # Four 880 Hz beeps a second, then a rest: the classic alarm clock.
    cycle = t % 1.0
    return sum(envelope(cycle, s, 0.09) for s in (0.0, 0.15, 0.30, 0.45)) * tone(880, t)

def chime(t):
    # A falling two-note chime every 1.5 s.
    cycle = t % 1.5
    return envelope(cycle, 0.0, 0.6, release=0.5) * tone(1046.5, t) + envelope(cycle, 0.5, 0.8, release=0.7) * tone(784, t)

def rise(t):
    # A tone that climbs an octave each second and gets louder over 10 s.
    cycle = t % 1.0
    freq = 440 * 2 ** cycle
    phase = 2 * math.pi * 440 * (2 ** cycle - 1) / math.log(2)
    return min(1.0, 0.3 + t / 10) * envelope(cycle, 0.0, 0.95) * (math.sin(phase + 2 * math.pi * 440 * (t - cycle)) )

def siren(t):
    # A wail between 600 and 1200 Hz, two cycles a second.
    phase = 2 * math.pi * (900 * t - 300 / (4 * math.pi) * math.cos(4 * math.pi * t))
    return math.sin(phase) + 0.25 * math.sin(3 * phase)

def beacon(t):
    # One long 660 Hz tone every 2 s.
    return envelope(t % 2.0, 0.0, 0.8, attack=0.05, release=0.3) * tone(660, t)

for name, fn in {"pulse": pulse, "chime": chime, "rise": rise, "siren": siren, "beacon": beacon}.items():
    frames = bytearray()
    peak = 0.0
    samples = [fn(i / RATE) for i in range(RATE * SECONDS)]
    peak = max(abs(s) for s in samples) or 1.0
    for s in samples:
        frames += struct.pack("<h", int(32000 * 0.9 * s / peak))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(name, len(frames), "bytes")
