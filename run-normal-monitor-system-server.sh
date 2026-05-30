TV_CMD='sh -s'
ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs

echo "--- start normal zygote/system_server ---"
ssh root@$TV_IP "$TV_CMD" < try-zygote-start-system-server-v2.sh

echo
echo "--- monitor 20s ---"
for i in $(seq 1 20); do
  echo
  echo "=== T+$i ==="
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

echo "--- sockets ---"
ls -l "$ROOTFS/dev/socket" 2>/dev/null | grep -E 'zygote|usap|property|tombstone' || true

echo "--- last zygote log ---"
tail -40 "$LOGDIR/zygote64.start-system-server.log" 2>/dev/null || true

echo "--- dmesg tail ---"
dmesg | grep -iE 'system_server|zygote|art|segv|fault|killed|oom|lowmemory|binder|property|fatal|exception' | tail -30 || true
EOS
  sleep 1
done
