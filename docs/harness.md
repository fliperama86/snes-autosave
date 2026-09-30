# Harness reference

`harness/run.lua` drives MAME's `snes` driver from a command file. Runs are
headless and about 10 times faster than real time.

## Running

```
harness/run.sh <cmdfile> <rom> [extra mame args]
harness/par.sh <rom> <name>:<cmdfile> [<name>:<cmdfile> ...]
```

| variable | meaning |
|---|---|
| `WORK` | work directory for snapshots, states and battery files (default `work`) |
| `DEBUG=1` | enable the debugger, needed by `bp` |
| `SHEET` | where `run.sh` writes the contact sheet (default `$WORK/sheet.png`) |

`par.sh` gives each run the work directory `$WORK/<name>` and stacks their
sheets into `$WORK/par.png`. Battery files are at
`$WORK/<name>/nv/snes/<rom name>.nv`; copy one there before a run to start
with a save.

## Command file

One command per line: `<frame> <command> [args]`. Frames count from the
start of the run, and commands run in frame order. `#` starts a comment.
Addresses and byte values are hex; frame counts and lengths in `hold` and
`auto` are decimal.

| command | effect |
|---|---|
| `hold <frames> <Btn[,Btn]>` | hold buttons: `A B X Y L R Up Down Left Right Start Select` |
| `snap` | screenshot |
| `dump <addr> <len> <file>` | write CPU memory to a file |
| `loadbin <addr> <file> [skip]` | write a file into memory |
| `poke <addr> <byte>` | write one byte |
| `pin <addr> <byte>` / `unpin` | rewrite a byte every frame / stop all pins |
| `save <name>` / `load <name>` | MAME save states (tied to the exact ROM) |
| `reset` / `hardreset` | soft or hard reset |
| `watch <addr> <len> <file>` | log every write: `frame pc addr byte` |
| `stackon <addr> <file> [peek...]` | on a write to addr, log PC, S, the 8 bytes above S (return addresses) and 16-bit values at the peek addresses |
| `dumpon <addr> <prefix> [start len]` | on a write to addr, dump memory (default low WRAM) to `<prefix>_<frame>.bin` |
| `bp <addr>` | log `frame pc` when execution reaches addr (needs `DEBUG=1`, log in `$WORK/bp.log`) |
| `auto <addr> <frames> [target] [band] [gas] [invert]` | hold `gas` (default X) and steer to keep the signed word at addr within band of target |
| `exit` | close logs and quit (battery file is written on exit) |

## Tools

| tool | use |
|---|---|
| `tools/romhdr.py <rom>` | header, CRC32, checksum, free space |
| `tools/dis.py <rom> <addr> [n] [--m 0] [--x 0] [--hirom]` | disassemble |
| `tools/xref.py <rom> <addr>... [--hirom]` | find JSL/JML/JSR/JMP to an address |
| `tools/mkips.py <orig> <patched> <out.ips>` | write an IPS patch |
| `harness/sheet.py` | contact sheets (used by the scripts) |
