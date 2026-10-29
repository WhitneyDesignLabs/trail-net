#!/bin/bash
# build.sh - trail-net: assemble the NET file with Ophis (github.com/michaelcmartin/Ophis): OPHIS=<ophis> bash build.sh
# -> NET.bin (at most 1,536 B, loaded at aux $3A00). Nothing outside this folder is read.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
"${OPHIS:-ophis}" net_top.s -o NET.bin
n=$(wc -c < NET.bin)
[ "$n" -le 1536 ] || { echo "build.sh: NET.bin is $n bytes, over 1,536"; exit 1; }
echo "build.sh: NET.bin $n bytes"
