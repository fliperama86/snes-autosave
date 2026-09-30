# Mega Man X battery save

Adds automatic battery saving to Mega Man X, using the ROM from the Mega Man
X Legacy Collection.

## Patch

`mmx-save.ips` in this folder applies to the ROM below with any IPS patcher.

## Build

```
megamanx/build.sh [clean-rom]
```

The ROM must be headerless, CRC32 `97A10846` (default
`megamanx/rom/base.sfc`). This is the Legacy Collection extract: US 1.0 code
plus a few stubs that write to unused registers `$21F0`/`$21FE`/`$21FF`
(host notifications for the collection's emulator; real hardware ignores
them). The US cartridge dump (CRC32 `1033EBA4`) is not supported yet.
Output: `megamanx/out/mmx-save.sfc` and `mmx-save.ips`.

## How it plays

- The game saves every time the stage select screen opens: after the intro
  stage, a cleared stage, ESCAPE.U or a game over.
- To resume, pick PASS WORD on the title screen. The grid is filled with the
  saved game's password. Confirm it unchanged to continue with everything,
  including what passwords drop: lives, sub tank energy and the Hadouken.
- A typed password works as in the original game.
- GAME START begins a new game, which replaces the save when its stage
  select first opens.
- The attract demo never saves.

## Game notes

| what | where |
|---|---|
| progress block (new game clears exactly this) | `$7E1F7A-$7E1F9C` |
| stage cursor / fortress / Hadouken / lives | `$1F7A` / `$1F7B` / `$1F7E` / `$1F80` |
| sub tanks / weapons / armor / max HP / intro done / heart tanks | `$1F83-86` / `$1F88-97` / `$1F99` / `$1F9A` / `$1F9B` / `$1F9C` |
| stage select state 0 (save hook) | `$80BCF7` |
| password entry screen | `$80EF4A` input, `$80EF2C` init copies `$7EFFCB` into the digits; D = `$1E48`, digits at `$7E1E60` stored as value-1 |
| password encoder / decoder | `$80F0A6` (uses the RNG, so one state has many passwords) / `$80F1A2`, applied at `$80F24A-$80F2DF` |
| new game setup | `$8094E7` |
| free space | bank `$AB` from `$AB8000` (the patch code) |

### Copy protection

The game probes the SRAM area and cripples itself when it finds SRAM, so a
battery save needs these probes neutralized:

| probe | counter | patched to its "no SRAM" branch |
|---|---|---|
| every frame, `STA/CMP $700800` | `$83` | `$81816B` |
| falling, `$700804` | `$1F9E` | `$818526` |
| taking damage, `$700505` | `$1F9F` | `$849D07` |
| enemy destroyed, `$701000` | `$1F9D` | `$84A46D` |

Tamper checks at `$81942E`, `$819602`, `$819950`, `$848FCD`, `$849F97` and
`$84A3BF` compare single bytes of the probe routines; the patch leaves those
bytes unchanged. The ROM mirroring checks (`$818242`, `$849FBB`, `$84A413`)
compare bank `$00` with bank `$40` and pass on any LoROM mapper, so they are
left alone. `$809AD6` increments a word at `$70000D` (debug leftover), so the
save slots avoid the first bytes of SRAM.

See the comments in `src/main.asm` for the hooks and the SRAM layout.

## Tests

`tests/run_tests.sh` runs twelve checks in MAME in about 90 seconds: saving
at stage select, the save matching live state, no save from the attract
demo, an exact resume, a typed password not being replaced, saving after
ESCAPE.U and after a game over (both show a password screen, then stage
select), the protection counters staying at 0, and a new game leaving the
save alone until its stage select.
