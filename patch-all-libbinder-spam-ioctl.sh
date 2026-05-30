set -e

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libbinder-spam
WORK=patch-libbinder-copies

rm -rf "$WORK"
mkdir -p "$WORK"

echo "--- find libbinder copies on TV ---"
ssh root@$TV_IP "find $ROOTFS -type f \( -name 'libbinder.so' -o -name 'libbinder_ndk.so' -o -name 'libbinder_rpc_unstable.so' \) 2>/dev/null" \
  | tee "$WORK/remote-libbinder-files.txt"

echo
echo "--- pull copies ---"
i=0
while read -r remote; do
  [ -n "$remote" ] || continue
  i=$((i+1))
  local="$WORK/lib_$i.so"
  echo "$remote" > "$WORK/lib_$i.remote"
  echo "[$i] $remote"
  scp "root@$TV_IP:$remote" "$local" >/dev/null
done < "$WORK/remote-libbinder-files.txt"

echo
echo "--- patch candidates ---"
python3 - <<'PY'
from pathlib import Path
import subprocess
import re
import struct

work = Path("patch-libbinder-copies")

MOV_W0_0 = bytes.fromhex("00008052")  # mov w0,#0

def run(cmd):
    return subprocess.check_output(cmd, text=True, errors="replace")

def vaddr_to_fileoff(path: Path, vaddr: int) -> int | None:
    out = run(["aarch64-linux-gnu-readelf", "-lW", str(path)])
    # LOAD           0x000000 0x0000000000000000 ...
    for line in out.splitlines():
        if not line.strip().startswith("LOAD"):
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        off = int(parts[1], 16)
        va = int(parts[2], 16)
        filesz = int(parts[4], 16)
        if va <= vaddr < va + filesz:
            return off + (vaddr - va)
    return None

def insn_at(data: bytes, off: int) -> int:
    if off < 0 or off + 4 > len(data):
        return -1
    return int.from_bytes(data[off:off+4], "little")

def wide_imm16(insn: int):
    # movz/movk/movn-ish wide immediate, enough for our scan.
    if (insn & 0x7f800000) in (0x52800000, 0x72800000, 0x12800000):
        return (insn >> 5) & 0xffff
    return None

patched_any = False

for so in sorted(work.glob("lib_*.so")):
    remote = so.with_suffix(".remote").read_text().strip()
    data = bytearray(so.read_bytes())

    try:
        dis = run(["aarch64-linux-gnu-objdump", "-d", "-C", str(so)])
    except Exception as e:
        print(f"{remote}: objdump failed: {e}")
        continue

    call_vaddrs = []
    for line in dis.splitlines():
        # Example:
        #  89be8: 94008042 bl a9cf0 <ioctl@plt>
        if "<ioctl@plt>" in line and re.search(r"\bbl\b", line):
            m = re.match(r"\s*([0-9a-fA-F]+):", line)
            if m:
                call_vaddrs.append(int(m.group(1), 16))

    candidates = []
    for va in call_vaddrs:
        fo = vaddr_to_fileoff(so, va)
        if fo is None:
            continue

        # Look back 96 bytes for immediate pieces 0x6210 and 0x4004.
        window_start = max(0, fo - 96)
        has_6210 = False
        has_4004 = False
        for off in range(window_start, fo, 4):
            imm = wide_imm16(insn_at(data, off))
            if imm == 0x6210:
                has_6210 = True
            if imm == 0x4004:
                has_4004 = True

        if has_6210 and has_4004:
            candidates.append((va, fo))

    print()
    print(f"### {remote}")
    print("ioctl@plt call count:", len(call_vaddrs))
    print("spam ioctl candidates:", [(hex(va), hex(fo)) for va, fo in candidates])

    if not candidates:
        continue

    for va, fo in candidates:
        before = bytes(data[fo:fo+4])
        print(f"patch {remote}: vaddr={hex(va)} fileoff={hex(fo)} before={before.hex()} -> mov w0,#0")
        data[fo:fo+4] = MOV_W0_0
        patched_any = True

    so.with_suffix(".patched.so").write_bytes(data)

if not patched_any:
    raise SystemExit("NO_CANDIDATES_PATCHED")
PY

echo
echo "--- push patched copies and bind mount ---"
ssh root@$TV_IP "mkdir -p $OVR"

for patched in "$WORK"/*.patched.so; do
  base="$(basename "$patched" .patched.so)"
  idx="${base#lib_}"
  remote="$(cat "$WORK/lib_${idx}.remote")"

  safe="$(echo "$remote" | tr '/:' '__')"
  remote_patch="$OVR/$safe"

  echo
  echo "remote original: $remote"
  echo "remote patch:    $remote_patch"

  scp "$patched" "root@$TV_IP:$remote_patch" >/dev/null

  ssh root@$TV_IP "sh -s" <<EOS
set -e
remote='$remote'
patch='$remote_patch'

chmod 644 "\$patch"

echo "--- unmount old bind if any: \$remote ---"
while mount | grep -q " \$remote "; do
  umount "\$remote" 2>/dev/null || break
done

echo "--- bind patched copy ---"
mount --bind "\$patch" "\$remote"

echo "--- verify grep mount ---"
mount | grep " \$remote " || true
EOS
done

echo
echo "--- verify patched bytes on TV ---"
ssh root@$TV_IP "sh -s" <<'EOS'
ROOTFS=/media/internal/android-usb/android-rootfs

for f in $(find "$ROOTFS" -type f \( -name 'libbinder.so' -o -name 'libbinder_ndk.so' -o -name 'libbinder_rpc_unstable.so' \) 2>/dev/null); do
  echo
  echo "### $f"
  # Show possible old site bytes around common offsets if file is big enough.
  size=$(wc -c < "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt $((0x89bec)) ]; then
    echo -n "0x89be8: "
    od -An -tx1 -j $((0x89be8)) -N 4 "$f" 2>/dev/null || true
  fi
  if [ "$size" -gt $((0x8a23c)) ]; then
    echo -n "0x8a238: "
    od -An -tx1 -j $((0x8a238)) -N 4 "$f" 2>/dev/null || true
  fi
done

echo
echo "PATCH_ALL_LIBBINDER_SPAM_IOCTL_DONE"
EOS
