USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap
PROBE=$SIDE/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

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

echo "--- sanity clean linker env ---"
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || true
grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" | head -3 || true

chroot "$ROOTFS" /system/bin/sh -c '
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
'

echo
echo "--- start zygote without LD_LIBRARY_PATH ---"

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
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
  >"$LOGDIR/zygote64.clean-linker-env.log" 2>&1 &

sleep 8

PID="$(pidof app_process64 || true)"

echo
echo "--- pid ---"
echo "$PID"

echo
echo "--- status ---"
if [ -n "$PID" ]; then
  grep -E "Name|State|Pid|PPid|Threads" /proc/$PID/status
fi

echo
echo "--- sockets ---"
ls -l "$ROOTFS/dev/socket/" | grep -E "zygote|usap" || true

echo
echo "--- log ---"
tail -n 220 "$LOGDIR/zygote64.clean-linker-env.log"

if [ -n "$PID" ] && [ -x "$PROBE" ]; then
  echo
  echo "--- probe ---"
  "$PROBE" "$ROOTFS/dev/socket/zygote" || true

  echo
  echo "--- log after probe ---"
  tail -n 220 "$LOGDIR/zygote64.clean-linker-env.log"
fi

echo
echo "--- maps ART duplicates check ---"
if [ -n "$PID" ]; then
  grep -E 'libart\.so|libartbase\.so|libopenjdkjvm\.so|libartpalette\.so' /proc/$PID/maps || true
fi

echo
echo "--- final pid ---"
pidof app_process64 || true
