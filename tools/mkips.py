#!/usr/bin/env python3
"""mkips.py <orig> <patched> <out.ips>: minimal IPS writer (no RLE)."""
import sys
a = open(sys.argv[1], "rb").read(); b = open(sys.argv[2], "rb").read()
assert len(b) >= len(a)
out = bytearray(b"PATCH"); i = 0
while i < len(b):
    if i < len(a) and a[i] == b[i]: i += 1; continue
    j = i
    while j < len(b) and j - i < 0xFFFF and not (j < len(a) and a[j] == b[j] and (j + 1 >= len(b) or (j + 1 < len(a) and a[j+1] == b[j+1]))): j += 1
    if i == 0x454F46: i -= 1  # avoid "EOF" offset
    out += i.to_bytes(3, "big") + (j - i).to_bytes(2, "big") + b[i:j]; i = j
out += b"EOF"
open(sys.argv[3], "wb").write(out)
