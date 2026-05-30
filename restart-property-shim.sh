USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs

mkdir -p "$ROOTFS/dev/socket" "$LOGDIR"

echo "--- find property shim ---"
SHIM=""
for p in \
  "$SIDE/bin/property_service_ack_shim" \
  "$SIDE/property_service_ack_shim" \
  "$USB/property_service_ack_shim"
do
  if [ -x "$p" ]; then
    SHIM="$p"
    break
  fi
done

if [ -z "$SHIM" ]; then
  SHIM="$(find "$USB" -name property_service_ack_shim -type f -perm /111 2>/dev/null | head -1)"
fi

echo "SHIM=$SHIM"

if [ -z "$SHIM" ] || [ ! -x "$SHIM" ]; then
  echo "ERROR: property_service_ack_shim not found/executable"
  echo "Run on NanoPi:"
  echo "  ./scripts/build-property-shim.sh"
  echo "  scp dist/property_service_ack_shim root@\$TV_IP:/media/internal/android-usb/android-sidecar/bin/"
  exit 1
fi

echo
echo "--- kill old shim ---"
killall property_service_ack_shim 2>/dev/null || true
pkill -f property_service_ack_shim 2>/dev/null || true
sleep 1

echo
echo "--- remove stale property socket ---"
rm -f "$ROOTFS/dev/socket/property_service"
rm -f /dev/socket/property_service 2>/dev/null || true

echo
echo "--- start property shim ---"
nohup "$SHIM" "$ROOTFS/dev/socket/property_service" \
  > "$LOGDIR/property_service_ack_shim.log" 2>&1 &

sleep 1

echo
echo "--- shim process ---"
ps -ef | grep property_service_ack_shim | grep -v grep || true

echo
echo "--- socket ---"
ls -l "$ROOTFS/dev/socket/property_service" /dev/socket/property_service 2>/dev/null || true

echo
echo "--- shim log ---"
cat "$LOGDIR/property_service_ack_shim.log" 2>/dev/null || true

echo
echo "--- test setprop inside rootfs ---"
env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/setprop debug.webos_android.test 2 2>&1
echo "setprop_test_rc=$?"

echo
echo "RESTART_PROPERTY_SHIM_DONE"
