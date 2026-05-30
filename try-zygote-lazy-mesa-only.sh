USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
WRAP=$USB/android-sidecar/zygote_socket_wrap
PROBE=$USB/android-sidecar/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath
EGLDIR=$ROOTFS/vendor/lib64/egl

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

echo "--- EGL actual ---"
ls -l "$EGLDIR" | grep -E "libEGL|libGLES" || true

echo
echo "--- props ---"
echo "ro.hardware.egl=$(chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true)"
echo "ro.board.platform=$(chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true)"
echo "ro.zygote.disable_gl_preload=$(chroot "$ROOTFS" /system/bin/getprop ro.zygote.disable_gl_preload 2>/dev/null || true)"

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
echo "--- BOOTCLASSPATH count ---"
echo "$BOOTCLASSPATH" | tr ':' '\n' | nl -ba | tail -5

cat > "$LOGDIR/zygote64.lazy-mesa.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BOOTCLASSPATH
DEX2OATBOOTCLASSPATH=$DEX2OATBOOTCLASSPATH
SYSTEMSERVERCLASSPATH=$SYSTEMSERVERCLASSPATH
LAZY_PRELOAD=1
ENV

echo
echo "--- start zygote lazy mesa-only ---"

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
      /system/bin \
      --zygote \
      --socket-name=zygote \
      --abi-list=arm64-v8a \
      --enable-lazy-preload \
  >"$LOGDIR/zygote64.lazy-mesa.log" 2>&1 &

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
echo "--- log before probe ---"
tail -n 250 "$LOGDIR/zygote64.lazy-mesa.log"

if [ -n "$PID" ] && [ -x "$PROBE" ]; then
  echo
  echo "--- query abi list ---"
  "$PROBE" "$ROOTFS/dev/socket/zygote" || true

  echo
  echo "--- log after probe ---"
  tail -n 250 "$LOGDIR/zygote64.lazy-mesa.log"
fi

echo
echo "--- final pid ---"
pidof app_process64 || true
