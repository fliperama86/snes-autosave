# snes-autosave

Battery-save patches for SNES games that only have passwords, plus the
toolkit and notes used to build them.

| folder | contents |
|---|---|
| `topracer2/` | Top Racer 2 (Japan, Piko 2018 reissue): patch source, build, tests |
| `harness/` | headless MAME harness: scripted input, screenshots, memory dumps, write and breakpoint tracing |
| `tools/` | disassembler, cross-references, ROM header and free space, IPS writer |
| `docs/` | [playbook](docs/playbook.md) for adding saves to a new game, [harness reference](docs/harness.md) |

## Requirements

- `mame` (tested with 0.284), `asar` (1.91), Python 3 with Pillow.
- The SNES sound CPU boot ROM for MAME at `roms/snes/spc700.rom`
  (64 bytes, CRC32 `44BB3A40`). It is Nintendo code and is not included.
- Your own copy of each game's ROM, headerless. ROMs are not included; each
  game folder says which dump it expects and where to put it.

## Quick start

```
topracer2/build.sh path/to/top-racer-2.sfc   # patched ROM + IPS in topracer2/out
topracer2/tests/run_tests.sh                 # needs topracer2/rom/base.sfc
```

## Adding a game

Make a folder for it next to `topracer2/` with its own `src/`, `build.sh`,
`tests/` and README, and follow the [playbook](docs/playbook.md).
