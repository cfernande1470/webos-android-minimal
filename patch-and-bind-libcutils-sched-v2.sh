set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libcutils-sched-v2
WORK=work-libcutils-sched-v2

rm -rf "$WORK"
mkdir -p "$WORK/libs"

echo "--- find libcutils copies on TV ---"
ssh root@$TV_IP "find '$ROOTFS' -type f -path '*/lib64/libcutils.so' 2>/dev/null" | tee "$WORK/libcutils.files"

[ -s "$WORK/libcutils.files" ] || {
  echo "ERROR: no lib64/libcutils.so found"
  exit 1
}

patched_any=0

echo
echo "--- patch local copies, skip ones without symbols ---"
while IFS= read -r REM; do
  [ -n "$REM" ] || continue

  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  ORIG="$WORK/libs/$TAG.orig"
  PATCH="$WORK/libs/$TAG.patched"

  echo
  echo "=== $REM ==="
  scp "root@$TV_IP:$REM" "$ORIG" >/dev/null
  cp -a "$ORIG" "$PATCH"

  echo "--- symbols ---"
  aarch64-linux-gnu-readelf -Ws "$PATCH" | grep -E 'set_sched_policy|set_cpuset_policy|SetTaskProfiles|set_task_profiles' || true

  if python3 - "$PATCH" <<'PY'
from pathlib import Path
import subprocess
import sys

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

syms = run(["aarch64-linux-gnu-readelf", "-Ws", str(path)])

target_substrings = [
    "set_sched_policy",
    "set_cpuset_policy",
    "SetTaskProfiles",
    "set_task_profiles",
]

patched = []
seen = set()

for line in syms.splitlines():
    parts = line.split()
    if len(parts) < 8:
        continue

    value_s = parts[1]
    size_s = parts[2]
    typ = parts[3]
    ndx = parts[6]
    name = parts[7]

    clean = name.split("@", 1)[0]

    if typ != "FUNC" or ndx == "UND":
        continue

    if not any(t in clean for t in target_substrings):
        continue

    try:
        vaddr = int(value_s, 16)
        size = int(size_s, 10)
    except Exception:
        continue

    if vaddr == 0 or vaddr in seen:
        continue

    # No parchear wrappers minúsculos de tamaño raro si son thunks vacíos, pero permitir size=0 en stripped dynsym.
    off = vaddr_to_off(vaddr)
    old = bytes(data[off:off+8])

    # AArch64:
    #   mov w0, #0
    #   ret
    new = bytes.fromhex("00008052c0035fd6")
    data[off:off+8] = new

    patched.append((clean, vaddr, off, size, old.hex(), new.hex()))
    seen.add(vaddr)

if not patched:
    print("NO_TARGET_SYMBOLS_IN_THIS_LIB")
    sys.exit(10)

path.write_bytes(data)

for clean, vaddr, off, size, old, new in patched:
    print(f"PATCHED {clean}: vaddr=0x{vaddr:x} off=0x{off:x} size={size} old={old} new={new}")
PY
  then
    if ! cmp -s "$ORIG" "$PATCH"; then
      patched_any=1
      echo "--- patched disasm snippets ---"
      aarch64-linux-gnu-objdump -d "$PATCH" | grep -A5 -E '<.*set_sched_policy.*>|<.*set_cpuset_policy.*>|<.*SetTaskProfiles.*>|<.*set_task_profiles.*>' || true
    else
      echo "UNCHANGED"
    fi
  else
    echo "SKIP: no patchable symbols in $REM"
    cp -a "$ORIG" "$PATCH"
  fi

done < "$WORK/libcutils.files"

[ "$patched_any" = 1 ] || {
  echo
  echo "ERROR: no libcutils copy was patched."
  exit 1
}

echo
echo "--- upload and bind patched libcutils copies ---"
ssh root@$TV_IP "mkdir -p '$OVR'"

while IFS= read -r REM; do
  [ -n "$REM" ] || continue

  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  ORIG="$WORK/libs/$TAG.orig"
  PATCH="$WORK/libs/$TAG.patched"

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

while mount | grep -q " \$REM "; do
  echo "umount old \$REM"
  umount "\$REM" 2>/dev/null || break
done

mount -o bind "\$REM_OVR" "\$REM"

echo "--- mounted ---"
mount | grep " \$REM " || true
ls -l "\$REM" "\$REM_OVR"
EOF2

done < "$WORK/libcutils.files"

echo
echo "--- final libcutils mounts ---"
ssh root@$TV_IP "mount | grep libcutils || true"

echo
echo "PATCH_AND_BIND_LIBCUTILS_SCHED_V2_DONE"
