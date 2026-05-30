ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

echo "--- kill old logd/logcat ---"
killall -9 logd logcat 2>/dev/null || true
pkill -9 -f '/system/bin/logd' 2>/dev/null || true
pkill -9 -f '/system/bin/logcat' 2>/dev/null || true
pkill -9 -f 'logd-socket-launcher' 2>/dev/null || true
sleep 1

echo "--- prepare dirs ---"
mkdir -p "$ROOTFS/dev/socket" "$ROOTFS/data/misc/logd" "$ROOTFS/data/system/dropbox" "$ROOTFS/data/local/tmp"
chmod 777 "$ROOTFS/dev/socket"
chmod 777 "$ROOTFS/data" "$ROOTFS/data/misc" "$ROOTFS/data/misc/logd" "$ROOTFS/data/local" "$ROOTFS/data/local/tmp" 2>/dev/null || true

echo "--- launcher exists? ---"
ls -l "$ROOTFS/data/local/tmp/logd-socket-launcher" || exit 1

echo "--- start logd through socket launcher ---"
env -i \
  PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/data/local/tmp \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /data/local/tmp/logd-socket-launcher /system/bin/logd \
  >"$LOGDIR/logd.out" 2>"$LOGDIR/logd.err" &

sleep 2

echo "--- logd pids ---"
ps -ef | grep -E 'logd|logcat|logd-socket-launcher' | grep -v grep || true

echo
echo "--- log sockets ---"
ls -l "$ROOTFS/dev/socket" | grep -E 'logd|logdr|logdw' || true

echo
echo "--- logd stderr ---"
tail -160 "$LOGDIR/logd.err" 2>/dev/null || true

echo
echo "--- dmesg logd ---"
dmesg | grep -iE 'logd|fatal|abort|segv|fault|denied|avc' | tail -120 || true

echo
echo "START_ANDROID_LOGD_WITH_SOCKETS_DONE"
