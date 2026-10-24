#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

mplab-gen firmware.X@default
xc-make -C firmware.X -j2 -f Makefile CONF=default

test -s firmware.X/dist/default/production/firmware.X.production.hex
# Compilation at the project's default optimisation level does not exercise the licence check.
status=$(xclm -status)
printf '%s\n' "$status"
if ! grep -Eq 'Product: xc16 .*Mode: PRO' <<< "$status"; then
  echo 'XC16 is not in PRO mode' >&2
  exit 1
fi
sha256sum firmware.X/dist/default/production/firmware.X.production.hex
