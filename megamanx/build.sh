#!/bin/bash
# Build the Mega Man X battery-save patch.
#   megamanx/build.sh [clean-rom]
# The clean ROM is Mega Man X as extracted from the Mega Man X Legacy
# Collection (US 1.0 code), headerless, CRC32 97A10846.
# Default: megamanx/rom/base.sfc.
# Outputs megamanx/out/mmx-save.sfc and megamanx/out/mmx-save.ips.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=${1:-$here/rom/base.sfc}
crc=$(python3 -c "import zlib,sys;print('%08X'%zlib.crc32(open(sys.argv[1],'rb').read()))" "$src")
[ "$crc" = 97A10846 ] || { echo "unexpected ROM CRC32 $crc (want 97A10846)"; exit 1; }
mkdir -p "$here/out"
cp "$src" "$here/out/mmx-save.sfc"
asar "$here/src/main.asm" "$here/out/mmx-save.sfc"
python3 "$here/../tools/mkips.py" "$src" "$here/out/mmx-save.sfc" "$here/out/mmx-save.ips"
echo "built $here/out/mmx-save.sfc and mmx-save.ips"
