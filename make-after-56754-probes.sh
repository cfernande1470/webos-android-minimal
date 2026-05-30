#!/bin/sh
set -e

BASE=pulled/installd.force-4cf38-56754-success
OUTDIR=pulled/after-56754-probes
mkdir -p "$OUTDIR"

make_probe() {
  name="$1"
  va="$2"
  out="$OUTDIR/probe-$name"
  ./patch-va.py "$BASE" "$out" "$va" "00 00 00 14"
  chmod 755 "$out"
}

make_probe 5d284 0x5d284
make_probe 5d340 0x5d340
make_probe 5d344 0x5d344
make_probe 5d5d8 0x5d5d8
make_probe 5d5fc 0x5d5fc
make_probe 5d610 0x5d610
make_probe 5d614 0x5d614
make_probe 5d618 0x5d618
make_probe 5d620 0x5d620
make_probe 5d624 0x5d624
make_probe 5d638 0x5d638

ls -l "$OUTDIR"
