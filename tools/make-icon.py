#!/usr/bin/env python3
"""Draws App/Assets.xcassets/AppIcon.appiconset/icon.png: an alarm clock in
white on abera.tech's wash blue, rgb(0, 26, 51). Standard library only, so
it runs anywhere: python3 tools/make-icon.py"""
import math, struct, zlib, pathlib

SIZE, SS = 1024, 3
BG, FG = (0, 26, 51), (255, 255, 255)
C = (512, 548)

def inside(x, y):
    dx, dy = x - C[0], y - C[1]
    r = math.hypot(dx, dy)
    if 300 <= r <= 360:                      # the ring
        return True
    for bx in (-250, 250):                   # the two bells
        if math.hypot(x - (C[0] + bx), y - (C[1] - 290)) <= 95 and y < C[1] - 250:
            return True
    for lx in (-1, 1):                       # the legs
        px, py = C[0] + lx * 230, C[1] + 330
        if abs((x - px) + lx * (y - py) * 0.6) < 26 and py - 10 < y < py + 90:
            return True
    def hand(angle, length, width):
        ux, uy = math.sin(angle), -math.cos(angle)
        t = dx * ux + dy * uy
        d = abs(dx * uy - dy * ux)
        return -20 <= t <= length and d <= width
    return hand(0, 220, 26) or hand(math.radians(120), 160, 26) or r <= 40

rows = []
for y in range(SIZE):
    row = bytearray([0])
    for x in range(SIZE):
        hits = sum(inside(x + (i + 0.5) / SS, y + (j + 0.5) / SS) for i in range(SS) for j in range(SS))
        a = hits / (SS * SS)
        row += bytes(round(BG[k] + (FG[k] - BG[k]) * a) for k in range(3))
    rows.append(bytes(row))

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
out = pathlib.Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/icon.png"
out.write_bytes(png)
print(out, len(png), "bytes")
