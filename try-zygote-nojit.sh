USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap
PROBE=$SIDE/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

run_one() {
  NAME="$1"
  shift
  EXTRA_ART_ARGS="$@"

  echo
  echo "=============================="
  echo "--- variant: $NAME ---"
  echo "--- ART args: $EXTRA_ART_ARGS ---"
  echo "=============================="

  killall -9 app_process64 2>/dev/null || true
  killall -9 zygote_socket_wrap 2>/dev/null || true
  rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

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

  echo "--- sanity ---"
  ls -l "$ROOTFS/linkerconfig/ld.config.txt" || true
  grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" | head -2 || true
  chroot "$ROOTFS" /system/bin/sh -c '
    echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
    echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
    echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
    echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
  '

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
        $EXTRA_ART_ARGS \
        /system/bin \
        --zygote \
        --socket-name=zygote \
        --abi-list=arm64-v8a \
    >"$LOGDIR/zygote64.$NAME.log" 2>&1 &

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
  echo "--- libart-compiler occurrences ---"
  grep -n "libart-compiler\|Unrecognized option\|Fatal signal\|SIGSEGV\|ZygoteInit\|ABI_LIST" "$LOGDIR/zygote64.$NAME.log" | tail -80 || true

  echo
  echo "--- log tail ---"
  tail -n 220 "$LOGDIR/zygote64.$NAME.log"

  if [ -n "$PID" ] && [ -x "$PROBE" ]; then
    echo
    echo "--- query abi list ---"
    "$PROBE" "$ROOTFS/dev/socket/zygote" || true

    echo
    echo "--- log after probe ---"
    tail -n 220 "$LOGDIR/zygote64.$NAME.log"
  fi

  echo
  echo "--- final pid ---"
  pidof app_process64 || true
}

run_one nojit -Xusejit:false

if ! pidof app_process64 >/dev/null 2>&1; then
  run_one nojit_xint -Xusejit:false -Xint
fi
