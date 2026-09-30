#!/bin/bash
# Regression tests for the Mega Man X save patch (about 3 minutes).
#   megamanx/tests/run_tests.sh
# Needs megamanx/rom/base.sfc and roms/snes/spc700.rom (see README.md).
# Runs in a window; FAST=1 (default here) unthrottles it. Exit code 1 on any FAIL.
set -e
cd "$(dirname "$0")/../.."
mx=megamanx
$mx/build.sh >/dev/null
rom=$mx/out/mmx-save.sfc
export WORK=work/mmx FAST=${FAST:-1}
rm -rf "$WORK"; mkdir -p "$WORK"
nv=nv/snes/mmx-save.nv

echo "stage 1: new game to stage select, attract demo"
mkdir -p "$WORK"/{select,demo}
harness/par.sh $rom select:$mx/tests/select.txt demo:$mx/tests/demo.txt
# The seed: the save from "select" with lives 5, Hadouken, two sub tanks, cursor on stage 3.
for n in resume typed exit gameover newgame; do
  mkdir -p "$WORK/$n/nv/snes"
  python3 $mx/tools/sram.py edit "$WORK/select/$nv" "$WORK/$n/$nv" \
    1F80=05 1F83=8C 1F84=85 1F7E=80 1F7A=03
done
echo "stage 2: resume, typed password, exit, game over, new game over a save"
harness/par.sh $rom resume:$mx/tests/resume.txt typed:$mx/tests/typed.txt \
  exit:$mx/tests/exit.txt gameover:$mx/tests/gameover.txt newgame:$mx/tests/newgame.txt
pkill -9 -f "mame snes" 2>/dev/null || true
python3 - "$WORK" <<'P'
import os, sys
sys.path.insert(0, "megamanx/tools")
from sram import slots, newest, BLK
w = sys.argv[1]; nv = "nv/snes/mmx-save.nv"
ok = True
def check(name, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + name); ok &= bool(cond)
def rd(p):
    try: return open(os.path.join(w, p), "rb").read()
    except OSError: return b""
def sv(n):
    d = rd(f"{n}/{nv}")
    return newest(d) if d else None
def g(b, a): return b[a - BLK] if len(b) > a - BLK else None
def prot(n):
    p = rd(f"{n}/prot.bin")
    try: lines = open(os.path.join(w, n, "watch.log")).read().split("\n")
    except OSError: lines = ["?"]
    bad = [l for l in lines if l and (len(l.split()) < 4 or 1 <= int(l.split()[3], 16) <= 0x7F)]
    return p == b"\0\0\0" and not bad

sel = sv("select"); live = rd("select/blk.bin")
check("select: valid slot, block equals live except $1F7A",
      sel and len(live) == 0x23 and sel["data"][1:] == live[1:] and sel["data"][0] == 0 and live[0] == 1)
check("select: lives 2, hearts FF, armor FF, intro flag 10",
      sel and g(sel["data"], 0x1F80) == 2 and g(sel["data"], 0x1F9C) == 0xFF
      and g(sel["data"], 0x1F99) == 0xFF and g(sel["data"], 0x1F9B) == 0x10)
d = rd(f"demo/{nv}")
check("demo: nothing saved", not d or not any(s["valid"] for s in slots(d)))

seed = None
if sel:
    import subprocess
    subprocess.run(["python3", "megamanx/tools/sram.py", "edit", f"{w}/select/{nv}", f"{w}/seed.nv",
                    "1F80=05", "1F83=8C", "1F84=85", "1F7E=80", "1F7A=03"], check=True)
    seed = newest(open(f"{w}/seed.nv", "rb").read())
r = rd("resume/blk.bin")
check("resume: live block equals the seeded block exactly", seed and r == bytes(seed["data"]))
t = rd("typed/blk.bin")
check("typed: other password is not replaced by the save (lives 2, $1F7E 00)",
      len(t) == 0x23 and g(t, 0x1F80) == 2 and g(t, 0x1F7E) == 0)
# the resume itself saves once at stage select (seq 1), so later saves have seq >= 2
e = sv("exit"); eb = rd("exit/blk.bin")
check("exit: newest slot has lives 7, newer than the seed", e and g(e["data"], 0x1F80) == 7 and e["seq"] > 1 and e["data"] == eb)
o = sv("gameover"); ob = rd("gameover/blk.bin")
check("gameover: newer slot saved, equals live at stage select", o and o["seq"] > 1 and o["data"] == ob)
print("INFO gameover: lives after game over =", g(o["data"], 0x1F80) if o else None,
      "hadouken", hex(g(o["data"], 0x1F7E)) if o else None)
wl = [l for l in open(os.path.join(w, "demo", "watch.log")).read().split("\n") if l] if os.path.exists(os.path.join(w, "demo", "watch.log")) else []
check("protection (demo): probes ran, $1F9D-$1F9F stay 0", len(wl) > 0 and prot("demo"))
check("protection (exit): $1F9D-$1F9F are 0, no write of 01-7F", prot("exit"))
check("protection (gameover): $1F9D-$1F9F are 0, no write of 01-7F", prot("gameover"))
n = rd("newgame/blk.bin"); ns = newest(rd(f"newgame/{nv}"))
check("newgame: new-game values (lives 2, $1F9B 00, $1F7E 00)",
      len(n) == 0x23 and g(n, 0x1F80) == 2 and g(n, 0x1F9B) == 0 and g(n, 0x1F7E) == 0)
check("newgame: SRAM slots unchanged", ns and seed and ns["seq"] == seed["seq"] and ns["data"] == seed["data"]
      and rd(f"newgame/{nv}") == rd("seed.nv"))
sys.exit(0 if ok else 1)
P
