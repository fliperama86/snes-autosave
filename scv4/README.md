# Super Castlevania IV battery save

Adds automatic battery saving to Super Castlevania IV (US) and Akumajou
Dracula (JP), using the ROMs from the Castlevania Anniversary Collection.

## Patch

`scv4-save-us.ips` and `scv4-save-jp.ips` in this folder apply to the ROMs
below with any IPS patcher.

## Build

```
scv4/build.sh us|jp [clean-rom]
```

| region | ROM | CRC32 |
|---|---|---|
| `us` | Super Castlevania IV (USA), Anniversary Collection | `48344DCB` |
| `jp` | Akumajou Dracula (Japan), Anniversary Collection | `32C06183` |

Both headerless; default `scv4/rom/us.sfc` and `scv4/rom/jp.sfc`. The
cartridge dumps (`B64FFB12`, `EDA59A2A`) are not supported yet. Output:
`scv4/out/scv4-save-<region>.sfc` and `.ips`.

## How it plays

- The game saves every time a block starts: after finishing a block, after
  a death and after a continue.
- A new game started with START does not touch the save until the player
  reaches the second block. The attract demo never saves.
- To resume, pick CONTINUE and enter any name. The password grid opens
  filled with the password for the saved stage under that name. Confirm it
  unchanged to continue at the exact block with everything the password
  drops: lives, hearts, health, whip, subweapon, multi-shot, score and timer.
- A typed password works as in the original game.

## Game notes

The US and JP ROMs run the same code at the same addresses; only data
tables moved (the stage-start table is `$81FBAC` in US, `$81FBA2` in JP).
Detailed research: [notes-state.md](notes-state.md) and
[notes-password.md](notes-password.md).

| what | where |
|---|---|
| block / quest | `$86` / `$88` |
| lives / extra-life counter (BCD) | `$7C` / `$7E` |
| subweapon / multi-shot / whip | `$8E` / `$90` / `$92` |
| timer / hearts / health (BCD) | `$13F0` / `$13F2` / `$13F4` |
| score (BCD, 4 bytes) | `$1F40` |
| event flags, table cleared by new game | `$1600-$1605`, `$19C0-$19FF` |
| game mode | `$70` (3 block setup, 4 fade-in, 5 play, 7 game over) |
| attract demo flag | `$4A` = 1 |
| block entry, mode 4 to 5 (save hook) | `$8095FB` |
| new-game setup, also after a password (restore hook at its end) | `$8094C5-$80952E` |
| password grid: cells, name | `$7E1C20-$1C2F` (values 0-3), `$7E1700` (8 bytes) |
| grid entry init (prefill hook) / accepted (state 8) | `$838272` / `$838347` |
| password build / expand | `$8384DE` / `$838549` (DB = `$01`) |
| free space | `$9FF3C4-$9FFFFF` (patch code from `$9FF400`) |

The password holds only the stage start and the quest, checksummed with the
name. The game has no copy protection that probes SRAM. An earlier SRAM hack
exists (BillyTime! Games, romhacking.net 6534) for the cartridge US dump; it
saves per level and loads through a hidden options-menu input.

See the comments in `src/main.asm` for the hooks and the SRAM layout.

## Tests

`tests/run_tests.sh` runs 25 checks in MAME in about a minute, US and JP in
parallel: saving at a block change with exact equipment, no save in 1-1-1 of
a new game or from the attract demo, an exact resume through the prefilled
grid, a typed password not being replaced, saving after a death and after a
game-over continue (including one back to 1-1-1), and a new game leaving the
save alone.
