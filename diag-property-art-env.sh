ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- property sockets / files ---"
ls -la /dev/socket 2>/dev/null || true
ls -la "$ROOTFS/dev/socket" 2>/dev/null || true
ls -la /dev/__properties__ 2>/dev/null || true
ls -la "$ROOTFS/dev/__properties__" 2>/dev/null || true
find /dev "$ROOTFS/dev" -maxdepth 3 \( -iname '*prop*' -o -iname '*socket*' \) -ls 2>/dev/null | head -200

echo
echo "--- android init/property/service processes ---"
ps -ef | grep -E 'init|property|servicemanager|zygote|system_server|app_process' | grep -v grep || true

echo
echo "--- try getprop inside rootfs ---"
env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/getprop 2>&1 | head -80
echo "getprop_rc=$?"

echo
echo "--- try setprop inside rootfs ---"
env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/setprop debug.webos_android.test 1 2>&1
echo "setprop_rc=$?"

echo
echo "--- data dirs / permissions ---"
ls -ld "$ROOTFS/data" "$ROOTFS/data/system" "$ROOTFS/data/dalvik-cache" "$ROOTFS/data/misc" "$ROOTFS/data/misc/profiles" 2>/dev/null || true
find "$ROOTFS/data" -maxdepth 2 -type d -printf '%m %u:%g %p\n' 2>/dev/null | head -120

echo
echo "--- art/dalvik props from default prop files ---"
grep -RInE '^(ro\.zygote|dalvik\.|persist\.device_config\.runtime|debug\.|sys\.)' \
  "$ROOTFS/default.prop" \
  "$ROOTFS/system/build.prop" \
  "$ROOTFS/vendor/build.prop" \
  "$ROOTFS/product/build.prop" \
  "$ROOTFS/system_ext/build.prop" \
  2>/dev/null | head -240

echo
echo "--- recent kernel/art/property logs ---"
dmesg | grep -iE 'art|zygote|system_server|property|segv|fault|signal|binder|avc|selinux|denied|killed|oom' | tail -220 || true

echo
echo "DIAG_PROPERTY_ART_ENV_DONE"
