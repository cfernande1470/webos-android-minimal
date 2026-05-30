set -e

: "${TV_IP:?TV_IP not set}"

ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar

GOOD=$SIDE/overrides-libandroid-servers-istats/libandroid_servers.so
OVR=$SIDE/overrides-libandroid-servers-power-istats-memtrack-entry
REM=$ROOTFS/system/lib64/libandroid_servers.so

WORK=work-libandroid-servers-memtrack-entry-good
PATCH_VADDR=0x74f1c

rm -rf "$WORK"
mkdir -p "$WORK"
ssh root@$TV_IP "mkdir -p '$OVR'"

echo "--- pull last known-good libandroid_servers: PowerStats + IStats only ---"
scp "root@$TV_IP:$GOOD" "$WORK/libandroid_servers.so.good" >/dev/null
cp -a "$WORK/libandroid_servers.so.good" "$WORK/libandroid_servers.so.patched"

echo
echo "--- disasm before around startMemtrackProxyService entry 0x74f1c ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x74ef0 \
  --stop-address=0x74f80 \
  "$WORK/libandroid_servers.so.patched" | tee "$WORK/disasm-before.txt"

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

if old.startswith(bytes.fromhex("c0035fd6")):
    print("NOTE: target already starts with ret")

data[off:off+16] = new
path.write_bytes(data)

print(f"PATCHED startMemtrackProxyService ENTRY vaddr=0x{vaddr:x} file_off=0x{off:x}")
print(f"old={old.hex()}")
print(f"new={new.hex()}")
PY

echo
echo "--- disasm after patch ---"
aarch64-linux-gnu-objdump -d \
  --start-address=0x74ef0 \
  --stop-address=0x74f80 \
  "$WORK/libandroid_servers.so.patched" | tee "$WORK/disasm-after.txt"

echo
echo "--- upload patched libandroid_servers.so ---"
scp "$WORK/libandroid_servers.so.patched" "root@$TV_IP:$OVR/libandroid_servers.so" >/dev/null

ssh root@$TV_IP "sh -s" <<EOF2
set -e

REM='$REM'
OVR='$OVR/libandroid_servers.so'

echo "--- stop android userspace ---"
killall -9 app_process64 system_server zygote_socket_wrap servicemanager hwservicemanager vndservicemanager statsd incidentd 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f system_server 2>/dev/null || true
sleep 1

echo "--- unmount libandroid_servers binds ---"
while mount | grep -q " \$REM "; do
  umount "\$REM" 2>/dev/null || break
done

echo "--- bind PowerStats + IStats + Memtrack-entry patched libandroid_servers ---"
mount -o bind "\$OVR" "\$REM"

echo "--- ensure no libbinder bind overrides ---"
for p in \
  "$ROOTFS/system/lib64/libbinder.so" \
  "$ROOTFS/apex/com.android.vndk.v33/lib64/libbinder.so" \
  "$ROOTFS/apex/com.android.vndk.v33/lib64/vndk-sp/libbinder.so"
do
  while mount | grep -q " \$p "; do
    umount "\$p" 2>/dev/null || break
  done
done

echo "--- verify mounts ---"
mount | grep -E 'libandroid_servers|libbinder' || true

echo "PATCH_LIBANDROID_SERVERS_MEMTRACK_ENTRY_FROM_GOOD_BOUND"
EOF2

echo
echo "PATCH_LIBANDROID_SERVERS_MEMTRACK_ENTRY_FROM_GOOD_DONE"
