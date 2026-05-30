USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

killall app_process64 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

ENVRC="$(grep -Rsl "export BOOTCLASSPATH" \
  "$ROOTFS/system/etc/init" \
  "$ROOTFS/system/etc" \
  "$ROOTFS/vendor/etc/init" \
  "$ROOTFS/product/etc/init" \
  "$ROOTFS/system_ext/etc/init" \
  2>/dev/null | head -1)"

if [ -n "$ENVRC" ]; then
  echo "ENVRC=$ENVRC"
  BCP="$(sed -n 's/^[[:space:]]*export[[:space:]]*BOOTCLASSPATH[[:space:]]*//p' "$ENVRC" | tail -1)"
  DEXBCP="$(sed -n 's/^[[:space:]]*export[[:space:]]*DEX2OATBOOTCLASSPATH[[:space:]]*//p' "$ENVRC" | tail -1)"
else
  echo "NO ENVRC; fallback manual"
  BCP="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/system/framework/framework.jar:/system/framework/ext.jar:/system/framework/framework-graphics.jar"
  DEXBCP="$BCP"
fi

[ -z "$DEXBCP" ] && DEXBCP="$BCP"

cat > "$LOGDIR/zygote64.realbcp.env.log" <<ENV
ENVRC=$ENVRC
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BCP
DEX2OATBOOTCLASSPATH=$DEXBCP
ENV

echo "--- usar BCP ---"
cat "$LOGDIR/zygote64.realbcp.env.log"

echo
echo "--- comprobar entradas BCP existentes ---"
OLDIFS="$IFS"
IFS=:
for j in $BCP; do
  if [ -e "$ROOTFS$j" ]; then
    echo "OK $j"
  else
    echo "MISS $j"
  fi
done
IFS="$OLDIFS"

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  BOOTCLASSPATH="$BCP" \
  DEX2OATBOOTCLASSPATH="$DEXBCP" \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  ANDROID_I18N_ROOT=/apex/com.android.i18n \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  chroot "$ROOTFS" /system/bin/app_process64 \
    -Xzygote \
    /system/bin --zygote \
    --socket-name=zygote \
    --abi-list=arm64-v8a \
  >"$LOGDIR/zygote64.realbcp.log" 2>&1 &

sleep 6

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
echo "--- sockets rootfs ---"
ls -l "$ROOTFS/dev/socket/" | grep -E "zygote|usap" || true

echo
echo "--- log ---"
tail -n 300 "$LOGDIR/zygote64.realbcp.log"

echo
echo "--- cmdline ---"
if [ -n "$PID" ]; then
  tr "\0" " " < /proc/$PID/cmdline
  echo
fi
