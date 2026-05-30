ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

echo "--- kill android logd/logcat and stale capture ---"
killall -9 logd logcat logdw-capture 2>/dev/null || true
pkill -9 -f '/system/bin/logd' 2>/dev/null || true
pkill -9 -f '/system/bin/logcat' 2>/dev/null || true
sleep 1

echo "--- prepare socket dir ---"
mkdir -p "$ROOTFS/dev/socket"
chmod 777 "$ROOTFS/dev/socket"

echo "--- start direct logdw capture ---"
rm -f "$LOGDIR/logdw-capture.txt" "$LOGDIR/logdw-capture.err"

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
  >"$LOGDIR/logdw-capture.txt" 2>"$LOGDIR/logdw-capture.err" &

CAP_PID=$!
echo "cap_pid=$CAP_PID"

sleep 1

echo "--- logdw socket ---"
ls -l "$ROOTFS/dev/socket/logdw" 2>/dev/null || true
tail -20 "$LOGDIR/logdw-capture.err" 2>/dev/null || true

echo "--- clear dmesg ---"
dmesg -c >/tmp/dmesg.before-logdw-systemserver 2>/dev/null || true

echo "--- start zygote/system_server ---"
sh /tmp/try-zygote-start-system-server-v2.sh 2>/dev/null || true

sleep 5

kill "$CAP_PID" 2>/dev/null || true
sleep 1

echo "--- collect ---"
{
  echo "--- pids ---"
  ps -ef | grep -E 'app_process|zygote|system_server|servicemanager|hwservicemanager|vndservicemanager|logdw-capture|property_service_ack' | grep -v grep || true

  echo
  echo "--- zygote log ---"
  tail -260 "$LOGDIR/zygote64.start-system-server.log" 2>/dev/null || true

  echo
  echo "--- capture stderr ---"
  cat "$LOGDIR/logdw-capture.err" 2>/dev/null || true

  echo
  echo "--- logdw fatal/exceptions ---"
  grep -iE 'AndroidRuntime|FATAL EXCEPTION|SystemServer|system_server|RuntimeInit|Exception|Error|ServiceManager|PackageManager|ActivityManager|fatal|crash|die|killing|SELinux|avc|denied|permission|not found|No such|failed|Failure|Watchdog|Zygote|zygote|System\.exit|Killing' \
    "$LOGDIR/logdw-capture.txt" 2>/dev/null | tail -700 || true

  echo
  echo "--- raw logdw tail ---"
  tail -500 "$LOGDIR/logdw-capture.txt" 2>/dev/null || true

  echo
  echo "--- dmesg focused ---"
  dmesg | grep -iE 'WEBOS accept|40046210|returned -22|binder_mmap|binder|system_server|zygote|killed|oom|fault|segv|fatal|avc|denied|property' | tail -300 || true

  echo
  echo "AFTER_LOGDW_SYSTEMSERVER_DONE"
} > "$LOGDIR/after-logdw-systemserver.out"

cat "$LOGDIR/after-logdw-systemserver.out"
