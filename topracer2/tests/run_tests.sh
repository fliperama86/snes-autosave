#!/bin/bash
# Regression tests for the Top Racer 2 save patch (about 2 minutes).
#   topracer2/tests/run_tests.sh
# Needs topracer2/rom/base.sfc and roms/snes/spc700.rom (see README.md).
set -e
cd "$(dirname "$0")/../.."
tr=topracer2
$tr/build.sh >/dev/null
rom=$tr/out/tr2-save.sfc
export WORK=work/tr2 FAST=1
rm -rf "$WORK"; mkdir -p "$WORK"/{race1,resume,resume_race2,newgame,typed,demo}
nv=nv/snes/tr2-save.nv

echo "stage 1: new game + race 1, attract demo"
harness/par.sh $rom race1:$tr/tests/race1.txt demo:$tr/tests/demo.txt
for n in resume resume_race2 newgame typed; do
  mkdir -p "$WORK/$n/nv/snes"; cp "$WORK/race1/$nv" "$WORK/$n/$nv"
done
echo "stage 2: resume, resume + race 2, new game over a save, typed password"
harness/par.sh $rom resume:$tr/tests/resume.txt resume_race2:$tr/tests/resume_race2.txt \
  newgame:$tr/tests/newgame.txt typed:$tr/tests/typed.txt
python3 - "$WORK" <<'P'
import os, sys
sys.path.insert(0, "topracer2/tools")
from sram import slots, newest
w = sys.argv[1]; nv = "nv/snes/tr2-save.nv"
ok = True
def check(name, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + name); ok &= bool(cond)
def rd(p): return open(os.path.join(w, p), "rb").read()
r1 = newest(os.path.join(w, "race1", nv))
check("race1: saved after the race, next race is 2 of country 1", r1 and r1["race"] == 1 and r1["country"] == 0)
check("race1: save equals live state at the next track", r1 and r1["block"] == rd("race1/blk.bin")[4:] and r1["table"] == rd("race1/tbl.bin"))
check("demo: nothing saved", not os.path.exists(os.path.join(w, "demo", nv)) or newest(os.path.join(w, "demo", nv)) is None)
check("resume: live state equals the save", r1 and rd("resume/blk.bin")[4:] == r1["block"] and rd("resume/tbl.bin") == r1["table"])
r2 = newest(os.path.join(w, "resume_race2", nv))
check("resume_race2: saved after race 2, next race is 3", r2 and r2["race"] == 2 and r2["seq"] > r1["seq"])
ng = newest(os.path.join(w, "newgame", nv))
check("newgame: save replaced by a fresh championship", ng and ng["race"] == 0 and ng["money"] == 0 and ng["seq"] > r1["seq"])
t = rd("typed/blk.bin"); race = t[0x1CE5 - 0x1CD7] | t[0x1CE5 - 0x1CD7 + 1] << 8
check("typed: other password is not replaced by the save", race == 0)
sys.exit(0 if ok else 1)
P
echo "contact sheets: $WORK/par.png and $WORK/<test>/sheet.png"
