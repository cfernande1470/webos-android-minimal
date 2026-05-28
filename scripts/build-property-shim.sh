#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build

CC_BIN="${CC:-}"
if [ -z "$CC_BIN" ]; then
  if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    CC_BIN=aarch64-linux-gnu-gcc
  else
    CC_BIN=gcc
  fi
fi

"$CC_BIN" -static -O2 -Wall -Wextra \
  -o build/property_service_ack_shim-aarch64-static \
  src/property_service_ack_shim.c

file build/property_service_ack_shim-aarch64-static || true
ls -lh build/property_service_ack_shim-aarch64-static
