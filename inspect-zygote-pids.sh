ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- raw pidof app_process64 ---"
PIDS="$(pidof app_process64 2>/dev/null || true)"
echo "$PIDS"

echo
echo "--- per pid status ---"
for PID in $PIDS; do
  echo
  echo "=== PID $PID ==="

  if [ ! -d "/proc/$PID" ]; then
    echo "missing /proc/$PID"
    continue
  fi

  echo "--- status ---"
  sed -n '1,40p' "/proc/$PID/status" 2>/dev/null || true

  echo "--- cmdline ---"
  tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null
  echo

  echo "--- comm ---"
  cat "/proc/$PID/comm" 2>/dev/null || true

  echo "--- threads ---"
  ls "/proc/$PID/task" 2>/dev/null | wc -l

  echo "--- fds socket-ish ---"
  ls -l "/proc/$PID/fd" 2>/dev/null | grep -E 'socket|zygote|ashmem|binder|anon_inode' | head -30 || true

  echo "--- maps ART quick ---"
  grep -E 'libart.so|libandroid_runtime.so|libprocessgroup.so' "/proc/$PID/maps" 2>/dev/null | head -20 || true
done

echo
echo "--- android-ish /proc scan ---"
for D in /proc/[0-9]*; do
  PID="${D#/proc/}"
  COMM="$(cat "$D/comm" 2>/dev/null || true)"
  CMD="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null || true)"
  case "$COMM $CMD" in
    *app_process*|*zygote*|*system_server*)
      echo "PID=$PID COMM=$COMM CMD=$CMD"
      ;;
  esac
done

echo
echo "--- zygote sockets ---"
ls -l "$ROOTFS/dev/socket" 2>/dev/null | grep -E 'zygote|usap' || true
