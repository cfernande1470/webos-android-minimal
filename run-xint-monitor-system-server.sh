set -e

cp try-zygote-start-system-server-v2.sh try-zygote-start-system-server-xint-monitor.sh

python3 - <<'PY'
from pathlib import Path
p = Path("try-zygote-start-system-server-xint-monitor.sh")
s = p.read_text()

# Primero solo -Xint, sin -Xusejit:false para evitar opciones no soportadas.
if "-Xzygote -Xint " not in s:
    s = s.replace("-Xzygote ", "-Xzygote -Xint ", 1)

p.write_text(s)
print("patched", p)
PY

echo "--- start Xint zygote/system_server ---"
ssh root@$TV_IP 'sh -s' < try-zygote-start-system-server-xint-monitor.sh

echo
echo "--- monitor 30s ---"
for i in $(seq 1 30); do
  echo
  echo "=== XINT T+$i ==="
  ssh root@$TV_IP 'sh -s' <<'EOS'
ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs

echo "--- android-ish pids ---"
ps -ef | grep -E 'app_process|zygote|system_server|servicemanager|property_service_ack|tombstoned' | grep -v grep || true

echo "--- pidof ---"
pidof app_process64 2>/dev/null || true
pidof system_server 2>/dev/null || true
pidof zygote_socket_wrap 2>/dev/null || true

echo "--- last zygote log ---"
tail -80 "$LOGDIR/zygote64.start-system-server.log" 2>/dev/null || true

echo "--- dmesg tail ---"
dmesg | grep -iE 'system_server|zygote|art|segv|fault|killed|oom|lowmemory|binder|property|fatal|exception' | tail -40 || true
EOS
  sleep 1
done
