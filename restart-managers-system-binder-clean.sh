ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

ENV='PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin ANDROID_ROOT=/system ANDROID_DATA=/data ANDROID_STORAGE=/storage ANDROID_RUNTIME_ROOT=/apex/com.android.runtime ANDROID_TZDATA_ROOT=/apex/com.android.tzdata ANDROID_ART_ROOT=/apex/com.android.art LD_CONFIG_FILE=/linkerconfig/ld.config.txt'

echo "--- kill managers ---"
killall -9 servicemanager hwservicemanager vndservicemanager 2>/dev/null || true
sleep 1

echo "--- start system servicemanager only on /dev/binder ---"
env -i $ENV chroot "$ROOTFS" /system/bin/servicemanager \
  >"$LOGDIR/servicemanager.system.out" \
  2>"$LOGDIR/servicemanager.system.err" &

sleep 1

echo "--- start hwservicemanager ---"
env -i $ENV chroot "$ROOTFS" /system/bin/hwservicemanager \
  >"$LOGDIR/hwservicemanager.out" \
  2>"$LOGDIR/hwservicemanager.err" &

sleep 1

echo "--- start vndservicemanager ---"
env -i $ENV chroot "$ROOTFS" /vendor/bin/vndservicemanager \
  >"$LOGDIR/vndservicemanager.out" \
  2>"$LOGDIR/vndservicemanager.err" &

sleep 2

echo "--- pids ---"
ps -ef | grep -E 'servicemanager|hwservicemanager|vndservicemanager' | grep -v grep || true

echo
echo "--- servicemanager maps: libbinder source ---"
SMPID="$(pidof servicemanager 2>/dev/null | awk '{print $1}')"
echo "servicemanager_pid=$SMPID"
if [ -n "$SMPID" ]; then
  grep -E 'libbinder|libhidl|vndk' /proc/$SMPID/maps || true
fi

echo
echo "--- service list smoke ---"
chroot "$ROOTFS" /system/bin/service list 2>&1 | head -80 || true

echo
echo "--- manager stderr ---"
echo "### servicemanager"
tail -80 "$LOGDIR/servicemanager.system.err" 2>/dev/null || true
echo "### hwservicemanager"
tail -80 "$LOGDIR/hwservicemanager.err" 2>/dev/null || true
echo "### vndservicemanager"
tail -80 "$LOGDIR/vndservicemanager.err" 2>/dev/null || true

echo "RESTART_MANAGERS_SYSTEM_BINDER_CLEAN_DONE"
