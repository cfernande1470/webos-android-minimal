set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libprocessgroup-sched
WORK=work-libprocessgroup-sched

rm -rf "$WORK"
mkdir -p "$WORK/libs"

echo "--- find libprocessgroup copies ---"
ssh root@$TV_IP "find '$ROOTFS' -type f -path '*/lib64/libprocessgroup.so' 2>/dev/null" | tee "$WORK/files"

[ -s "$WORK/files" ] || {
  echo "ERROR: no libprocessgroup.so found"
  exit 1
}

patched_any=0

while IFS= read -r REM; do
  [ -n "$REM" ] || continue

  TAG="$(echo "$REM" | sed "s#^$ROOTFS/##" | tr '/ ' '__')"
  ORIG="$WORK/libs/$TAG.orig"
  PATCH="$WORK/libs/$TAG.patched"

  echo
  echo "=== $REM ==="
  scp "root@$TV_IP:$REM" "$ORIG" >/dev/null
  cp -a "$ORIG" "$PATCH"

  echo "--- candidate symbols ---"
  aarch64-linux-gnu-readelf -Ws "$PATCH" | grep -E 'androidSetThreadSchedulingGroup|set_sched_policy|set_cpuset_policy|SetTaskProfiles|SetProcessProfiles|SetThreadProfiles' || true

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

zero_success = [
    "androidSetThreadSchedulingGroup",
    "set_sched_policy",
    "set_cpuset_policy",
]

true_success = [
    "SetTaskProfiles",
    "SetProcessProfiles",
    "SetThreadProfiles",
]

patched = []
seen = set()

for line in syms.splitlines():
    parts = line.split()
    if len(parts) < 8:
        continue

    try:
        vaddr = int(parts[1], 16)
    except Exception:
        continue

    typ = parts[3]
    ndx = parts[6]
    name = parts[7].split("@", 1)[0]

    if typ != "FUNC" or ndx == "UND" or vaddr == 0 or vaddr in seen:
        continue

    ret_true = any(s in name for s in true_success)
    ret_zero = any(s in name for s in zero_success)

    if not ret_true and not ret_zero:
        continue

    off = vaddr_to_off(vaddr)
    old = bytes(data[off:off+8])

    # AArch64:
    #   mov w0,#0 ; ret     for int success
    #   mov w0,#1 ; ret     for bool true
    new = bytes.fromhex("20008052c0035fd6") if ret_true else bytes.fromhex("00008052c0035fd6")

    data[off:off+8] = new
    patched.append((name, vaddr, off, old.hex(), new.hex(), "true" if ret_true else "zero"))
    seen.add(vaddr)

if not patched:
    print("NO_TARGET_SYMBOLS_IN_THIS_LIB")
    sys.exit(10)

path.write_bytes(data)

for name, vaddr, off, old, new, mode in patched:
    print(f"PATCHED {name}: mode={mode} vaddr=0x{vaddr:x} off=0x{off:x} old={old} new={new}")
PY
  then
    if ! cmp -s "$ORIG" "$PATCH"; then
      patched_any=1
      echo "--- patched snippets ---"
      aarch64-linux-gnu-objdump -d "$PATCH" | grep -A5 -E 'androidSetThreadSchedulingGroup|set_sched_policy|set_cpuset_policy|SetTaskProfiles|SetProcessProfiles|SetThreadProfiles' || true
    else
      echo "UNCHANGED"
    fi
  else
    echo "SKIP: no patchable symbols in $REM"
    cp -a "$ORIG" "$PATCH"
  fi

done < "$WORK/files"

[ "$patched_any" = 1 ] || {
  echo "ERROR: no libprocessgroup copy was patched"
  exit 1
}

echo
echo "--- upload and bind patched libprocessgroup copies ---"
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

done < "$WORK/files"

echo
echo "--- final libprocessgroup mounts ---"
ssh root@$TV_IP "mount | grep libprocessgroup || true"

echo
echo "PATCH_AND_BIND_LIBPROCESSGROUP_SCHED_DONE"
