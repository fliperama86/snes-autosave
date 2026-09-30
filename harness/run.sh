#!/bin/bash
# Run one headless MAME session driven by a command file.
#   harness/run.sh <cmdfile> <rom> [extra mame args]
# Env:
#   WORK   work directory for snapshots, states, battery files (default: work)
#   DEBUG  set to 1 to enable the debugger, needed by the 'bp' command
#   SHEET  contact sheet path (default: $WORK/sheet.png)
# Paths in the command file are relative to the current directory.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
cmds=$1; rom=$2; shift 2
work=${WORK:-work}
mkdir -p "$work"
rm -rf "$work/snap/snes"
dbg=()
[ "${DEBUG:-0}" = 1 ] && dbg=(-debug -debugger none)
HARNESS_CMDS=$cmds HARNESS_BPLOG=$work/bp.log mame snes \
  -rompath "$here/roms" -cart "$rom" \
  -video none -sound none -nothrottle -skip_gameinfo \
  -snapshot_directory "$work/snap" -state_directory "$work/sta" \
  -nvram_directory "$work/nv" -cfg_directory "$work/cfg" \
  -autoboot_script "$here/harness/run.lua" "${dbg[@]}" "$@" 2>&1 \
  | grep -v -E "^Warning|^Average speed" || true
if ls "$work"/snap/snes/*.png >/dev/null 2>&1; then
  python3 "$here/harness/sheet.py" "${SHEET:-$work/sheet.png}" "$work"/snap/snes/*.png
fi
