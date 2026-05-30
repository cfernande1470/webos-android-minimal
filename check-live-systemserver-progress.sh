ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

PID="$(pidof system_server 2>/dev/null || true)"
echo "system_server_pid=$PID"

echo
echo "--- pids ---"
ps -ef | grep -E 'system_server|app_process64|servicemanager|hwservicemanager|vndservicemanager' | grep -v grep || true

echo
echo "--- service list count ---"
chroot "$ROOTFS" /system/bin/service list 2>&1 | tee "$LOGDIR/service-list-live.txt" | head -200
echo "service_count=$(grep -c '^[0-9]' "$LOGDIR/service-list-live.txt" 2>/dev/null || echo 0)"

if [ -n "$PID" ]; then
  echo
  echo "--- system_server status ---"
  sed -n '1,120p' /proc/$PID/status

  echo
  echo "--- system_server threads wchan/stat ---"
  for t in /proc/$PID/task/*; do
    tid="${t##*/}"
    comm="$(cat "$t/comm" 2>/dev/null)"
    wchan="$(cat "$t/wchan" 2>/dev/null)"
    stat="$(cat "$t/stat" 2>/dev/null)"
    echo "TID=$tid COMM=$comm WCHAN=$wchan STAT=$stat"
  done | head -300

  echo
  echo "--- native kernel stacks if available ---"
  for t in /proc/$PID/task/*; do
    tid="${t##*/}"
    comm="$(cat "$t/comm" 2>/dev/null)"
    echo "=== TID=$tid COMM=$comm ==="
    cat "$t/stack" 2>/dev/null | head -40
  done | head -500
fi

echo
echo "CHECK_LIVE_SYSTEMSERVER_PROGRESS_DONE"
