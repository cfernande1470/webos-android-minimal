set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libandroid-runtime-sched
WORK=work-libandroid-runtime-sched-plt

rm -rf "$WORK"
mkdir -p "$WORK"

echo "--- find libandroid_runtime.so copies ---"
ssh root@$TV_IP "find '$ROOTFS' -type f -path '*/lib64/libandroid_runtime.so' 2>/dev/null" | tee "$WORK/files"

if [ ! -s "$WORK/files" ]; then
  echo "ERROR: no libandroid_runtime.so found"
  exit 1
fi

mkdir -p "$WORK/libs"

echo
echo "--- patch local copies ---"
i=0
patched_any=0

while IFS= read -r REM; do
  [ -n "$REM" ] || continue
  i=$((i+1))

  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  ORIG="$WORK/libs/$TAG.orig"
  PATCH="$WORK/libs/$TAG.patched"

  echo
  echo "=== [$i] $REM ==="
  scp "root@$TV_IP:$REM" "$ORIG" >/dev/null
  cp -a "$ORIG" "$PATCH"

  echo "--- relevant plt/symbols before ---"
  aarch64-linux-gnu-objdump -d "$PATCH" | grep -E '<set_sched_policy@plt>|<set_cpuset_policy@plt>' || true
  aarch64-linux-gnu-readelf -Ws "$PATCH" | grep -E 'set_sched_policy|set_cpuset_policy' || true

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
    raise RuntimeError(f"vaddr 0x{v:x} not in LOAD")

dis = run(["aarch64-linux-gnu-objdump", "-d", str(path)])

targets = [
    "set_sched_policy@plt",
    "set_cpuset_policy@plt",
]

patched = []

for target in targets:
    m = re.search(r"^\s*([0-9a-fA-F]+)\s+<" + re.escape(target) + r">:", dis, re.M)
    if not m:
        continue

    vaddr = int(m.group(1), 16)
    off = vaddr_to_off(vaddr)

    old = bytes(data[off:off+16])

    # AArch64:
    #   mov w0, #0
    #   ret
    #   nop
    #   nop
    new = bytes.fromhex("00008052c0035fd61f2003d51f2003d5")

    data[off:off+16] = new
    patched.append((target, vaddr, off, old.hex(), new.hex()))

if not patched:
    print("NO_PLT_TARGETS_FOUND")
    sys.exit(3)

path.write_bytes(data)

for target, vaddr, off, old, new in patched:
    print(f"PATCHED {target}: vaddr=0x{vaddr:x} file_off=0x{off:x} old={old} new={new}")
PY

  rc=$?
  if [ "$rc" = 0 ]; then
    patched_any=1
    echo "--- verify patched plt ---"
    aarch64-linux-gnu-objdump -d "$PATCH" | grep -A6 -E '<set_sched_policy@plt>|<set_cpuset_policy@plt>' || true
  else
    echo "SKIP: no set_sched_policy/set_cpuset_policy PLT in $REM"
    cp -a "$ORIG" "$PATCH"
  fi

done < "$WORK/files"

if [ "$patched_any" != 1 ]; then
  echo "ERROR: no libandroid_runtime.so PLT target was patched"
  exit 1
fi

echo
echo "--- upload and bind patched copies ---"
ssh root@$TV_IP "mkdir -p '$OVR'"

while IFS= read -r REM; do
  [ -n "$REM" ] || continue

  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  ORIG="$WORK/libs/$TAG.orig"
  PATCH="$WORK/libs/$TAG.patched"

  # Solo monta si cambió.
  if cmp -s "$ORIG" "$PATCH"; then
    echo "SKIP unchanged: $REM"
    continue
  fi

  REM_OVR="$OVR/$TAG"

  echo
  echo "=== bind patched $REM ==="
  scp "$PATCH" "root@$TV_IP:$REM_OVR" >/dev/null

  ssh root@$TV_IP "sh -s" <<EOF2
set -e
REM='$REM'
REM_OVR='$REM_OVR'

echo "--- unmount old bind if any ---"
while mount | grep -q " \$REM "; do
  umount "\$REM" 2>/dev/null || break
done

echo "--- bind patched runtime ---"
mount -o bind "\$REM_OVR" "\$REM"

echo "--- mount result ---"
mount | grep " \$REM " || true
ls -l "\$REM" "\$REM_OVR"
EOF2

done < "$WORK/files"

echo
echo "PATCH_LIBANDROID_RUNTIME_SET_SCHED_PLT_DONE"
