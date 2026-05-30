set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libandroid-servers-memtrack-callsite
WORK=work-libandroid-servers-memtrack-callsite

REM=$ROOTFS/system/lib64/libandroid_servers.so

rm -rf "$WORK"
mkdir -p "$WORK"
ssh root@$TV_IP "mkdir -p '$OVR'"

echo "--- pull current GOOD libandroid_servers.so: PowerStats + IStats bypasses ---"
scp "root@$TV_IP:$REM" "$WORK/libandroid_servers.so.orig" >/dev/null
cp -a "$WORK/libandroid_servers.so.orig" "$WORK/libandroid_servers.so.patched"

echo
echo "--- disasm around startMemtrackProxyService ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x74f00 \
  --stop-address=0x74f80 \
  "$WORK/libandroid_servers.so.patched" | tee "$WORK/disasm-memtrack.txt"

python3 - "$WORK/libandroid_servers.so.patched" <<'PY'
from pathlib import Path
import subprocess
import struct
import sys

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())

# Stack:
#   0x74f48 = startMemtrackProxyService + 44
# Return PC after the blocking call is usually 0x74f48,
# so the BL instruction is usually at 0x74f44.
SEARCH_START = 0x74f00
SEARCH_END   = 0x74f70
PREFERRED_PC = 0x74f44

ph = subprocess.check_output(
    ["aarch64-linux-gnu-readelf", "-lW", str(path)],
    text=True,
    stderr=subprocess.STDOUT,
)

segs = []
for line in ph.splitlines():
    parts = line.split()
    if len(parts) >= 6 and parts[0] == "LOAD":
        off = int(parts[1], 16)
        va = int(parts[2], 16)
        filesz = int(parts[4], 16)
        segs.append((va, va + filesz, off))

def vaddr_to_off(v):
    for start, end, off in segs:
        if start <= v < end:
            return off + (v - start)
    raise SystemExit(f"ERROR: vaddr 0x{v:x} not in LOAD segment")

def decode_bl_target(pc, insn):
    if (insn & 0xFC000000) != 0x94000000:
        return None
    imm26 = insn & 0x03FFFFFF
    if imm26 & 0x02000000:
        imm26 -= 0x04000000
    return pc + (imm26 << 2)

cands = []
for pc in range(SEARCH_START, SEARCH_END, 4):
    off = vaddr_to_off(pc)
    insn = struct.unpack("<I", data[off:off+4])[0]
    tgt = decode_bl_target(pc, insn)
    if tgt is not None:
        cands.append((pc, tgt, off, insn))

if not cands:
    print("ERROR: no BL found near startMemtrackProxyService")
    sys.exit(2)

chosen = None
for c in cands:
    if c[0] == PREFERRED_PC:
        chosen = c
        break

if chosen is None:
    # Choose last BL before/at the return PC seen in the stack.
    before = [c for c in cands if c[0] <= PREFERRED_PC]
    chosen = before[-1] if before else cands[0]

pc, tgt, off, insn = chosen
old = data[off:off+4]

# NOP the blocking call. x0 may remain whatever, but Java side ignores native void.
data[off:off+4] = bytes.fromhex("1f2003d5")
path.write_bytes(data)

print("BL_CANDIDATES:")
for pc2, tgt2, off2, insn2 in cands:
    mark = " <-- PATCH" if pc2 == pc else ""
    print(f"  pc=0x{pc2:x} target=0x{tgt2:x} off=0x{off2:x} insn=0x{insn2:08x}{mark}")

print(f"PATCHED_MEMTRACK_CALLSITE pc=0x{pc:x} target=0x{tgt:x} file_off=0x{off:x} old={old.hex()} new=1f2003d5")
PY

echo
echo "--- disasm after patch ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x74f00 \
  --stop-address=0x74f80 \
  "$WORK/libandroid_servers.so.patched"

echo
echo "--- upload and bind patched libandroid_servers.so ---"
scp "$WORK/libandroid_servers.so.patched" "root@$TV_IP:$OVR/libandroid_servers.so" >/dev/null

ssh root@$TV_IP "sh -s" <<EOF2
set -e

REM='$REM'
OVR='$OVR/libandroid_servers.so'

echo "--- stop zygote/system_server only ---"
killall -9 app_process64 system_server zygote_socket_wrap 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f system_server 2>/dev/null || true
sleep 1

echo "--- unmount old libandroid_servers bind if any ---"
while mount | grep -q " \$REM "; do
  umount "\$REM" 2>/dev/null || break
done

echo "--- bind patched libandroid_servers with PowerStats + IStats + Memtrack-callsite bypasses ---"
mount -o bind "\$OVR" "\$REM"

echo "--- verify mounts, and ensure no libbinder overrides ---"
mount | grep -E 'libandroid_servers|libbinder' || true

echo "PATCH_LIBANDROID_SERVERS_MEMTRACK_CALLSITE_BOUND"
EOF2

echo
echo "PATCH_LIBANDROID_SERVERS_MEMTRACK_CALLSITE_DONE"
