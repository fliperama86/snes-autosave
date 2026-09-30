# Super Castlevania IV (US): password system notes

All addresses are for `rom/us.sfc`. Work dir `work/scv4/pw/` (command files, dumps, `pwlib.py`
with the password encoder used to make test passwords). CPU DB is `$01` in these routines
(tables at `$01:D07D`, `$01:FBAC`).

## 1. Boot, title and menus

Frames are from power-on, harness FAST. Inputs held 4 frames.

| frame | screen |
|---|---|
| 0-250 | black, then Konami logo (white flash ~500-700) |
| ~900-1500 | title wall scrolls, logo drops in (no menu yet) |
| ~1500-2300 | title logo, no menu; later the graveyard intro, then the demo |
| Start at T (600, 1200, 1450 accepted; 900 ignored) | opens the PLAY SELECT menu: START / CONTINUE / OPTION |

- Start pressed at 900 was ignored (mid transition); 600, 1200, 1450 all opened the menu. Use
  Start at 1700 (verified everywhere below).
- Menu times out about 400 frames after opening (open at ~1700, visible at 2100, black at 2150,
  back at the wall at 2200). Menu input is ignored for the first ~30 frames after opening
  (Down at +5/+15/+30 did nothing, at +60 worked).
- `$1E02` = selected item (0 START, 1 CONTINUE, 2 OPTION; cycles mod 3).
- Both START and CONTINUE go to an `ENTER YOUR NAME` screen. Input is ignored until about
  135 frames after choosing the item (A at +125 ignored, +140 worked).
- Name screen: grid A-Z then 1-9 (4 rows of 9/9/8/9). Name buffer `$7E1700`, 8 bytes, cursor `$1C08`;
  A=`$0B` .. Z=`$24`, 1-9=`$25-$2D`, 0 = empty. A places, Start confirms (works with 1 letter,
  not tested with 0). After the 8th letter the cursor wraps to slot 0 (8 A presses gave `0B`x8).
  B is the backspace handler per code (`$0381AA`), not exercised.
- START then name then Start: new game, `BLOCK 1-1`.
- CONTINUE then name then Start: password grid screen.

Input sequence (verified, `work/scv4/pw/c/p*.txt`):

```
1700 Start          # open menu
1800 Down           # CONTINUE (skip for new game)
1840 Start          # to name screen
1990 A              # name "A" (after 1975)
2020 Start          # confirm name; new game starts here, or grid screen opens
2200 ...            # grid entry (ready ~2100)
```

New game: `1700 Start`, `1800 Start`, `1990 A`, `2020 Start`; gameplay at ~2300.

## 2. Password entry screen (grid)

The password is a 4x4 grid of 4 symbols (0 blank, 1 whip/axe, 2 potion, 3 heart) plus the name.

| what | where |
|---|---|
| screen state | `$1C00` (name screen table `$038231`, grid state 6 = input loop, 7 = "NOT COMPLETE" 64 frames, 8 = accepted) |
| cells | `$7E1C20-1C2F`, index = y*4+x, raw 0-3 (entry mode) |
| cursor x / y | `$1C04` / `$1C06` (words, masked to 0-3 each frame, wrap) |
| selected symbol | `$1C0A` (word, masked 0-3) |
| joypad edge word | `$28` (A `$0080`, L `$0020`, R `$0010`, B `$8000`, Start `$1000`, Select `$2000`) |
| name | `$7E1700`, 8 bytes, part of the checksum |

Buttons (`$038354`, `$038384`): D-pad moves, L decrements / R increments the selected symbol,
A writes it to the cell under the cursor, B clears the cell to 0, Start confirms, Select aborts to
the title (`JML $008771`). Blank cells are legal; "NOT COMPLETE TRY AGAIN" just means invalid.
Button entry with 12-frame spacing works (used in the tests below).

## 3. Grid initialization

No "last password" buffer. The grid opens empty: verified after a full game-over password display
(which ends in a reset to the Konami logo) then CONTINUE again: `$1C20-2F` all 0. Nothing in
`$1C00-1C3F` is prefilled at open (watch from frame 2000: first write to `$1C20` is the user's A
press). Entry init is state 4 of the name-screen table at `$038264` (clears cursor/symbol only).

## 4. Confirm handler and decoder

Start in state 6 is at `$038285`-`$038311` (bank 03):

1. `$038505` packs the 16 cells into bytes `$1C14-1C17` using the scramble table `$01:D07D`
   (16 pairs: byte index, 2-bit slot): `(2,3)(1,0)(3,2)(2,1)(3,1)(0,0)(1,2)(3,0)(1,1)(2,0)(3,3)(0,2)(0,1)(2,2)(0,3)(1,3)`
   for cells 0..15.
2. `$86 = byte0`. Valid only if it is one of (`$0382A2-$0382E8`):
   `00 08 0C 12 18 1A 23 2A 2E 37 3C 3F 40 41 42` (the stage-start blocks, same set as the values of
   the `$01:FBAC` table). Otherwise fail.
3. `$88 = byte1` (any value passes this step; the checksum guards it).
4. Recompute with `$0384DE`: `$1C10 = $86 | $88<<8`, `$1C12 = $86 + $88 + sum(0xFF - name[i])` (16-bit, all 8 name bytes,
   empty slots count 0xFF). Compare `$1C10==$1C14` and `$1C12==$1C16`. Equal: state 8.
5. State 8 (`$038342`): `$32=4, $70=0, $72=4`, which is the new-game init at `$0094C5`.
   Because `$1E02` is 1, that init skips `STZ $86`.

RAM the decoder writes: `$86` (stage block), `$88` (quest), scratch `$1C10-1C17`, `$1C00`.
Everything else comes from the new-game init (section 6). Example, name `A`, password bytes
`23 00 10 08`: `$86=$23`, `$88=0`, `$7C=5`, `$13F2=5`, `$13F4=$13F6=$10`, `$8E/$90/$92=0`, score 0.

## 5. Encoder (game over "PASSWORD")

- Game over screen is mode `$70 = 7` (routine `$0096D4` -> `$0CFD1B`; state `$72`). State 0 (`$0CFD32`)
  replaces `$86` with the stage start: `$86 = $01:FBAC[$86]` (table: blocks 0-7 -> 0, 8-11 -> 8,
  12-17 -> 0C, 18-23 -> 12 ... 0x42 -> 42). State 1 menu: CONTINUE / PASSWORD (`$68` 0/2, Up/Down/Select toggle).
  CONTINUE (`$0CFD9A`) resets lives 5, health `$10`, hearts 5, `$8E/$90/$92` 0, `$1600-04` 0, score
  `$1F40/42` 0, `$70=3` (reload the level at the stage start). PASSWORD goes to state 3
  and `JML $03845A`, the display handler (`$038470`).
- Display init (`$038470`, bank 03): `$0384B0` draws the name, `$0384DE` builds
  `$1C10-13 = [$86, $88, checksum lo, hi]`, `$038549` expands them with the same scramble table to
  `$1C20-2F` (raw bytes, not masked; drawing masks with 3), `$03857D` draws the cells.
- Reads: `$86`, `$88`, name `$1700-1707`. No randomness (hand-computed values match the game, see tests).
  One state and name give exactly one password.
- Start on the display (`$0384D2` clears `$32/$34`) resets the game to the Konami logo: no return to title.
- Observed (natural game over at block `$25`, name `A`): `$86` became `$23`, bytes `23 00 10 08`.

## 6. What a password restores

Restores: stage start block `$86` and quest `$88`. The rest is the new-game init
(`$0094C5-$00952A`), identical to what GAME OVER CONTINUE gives:

| field | password value | real play |
|---|---|---|
| `$86` stage block | stage start (rounded down via `$FBAC`) | any block, mid-stage |
| `$88` quest | exact (0 or 8 tested) | same |
| `$7C` lives | 5 | dropped |
| `$13F4` / `$13F6` health | `$10` | dropped |
| `$13F2` hearts | 5 | dropped |
| `$8E` subweapon / `$90` multi / `$92` whip | 0 | dropped |
| `$1F40/$1F42` score | 0 | dropped |
| `$1600/02/04`, `$13C2/C4`, `$13E2`, `$19C0-1A00`, `$7E` | cleared / defaults | dropped |
| `$13D4` entrance, mid-stage checkpoint | stage start | dropped |

Not yet compared against a full real-play WRAM diff beyond the progress block; a raw diff
of "password state" vs "new game" (`work/scv4/pw/a/r1.bin` vs `s_new.bin`) was dominated by
transient memory (OAM, DMA lists, stack), so use the second agent's progress variable list for that.

## 7. Test passwords (name `A`, verified by button entry and loading)

Name `A`, entered as in section 1. Cell grids are row-major, 0 blank, 1 whip, 2 potion, 3 heart.
Generator: `python3 work/scv4/pw/pwlib.py <NAME> <stage hex> <quest hex>`.

| stage start `$86` | quest `$88` | bytes | grid rows | result seen |
|---|---|---|---|---|
| `$00` (1-1) | 8 | `00 08 F5 07` | 3001 / 1003 / 2100 / 0300 | BLOCK 1-1, `$88=8` |
| `$12` (4-1) | 8 | `12 08 07 08` | 0001 / 2200 / 2301 / 0000 | BLOCK 4-1, `$88=8` |
| `$23` (7-1) | 0 | `23 00 10 08` | 0000 / 2300 / 0002 / 0100 | BLOCK 7-1, `$88=0` (also produced by the game itself) |
| `$40` (8-3) | 0 | `40 00 2D 08` | 0003 / 2000 / 0100 / 0210 | BLOCK 8-3, `$88=0` |

Other valid stage values: `08 0C 18 1A 2A 2E 37 3C 3F 41 42` (labels not checked). Changing the
name changes the checksum: the passwords above are only valid for name `A` alone (slots 1-7 empty).

## Open points

- Second-quest behavior beyond `$88=8` loading (what the game does differently) is not checked.
- B as name backspace, empty name, and the OPTION menu were not tested.
- The exact Konami-logo reset on leaving the password display means a save patch cannot hook
  "return to title" from there.
