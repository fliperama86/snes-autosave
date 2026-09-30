# Playbook: adding battery saves to a SNES game

How the Top Racer 2 patch was built, written so the same steps apply to the
next game. Each step says what to look for, how to find it with the tools in
this repo, and what went wrong the first time.

## 0. Before starting

- **Look for prior art.** Search romhacking.net and similar sites for an
  existing SRAM or save patch for the game and the exact ROM revision. A
  finished patch may already exist, or a disassembly that names the RAM.
- **Identify the exact ROM.** Run `tools/romhdr.py`. Note the CRC32, the map
  mode (LoROM or HiROM), whether the header already declares SRAM, and
  whether a 512-byte copier header is present (strip it first). Reissues and
  translations differ from the original release, so pin the CRC in the build
  script.
- **Find free space.** `romhdr.py` lists runs of `$00`/`$FF`. Whole empty
  banks at the end of the image are the easiest home for new code. If there
  are none, the ROM can be expanded, which changes the header size byte.

## 1. Learn the game's flow in the harness

Boot the game headless (`harness/run.sh`) with `snap` every 100 frames or so
and look at the contact sheet. Then map the menus by probing: run the same
state with different buttons in parallel (`harness/par.sh`) and compare one
screenshot per run. Button meanings are often not what you expect (in Top
Racer 2 every button toggled 1P/2P, and the real start was a menu item). Use
`save`/`load` to checkpoint a menu so each probe starts from there, but note
that MAME save states break when the ROM changes, so re-derive them from boot
for patched builds.

Hold buttons for at least 3 to 6 frames: some games poll input every other
frame or act on release.

## 2. Find the progress state

The goal is the set of RAM bytes that make up "your game": level or race,
money, upgrades, lives, unlocked items, standings.

- **If the game has passwords, start there.** The password is the
  developers' own list of what matters. Open the password screen and dump
  WRAM (`dump 7E0000 20000`). Search it for the displayed characters under a
  few encodings: ASCII, index into the password alphabet, tile numbers.
- **Find the encoder.** `watch` the password buffer: the writer's PC is the
  encoder. Disassemble it (`tools/dis.py`). An encoder is a list of
  "load variable, pack with radix N" steps, so it names every progress
  variable and its range.
- **Check what the password leaves out.** Top Racer 2's password stored only
  the country, not the race within it, and none of the other drivers'
  points. Restoring through the password alone would have lost progress.
  Compare a password continue with the real state before relying on it.
- **Without passwords,** diff WRAM before and after a progress event (beating
  a level, buying an item) and keep the bytes that change consistently.

The progress variables usually sit in one contiguous block. Find its bounds;
the whole block is easier and safer to save than a list of fields.

## 3. Find where the game commits progress

You need moments when the state is complete and consistent.

- **Look for existing snapshot code.** Games whose race or level engine
  reuses the menu RAM keep a copy of the progress block across the
  transition. Top Racer 2 copied it (with a checksum) before every race and
  restored it after. `watch` the progress block during a transition and look
  for a bulk copy; `stackon` on the copy's first write gives the caller.
- **Find the post-event update.** `watch` the level/money variables across
  the end of a level to find the code that applies the result. Then check
  whether later screens (results, standings) still change the block. In Top
  Racer 2 the results screen added the championship points after the money
  and race index were updated, so the save had to go after that screen.
- **Beware WRAM clears.** Program transitions may clear most of WRAM (a DMA
  fill) and rebuild it from the snapshot. A flag you keep in WRAM may not
  survive; keep patch state in SRAM.

Prefer saving at the end of a complete step over saving the moment one value
changes. A save that holds "race counted but points not awarded" is worse
than losing the race.

## 4. Tell real play from the attract demo

The demo usually runs the same code paths as real play and will overwrite a
save if not excluded. Find the demo trigger (the title's idle timer: `watch`
the variables that change when the demo starts) and look for a flag it sets.
In Top Racer 2 the idle timer set bit 3 of `$7E0022`. Verify the flag in all
three cases: demo, real play, and real play started after a demo ran.

Do not trust a variable's name from one observation. `$7E1DF1` looked like a
demo flag (2 in the demo, 0 in a race) but was the next-program selector.

## 5. Design the save

- **Header:** set the cartridge type byte (`$FFD6` in the LoROM header,
  `$02` = ROM + RAM + battery) and the SRAM size byte (`$FFD8`, size is
  `1 KB << n`, `$03` = 8 KB). asar recomputes the checksum.
- **Where SRAM lives:** LoROM `$70-$7D:0000-7FFF`; HiROM `$20-$3F:6000-7FFF`
  (and mirrors). Emulators and flash carts follow the header.
- **Format:** two slots written alternately, each with a magic, a sequence
  number and a checksum. Invalidate the target slot's magic first, write the
  data, then the checksum, then the magic. The newest valid slot wins, so a
  power cut mid-write leaves the previous save.
- **What to store:** the whole progress block plus any tables it depends on,
  copied from live RAM.

## 6. Design the load

Two options, in order of preference:

1. **Through the game's own continue path.** Top Racer 2 fills its password
   screen from the current state. The patch fills it from the save instead,
   and when that password is confirmed unchanged, restores the full block.
   The player sees a familiar screen, typed passwords keep working, and the
   game's own setup code runs.
2. **At boot.** Copy the save into RAM before the title. Simpler, but the
   title, demo or new-game code may reinitialize parts of it, and there is no
   way to start fresh without a menu option.

Apply the restore after the game's own setup, not before it. Top Racer 2's
password path ran a new-championship setup afterwards that reset the driver
order and standings, which overwrote a restore done at password time. The
fix was a pending flag set when the password matches, applied at the end of
that setup, and cleared by the new-game code.

## 7. Hooking techniques (65816)

- **Hook with JSL.** Overwrite at least 4 bytes of whole instructions with
  `JSL hook`, pad with `NOP`, and replay the overwritten instructions inside
  the hook. Keep the result registers and flags the original code expects
  after the hook (for example the Z flag feeding a following `BNE`).
- **Check branch targets.** No jump or branch may land inside the replaced
  bytes, except at its first byte. `tools/xref.py` finds JSR/JMP/JSL; also
  scan for relative branches into the range.
- **Know the register widths** at each hook site (`dis.py --m/--x`), and set
  them explicitly in the hook (`REP #$30`). Save and restore A, X, Y, P and
  the data bank if you change them.
- **Use long addressing** (`LDA.l $7E1CE5`, `STA.l $700000,X`) so the hook
  does not depend on the caller's data bank.
- **Block moves:** `MVN` is encoded `54 dst src` and sets the data bank to
  the destination, so wrap it in `PHB`/`PLB`. After it, X and Y point past the
  copied ranges, which chains a second copy nicely.
- **Calling a bank-local subroutine from your bank.** A routine that ends in
  `RTS` cannot be `JSL`ed. Push a return for `RTL`, then push the address of
  any `$6B` (RTL) byte in the routine's bank minus one, and `JML` in:

  ```
  phk
  pea.w ret-1
  pea.w rtl_in_that_bank-1
  jml routine
  ret:
  ```

  The routine's `RTS` lands on the `RTL`, which returns to `ret`. Any `$6B`
  byte works, even inside data, because execution jumps straight to it.

## 8. Testing

- **Automate the long path.** Reaching a save point may need finishing a
  level. For racing games the `auto` command steers on a lateral-position
  variable (found by diffing RAM after steering left, straight and right);
  `pin` forces a variable, such as race position, every frame.
- **Power cycles** are just separate MAME runs sharing the battery file
  (`$WORK/nv/snes/<rom>.nv`). Seed a run's `nv` folder with a saved file to
  test loading, as `topracer2/tests/run_tests.sh` does.
- **Compare bytes, not screens.** Dump the live block after a resume and
  compare it with the save. Screens then confirm the flow.
- **Test the negatives:** the demo saves nothing, a new game replaces the
  save, a typed password is not overridden, and a failed attempt leaves the
  previous save.
- **Real hardware:** SD2SNES/FXPak and MiSTer read the header. Old save
  states of the unpatched ROM are not compatible with the patched one.

## 9. Harness pitfalls that cost time

- Commands run in frame order; before that was enforced, one late line at
  the top of a file silently delayed every input, and several traces
  recorded the attract demo instead of real play. When a trace makes no
  sense, look at a screenshot from the same run first.
- Write taps must stay referenced from Lua or they are garbage collected
  and silently stop.
- Low WRAM is written through bank mirrors; `watch` taps all of them for
  addresses below `$7E2000`, and plain taps elsewhere.
- `soft_reset` re-runs the autoboot script, so the harness guards against
  loading twice.
- MAME fills WRAM on reset, so it cannot test "survives reset" behavior of
  real hardware.
- A text-input screen may keep typed characters somewhere other than the
  buffer the game checks (Top Racer 2 copies a grid into the buffer on
  confirm), so poke the source, not the buffer.
- MAME needs the 64-byte SPC700 boot ROM (`roms/snes/spc700.rom`, CRC32
  `44BB3A40`), which is not in this repo.
