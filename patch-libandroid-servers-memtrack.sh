set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-libandroid-servers-memtrack
WORK=work-libandroid-servers-memtrack

REM=$ROOTFS/system/lib64/libandroid_servers.so

# Stack:
#   0x74f48 = android_server_SystemServer_startMemtrackProxyService + 44
# entry ~= 0x74f48 - 0x2c = 0x74f1c
PATCH_VADDR=0x74f1c

rm -rf "$WORK"
mkdir -p "$WORK"
ssh root@$TV_IP "mkdir -p '$OVR'"

echo "--- pull current bound libandroid_servers.so; should already contain PowerStats + IStats bypasses ---"
scp "root@$TV_IP:$REM" "$WORK/libandroid_servers.so.orig" >/dev/null
cp -a "$WORK/libandroid_servers.so.orig" "$WORK/libandroid_servers.so.patched"

echo
echo "--- disasm before around MemtrackProxyService entry estimate ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x74ef0 \
  --stop-address=0x74f80 \
  "$WORK/libandroid_servers.so.patched" || true

python3 - "$WORK/libandroid_servers.so.patched" "$PATCH_VADDR" <<'PY'
from pathlib import Path
import subprocess
import sys

path = Path(sys.argv[1])
vaddr = int(sys.argv[2], 16)
data = bytearray(path.read_bytes())

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

off = vaddr_to_off(vaddr)
old = bytes(data[off:off+16])

# JNI void native: return immediately.
# ret; nop; nop; nop
new = bytes.fromhex("c0035fd61f2003d51f2003d51f2003d5")

data[off:off+16] = new
path.write_bytes(data)

print(f"PATCHED startMemtrackProxyService entry vaddr=0x{vaddr:x} file_off=0x{off:x}")
print(f"old={old.hex()}")
print(f"new={new.hex()}")
PY

echo
echo "--- disasm after patch ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x74ef0 \
  --stop-address=0x74f80 \
  "$WORK/libandroid_servers.so.patched"

echo
echo "--- upload and bind patched libandroid_servers.so ---"
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

echo "--- bind patched libandroid_servers with PowerStats + IStats + Memtrack bypasses ---"
mount -o bind "\$OVR" "\$REM"

echo "--- verify mount ---"
mount | grep " \$REM " || true
ls -l "\$REM" "\$OVR"

echo "PATCH_LIBANDROID_SERVERS_MEMTRACK_BOUND"
EOF2

echo
echo "PATCH_LIBANDROID_SERVERS_MEMTRACK_DONE"
