#!/usr/bin/env python3
"""Mega Man X save slots in a battery file.

  sram.py show <file.nv> [blk.bin]      print both slots, optionally compare
                                        the newest with a live dump of $7E1F7A
  sram.py edit <in.nv> <out.nv> addr=val [addr=val ...]
                                        copy the newest slot into a fresh file
                                        with bytes changed (addr in $7E1F7A-
                                        $7E1F9C, hex), checksum fixed
"""
import sys

BASE, STEP, BLK, BLKLEN, SIZE = 0x100, 0x80, 0x1F7A, 0x23, 0x2000


def slots(d):
    out = []
    for base in (BASE, BASE + STEP):
        data = d[base + 8:base + 8 + BLKLEN]
        out.append(dict(base=base, data=data,
                        valid=d[base:base + 4] == b"MMXS" and int.from_bytes(d[base + 6:base + 8], "little") == sum(data) & 0xFFFF,
                        seq=int.from_bytes(d[base + 4:base + 6], "little")))
    return out


def newest(d):
    v = [s for s in slots(d) if s["valid"]]
    if len(v) == 2:
        return v[1] if 0 < ((v[1]["seq"] - v[0]["seq"]) & 0xFFFF) < 0x8000 else v[0]
    return v[0] if v else None


def fields(b):
    g = lambda a: b[a - BLK]
    return (f"lives {g(0x1F80)} hearts {g(0x1F9C):02X} armor {g(0x1F99):02X} "
            f"tanks {bytes(b[0x1F83 - BLK:0x1F87 - BLK]).hex()} hadouken {g(0x1F7E):02X} "
            f"fortress {g(0x1F7B)} intro {g(0x1F9B):02X}")


def image(data, seq=0):
    d = bytearray(b"\xff" * SIZE)
    d[BASE:BASE + 4] = b"MMXS"
    d[BASE + 4:BASE + 6] = seq.to_bytes(2, "little")
    d[BASE + 6:BASE + 8] = (sum(data) & 0xFFFF).to_bytes(2, "little")
    d[BASE + 8:BASE + 8 + BLKLEN] = data
    return d


if __name__ == "__main__":
    cmd = sys.argv[1]
    d = open(sys.argv[2], "rb").read()
    if cmd == "show":
        live = open(sys.argv[3], "rb").read() if len(sys.argv) > 3 else None
        for s in slots(d):
            print(f"slot ${s['base']:03X} valid {s['valid']} seq {s['seq']} {fields(s['data'])}")
        n = newest(d)
        if live and n:
            diff = [f"{BLK + i:04X}:{n['data'][i]:02X}/{live[i]:02X}" for i in range(BLKLEN) if n["data"][i] != live[i]]
            print("newest vs live:", "equal" if not diff else " ".join(diff))
    elif cmd == "edit":
        n = newest(d)
        data = bytearray(n["data"])
        for kv in sys.argv[4:]:
            a, v = kv.split("=")
            data[int(a, 16) - BLK] = int(v, 16)
        open(sys.argv[3], "wb").write(image(data, n["seq"]))
