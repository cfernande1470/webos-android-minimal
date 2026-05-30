USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
PATCHDIR=$SIDE/prop-overrides

mkdir -p "$LOGDIR" "$PATCHDIR" "$ROOTFS/dev/socket"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
killall -9 property_service_ack_shim 2>/dev/null || true

echo "--- localizar prop.default ---"
TARGET=""
for f in \
  "$ROOTFS/system/etc/prop.default" \
  "$ROOTFS/system/build.prop" \
  "$ROOTFS/vendor/default.prop" \
  "$ROOTFS/vendor/build.prop"
do
  if [ -f "$f" ]; then
    echo "FOUND $f"
  fi
done

if [ -f "$ROOTFS/system/etc/prop.default" ]; then
  TARGET="$ROOTFS/system/etc/prop.default"
elif [ -f "$ROOTFS/system/build.prop" ]; then
  TARGET="$ROOTFS/system/build.prop"
else
  echo "ERROR: no encuentro prop.default/build.prop"
  exit 1
fi

PATCHED="$PATCHDIR/$(basename "$TARGET").zygote-disable-gl"

echo
echo "--- crear override de $TARGET ---"
cp "$TARGET" "$PATCHED"

# Evitar duplicados en el fichero parcheado.
grep -v '^ro\.zygote\.disable_gl_preload=' "$PATCHED" > "$PATCHED.tmp" || true
grep -v '^ro\.hardware\.egl=' "$PATCHED.tmp" > "$PATCHED" || true
rm -f "$PATCHED.tmp"

cat >> "$PATCHED" <<'PROPS'

# webos-android-minimal runtime zygote experiment
ro.zygote.disable_gl_preload=true
ro.hardware.egl=mesa
PROPS

echo "--- override tail ---"
tail -n 12 "$PATCHED"

echo
echo "--- bind mount override ---"
umount "$TARGET" 2>/dev/null || true
mount --bind "$PATCHED" "$TARGET" || {
  echo "ERROR: no pude bind-mount $PATCHED sobre $TARGET"
  exit 1
}

mount | grep "$TARGET" || true

echo
echo "--- reiniciar property area ---"
rm -rf "$ROOTFS/dev/__properties__" 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/property_service" 2>/dev/null || true

nohup "$SIDE/bin/property_service_ack_shim" "$ROOTFS/dev/socket/property_service" \
  </dev/null >"$LOGDIR/property_service_ack_shim.disable_gl.log" 2>&1 &

sleep 1
ls -l "$ROOTFS/dev/socket/property_service" || true

echo
echo "--- init second_stage para sembrar properties ---"
chroot "$ROOTFS" /system/bin/init second_stage \
  >"$LOGDIR/init.second_stage.disable_gl.log" 2>&1 &

INITPID="$!"
sleep 7
kill "$INITPID" 2>/dev/null || true
sleep 1
kill -9 "$INITPID" 2>/dev/null || true

echo
echo "--- getprop check ---"
echo "ro.zygote.disable_gl_preload=$(chroot "$ROOTFS" /system/bin/getprop ro.zygote.disable_gl_preload 2>/dev/null || true)"
echo "ro.hardware.egl=$(chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true)"
echo "ro.board.platform=$(chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true)"
echo "ro.vendor.api_level=$(chroot "$ROOTFS" /system/bin/getprop ro.vendor.api_level 2>/dev/null || true)"

echo
echo "--- property area ---"
ls -la "$ROOTFS/dev/__properties__" 2>/dev/null | head -40 || true

echo
echo "--- init property log tail ---"
tail -n 120 "$LOGDIR/init.second_stage.disable_gl.log" 2>/dev/null || true
