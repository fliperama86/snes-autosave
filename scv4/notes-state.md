# Super Castlevania IV (US): progress state, transitions, demo, protection, free space

Findings from disassembly plus MAME runs (`work/scv4/state/`). Addresses are
WRAM offsets (`$0086` = `$7E0086`) unless a bank is given. Code is shown with
the bank-`$80` mirror; the harness logs PCs in the bank-`$00` mirror (same
bytes). Direct-page variables use D=`$0000` in all game-mode code; the
dispatcher at `$028405` uses D=`$1F00`, so `$1Fxx` writes by `STA $xx` there
are a different set of variables.

## Corrections and additions to the practice-hack RAM map

| item | result |
|---|---|
| practice-hack RAM map | confirmed: `$86` block, `$88` quest, `$8E` subweapon, `$90` multi-shot, `$92` whip, `$7C` lives, `$13F0/2/4` timer/hearts/health, `$70` mode, `$13D4` entrance |
| lives | BCD, `$7C`=5 at start; HUD shows `P = $7C - 1`; game over when `$7C` reaches 0 at death |
| timer `$13F0` | BCD (`$0450` shows 450); ticks every 64 frames (`$028007`) |
| hearts `$13F2` | BCD (subtracted in decimal mode at `$80BD4F`) |
| score | NOT in the practice-hack list: 32-bit BCD at `$1F40` (low word) / `$1F42`, units of 10 (100 points = `$0010`). Add routine `$80DF54` |
| extra-life counter `$7E` | word, BCD, starts `$2000`; `$80DF72` subtracts each award and gives +1 life (`$7C`) when it runs out, then reloads from `$5000` |
| quest `$88` | set to 1 by the ending routine (`$83FCC0`, with `$86=0`). The practice hack's `$08` is not what the game writes (nonzero is what matters). Never cleared by new game; only the boot clear (`$0000-$00BD`) resets it |
| difficulty / Hard flag | none in the game. OPTION menu has only JUMP / WHIP / ITEM button assignment, SOUND, BGM, EFFECT (screenshot). Storage of those not located (not progress) |
| keys | none in this game |

Verified by poking `$8E=3, $90=1` and looking at the HUD (holy water icon and
a multi-shot icon appear). `$92` whip not visually verified (new game zeroes it
like the other two).

## 1. New-game setup

Mode 0 (`$70 = 0`) runs sub-steps selected by `$72` through the table at
`$8094AA`: step 0 `$8094B4` name-entry program (bank `$03`), step 1 `$8094BF`
intro cinematic (skippable with Start), step 2 `$8094C5` = the setup below.
Order seen in MAME: name grid, intro, setup (frame of first write `$13F4`),
then `$70` 1, 2, 3, 4, 5.

Start flow in the harness: title needs one Start to skip the logo scroll
(menu appears), a second Start on START opens the name grid, A types a
letter, Start confirms, Start again skips the intro. CONTINUE on the same menu
opens the same grid (password entry, see notes-password.md) and reaches the
same step 2 with `$1E02` (menu cursor) = 1.

Writes by `$8094C5-$80952E` (watched, `$8094D0` decides the `$86` line):

| address | value | meaning |
|---|---|---|
| `$007E` | `$2000` | extra-life counter |
| `$13C2`, `$13C4` | 0 | level graphics cache keys |
| `$0086` | 0, only if `$1E02 == 0` | block (skipped when started from the CONTINUE/password item, which keeps the decoded `$86`) |
| `$13E8` | +1 | "reset timer from table" flag (consumed in block setup) |
| `$007C` | 5 | lives |
| `$13F4`, `$13F6` | `$10` | health, health mirror |
| `$13F2` | 5 | hearts |
| `$1600,$1602,$1604` | 0 | event flags (`$1604` is a one-shot door flag at `$85FC8A`) |
| `$008E,$0090,$0092` | 0 | subweapon, multi-shot, whip |
| `$1F40,$1F42` | 0 | score |
| `$13E2` | `$FFFF` | graphics cache key |
| `$19C0-$19FF` (bank `$01` mirror) | 0 | unknown 64-byte table |
| `$0070` / `$0072` | +1 / 0 | goes to mode 1 |

Not touched: `$88` quest, `$1E00-$1FFF` (warm-boot area, survives reset).

Progress fields (what a save must hold):

| field | address | note |
|---|---|---|
| block | `$0086` | word |
| quest | `$0088` | word |
| lives | `$007C` | BCD word |
| extra-life counter | `$007E` | word |
| subweapon / multi / whip | `$008E` / `$0090` / `$0092` | words |
| timer / hearts / health | `$13F0` / `$13F2` / `$13F4` | words; `$13F6` is a health mirror rewritten to `$10` by block setup (not progress) |
| score | `$1F40-$1F43` | 4 bytes BCD |

Not contiguous: the `$7C-$93` cluster also holds transients (`$80,$82,$84,$8A,$8C`
change during play: seen `$82=6`, `$8A=4`, `$8C=1` after setup). Save the 7 words
plus `$13F0-$13F4` plus the score, 24 bytes total. Timer is only reloaded from
the table when `$13E8 != 0`, so restore `$13F0` after setup or set `$13E8=0`.

## 2. Level transitions, death, game over

Game mode `$70` (table at `$809477`):

| `$70` | handler | meaning (observed) |
|---|---|---|
| 0 | `$809491` | title/name/intro steps via `$72`, ends in setup above |
| 1, 2 | `$80952F`, `$809537` | one-frame steps |
| 3 | `$80953A` | block setup: death reset (only if health = 0), graphics, `JSL $06B4EE` |
| 4 | `$8095CF` | fade-in, 15 frames (`$1E80`), then `INC $70` at `$8095FE` |
| 5 | `$80960B` | play (also pause via `$66`) |
| 6 | `$809692` | fade-out, `DEC $1E80` then `$70=3` |
| 7 | `$8096D4` -> `$0CFD1B` | game over / continue screen |
| 9, A, B, C | `$80971D`, `$809721`, `$809767`, `$80976B` | stage-clear tally, bonus, pit-death countdown (`$76`) then `$70=6` |

Every way of entering a block goes `... -> 6 -> 3 -> 4 -> 5`: block end, death,
continue, new game (via 1, 2), demo start.

Who advances `$86` and sets `$70=6` (all set `$13D4=0` or leave the entrance):

| site | used for |
|---|---|
| `$82BB1B` (pointer `$82BB13`) | generic exit object: `$86` +1 (skips `$1D` to `$1E`), `$13D4=0`, `$70=6`. The caller `$82BB01` picks entry 0 of 4 by the object's low bits; other entries go back (`$82BB2F`) or to mode `$0B` (`$82BB4E`) |
| `$0CFF6E` | end of block 1-1-1 (Simon X >= `$03E0`): `$86 = 1`, `$70 = 6`. This is what ended the first block in my runs (stack return `$00C8E8`). Other stage-specific object code in bank `$0C` does the same |
| `$85FC9C` | door: `$86 = table $85:F5A7`, `$70=6`, `$1604=1` |
| `$85FF5E` | stage/boss end: `$86` +1, `$13E8` +1 (timer reload), then mode 6 |
| `$83FCC0` | after the ending: `$88=1`, `$86=0`, health 0, `$13E8=1`, `$70=3` |

Good save point: the `INC $70` at `$8095FE` (mode 4 to 5), five bytes
`9C C0 13 E6 70` at `$8095FB`, next instruction is the `RTL` at `$809600`; no
branch lands inside (the two branches at `$8095F3/$8095F9` go to `$809600`).
Runs once per block entry, after `$86` is final and block setup and fade-in are
done. Because death, continue and new game use it too, filter as needed
(new game at `$86=0` would overwrite a save at once; demo: see section 3).

Does block setup reset anything? Not the progress fields. Test (poked
`$8E=3,$90=1,$92=2,$13F2=$2A,$7C=3,$13F4=$0B`, score `$1234`, then walked to the
end of 1-1-1): all identical before and after except `$86` 0 to 1 and the timer
ticking (`$0428` to `$0423`, not reloaded: `$13E8` was 0). Setup does reset
`$13C0`, `$13EC`, `$1FA2`, `$13CE`, `$13D0`, `$13DE` (per-block scroll/object
state) and reloads the timer from table `$05:BCF8[$86]` only when `$13E8 != 0`.

Death (`$0280A0` region, checked with runs):

| step | effect |
|---|---|
| `$02809A` | `$13E8` +1 (timer reload), `$7C` -1 (BCD) |
| `$0280A7` | `$86 = table $01:B395[$86]` (nearest checkpoint block: starts `00 01 02 02 02 05 06 06 08 ...`; read from ROM, only entry 0 observed), `$13D4 = 0` |
| `$0280B4` | health nonzero (pit): `$70 = $0C` (countdown, then 6); health 0: `$70 = 6` directly. Then `$13F4 = 0`, `$13E2 = $FFFF`, `$13C2/4 = 0` |
| mode 3 (`$80953E`) | health is 0: hearts = 5, `$8E/$90/$92` = 0, `$13C6` = 0, health `$10`. Seen: hearts `$2A` to 5, subweapon 3 to 0 |
| kept | score, `$7E`, `$88`, block (checkpoint) |

Game over (`$7C` = 0 at `$80955D` sets `$70=7`; `$0CFD1B`, cursor `$68`, 0 = continue):

| choice | effect (observed) |
|---|---|
| CONTINUE (Start) | `$86 = table $01:FBAC[$86]` (stage start: `00 x8, 08 x4, 0C x6, 12 x6, 18 x2, 1A x9, 23 x7, 2A x4, 2E x9, 37 x5, 3C x3, 3F`), `$7C=5`, health `$10`, hearts 5, `$8E/90/92` 0, `$1600-04` 0, **score `$1F40/42` = 0**, then `$70=3`. `$7E` is not reset. Timer reloaded (flag set at death) |
| NO (Down, Start) | `$72 = 3`, program restart: password screen with the item grid (screenshot), see notes-password.md |

## 3. Attract demo

Start: boot -> Konami logo -> title logo scroll (about frames 900-2500, menu
only after a button press) -> story intro (`$1C00` states at `$05F1B6-$05F5D1`)
-> demo. First demo began at frame 11488 from boot (`$809807`, called from
`$8086B0`): `$4C` cycles 1,2,3,0; `$1C00 = $01:8B31[$4C]` (input script
pointer, bank `$1F` data), `$86 = $01:8B39[$4C]` (demo blocks 1, 3, `$1B`,
`$0A`; the first run played block 3), `$7C=5`, `$13F2=5`, `$4A=1`, `$13E8=1`,
`$70=3`. The demo then goes `3, 4, 5` like real play, reads recorded input
from `$1F:xxxx` in mode 5 (`$809863`), ends at frame 13030 and returns to the
title.

Flag: `$004A` (word) = 1 during the demo, 0 in real play.

| case | `$4A` | other |
|---|---|---|
| demo (frame 12000) | 1 (set once at `$80984D`, stays until the title program clears it at `$8086EA`/`$808818`) | `$86=3`, `$1C06` counts down, `$1C00` walks the script |
| real play (new game, no demo run first), modes 3-5, block change, death, game over | 0 (no write to `$4A` in any of these runs) | |
| real play started after a demo ran | 0 (`$4A` cleared at frame 13802, run then started at 14239, `$4A` still 0 at mode 5) | `$1C00` = 3 (leftover), `$1C06` = 0 |

`$4A` is also set to 1 by the title program (`$808663`, fades), so only trust
it with mode 3-5 running. Mode 3 itself reads it (`$80957A`: nonzero skips the
graphics reload). The demo does pass through `$8095FE`, so a save hook there
must test `$4A`.

## 4. Copy protection

None found.

- Dynamic: write taps over `$70:0000-$7D:FFFF` and its mirror `$F0-$FD` logged zero
  writes across boot, title, name grid, options, password screen, a full demo,
  new game, play, block change, death, game over, continue (control test: a
  poke into the region does fire the tap).
- Static: no `STA long`/`CMP long` pair on the same address in banks `$70-$7D`,
  no `PLB` to such a bank, no reads of the header bytes at `$FFD6/$FFD8`.
  Other long-bank hits from a byte scan are data in compressed graphics.
- The only SRAM-like thing is WRAM: the boot code (`$808099-$8080C9`) checks a
  6-word signature at `$1E0A-$1E14` and skips clearing `$1E00-$1FFF` when it
  matches (warm boot). Not SRAM, not a probe.

Declaring SRAM in the header should be safe; confirm with a header-only
control build when the patch exists.

## 5. Free space

Every `$FF` run from `romhdr.py` sits at the end of its bank (except `$8CF4CA`,
which ends at `$8CF800`). A sweep of all 64 blocks (poke `$86`, `$70=6`, 260
frames each) plus demo, title, options, password, death and game over with
read taps on all 20 runs (both the `$8x` bank and its `$0x` mirror, which is
the one the game executes from) gave exactly one hit: a 1-byte read at
`$96FDE6` (PC `$028765`, while loading block `$31`), the first byte of that
run, i.e. the last byte of the preceding data (`FF` terminator). So treat
that run as starting at `$96FDE7`. All other runs: zero reads.

| run | bytes | use |
|---|---|---|
| `$9FF3C4` | 3132 | recommended: last bank, end of ROM, clear in all runs; use from `$9FF400` (about 3 KB) |
| `$9EF596` | 2666 | second choice |
| `$9DF8A9` | 1879 | |
| `$9BFA75` | 1419 | |
| `$95FBB4` | 1100 | |
| rest | 279-860 | too small or leave |

Caveat: not exercised: ending credits, cutscenes after the last boss, bosses
actually fought, the options menu beyond the first screen. The last bank is
the least likely to be touched by any of these. `$0CFF9E`-`$0CFFFF` and
`$85FF7B` onwards are also `$FF` but are code-adjacent tails (not reported by
`romhdr.py`), and bank `$0C` holds stage code, so avoid them.

## Harness notes

- `snap` under `FAST=1` lags the emulation (frame skip): screenshots do not
  match the frame number. Trust `watch`/`dump` logs, or use unthrottled runs
  only for logs and take screenshots in normal-speed runs.
- Boot timing: Konami logo until about frame 900; Start before about 700 is
  ignored; title menu needs one Start (skip scroll) first.
- Save state of a fresh block 1-1-1 (unpatched ROM): `work/scv4/state/sta/snes/s11.sta`
  (load with `load s11` at frame 2). Walk right with jumps (`B` held 25 frames)
  at frames 470 and 552 to reach the end of 1-1-1 at frame about 746.
- Read taps: my own copy of `harness/run.lua` with an `rtap` command lives in
  `work/scv4/state/run2.lua` (not a repo change).
