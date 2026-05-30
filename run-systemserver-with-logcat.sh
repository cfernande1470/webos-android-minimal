ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

echo "--- clear previous logcat ---"
rm -f "$LOGDIR/logcat-systemserver.txt"

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

LOGCAT_PID=$!
echo "logcat_pid=$LOGCAT_PID"

sleep 1

echo "--- dmesg clear ---"
dmesg -c >/tmp/dmesg.before-logcat-systemserver 2>/dev/null || true

echo "--- start zygote/system_server ---"
sh /tmp/try-zygote-start-system-server-v2.sh 2>/dev/null || true
