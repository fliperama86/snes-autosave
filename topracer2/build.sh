#!/bin/bash
# Build the Top Racer 2 battery-save patch.
#   topracer2/build.sh [clean-rom]
# The clean ROM is Top Racer 2 (Japan, Piko Interactive 2018 reissue),
# headerless, CRC32 F7665EAF. Default: topracer2/rom/base.sfc.
# Outputs topracer2/out/tr2-save.sfc and topracer2/out/tr2-save.ips.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=${1:-$here/rom/base.sfc}
crc=$(python3 -c "import zlib,sys;print('%08X'%zlib.crc32(open(sys.argv[1],'rb').read()))" "$src")
[ "$crc" = F7665EAF ] || { echo "unexpected ROM CRC32 $crc (want F7665EAF)"; exit 1; }
mkdir -p "$here/out"
cp "$src" "$here/out/tr2-save.sfc"
asar "$here/src/main.asm" "$here/out/tr2-save.sfc"
python3 "$here/../tools/mkips.py" "$src" "$here/out/tr2-save.sfc" "$here/out/tr2-save.ips"
echo "built $here/out/tr2-save.sfc and tr2-save.ips"
