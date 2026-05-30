ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
mkdir -p "$LOGDIR"

echo "--- kill managers ---"
killall -9 servicemanager hwservicemanager vndservicemanager service 2>/dev/null || true
pkill -9 -f '/system/bin/servicemanager' 2>/dev/null || true
pkill -9 -f '/system/bin/hwservicemanager' 2>/dev/null || true
pkill -9 -f '/vendor/bin/vndservicemanager' 2>/dev/null || true
sleep 1

echo "--- verify no libbinder bind mounts ---"
mount | grep -E 'libbinder|overrides-libbinder' || true

COMMON='PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin ANDROID_ROOT=/system ANDROID_DATA=/data ANDROID_STORAGE=/storage ANDROID_RUNTIME_ROOT=/apex/com.android.runtime ANDROID_TZDATA_ROOT=/apex/com.android.tzdata ANDROID_ART_ROOT=/apex/com.android.art LD_CONFIG_FILE=/linkerconfig/ld.config.txt'

SYSTEM_LIBS='/system/lib64:/system_ext/lib64:/product/lib64:/apex/com.android.runtime/lib64/bionic:/apex/com.android.i18n/lib64:/apex/com.android.art/lib64'

echo "--- start SYSTEM servicemanager forced to system libbinder ---"
env -i $COMMON \
  LD_LIBRARY_PATH="$SYSTEM_LIBS" \
  LD_PRELOAD=/system/lib64/libbinder.so \
  chroot "$ROOTFS" /system/bin/servicemanager \
  >"$LOGDIR/servicemanager.force-system.out" \
  2>"$LOGDIR/servicemanager.force-system.err" &

echo "--- start hwservicemanager normal system side ---"
env -i $COMMON \
  LD_LIBRARY_PATH="$SYSTEM_LIBS" \
  LD_PRELOAD=/system/lib64/libbinder.so \
  chroot "$ROOTFS" /system/bin/hwservicemanager \
  >"$LOGDIR/hwservicemanager.force-system.out" \
  2>"$LOGDIR/hwservicemanager.force-system.err" &

echo "--- start vendor servicemanager normal vendor side ---"
env -i $COMMON \
  chroot "$ROOTFS" /vendor/bin/vndservicemanager \
  >"$LOGDIR/vndservicemanager.normal.out" \
  2>"$LOGDIR/vndservicemanager.normal.err" &

sleep 2

echo "--- managers ---"
ps -ef | grep -E 'servicemanager|hwservicemanager|vndservicemanager' | grep -v grep || true

echo
echo "--- libbinder maps ---"
for p in $(pidof servicemanager hwservicemanager vndservicemanager 2>/dev/null); do
  echo
  echo "=== PID $p ==="
  tr '\0' ' ' < /proc/$p/cmdline; echo
  grep -E 'libbinder|libutils|libcutils' /proc/$p/maps || true
done

echo
echo "--- stderr ---"
tail -100 "$LOGDIR/servicemanager.force-system.err" 2>/dev/null || true
tail -100 "$LOGDIR/hwservicemanager.force-system.err" 2>/dev/null || true
tail -100 "$LOGDIR/vndservicemanager.normal.err" 2>/dev/null || true

echo
echo "--- service list smoke ---"
env -i $COMMON \
  LD_LIBRARY_PATH="$SYSTEM_LIBS" \
  LD_PRELOAD=/system/lib64/libbinder.so \
  chroot "$ROOTFS" /system/bin/service list 2>&1 | head -100
echo "service_list_rc=$?"

echo
echo "RESTART_MANAGERS_FORCE_SYSTEM_SERVICEMANAGER_DONE"
