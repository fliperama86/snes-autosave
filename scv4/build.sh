#!/bin/bash
# Build the Super Castlevania IV battery-save patch.
#   scv4/build.sh us|jp [clean-rom]
# The clean ROMs are the Castlevania Anniversary Collection extracts,
# headerless: US CRC32 48344DCB, JP CRC32 32C06183.
# Default: scv4/rom/<region>.sfc.
# Outputs scv4/out/scv4-save-<region>.sfc and .ips.
set -e
here=$(cd "$(dirname "$0")" && pwd)
region=${1:-us}
case $region in
  us) want=48344DCB ;;
  jp) want=32C06183 ;;
  *) echo "region must be us or jp"; exit 1 ;;
esac
src=${2:-$here/rom/$region.sfc}
crc=$(python3 -c "import zlib,sys;print('%08X'%zlib.crc32(open(sys.argv[1],'rb').read()))" "$src")
[ "$crc" = $want ] || { echo "unexpected ROM CRC32 $crc (want $want)"; exit 1; }
out=$here/out/scv4-save-$region
mkdir -p "$here/out"
cp "$src" "$out.sfc"
asar -DREGION=$region "$here/src/main.asm" "$out.sfc"
python3 "$here/../tools/mkips.py" "$src" "$out.sfc" "$out.ips"
echo "built $out.sfc and $out.ips"
