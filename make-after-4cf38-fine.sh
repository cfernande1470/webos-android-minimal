#!/bin/sh
set -e

BASE=pulled/installd.force-4cf38-success
OUTDIR=pulled/after-4cf38-fine
mkdir -p "$OUTDIR"

make_probe() {
  name="$1"
  va="$2"
  out="$OUTDIR/probe-$name"
  ./patch-va.py "$BASE" "$out" "$va" "00 00 00 14"
  chmod 755 "$out"
}

make_probe 5d224 0x5d224   # después de fs_read_atomic_int
make_probe 5d254 0x5d254   # rama si fs_read_atomic_int falla
make_probe 5d274 0x5d274   # antes de call 0x56754
make_probe 5d27c 0x5d27c   # después de call 0x56754
make_probe 5d284 0x5d284   # logging siguiente
make_probe 5d2a0 0x5d2a0   # construcción ruta 1
make_probe 5d2d8 0x5d2d8   # construcción ruta 2
make_probe 5d308 0x5d308   # construcción ruta 3
make_probe 5d338 0x5d338   # justo antes de opendir path
make_probe 5d340 0x5d340   # opendir

ls -l "$OUTDIR"
