#!/bin/bash
# Run several harness sessions in parallel, one row per run in a contact sheet.
#   harness/par.sh <rom> <name>:<cmdfile> [<name>:<cmdfile> ...]
# Each run gets its own work directory $WORK/<name> (battery file in
# $WORK/<name>/nv/snes/). Seed a battery file there before running to test
# loading. The combined sheet goes to $WORK/par.png.
set -e
here=$(cd "$(dirname "$0")" && pwd)
rom=$1; shift
work=${WORK:-work}
names=()
for arg in "$@"; do
  n=${arg%%:*}; f=${arg#*:}; names+=("$n")
  WORK=$work/$n SHEET=$work/$n/sheet.png "$here/run.sh" "$f" "$rom" >"$work/$n.log" 2>&1 &
done
wait
sheets=()
for n in "${names[@]}"; do [ -f "$work/$n/sheet.png" ] && sheets+=("$n=$work/$n/sheet.png"); done
[ ${#sheets[@]} -gt 0 ] && python3 "$here/sheet.py" --rows "$work/par.png" "${sheets[@]}"
