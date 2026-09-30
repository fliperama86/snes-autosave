#!/usr/bin/env python3
"""Read Top Racer 2 save slots from a battery file.

  sram.py <file.nv> [blk.bin tbl.bin]   print both slots, optionally compare
                                        with live dumps of $7E1CD7 and $7EF000
"""
import sys

DATALEN, BLKLEN = 0x298, 0x118


def slots(path):
    d = open(path, "rb").read()
    out = []
    for base in (0, 0x400):
        data = d[base + 8:base + 8 + DATALEN]
        w = lambda a: data[a - 0x1CDB] | data[a - 0x1CDB + 1] << 8
        out.append(dict(
            base=base, valid=d[base:base + 4] == b"TR2S" and int.from_bytes(d[base + 6:base + 8], "little") == sum(data) & 0xFFFF,
            seq=int.from_bytes(d[base + 4:base + 6], "little"), country=w(0x1CE1), race=w(0x1CE5), money=w(0x1D19),
            block=data[:BLKLEN], table=data[BLKLEN:]))
    return out


def newest(path):
    v = [s for s in slots(path) if s["valid"]]
    if not v: return None
    if len(v) == 1: return v[0]
    a, b = v
    return b if ((b["seq"] - a["seq"]) & 0xFFFF) not in (0,) and ((b["seq"] - a["seq"]) & 0x8000) == 0 else a


if __name__ == "__main__":
    blk = open(sys.argv[2], "rb").read()[4:] if len(sys.argv) > 2 else None
    tbl = open(sys.argv[3], "rb").read() if len(sys.argv) > 3 else None
    for s in slots(sys.argv[1]):
        line = f"slot ${s['base']:03X} valid {s['valid']} seq {s['seq']} country {s['country']} race {s['race']} money {s['money']}"
        if blk: line += f" block==live {s['block'] == blk}"
        if tbl: line += f" table==live {s['table'] == tbl}"
        print(line)
