#!/usr/bin/env python3
"""Find references to code addresses.

  xref.py <rom> <addr>... [--hirom]

Reports JSL/JML (any bank) and JSR/JMP absolute (same bank only). This is a
byte search, so expect some false positives inside data or misaligned code;
confirm each hit with dis.py. Indirect calls (JSR (tbl,X), JML [ptr]) and
calls through pushed return addresses are not found: use the harness
'stackon' or 'bp' commands to catch those at run time.
"""
import sys
from snesmap import rom_offset, snes_addr

args = [a for a in sys.argv[1:] if not a.startswith("--")]
hirom = "--hirom" in sys.argv
rom = open(args[0], "rb").read()
for a in args[1:]:
    t = int(a, 16); lo = t & 0xFFFF; bk = t >> 16
    hits = []
    for i in range(len(rom) - 3):
        if rom[i] in (0x22, 0x5C) and rom[i + 1] | rom[i + 2] << 8 == lo and (rom[i + 3] & 0x7F) == (bk & 0x7F):
            hits.append(("JSL " if rom[i] == 0x22 else "JML ") + "%06X" % snes_addr(i, hirom))
    base = rom_offset(t, hirom) & ~(0xFFFF if hirom else 0x7FFF)
    size = 0x10000 if hirom else 0x8000
    for i in range(base, min(base + size, len(rom)) - 2):
        if rom[i] in (0x20, 0x4C) and rom[i + 1] | rom[i + 2] << 8 == lo:
            hits.append(("JSR " if rom[i] == 0x20 else "JMP ") + "%06X" % snes_addr(i, hirom))
    print(a, hits)
