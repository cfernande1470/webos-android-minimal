ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

echo "--- kill old logd/logcat ---"
killall -9 logd logcat 2>/dev/null || true
pkill -9 -f '/system/bin/logd' 2>/dev/null || true
pkill -9 -f '/system/bin/logcat' 2>/dev/null || true

echo "--- prepare log sockets dir ---"
mkdir -p "$ROOTFS/dev/socket"
chmod 777 "$ROOTFS/dev/socket"

echo "--- start logd ---"
env -i \
  PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/logd >"$LOGDIR/logd.out" 2>"$LOGDIR/logd.err" &

sleep 1

echo "--- logd pids/sockets ---"
ps -ef | grep -E '/system/bin/logd|logcat' | grep -v grep || true
ls -l "$ROOTFS/dev/socket" | grep -E 'logd|logdw|logdr|logdw' || true

echo "--- logd stderr ---"
tail -80 "$LOGDIR/logd.err" 2>/dev/null || true

echo "START_ANDROID_LOGD_DONE"
