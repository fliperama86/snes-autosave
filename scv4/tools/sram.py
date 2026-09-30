#!/usr/bin/env python3
"""Super Castlevania IV save slots in a battery file.

  sram.py show <file.nv>                  print both slots
  sram.py make <out.nv> name=val ...      write a battery file with one slot;
                                          fields as below (hex), rest from a
                                          new game at block 0
  sram.py edit <in.nv> <out.nv> name=val  copy the newest slot with changes
  sram.py live <file.nv> <dir>            compare the newest slot with live
                                          dumps <dir>/w_<addr>.bin written by
                                          the tests (one per region)
"""
import sys

BASE, STEP, SIZE = 0x000, 0x100, 0x2000
REGIONS = [(0x007C, 4), (0x0086, 4), (0x008E, 6), (0x13F0, 6), (0x1F40, 4), (0x1600, 6), (0x19C0, 64)]
DATALEN = sum(n for _, n in REGIONS)
# word fields: name -> WRAM address
FIELDS = {"lives": 0x7C, "extra": 0x7E, "block": 0x86, "quest": 0x88, "sub": 0x8E, "multi": 0x90,
          "whip": 0x92, "timer": 0x13F0, "hearts": 0x13F2, "health": 0x13F4, "score": 0x1F40, "score_hi": 0x1F42}


def offset(addr):
    o = 0
    for a, n in REGIONS:
        if a <= addr < a + n:
            return o + addr - a
        o += n
    raise KeyError(hex(addr))


def slots(d):
    out = []
    for base in (BASE, BASE + STEP):
        data = d[base + 8:base + 8 + DATALEN]
        out.append(dict(base=base, data=bytes(data),
                        valid=d[base:base + 4] == b"SCV4" and int.from_bytes(d[base + 6:base + 8], "little") == sum(data) & 0xFFFF,
                        seq=int.from_bytes(d[base + 4:base + 6], "little")))
    return out


def newest(d):
    v = [s for s in slots(d) if s["valid"]]
    if len(v) == 2:
        return v[1] if 0 < ((v[1]["seq"] - v[0]["seq"]) & 0xFFFF) < 0x8000 else v[0]
    return v[0] if v else None


def get(data, name):
    o = offset(FIELDS[name])
    return data[o] | data[o + 1] << 8


def fields(data):
    return " ".join(f"{k} {get(data, k):04X}" for k in FIELDS)


def image(data, seq=0):
    d = bytearray(b"\xff" * SIZE)
    d[BASE:BASE + 4] = b"SCV4"
    d[BASE + 4:BASE + 6] = seq.to_bytes(2, "little")
    d[BASE + 6:BASE + 8] = (sum(data) & 0xFFFF).to_bytes(2, "little")
    d[BASE + 8:BASE + 8 + DATALEN] = data
    return d


def apply(data, kvs):
    data = bytearray(data)
    for kv in kvs:
        k, v = kv.split("=")
        o = offset(FIELDS[k]) if k in FIELDS else offset(int(k, 16))
        val = int(v, 16)
        data[o] = val & 0xFF
        if k in FIELDS:
            data[o + 1] = val >> 8
    return data


NEW_GAME = apply(bytes(DATALEN), ["lives=5", "extra=2000", "hearts=5", "health=10", "timer=500"])

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "show":
        d = open(sys.argv[2], "rb").read()
        for s in slots(d):
            print(f"slot ${s['base']:03X} valid {s['valid']} seq {s['seq']} {fields(s['data'])}")
    elif cmd == "make":
        open(sys.argv[2], "wb").write(image(apply(NEW_GAME, sys.argv[3:])))
    elif cmd == "edit":
        n = newest(open(sys.argv[2], "rb").read())
        open(sys.argv[3], "wb").write(image(apply(n["data"], sys.argv[4:]), n["seq"]))
    elif cmd == "live":
        n = newest(open(sys.argv[2], "rb").read())
        live = b"".join(open(f"{sys.argv[3]}/w_{a:04X}.bin", "rb").read() for a, _ in REGIONS)
        diff = [f"{k}" for k in FIELDS if get(n["data"], k) != get(live, k)]
        rest = [i for i in range(DATALEN) if n["data"][i] != live[i]]
        print("newest vs live:", "equal" if not rest else f"fields differ: {diff}, bytes differ at {rest}")
