USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

killall app_process64 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

BCP=""
for j in \
  /apex/com.android.art/javalib/core-oj.jar \
  /apex/com.android.art/javalib/core-libart.jar \
  /apex/com.android.i18n/javalib/core-icu4j.jar \
  /apex/com.android.conscrypt/javalib/conscrypt.jar \
  /apex/com.android.media/javalib/updatable-media.jar \
  /system/framework/framework.jar \
  /system/framework/ext.jar \
  /system/framework/framework-graphics.jar \
  /system/framework/telephony-common.jar \
  /system/framework/voip-common.jar \
  /system/framework/ims-common.jar
do
  [ -f "$ROOTFS$j" ] && BCP="${BCP:+$BCP:}$j"
done

cat > "$LOGDIR/zygote64.apexns.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BCP
ENV

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  BOOTCLASSPATH="$BCP" \
  DEX2OATBOOTCLASSPATH="$BCP" \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  ANDROID_I18N_ROOT=/apex/com.android.i18n \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  chroot "$ROOTFS" /system/bin/app_process64 \
    -Xzygote /system/bin --zygote \
    --socket-name=zygote \
    --abi-list=arm64-v8a \
  >"$LOGDIR/zygote64.apexns.log" 2>&1 &

sleep 6

PID="$(pidof app_process64 || true)"

echo "--- pid ---"
echo "$PID"

echo
echo "--- status ---"
if [ -n "$PID" ]; then
  grep -E "Name|State|Pid|PPid|Threads" /proc/$PID/status
fi

echo
echo "--- sockets rootfs ---"
ls -l "$ROOTFS/dev/socket/" | grep -E "zygote|usap" || true

echo
echo "--- log ---"
tail -n 260 "$LOGDIR/zygote64.apexns.log"

echo
echo "--- cmdline ---"
if [ -n "$PID" ]; then
  tr "\0" " " < /proc/$PID/cmdline
  echo
fi
