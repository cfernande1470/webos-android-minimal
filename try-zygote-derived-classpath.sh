USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
WRAP=$USB/android-sidecar/zygote_socket_wrap
PROBE=$USB/android-sidecar/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket" "$ROOTFS/data/system/environ"

killall app_process64 2>/dev/null || true
killall zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

echo "--- regenerar classpath con derive_classpath ---"
if [ -x "$ROOTFS/apex/com.android.sdkext/bin/derive_classpath" ]; then
  env -i \
    PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
    LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
    LD_LIBRARY_PATH="$LD_PATH" \
    ANDROID_ROOT=/system \
    ANDROID_DATA=/data \
    ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
    ANDROID_ART_ROOT=/apex/com.android.art \
    ANDROID_I18N_ROOT=/apex/com.android.i18n \
    chroot "$ROOTFS" /apex/com.android.sdkext/bin/derive_classpath /data/system/environ/classpath \
    >"$LOGDIR/derive_classpath.log" 2>&1 || true

  cat "$LOGDIR/derive_classpath.log"
fi

echo
echo "--- classpath generado ---"
ls -l "$ENVFILE" 2>/dev/null || true
cat "$ENVFILE" 2>/dev/null || true

BOOTCLASSPATH=""
DEX2OATBOOTCLASSPATH=""
SYSTEMSERVERCLASSPATH=""

if [ -s "$ENVFILE" ]; then
  BOOTCLASSPATH="$(sed -n \
    -e 's/^[[:space:]]*export[[:space:]]\+BOOTCLASSPATH[[:space:]]\+//p' \
    -e 's/^[[:space:]]*BOOTCLASSPATH=//p' \
    "$ENVFILE" | tail -1 | tr -d '"' )"

  DEX2OATBOOTCLASSPATH="$(sed -n \
    -e 's/^[[:space:]]*export[[:space:]]\+DEX2OATBOOTCLASSPATH[[:space:]]\+//p' \
    -e 's/^[[:space:]]*DEX2OATBOOTCLASSPATH=//p' \
    "$ENVFILE" | tail -1 | tr -d '"' )"

  SYSTEMSERVERCLASSPATH="$(sed -n \
    -e 's/^[[:space:]]*export[[:space:]]\+SYSTEMSERVERCLASSPATH[[:space:]]\+//p' \
    -e 's/^[[:space:]]*SYSTEMSERVERCLASSPATH=//p' \
    "$ENVFILE" | tail -1 | tr -d '"' )"
fi

if [ -z "$BOOTCLASSPATH" ]; then
  echo "WARN: derive_classpath no dio BOOTCLASSPATH; fallback manual ampliado"
  BOOTCLASSPATH="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/system/framework/framework.jar:/system/framework/ext.jar:/system/framework/framework-graphics.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar"
fi

[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

echo
echo "--- BOOTCLASSPATH final ---"
echo "$BOOTCLASSPATH" | tr ':' '\n' | nl -ba

echo
echo "--- check jars ---"
OLDIFS="$IFS"
IFS=:
for j in $BOOTCLASSPATH; do
  if [ -e "$ROOTFS$j" ]; then
    echo "OK   $j"
  else
    echo "MISS $j"
  fi
done
IFS="$OLDIFS"

cat > "$LOGDIR/zygote64.derived.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BOOTCLASSPATH
DEX2OATBOOTCLASSPATH=$DEX2OATBOOTCLASSPATH
SYSTEMSERVERCLASSPATH=$SYSTEMSERVERCLASSPATH
ENV

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
  >"$LOGDIR/zygote64.derived.log" 2>&1 &

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
tail -n 300 "$LOGDIR/zygote64.derived.log"

if [ -n "$PID" ] && [ -x "$PROBE" ]; then
  echo
  echo "--- query abi list ---"
  "$PROBE" "$ROOTFS/dev/socket/zygote" || true

  echo
  echo "--- log after probe ---"
  tail -n 300 "$LOGDIR/zygote64.derived.log"
fi

echo
echo "--- final pid ---"
pidof app_process64 || true
