#!/bin/sh
set -e

BASE=pulled/installd.no-selinux-status-open
OUTDIR=pulled/main-probes
mkdir -p "$OUTDIR"

make_probe() {
  name="$1"
  va="$2"
  out="$OUTDIR/probe-$name"
  ./patch-va.py "$BASE" "$out" "$va" "00 00 00 14"
  chmod 755 "$out"
}

make_probe 5d0a4 0x5d0a4   # antes de TLS/canary
make_probe 5d0b4 0x5d0b4   # antes de is_selinux_enabled
make_probe 5d0d4 0x5d0d4   # después de setenv
make_probe 5d140 0x5d140   # antes de InitLogging
make_probe 5d144 0x5d144   # después de InitLogging
make_probe 5d1b4 0x5d1b4   # antes de __android_log_buf_print
make_probe 5d1c8 0x5d1c8   # antes de call 0x4cf38
make_probe 5d1cc 0x5d1cc   # después de call 0x4cf38
make_probe 5d220 0x5d220   # antes de fs_read_atomic_int
make_probe 5d224 0x5d224   # después de fs_read_atomic_int
make_probe 5d340 0x5d340   # antes de opendir
make_probe 5d344 0x5d344   # después de opendir
make_probe 5d5d8 0x5d5d8   # antes del tramo final fs_write/selinux/register
make_probe 5d5fc 0x5d5fc   # justo antes de cmp w22
make_probe 5d610 0x5d610   # justo antes del call 0x1bca8

ls -l "$OUTDIR"
