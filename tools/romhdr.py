#!/usr/bin/env python3
"""Print a headerless SNES ROM's internal header, checksum check and free space.

  romhdr.py <rom> [--min 256]

Free space is listed as runs of $00 or $FF within one bank; whole empty banks
past the end of the data are usually padding and safe for new code, but
confirm nothing references them (xref.py, or a harness read tap).
"""
import sys, zlib, os
sys.path.insert(0, os.path.dirname(__file__))

rom = open(sys.argv[1], "rb").read()
minrun = int(sys.argv[sys.argv.index("--min") + 1]) if "--min" in sys.argv else 256
print(f"size {len(rom)} bytes, CRC32 {zlib.crc32(rom):08X}" + ("  (has 512-byte copier header!)" if len(rom) % 1024 == 512 else ""))
best = None
for base, name in ((0x7FC0, "LoROM"), (0xFFC0, "HiROM"), (0x40FFC0, "ExHiROM")):
    if base + 0x40 > len(rom): continue
    h = rom[base:base + 0x40]
    ck, cm = h[0x1E] | h[0x1F] << 8, h[0x1C] | h[0x1D] << 8
    score = (ck ^ cm) == 0xFFFF
    print(f"{name} @{base:06X}: title {h[:21]!r} map ${h[0x15]:02X} type ${h[0x16]:02X} "
          f"rom ${h[0x17]:02X} sram ${h[0x18]:02X} region ${h[0x19]:02X} checksum ${ck:04X} complement-ok {score}")
    if score and best is None: best = (name, base)
# checksum: sum of image mirrored up to a power of two
size = 1 << (len(rom) - 1).bit_length()
main = 1 << (len(rom).bit_length() - 1)
s = sum(rom[:main])
rest = rom[main:]
if rest:
    s += sum(rest) * ((size - main) // len(rest))
print(f"computed checksum ${s & 0xFFFF:04X}")
hirom = best and best[0] != "LoROM"
bank = 0x10000 if hirom else 0x8000
runs, i = [], 0
while i < len(rom):
    if rom[i] in (0, 0xFF):
        j = i
        while j < len(rom) and rom[j] == rom[i] and j // bank == i // bank: j += 1
        if j - i >= minrun: runs.append((i, j - i, rom[i]))
        i = j
    else:
        i += 1
from snesmap import snes_addr
print("free runs:")
for off, n, b in runs:
    print(f"  ${snes_addr(off, hirom):06X} {n:6d} bytes of ${b:02X}")
