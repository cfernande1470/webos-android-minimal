set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libcutils-sched
WORK=work-libcutils-sched-patch

mkdir -p "$WORK"

echo "--- find libcutils copies on TV ---"
ssh root@$TV_IP "find '$ROOTFS' -type f -path '*/lib64/libcutils.so' 2>/dev/null" | tee "$WORK/libcutils.files"

if [ ! -s "$WORK/libcutils.files" ]; then
  echo "ERROR: no lib64/libcutils.so found"
  exit 1
fi

echo
echo "--- copy libs from TV ---"
rm -rf "$WORK/libs"
mkdir -p "$WORK/libs"

i=0
while IFS= read -r REM; do
  [ -n "$REM" ] || continue
  i=$((i+1))
  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  LOC="$WORK/libs/$TAG.orig"
  PATCH="$WORK/libs/$TAG.patched"

  echo
  echo "=== [$i] $REM ==="
  scp "root@$TV_IP:$REM" "$LOC" >/dev/null
  cp -a "$LOC" "$PATCH"

  echo "--- symbols before ---"
  aarch64-linux-gnu-readelf -Ws "$PATCH" | grep -E ' set_sched_policy$| set_cpuset_policy$' || true

  python3 - "$PATCH" <<'PY'
from pathlib import Path
import subprocess
import sys
import re

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())

def run(cmd):
    return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)

ph = run(["aarch64-linux-gnu-readelf", "-lW", str(path)])
segs = []
for line in ph.splitlines():
    parts = line.split()
    if len(parts) >= 6 and parts[0] == "LOAD":
        off = int(parts[1], 16)
        vaddr = int(parts[2], 16)
        filesz = int(parts[4], 16)
        segs.append((vaddr, vaddr + filesz, off))

def vaddr_to_off(v):
    for start, end, off in segs:
        if start <= v < end:
            return off + (v - start)
    raise RuntimeError(f"vaddr 0x{v:x} not in LOAD segments")

syms = run(["aarch64-linux-gnu-readelf", "-Ws", str(path)])
targets = {"set_sched_policy", "set_cpuset_policy"}
patched = []

for line in syms.splitlines():
    parts = line.split()
    if len(parts) < 8:
        continue
    # Num: Value Size Type Bind Vis Ndx Name
    typ = parts[3]
    ndx = parts[6]
    name = parts[7].split("@", 1)[0]
    if typ != "FUNC" or ndx == "UND" or name not in targets:
        continue

    v = int(parts[1], 16)
    off = vaddr_to_off(v)

    old = bytes(data[off:off+8])
    # aarch64:
    #   mov w0, #0
    #   ret
    new = bytes.fromhex("00008052c0035fd6")

    data[off:off+8] = new
    patched.append((name, v, off, old.hex(), new.hex()))

if not patched:
    print("ERROR: no target symbols patched")
    sys.exit(2)

path.write_bytes(data)

for name, v, off, old, new in patched:
    print(f"PATCHED {name}: vaddr=0x{v:x} file_off=0x{off:x} old={old} new={new}")
PY

  echo "--- verify patch marker bytes ---"
  aarch64-linux-gnu-objdump -d "$PATCH" | grep -A4 -E '<set_sched_policy>|<set_cpuset_policy>' || true

done < "$WORK/libcutils.files"

echo
echo "--- upload patched libs and bind-mount over originals ---"
ssh root@$TV_IP "mkdir -p '$OVR'"

i=0
while IFS= read -r REM; do
  [ -n "$REM" ] || continue
  i=$((i+1))
  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  PATCH="$WORK/libs/$TAG.patched"
  REM_OVR="$OVR/$TAG"

  echo
  echo "=== bind [$i] $REM ==="
  scp "$PATCH" "root@$TV_IP:$REM_OVR" >/dev/null

  ssh root@$TV_IP "sh -s" <<EOF2
set -e
REM='$REM'
REM_OVR='$REM_OVR'

echo "--- before mounts for \$REM ---"
mount | grep " \$REM " || true

while mount | grep -q " \$REM "; do
  umount "\$REM" 2>/dev/null || break
done

mount -o bind "\$REM_OVR" "\$REM"

echo "--- after mount ---"
mount | grep " \$REM " || true

echo "--- first bytes of symbols if available ---"
ls -l "\$REM" "\$REM_OVR"
EOF2

done < "$WORK/libcutils.files"

echo
echo "PATCH_AND_BIND_LIBCUTILS_SCHED_DONE"
