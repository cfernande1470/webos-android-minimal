USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap
PTRACE=$SIDE/bin/ptrace_segv_wrap
ENVFILE=$ROOTFS/data/system/environ/classpath
SHIM=/data/local/tmp/libzygote_taskprofiles_shim.so
HOST_SHIM=$ROOTFS$SHIM

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

echo "--- sanity shim bt ---"
ls -l "$PTRACE" || exit 1
ls -l "$HOST_SHIM" || exit 1
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || true

echo
echo "--- preload smoke test inside chroot ---"
chroot "$ROOTFS" /system/bin/sh -c '
  echo "LD_PRELOAD=$LD_PRELOAD"
  LD_PRELOAD=/data/local/tmp/libzygote_taskprofiles_shim.so /system/bin/toybox true
  echo "toybox rc=$?"
' 2>&1 || true

echo
echo "--- ptrace zygote with LD_PRELOAD shim ---"

env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_PRELOAD="$SHIM" \
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
  "$PTRACE" \
  "$WRAP" \
    "$ROOTFS" \
    "$ROOTFS/dev/socket/zygote" \
    "$ROOTFS/dev/socket/usap_pool_primary" \
    /system/bin/app_process64 \
      -Xzygote \
      /system/bin --zygote \
      --socket-name=zygote \
      --abi-list=arm64-v8a \
  >"$LOGDIR/zygote64.taskprofiles-shim.fullmaps.log" 2>&1

echo
echo "--- important ---"
grep -n -E 'CRASH STOP|AArch64 regs|pc =|lr/x30|pc owner|lr owner|libzygote_taskprofiles_shim|libprocessgroup|libandroid_runtime|libart\.so|Fatal signal|CANNOT LINK|not accessible|LD_PRELOAD|END CRASH' "$LOGDIR/zygote64.taskprofiles-shim.fullmaps.log" | head -320 || true

echo
echo "--- shim/processgroup maps only ---"
grep -n -E 'libzygote_taskprofiles_shim|libprocessgroup' "$LOGDIR/zygote64.taskprofiles-shim.fullmaps.log" || true

echo
echo "--- tail ---"
tail -n 180 "$LOGDIR/zygote64.taskprofiles-shim.fullmaps.log"
