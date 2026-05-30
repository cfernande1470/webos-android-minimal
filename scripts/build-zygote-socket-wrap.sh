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
  -o build/zygote_socket_wrap-aarch64-static \
  src/zygote_socket_wrap.c

file build/zygote_socket_wrap-aarch64-static || true
ls -lh build/zygote_socket_wrap-aarch64-static
