ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs

echo "--- logs dir ---"
ls -lah "$LOGDIR" 2>/dev/null || true

echo
echo "--- zygote logs full ---"
for f in "$LOGDIR"/*zygote* "$LOGDIR"/*system* "$LOGDIR"/*property*; do
  [ -e "$f" ] || continue
  echo
  echo "### $f"
  sed -n '1,260p' "$f" 2>/dev/null || true
done

echo
echo "--- sockets ---"
ls -lah "$ROOTFS/dev/socket" 2>/dev/null || true

echo
echo "--- pids ---"
ps -ef | grep -E 'app_process|zygote|system_server|servicemanager|property_service_ack|tombstone' | grep -v grep || true

echo
echo "--- dmesg focused ---"
dmesg | grep -iE 'system_server|app_process|zygote|sigkill|killed|oom|lowmemory|binder|ioctl|fault|segv|property|tombstone' | tail -240 || true

echo
echo "DUMP_START_LOGS_DONE"
