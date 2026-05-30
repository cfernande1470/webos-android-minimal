USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap
TOMBWRAP=$SIDE/bin/tombstoned_socket_wrap
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket" "$ROOTFS/data/tombstones"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
killall -9 tombstoned 2>/dev/null || true
killall -9 tombstoned_socket_wrap 2>/dev/null || true

rm -f "$ROOTFS/dev/socket/zygote" \
      "$ROOTFS/dev/socket/usap_pool_primary" \
      "$ROOTFS/dev/socket/tombstoned_crash" \
      "$ROOTFS/dev/socket/tombstoned_intercept" \
      "$ROOTFS/dev/socket/tombstoned_java_trace"

rm -f "$ROOTFS/data/tombstones"/tombstone_* 2>/dev/null || true

echo "--- sanity ---"
ls -l "$TOMBWRAP" || exit 1
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || true
grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" | head -3 || true

chroot "$ROOTFS" /system/bin/sh -c '
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
'

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

read_env_var() {
  VAR="$1"
  sed -n \
    -e "s/^[[:space:]]*export[[:space:]]\+$VAR[[:space:]]\+//p" \
    -e "s/^[[:space:]]*$VAR=//p" \
    "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"'
}

BOOTCLASSPATH="$(read_env_var BOOTCLASSPATH)"
DEX2OATBOOTCLASSPATH="$(read_env_var DEX2OATBOOTCLASSPATH)"
SYSTEMSERVERCLASSPATH="$(read_env_var SYSTEMSERVERCLASSPATH)"
[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

echo
echo "--- start tombstoned via socket wrapper ---"
nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  "$TOMBWRAP" "$ROOTFS" /system/bin/tombstoned \
  >"$LOGDIR/tombstoned.socketwrap.log" 2>&1 &

sleep 1

echo "--- tombstoned pid/socket ---"
pidof tombstoned || true
ls -l "$ROOTFS/dev/socket/" | grep tombstoned || true
tail -n 80 "$LOGDIR/tombstoned.socketwrap.log" 2>/dev/null || true

echo
echo "--- start zygote ---"
nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  BOOTCLASSPATH="$BOOTCLASSPATH" \
  DEX2OATBOOTCLASSPATH="$DEX2OATBOOTCLASSPATH" \
  SYSTEMSERVERCLASSPATH="$SYSTEMSERVERCLASSPATH" \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  ANDROID_I18N_ROOT=/apex/com.android.i18n \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  "$WRAP" \
    "$ROOTFS" \
    "$ROOTFS/dev/socket/zygote" \
    "$ROOTFS/dev/socket/usap_pool_primary" \
    /system/bin/app_process64 \
      -Xzygote \
      /system/bin --zygote \
      --socket-name=zygote \
      --abi-list=arm64-v8a \
  >"$LOGDIR/zygote64.tombwrap.log" 2>&1 &

sleep 8

echo
echo "--- zygote pid ---"
pidof app_process64 || true

echo
echo "--- zygote log ---"
tail -n 160 "$LOGDIR/zygote64.tombwrap.log"

echo
echo "--- tombstoned log ---"
tail -n 200 "$LOGDIR/tombstoned.socketwrap.log" 2>/dev/null || true

echo
echo "--- tombstones ---"
ls -lt "$ROOTFS/data/tombstones" 2>/dev/null | head || true
LATEST="$(ls -t "$ROOTFS/data/tombstones"/tombstone_* 2>/dev/null | head -1)"
if [ -n "$LATEST" ]; then
  echo "--- latest tombstone: $LATEST ---"
  sed -n '1,260p' "$LATEST"
else
  echo "NO_TOMBSTONE"
fi

echo
echo "--- dmesg crash tail ---"
dmesg | grep -E "app_process|zygote|SIGSEGV|Fatal signal|tombstoned|debuggerd|libart|libandroid_runtime" | tail -200 || true
