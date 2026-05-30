set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libandroid-servers-powerstats-callsite
WORK=work-libandroid-servers-powerstats-callsite

REM=$ROOTFS/system/lib64/libandroid_servers.so

rm -rf "$WORK"
mkdir -p "$WORK"
ssh root@$TV_IP "mkdir -p '$OVR'"

echo "--- pull clean unbound libandroid_servers.so ---"
scp "root@$TV_IP:$REM" "$WORK/libandroid_servers.so.orig" >/dev/null
cp -a "$WORK/libandroid_servers.so.orig" "$WORK/libandroid_servers.so.patched"

echo
echo "--- disasm around caller/callee ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x6f380 \
  --stop-address=0x6f480 \
  "$WORK/libandroid_servers.so.patched" | tee "$WORK/disasm-caller.txt"

echo
echo "--- disasm around connectToPowerStatsHal entry estimate ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x6fb40 \
  --stop-address=0x6fc20 \
  "$WORK/libandroid_servers.so.patched" | tee "$WORK/disasm-connect.txt"

python3 - "$WORK/libandroid_servers.so.patched" <<'PY'
from pathlib import Path
import subprocess
import struct
import sys

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())

# Stack SIGQUIT showed:
#   connectToPowerStatsHal()+100 at pc 0x6fbc8
#   caller nativeInit return pc 0x6f428
#
# So the blocking BL is normally at 0x6f424.
# To avoid relying blindly on one offset, search nearby for a BL whose target
# falls in the 0x6fb40..0x6fc20 connectToPowerStatsHal region.

SEARCH_START = 0x6f380
SEARCH_END   = 0x6f480
TARGET_START = 0x6fb40
TARGET_END   = 0x6fc20

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
    # BL immediate, op bits 100101
    if (insn & 0xFC000000) != 0x94000000:
        return None
    imm26 = insn & 0x03FFFFFF
    if imm26 & 0x02000000:
        imm26 -= 0x04000000
    return pc + (imm26 << 2)

candidates = []

for pc in range(SEARCH_START, SEARCH_END, 4):
    off = vaddr_to_off(pc)
    insn = struct.unpack("<I", data[off:off+4])[0]
    tgt = decode_bl_target(pc, insn)
    if tgt is not None and TARGET_START <= tgt < TARGET_END:
        candidates.append((pc, tgt, off, insn))

if not candidates:
    print("ERROR: no BL to connectToPowerStatsHal region found near nativeInit")
    print("Dump the disasm-caller.txt shown above.")
    sys.exit(2)

# Prefer exact expected pc 0x6f424, otherwise first candidate.
chosen = None
for c in candidates:
    if c[0] == 0x6f424:
        chosen = c
        break
if chosen is None:
    chosen = candidates[0]

pc, tgt, off, insn = chosen
old = data[off:off+4]

# AArch64 NOP
data[off:off+4] = bytes.fromhex("1f2003d5")
path.write_bytes(data)

print("CANDIDATES:")
for pc2, tgt2, off2, insn2 in candidates:
    print(f"  pc=0x{pc2:x} target=0x{tgt2:x} off=0x{off2:x} insn=0x{insn2:08x}")

print(f"PATCHED_CALLSITE pc=0x{pc:x} target=0x{tgt:x} file_off=0x{off:x} old={old.hex()} new=1f2003d5")
PY

echo
echo "--- disasm after patch ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x6f400 \
  --stop-address=0x6f450 \
  "$WORK/libandroid_servers.so.patched"

echo
echo "--- upload and bind patched libandroid_servers ---"
scp "$WORK/libandroid_servers.so.patched" "root@$TV_IP:$OVR/libandroid_servers.so" >/dev/null

ssh root@$TV_IP "sh -s" <<EOF2
set -e

REM='$REM'
OVR='$OVR/libandroid_servers.so'

echo "--- stop zygote/system_server ---"
killall -9 app_process64 system_server zygote_socket_wrap 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f system_server 2>/dev/null || true
sleep 1

echo "--- unmount old libandroid_servers bind if any ---"
while mount | grep -q " \$REM "; do
  umount "\$REM" 2>/dev/null || break
done

echo "--- bind callsite-patched libandroid_servers ---"
mount -o bind "\$OVR" "\$REM"

echo "--- verify mount ---"
mount | grep " \$REM " || true
ls -l "\$REM" "\$OVR"

echo "PATCH_LIBANDROID_SERVERS_POWERSTATS_CALLSITE_BOUND"
EOF2

echo
echo "PATCH_LIBANDROID_SERVERS_POWERSTATS_CALLSITE_DONE"
