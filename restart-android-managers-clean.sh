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

echo "--- verify no libbinder mounts ---"
mount | grep -E 'libbinder|overrides-libbinder' || true

ENV_COMMON='PATH=/system/bin:/vendor/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin ANDROID_ROOT=/system ANDROID_DATA=/data ANDROID_STORAGE=/storage ANDROID_RUNTIME_ROOT=/apex/com.android.runtime ANDROID_TZDATA_ROOT=/apex/com.android.tzdata ANDROID_ART_ROOT=/apex/com.android.art LD_CONFIG_FILE=/linkerconfig/ld.config.txt'

echo "--- start servicemanager ---"
env -i $ENV_COMMON chroot "$ROOTFS" /system/bin/servicemanager >"$LOGDIR/servicemanager.clean.out" 2>"$LOGDIR/servicemanager.clean.err" &

echo "--- start hwservicemanager ---"
env -i $ENV_COMMON chroot "$ROOTFS" /system/bin/hwservicemanager >"$LOGDIR/hwservicemanager.clean.out" 2>"$LOGDIR/hwservicemanager.clean.err" &

echo "--- start vndservicemanager ---"
env -i $ENV_COMMON chroot "$ROOTFS" /vendor/bin/vndservicemanager >"$LOGDIR/vndservicemanager.clean.out" 2>"$LOGDIR/vndservicemanager.clean.err" &

sleep 2

echo "--- managers ---"
ps -ef | grep -E 'servicemanager|hwservicemanager|vndservicemanager' | grep -v grep || true

echo
echo "--- manager stderr ---"
tail -80 "$LOGDIR/servicemanager.clean.err" 2>/dev/null || true
tail -80 "$LOGDIR/hwservicemanager.clean.err" 2>/dev/null || true
tail -80 "$LOGDIR/vndservicemanager.clean.err" 2>/dev/null || true

echo
echo "--- service list smoke ---"
env -i $ENV_COMMON chroot "$ROOTFS" /system/bin/service list 2>&1 | head -80
echo "service_list_rc=$?"

echo
echo "RESTART_ANDROID_MANAGERS_CLEAN_DONE"
