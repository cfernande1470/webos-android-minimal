ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

rm -f "$LOGDIR/logcat-systemserver.txt" "$LOGDIR/logcat-systemserver.err"

echo "--- start logcat collector ---"
env -i \
  PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/logcat -v threadtime '*:V' \
  >"$LOGDIR/logcat-systemserver.txt" 2>"$LOGDIR/logcat-systemserver.err" &

echo "logcat_pid=$!"
sleep 1

dmesg -c >/tmp/dmesg.before-logcat-systemserver 2>/dev/null || true

echo "--- start zygote/system_server ---"
sh /tmp/try-zygote-start-system-server-v2.sh 2>/dev/null || true

sleep 6

echo "--- collect ---"
{
  echo "--- pids ---"
  ps -ef | grep -E 'app_process|zygote|system_server|servicemanager|hwservicemanager|vndservicemanager|logd|logcat|property_service_ack' | grep -v grep || true

  echo
  echo "--- zygote log ---"
  tail -280 "$LOGDIR/zygote64.start-system-server.log" 2>/dev/null || true

  echo
  echo "--- logcat stderr ---"
  tail -160 "$LOGDIR/logcat-systemserver.err" 2>/dev/null || true

  echo
  echo "--- logcat fatal/exceptions ---"
  grep -iE 'AndroidRuntime|FATAL EXCEPTION|SystemServer|system_server|RuntimeInit|Exception|Error|ServiceManager|PackageManager|ActivityManager|fatal|crash|die|killing|SELinux|avc|denied|permission|not found|No such|failed|Failure' \
    "$LOGDIR/logcat-systemserver.txt" 2>/dev/null | tail -500 || true

  echo
  echo "--- dmesg focused ---"
  dmesg | grep -iE 'WEBOS accept|40046210|returned -22|missing address|get_vm_area|binder_mmap|binder|system_server|zygote|killed|oom|fault|segv|fatal|property|avc|denied|ioctl|failed' | tail -500 || true

  echo
  echo "--- raw logcat tail ---"
  tail -320 "$LOGDIR/logcat-systemserver.txt" 2>/dev/null || true

  echo
  echo "AFTER_LOGCAT_SYSTEMSERVER_DONE"
} > "$LOGDIR/after-logcat-systemserver.out"

cat "$LOGDIR/after-logcat-systemserver.out"
