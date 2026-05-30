USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
COREDIR=$SIDE/cores
WRAP=$SIDE/zygote_socket_wrap
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$COREDIR" "$ROOTFS/dev/socket"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true

rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"
rm -f "$COREDIR"/core.*

echo "--- preparar core dumps ---"
OLD_CORE_PATTERN="$(cat /proc/sys/kernel/core_pattern 2>/dev/null || true)"
OLD_CORE_USES_PID="$(cat /proc/sys/kernel/core_uses_pid 2>/dev/null || true)"

echo "$COREDIR/core.%e.%p.%t" > /proc/sys/kernel/core_pattern 2>/dev/null || true
echo 0 > /proc/sys/kernel/core_uses_pid 2>/dev/null || true
echo 2 > /proc/sys/fs/suid_dumpable 2>/dev/null || true

echo "core_pattern=$(cat /proc/sys/kernel/core_pattern 2>/dev/null || true)"
echo "core_uses_pid=$(cat /proc/sys/kernel/core_uses_pid 2>/dev/null || true)"
echo "suid_dumpable=$(cat /proc/sys/fs/suid_dumpable 2>/dev/null || true)"

ulimit -c unlimited

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
echo "--- sanity ---"
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || true
grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" | head -3 || true
chroot "$ROOTFS" /system/bin/sh -c '
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
'

echo
echo "--- start zygote core test ---"

env -i \
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
  >"$LOGDIR/zygote64.coretest.log" 2>&1

RC=$?

sleep 2

echo
echo "--- zygote rc/log ---"
echo "rc=$RC"
tail -n 220 "$LOGDIR/zygote64.coretest.log"

echo
echo "--- cores ---"
ls -lh "$COREDIR"/core.* 2>/dev/null || true

CORE="$(ls -t "$COREDIR"/core.* 2>/dev/null | head -1)"
if [ -n "$CORE" ]; then
  echo "CORE=$CORE"
  file "$CORE" 2>/dev/null || true

  echo
  echo "--- tools ---"
  command -v gdb || true
  command -v gdb-multiarch || true
  command -v eu-stack || true
  command -v readelf || true

  if command -v gdb >/dev/null 2>&1; then
    echo
    echo "--- gdb backtrace ---"
    gdb -batch \
      -ex "set solib-search-path $ROOTFS/system/lib64:$ROOTFS/vendor/lib64:$ROOTFS/apex/com.android.art/lib64:$ROOTFS/apex/com.android.runtime/lib64:$ROOTFS/apex/com.android.i18n/lib64:$ROOTFS/apex/com.android.conscrypt/lib64:$ROOTFS/apex/com.android.os.statsd/lib64" \
      -ex "set sysroot $ROOTFS" \
      -ex "info files" \
      -ex "info sharedlibrary" \
      -ex "thread apply all bt full" \
      "$ROOTFS/system/bin/app_process64" "$CORE" \
      >"$LOGDIR/zygote64.core.gdb.log" 2>&1 || true

    tail -n 240 "$LOGDIR/zygote64.core.gdb.log"
  elif command -v gdb-multiarch >/dev/null 2>&1; then
    echo
    echo "--- gdb-multiarch backtrace ---"
    gdb-multiarch -batch \
      -ex "set solib-search-path $ROOTFS/system/lib64:$ROOTFS/vendor/lib64:$ROOTFS/apex/com.android.art/lib64:$ROOTFS/apex/com.android.runtime/lib64:$ROOTFS/apex/com.android.i18n/lib64:$ROOTFS/apex/com.android.conscrypt/lib64:$ROOTFS/apex/com.android.os.statsd/lib64" \
      -ex "set sysroot $ROOTFS" \
      -ex "info sharedlibrary" \
      -ex "thread apply all bt full" \
      "$ROOTFS/system/bin/app_process64" "$CORE" \
      >"$LOGDIR/zygote64.core.gdb.log" 2>&1 || true

    tail -n 240 "$LOGDIR/zygote64.core.gdb.log"
  else
    echo "NO_GDB_AVAILABLE"
    echo "core listo para copiar: $CORE"
  fi
fi

echo
echo "--- restore core_pattern best effort ---"
[ -n "$OLD_CORE_PATTERN" ] && echo "$OLD_CORE_PATTERN" > /proc/sys/kernel/core_pattern 2>/dev/null || true
[ -n "$OLD_CORE_USES_PID" ] && echo "$OLD_CORE_USES_PID" > /proc/sys/kernel/core_uses_pid 2>/dev/null || true

echo
echo "--- done ---"
