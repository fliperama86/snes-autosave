#!/bin/bash
# Regression tests for the Super Castlevania IV save patch (a few minutes).
#   scv4/tests/run_tests.sh
# Needs scv4/rom/{us,jp}.sfc (see scv4/build.sh) and roms/snes/spc700.rom.
# Runs in windows; FAST=1 (default here) unthrottles them. Exit code 1 on any FAIL.
# Region us runs every test, jp runs save, resume and typed.
set -e
cd "$(dirname "$0")/../.."
sc=scv4
$sc/build.sh us >/dev/null
$sc/build.sh jp >/dev/null
export WORK=work/scv4/tests FAST=${FAST:-1}
rm -rf "${WORK:?}"; mkdir -p "$WORK/cmds"
sram=$sc/tools/sram.py

# Seed for the resume family: block 5, full power-up.
SEED="block=5 lives=3 whip=2 sub=3 multi=1 hearts=42 health=0B score=1234 timer=0321"
# Game over seed: lives 1, block $0A (game over CONTINUE goes to stage start $08).
SEEDGO="block=0A lives=1 whip=2 sub=3 multi=1 hearts=42 health=0B score=1234 timer=0321"

# prepare <region> <name> <cmdfile> [sram.py make fields...]; empty fields: no seed
prep() {
  local r=$1 n=$2 f=$3; shift 3
  local d=$WORK/$r-$n
  mkdir -p "$d/nv/snes"
  sed "s#@W@#$d#g" "$sc/tests/$f" > "$WORK/cmds/$r-$n.txt"
  [ $# -gt 0 ] && python3 $sram make "$d/nv/snes/scv4-save-$r.nv" "$@"
  return 0
}
runs=()
for r in us jp; do
  prep $r save save.txt
  prep $r resume resume.txt $SEED
  prep $r typed typed.txt $SEED
done
prep us nosave1 nosave1.txt
prep us demo demo.txt
prep us death death.txt $SEED
prep us newgame newgame.txt $SEED
prep us gameover gameover.txt $SEEDGO
prep us gameover5 gameover.txt block=5 lives=1 whip=2 sub=3 multi=1 hearts=42 health=0B score=1234 timer=0321

echo "running 11 us and 3 jp sessions in parallel"
par() { local r=$1; shift; local a=(); for n in "$@"; do a+=("$r-$n:$WORK/cmds/$r-$n.txt"); done
        harness/par.sh $sc/out/scv4-save-$r.sfc "${a[@]}"; }
par us save resume typed nosave1 demo death newgame gameover gameover5 &
par jp save resume typed &
wait
pkill -9 -f "mame snes.*work/scv4" 2>/dev/null || true

python3 - "$WORK" $sram <<'P'
import os, sys
w = sys.argv[1]
sys.path.insert(0, os.path.dirname(sys.argv[2]))
import sram as S
ok = True
def check(name, cond, why=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + ("" if cond or not why else "  (" + why + ")"))
    ok &= bool(cond)
def rd(p):
    try: return open(os.path.join(w, p), "rb").read()
    except OSError: return b""
def nv(r, n): return rd(f"{r}-{n}/nv/snes/scv4-save-{r}.nv")
def newest(r, n):
    d = nv(r, n)
    return S.newest(d) if len(d) == S.SIZE else None
def nvalid(r, n):
    d = nv(r, n)
    return sum(s["valid"] for s in S.slots(d)) if len(d) == S.SIZE else 0
def live(r, n):
    try: return b"".join(rd(f"{r}-{n}/w_{a:04X}.bin") for a, _ in S.REGIONS)
    except Exception: return b""
def mode(r, n):
    m = rd(f"{r}-{n}/mode.bin"); return m[0] if m else None
def f(data, k): return S.get(data, k)
def diff(a, b, skip_timer=False):
    o = S.offset(0x13F0)
    return [i for i in range(S.DATALEN) if a[i] != b[i] and not (skip_timer and o <= i < o + 2)]
def eq_live(sl, lv, skip_timer=True):
    return sl and len(lv) == S.DATALEN and not diff(sl["data"], lv, skip_timer)
def seedimg(fields):
    return S.newest(S.image(S.apply(S.NEW_GAME, fields)))
SEEDF = "block=5 lives=3 whip=2 sub=3 multi=1 hearts=42 health=0B score=1234 timer=0321".split()

for r in ("us", "jp"):
    n = newest(r, "save")
    d = n["data"] if n else None
    check(f"{r} save: valid slot, block 1, poked values (whip 2 sub 3 multi 1 hearts 42 lives 3 score 1234)",
          d and f(d, "block") == 1 and f(d, "quest") == 0 and f(d, "whip") == 2 and f(d, "sub") == 3
          and f(d, "multi") == 1 and f(d, "hearts") == 0x42 and f(d, "lives") == 3 and f(d, "score") == 0x1234
          and f(d, "score_hi") == 0, S.fields(d) if d else "no valid slot")
    lv = live(r, "save")
    check(f"{r} save: slot equals live regions after 1-1-2 starts (timer excepted)",
          mode(r, "save") == 5 and eq_live(n, lv),
          f"mode {mode(r, 'save')} diff {diff(d, lv, True) if d and len(lv) == S.DATALEN else 'n/a'}")

    seed = seedimg([x for x in SEEDF])
    rn = newest(r, "resume"); lv = live(r, "resume"); g = rd(f"{r}-resume/grid.bin")
    check(f"{r} resume: prefilled grid is not blank", len(g) == 16 and any(g))
    check(f"{r} resume: mode 5 and live regions equal the save (timer excepted)",
          mode(r, "resume") == 5 and eq_live(seed, lv),
          f"mode {mode(r, 'resume')} diff {diff(seed['data'], lv, True) if len(lv) == S.DATALEN else 'n/a'}")
    check(f"{r} resume: newer slot written at block entry with timer 0321 and the seed data",
          rn and rn["seq"] > seed["seq"] and rn["data"] == seed["data"] and f(rn["data"], "timer") == 0x321,
          S.fields(rn["data"]) if rn else "no slot")

    lv = live(r, "typed"); g2 = rd(f"{r}-typed/grid2.bin")
    check(f"{r} typed: block $12 quest 8, lives 5, whip 0, sub 0, multi 0, score 0 (save not restored)",
          len(lv) == S.DATALEN and mode(r, "typed") == 5 and f(lv, "block") == 0x12 and f(lv, "quest") == 8
          and f(lv, "lives") == 5 and f(lv, "whip") == 0 and f(lv, "sub") == 0 and f(lv, "multi") == 0
          and f(lv, "score") == 0 and f(lv, "score_hi") == 0, S.fields(lv) if lv else "no dump")
    check(f"{r} typed: poked grid was in place", g2 == bytes([0,0,0,1,2,2,0,0,2,3,0,1,0,0,0,0]))

check("us nosave1: exit in 1-1-1, no valid slot (mode 5, block 0)",
      nvalid("us", "nosave1") == 0 and mode("us", "nosave1") == 5 and rd("us-nosave1/w_0086.bin")[:2] == b"\0\0")
# demo: $4A/$70/$86 sampled every 200 frames
ds = {}
for fr in range(11000, 14000, 200):
    try: ds[fr] = tuple(int.from_bytes(rd(f"us-demo/{p}_{fr}.bin")[:2], "little") for p in ("d4a", "d70", "d86"))
    except Exception: pass
ran = [fr for fr, (a, m, b) in ds.items() if a == 1 and m == 5]
check("us demo: the attract demo played (frames with $4A=1 in mode 5 seen)", len(ran) > 0, f"{len(ds)} samples, {ds}")
check("us demo: no valid slot", nvalid("us", "demo") == 0)
print(f"INFO demo: $4A=1 and mode 5 at frames {ran[:1]}..{ran[-1:]}")

dn = newest("us", "death"); lv = live("us", "death"); seed = seedimg(SEEDF)
d = dn["data"] if dn else None
check("us death: newer slot, lives 2, whip/sub/multi 0, hearts 5, block 5",
      d and dn["seq"] >= 2 and f(d, "lives") == 2 and f(d, "whip") == 0 and f(d, "sub") == 0 and f(d, "multi") == 0
      and f(d, "hearts") == 5 and f(d, "block") == 5, S.fields(d) if d else "no slot")
check("us death: slot equals live after the respawn (timer excepted), mode 5",
      mode("us", "death") == 5 and eq_live(dn, lv),
      f"mode {mode('us', 'death')} diff {diff(d, lv, True) if d and len(lv) == S.DATALEN else 'n/a'}")

# Only the slot area (first $300 bytes) is compared: new game legitimately clears the resume flag at $312.
check("us newgame: save slots unchanged from the seed, new game reached mode 5 at block 0",
      nv("us", "newgame")[:0x300] == S.image(S.apply(S.NEW_GAME, SEEDF))[:0x300] and mode("us", "newgame") == 5
      and rd("us-newgame/w_0086.bin")[:2] == b"\0\0")

go = newest("us", "gameover"); lv = live("us", "gameover")
d = go["data"] if go else None
check("us gameover: game over screen (mode 7) was reached",
      rd("us-gameover/mode_go.bin")[:1] == b"\x07")
check("us gameover: newer slot at stage start block 8, lives 5, score 0, whip/sub/multi 0, hearts 5",
      d and go["seq"] >= 2 and f(d, "block") == 8 and f(d, "quest") == 0 and f(d, "lives") == 5
      and f(d, "score") == 0 and f(d, "score_hi") == 0 and f(d, "whip") == 0 and f(d, "sub") == 0
      and f(d, "multi") == 0 and f(d, "hearts") == 5, S.fields(d) if d else "no slot")
check("us gameover: slot equals live at the stage start (timer excepted)",
      mode("us", "gameover") == 5 and eq_live(go, lv),
      f"mode {mode('us', 'gameover')} diff {diff(d, lv, True) if d and len(lv) == S.DATALEN else 'n/a'}")

g5 = newest("us", "gameover5"); lv = live("us", "gameover5")
d = g5["data"] if g5 else None
check("us gameover5: continue in stage 1 saves block 0 (lives 5, score 0), not left at the pre-game-over state",
      d and g5["seq"] >= 2 and f(d, "block") == 0 and f(d, "lives") == 5 and f(d, "score") == 0
      and f(d, "whip") == 0, S.fields(d) if d else "no slot")
check("us gameover5: slot equals live at block 0 (timer excepted)",
      mode("us", "gameover5") == 5 and eq_live(g5, lv),
      f"mode {mode('us', 'gameover5')} diff {diff(d, lv, True) if d and len(lv) == S.DATALEN else 'n/a'}")
sys.exit(0 if ok else 1)
P
