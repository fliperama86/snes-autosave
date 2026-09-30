#!/bin/bash
# Run one MAME session driven by a command file, in a window by default.
#   harness/run.sh <cmdfile> <rom> [extra mame args]
# Env:
#   WORK   work directory for snapshots, states, battery files (default: work)
#   DEBUG  set to 1 to enable the debugger, needed by the 'bp' command
#   FAST     set to 1 to run the window unthrottled (about 10x)
#   HEADLESS set to 1 to run without a window, unthrottled
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
# A windowed MAME stops on a "press any key" warnings screen. It skips the
# screen when skip_warnings is set (harness/ini/ui.ini) and the cfg says the
# same warnings were shown recently, so seed that record with the time now.
mkdir -p "$work/cfg"
now=$(date +%s)
cat > "$work/cfg/snes.cfg" <<EOF
<?xml version="1.0"?>
<mameconfig version="10">
    <system name="snes">
        <ui_warnings launched="$now" warned="$now">
            <feature device="snes" type="graphics" status="imperfect" />
            <feature device="snes" type="sound" status="imperfect" />
        </ui_warnings>
    </system>
</mameconfig>
EOF
video=(-window -nomaximize -resolution 1024x896)
[ "${FAST:-0}" = 1 ] && video+=(-nothrottle)
[ "${HEADLESS:-0}" = 1 ] && video=(-video none -nothrottle)
HARNESS_CMDS=$cmds HARNESS_BPLOG=$work/bp.log mame snes \
  -rompath "$here/roms" -cart "$rom" \
  -inipath "$here/harness/ini;$HOME/Library/Application Support/mame;$HOME/.mame;.;ini" \
  "${video[@]}" -sound none -skip_gameinfo \
  -snapshot_directory "$work/snap" -state_directory "$work/sta" \
  -nvram_directory "$work/nv" -cfg_directory "$work/cfg" \
  -autoboot_script "$here/harness/run.lua" "${dbg[@]}" "$@" 2>&1 \
  | grep -v -E "^Warning|^Average speed" || true
if ls "$work"/snap/snes/*.png >/dev/null 2>&1; then
  python3 "$here/harness/sheet.py" "${SHEET:-$work/sheet.png}" "$work"/snap/snes/*.png
fi
