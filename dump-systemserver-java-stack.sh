ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

PID="$(pidof system_server 2>/dev/null || true)"
echo "system_server_pid=$PID"
[ -n "$PID" ] || exit 1

echo "--- prepare logdw capture ---"
killall -9 logdw-capture 2>/dev/null || true
pkill -9 -f logdw-capture 2>/dev/null || true
sleep 1

rm -f "$LOGDIR/sigquit-systemserver-logdw.txt" "$LOGDIR/sigquit-systemserver-logdw.err"

env -i \
  PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/data/local/tmp \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /data/local/tmp/logdw-capture \
  >"$LOGDIR/sigquit-systemserver-logdw.txt" \
  2>"$LOGDIR/sigquit-systemserver-logdw.err" &

CAP=$!
echo "cap_pid=$CAP"
sleep 1

echo "--- send SIGQUIT ---"
kill -3 "$PID"

sleep 6

kill "$CAP" 2>/dev/null || true
sleep 1

echo "--- look for ANR/traces files ---"
find "$ROOTFS/data/anr" "$ROOTFS/data/tombstones" "$ROOTFS/data/misc" \
  -type f 2>/dev/null | sort | tail -80

echo
echo "--- logdw stack focused ---"
grep -iE 'SIGQUIT|DALVIK THREADS|Cmd line: system_server|main|system-server-init|PowerStats|SystemServer|StartPowerStats|Binder|futex|WAIT|BLOCKED|native|at com\.android|at android' \
  "$LOGDIR/sigquit-systemserver-logdw.txt" 2>/dev/null | head -1200 || true

echo
echo "--- raw logdw tail ---"
tail -600 "$LOGDIR/sigquit-systemserver-logdw.txt" 2>/dev/null || true

echo
echo "--- traces tail if present ---"
for f in "$ROOTFS"/data/anr/* "$ROOTFS"/data/tombstones/*; do
  [ -f "$f" ] || continue
  echo "=== $f ==="
  tail -260 "$f" 2>/dev/null
done

echo
echo "DUMP_SYSTEMSERVER_JAVA_STACK_DONE"
