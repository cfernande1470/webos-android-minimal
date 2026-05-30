USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
WRAP=$USB/android-sidecar/zygote_socket_wrap
PROBE=$USB/android-sidecar/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

BOOTCLASSPATH="$(sed -n \
  -e 's/^[[:space:]]*export[[:space:]]\+BOOTCLASSPATH[[:space:]]\+//p' \
  -e 's/^[[:space:]]*BOOTCLASSPATH=//p' \
  "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"' )"

DEX2OATBOOTCLASSPATH="$(sed -n \
  -e 's/^[[:space:]]*export[[:space:]]\+DEX2OATBOOTCLASSPATH[[:space:]]\+//p' \
  -e 's/^[[:space:]]*DEX2OATBOOTCLASSPATH=//p' \
  "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"' )"

SYSTEMSERVERCLASSPATH="$(sed -n \
  -e 's/^[[:space:]]*export[[:space:]]\+SYSTEMSERVERCLASSPATH[[:space:]]\+//p' \
  -e 's/^[[:space:]]*SYSTEMSERVERCLASSPATH=//p' \
  "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"' )"

if [ -z "$BOOTCLASSPATH" ]; then
  BOOTCLASSPATH="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/system/framework/framework.jar:/system/framework/ext.jar:/system/framework/framework-graphics.jar"
fi

[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

cat > "$LOGDIR/zygote64.lazy.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BOOTCLASSPATH
DEX2OATBOOTCLASSPATH=$DEX2OATBOOTCLASSPATH
SYSTEMSERVERCLASSPATH=$SYSTEMSERVERCLASSPATH
LAZY_PRELOAD=1
ENV

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
      --enable-lazy-preload \
  >"$LOGDIR/zygote64.lazy.log" 2>&1 &

sleep 8

PID="$(pidof app_process64 || true)"

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
tail -n 200 "$LOGDIR/zygote64.lazy.log"

if [ -n "$PID" ] && [ -x "$PROBE" ]; then
  echo
  echo "--- query abi list ---"
  "$PROBE" "$ROOTFS/dev/socket/zygote" || true
fi

echo
echo "--- log after probe ---"
tail -n 300 "$LOGDIR/zygote64.lazy.log"

echo
echo "--- final pid ---"
pidof app_process64 || true
