#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

mplab-gen firmware.X@default
log=$(mktemp)
trap 'rm -f "$log"' EXIT
# A rebuild that finds its outputs would run no compile command, so the compiler check needs a clean tree.
rm -rf firmware.X/build firmware.X/dist
xc-make -C firmware.X -j2 -f Makefile CONF=default 2>&1 | tee "$log"
grep -Eq '/opt/microchip/xc-dsc/v4\.00/bin/xc-dsc-gcc"? .* -c ' "$log" || { echo 'The build did not compile with XC-DSC 4.00' >&2; exit 1; }

test -s firmware.X/dist/default/production/firmware.X.production.hex
sha256sum firmware.X/dist/default/production/firmware.X.production.hex
