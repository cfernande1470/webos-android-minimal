USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap
PROBE=$SIDE/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket" "$ROOTFS/data/tombstones"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
killall -9 tombstoned 2>/dev/null || true

rm -f "$ROOTFS/dev/socket/zygote" \
      "$ROOTFS/dev/socket/usap_pool_primary" \
      "$ROOTFS/dev/socket/tombstoned_crash" \
      "$ROOTFS/dev/socket/tombstoned_intercept" \
      "$ROOTFS/dev/socket/tombstoned_java_trace"

echo "--- sanity actual ---"
echo "apex linker:"
ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" 2>/dev/null || true
echo
echo "linkerconfig:"
ls -l "$ROOTFS/linkerconfig/ld.config.txt" 2>/dev/null || true
grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" 2>/dev/null | head -3 || true
grep -n 'vndk' "$ROOTFS/linkerconfig/ld.config.txt" 2>/dev/null | head -3 || true

echo
echo "--- props ---"
chroot "$ROOTFS" /system/bin/sh -c '
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
'

echo
echo "--- EGL ---"
ls -l "$ROOTFS/vendor/lib64/egl" | grep -E "libEGL|libGLES" || true

echo
echo "--- start tombstoned ---"
if [ -x "$ROOTFS/system/bin/tombstoned" ]; then
  nohup env -i \
    PATH=/system/bin:/apex/com.android.runtime/bin \
    LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
    ANDROID_ROOT=/system \
    ANDROID_DATA=/data \
    chroot "$ROOTFS" /system/bin/tombstoned \
    >"$LOGDIR/tombstoned.manual.log" 2>&1 &
  sleep 1
else
  echo "NO_TOMBSTONED_BINARY"
fi

ls -l "$ROOTFS/dev/socket/" | grep tombstoned || true
tail -n 80 "$LOGDIR/tombstoned.manual.log" 2>/dev/null || true

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
echo "--- start zygote debug ---"

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  LD_DEBUG=1 \
  DEBUG_LD_ALL=1 \
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
  >"$LOGDIR/zygote64.segv.debug.log" 2>&1 &

# Intentar pillar el proceso vivo para debuggerd/maps.
for i in $(seq 1 200); do
  PID="$(pidof app_process64 2>/dev/null || true)"
  if [ -n "$PID" ]; then
    echo "PID_SEEN=$PID" > "$LOGDIR/zygote64.segv.pidseen.log"
    cat /proc/$PID/maps > "$LOGDIR/zygote64.segv.maps.log" 2>/dev/null || true
    cat /proc/$PID/status > "$LOGDIR/zygote64.segv.status.log" 2>/dev/null || true

    if [ -x "$ROOTFS/system/bin/debuggerd" ]; then
      chroot "$ROOTFS" /system/bin/debuggerd -b "$PID" \
        >"$LOGDIR/zygote64.segv.debuggerd.log" 2>&1 || true
    fi
    break
  fi
done

sleep 5

echo
echo "--- pid final ---"
pidof app_process64 || true

echo
echo "--- sockets ---"
ls -l "$ROOTFS/dev/socket/" | grep -E "zygote|usap|tombstoned" || true

echo
echo "--- zygote log tail ---"
tail -n 260 "$LOGDIR/zygote64.segv.debug.log"

echo
echo "--- debuggerd capture ---"
cat "$LOGDIR/zygote64.segv.pidseen.log" 2>/dev/null || true
cat "$LOGDIR/zygote64.segv.status.log" 2>/dev/null || true
tail -n 200 "$LOGDIR/zygote64.segv.debuggerd.log" 2>/dev/null || true

echo
echo "--- maps tail/head if captured ---"
head -40 "$LOGDIR/zygote64.segv.maps.log" 2>/dev/null || true
echo "---"
tail -40 "$LOGDIR/zygote64.segv.maps.log" 2>/dev/null || true

echo
echo "--- tombstones ---"
ls -lt "$ROOTFS/data/tombstones" 2>/dev/null | head || true
LATEST="$(ls -t "$ROOTFS/data/tombstones"/tombstone_* 2>/dev/null | head -1)"
if [ -n "$LATEST" ]; then
  echo "--- latest tombstone: $LATEST ---"
  sed -n '1,220p' "$LATEST"
fi

echo
echo "--- dmesg crash/linker tail ---"
dmesg | grep -E "9577|app_process|zygote|SIGSEGV|Fatal signal|linker|debuggerd|tombstoned|libart|libandroid_runtime" | tail -160 || true

echo
echo "--- done ---"
