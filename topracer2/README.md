# Top Racer 2 battery save

Adds automatic battery saving to Top Racer 2 (Japan, Piko Interactive 2018
reissue). Confirmed working on an SD2SNES.

## Patch

`tr2-save.ips` in this folder applies to the clean ROM below with any IPS
patcher.

## Build

```
topracer2/build.sh [clean-rom]
```

The clean ROM must be headerless, CRC32 `F7665EAF` (default
`topracer2/rom/base.sfc`). Output: `topracer2/out/tr2-save.sfc` and
`tr2-save.ips`.

## How it plays

- The game saves before every race and after every qualifying race, once
  the results and standings screens are done.
- To resume, pick CONTINUE, then PASSWORD. The screen is filled with the
  saved game. Confirm it unchanged to continue at the exact race, with money,
  upgrades and the full championship standings.
- A typed password works as in the original game.
- RACE GAME starts a new championship, which replaces the save once its
  first race starts.
- Failing to qualify leaves the save at the start of that race.
- The attract demo never saves.

## Game notes

| what | where |
|---|---|
| progress block | `$7E1CDB-$7E1DF2` (bytes `$1CD7-$1CDA` hold a boot signature) |
| standings table | `$7EF000-$7EF17F` |
| country / race in country / money | `$7E1CE1` / `$7E1CE5` / `$7E1D19` |
| pre-race snapshot | `$9F81A6` copies both areas to `$7EFD00`; `$9F81F8` restores after the race |
| post-race progression | `$9FF460`, then results and standings screens at `$9FE343` |
| password encoder / decoder | `$9FD7AE` / `$9FD922`; buffer `$7E1780` (22 ASCII chars), entry grid `$7E17D7` |
| password accept | `$9FD3E9`; afterwards the new-championship setup at `$9F8085-$9F80AE` resets driver order and standings |
| new game setup | `$9FDE78` |
| attract demo | title idle timer at `$9FC7F8` sets bit 3 of `$7E0022` |
| free space | banks `$A1-$AF` are empty padding; the patch uses `$AF8000` |

The password only encodes the country, so continuing by password alone
restarts the country and drops the other drivers' points. See the comments
in `src/main.asm` for the hooks and the SRAM layout.

## Tests

`tests/run_tests.sh` runs seven checks in MAME in about 90 seconds: saving
after a race, the save matching live state, no save from the demo, an exact
resume, saving again after a resumed race, a new game replacing the save,
and a typed password not being replaced.
