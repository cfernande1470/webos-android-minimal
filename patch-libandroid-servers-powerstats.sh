set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libandroid-servers-powerstats
WORK=work-libandroid-servers-powerstats

REM=$ROOTFS/system/lib64/libandroid_servers.so

rm -rf "$WORK"
mkdir -p "$WORK"
ssh root@$TV_IP "mkdir -p '$OVR'"

echo "--- pull libandroid_servers.so ---"
scp "root@$TV_IP:$REM" "$WORK/libandroid_servers.so.orig" >/dev/null
cp -a "$WORK/libandroid_servers.so.orig" "$WORK/libandroid_servers.so.patched"

echo "--- symbol search ---"
aarch64-linux-gnu-nm -anC "$WORK/libandroid_servers.so.patched" > "$WORK/nm.txt" || true

grep -nE 'connectToPowerStatsHal|nativeInit\(_JNIEnv\*, _jclass\*\)' "$WORK/nm.txt" || true

python3 - "$WORK/libandroid_servers.so.patched" "$WORK/nm.txt" <<'PY'
from pathlib import Path
import subprocess
import sys
import re

lib = Path(sys.argv[1])
nm_path = Path(sys.argv[2])
data = bytearray(lib.read_bytes())

nm_lines = nm_path.read_text(errors="replace").splitlines()

def parse_addr(line):
    m = re.match(r"^\s*([0-9a-fA-F]+)\s+", line)
    return int(m.group(1), 16) if m else None

connect = []
native = []

for line in nm_lines:
    addr = parse_addr(line)
    if addr is None:
        continue
    if "connectToPowerStatsHal" in line:
        connect.append((addr, line))
    if "android::nativeInit(_JNIEnv*, _jclass*)" in line:
        native.append((addr, line))

if not connect:
    print("ERROR: connectToPowerStatsHal symbol not found")
    sys.exit(2)

caddr, cline = sorted(connect)[0]

# El nativeInit de PowerStats es el nativeInit más cercano antes de connectToPowerStatsHal.
cands = [(a, l) for a, l in native if a <= caddr and (caddr - a) < 0x10000]

if not cands:
    print("ERROR: nearby android::nativeInit(_JNIEnv*, _jclass*) not found")
    print(f"connectToPowerStatsHal=0x{caddr:x} {cline}")
    sys.exit(3)

naddr, nline = sorted(cands)[-1]

print(f"CONNECT_SYMBOL 0x{caddr:x}: {cline}")
print(f"PATCH_NATIVEINIT 0x{naddr:x}: {nline}")
print(f"DISTANCE connect-native = 0x{caddr-naddr:x}")

ph = subprocess.check_output(
    ["aarch64-linux-gnu-readelf", "-lW", str(lib)],
    text=True,
    stderr=subprocess.STDOUT,
)

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
    raise RuntimeError(f"vaddr 0x{v:x} not in LOAD segment")

off = vaddr_to_off(naddr)
old = bytes(data[off:off+16])

# AArch64:
#   mov w0, #0      ; jlong/native pointer result = 0
#   ret
#   nop
#   nop
new = bytes.fromhex("00008052c0035fd61f2003d51f2003d5")

data[off:off+16] = new
lib.write_bytes(data)

print(f"PATCHED file_off=0x{off:x} old={old.hex()} new={new.hex()}")
PY

echo
echo "--- verify patched disasm ---"
NATIVE_ADDR="$(python3 - "$WORK/nm.txt" <<'PY'
from pathlib import Path
import re
import sys

lines = Path(sys.argv[1]).read_text(errors="replace").splitlines()

def parse_addr(line):
    m = re.match(r"^\s*([0-9a-fA-F]+)\s+", line)
    return int(m.group(1), 16) if m else None

connect = []
native = []
for line in lines:
    a = parse_addr(line)
    if a is None:
        continue
    if "connectToPowerStatsHal" in line:
        connect.append(a)
    if "android::nativeInit(_JNIEnv*, _jclass*)" in line:
        native.append(a)

c = sorted(connect)[0]
cand = [a for a in native if a <= c and c - a < 0x10000]
print(hex(sorted(cand)[-1]))
PY
)"

START=$((NATIVE_ADDR))
STOP=$((START + 64))

aarch64-linux-gnu-objdump -d \
  --start-address="$START" \
  --stop-address="$STOP" \
  "$WORK/libandroid_servers.so.patched"

echo
echo "--- upload and bind ---"
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

echo "--- bind patched libandroid_servers ---"
mount -o bind "\$OVR" "\$REM"

echo "--- verify mount ---"
mount | grep " \$REM " || true
ls -l "\$REM" "\$OVR"

echo "PATCH_LIBANDROID_SERVERS_POWERSTATS_BOUND"
EOF2

echo
echo "PATCH_LIBANDROID_SERVERS_POWERSTATS_DONE"
