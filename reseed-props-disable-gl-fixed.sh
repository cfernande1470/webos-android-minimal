USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
PATCHDIR=$SIDE/prop-overrides

mkdir -p "$LOGDIR" "$PATCHDIR" "$ROOTFS/dev/socket"

echo "--- cleanup ---"
killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
killall -9 property_service_ack_shim 2>/dev/null || true
killall -9 init 2>/dev/null || true

# Deshacer bind-mount previo si quedó activo.
umount "$ROOTFS/system/build.prop" 2>/dev/null || true
umount "$ROOTFS/system/etc/prop.default" 2>/dev/null || true
umount "$ROOTFS/vendor/build.prop" 2>/dev/null || true

rm -rf "$ROOTFS/dev/__properties__" 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/property_service" 2>/dev/null || true

echo
echo "--- sidecar binaries ---"
ls -l "$SIDE"/property_service_ack_shim "$SIDE"/zygote_socket_wrap 2>/dev/null || true

SHIM="$SIDE/property_service_ack_shim"
if [ ! -x "$SHIM" ]; then
  echo "ERROR: no encuentro shim ejecutable en $SHIM"
  exit 1
fi

echo
echo "--- localizar build.prop ---"
SYSBUILD="$ROOTFS/system/build.prop"
VENBUILD="$ROOTFS/vendor/build.prop"

[ -f "$SYSBUILD" ] || {
  echo "ERROR: falta $SYSBUILD"
  exit 1
}

echo "SYSBUILD=$SYSBUILD"
[ -f "$VENBUILD" ] && echo "VENBUILD=$VENBUILD"

echo
echo "--- crear override system/build.prop ---"
PATCHED_SYS="$PATCHDIR/system.build.prop.disable-gl"
cp "$SYSBUILD" "$PATCHED_SYS"

grep -v '^ro\.zygote\.disable_gl_preload=' "$PATCHED_SYS" > "$PATCHED_SYS.tmp" || true
grep -v '^ro\.hardware\.egl=' "$PATCHED_SYS.tmp" > "$PATCHED_SYS" || true
rm -f "$PATCHED_SYS.tmp"

cat >> "$PATCHED_SYS" <<'PROPS'

# webos-android-minimal runtime zygote experiment
ro.zygote.disable_gl_preload=true
ro.hardware.egl=mesa
PROPS

tail -n 8 "$PATCHED_SYS"

mount --bind "$PATCHED_SYS" "$SYSBUILD" || {
  echo "ERROR: no pude bind-mount system/build.prop"
  exit 1
}

echo
echo "--- arrancar ack shim correcto ---"
nohup "$SHIM" "$ROOTFS/dev/socket/property_service" \
  </dev/null >"$LOGDIR/property_service_ack_shim.fixed.log" 2>&1 &

sleep 1
ls -l "$ROOTFS/dev/socket/property_service" || {
  echo "ERROR: el shim no creó property_service"
  echo "--- shim log ---"
  cat "$LOGDIR/property_service_ack_shim.fixed.log" 2>/dev/null || true
  exit 1
}

echo
echo "--- init second_stage para sembrar property area ---"
chroot "$ROOTFS" /system/bin/init second_stage \
  >"$LOGDIR/init.second_stage.fixed.log" 2>&1 &

INITPID="$!"
sleep 7
kill "$INITPID" 2>/dev/null || true
sleep 1
kill -9 "$INITPID" 2>/dev/null || true

echo
echo "--- sanity exec dentro chroot ---"
ls -l "$ROOTFS/system/bin/app_process64" "$ROOTFS/system/bin/linker64" 2>/dev/null || true
chroot "$ROOTFS" /system/bin/toybox true && echo "CHROOT_EXEC_OK" || echo "CHROOT_EXEC_FAIL"

echo
echo "--- getprop check ---"
echo "ro.zygote.disable_gl_preload=$(chroot "$ROOTFS" /system/bin/getprop ro.zygote.disable_gl_preload 2>/dev/null || true)"
echo "ro.hardware.egl=$(chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true)"
echo "ro.board.platform=$(chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true)"
echo "ro.vendor.api_level=$(chroot "$ROOTFS" /system/bin/getprop ro.vendor.api_level 2>/dev/null || true)"
echo "ro.product.cpu.abilist64=$(chroot "$ROOTFS" /system/bin/getprop ro.product.cpu.abilist64 2>/dev/null || true)"

echo
echo "--- property area head ---"
ls -la "$ROOTFS/dev/__properties__" 2>/dev/null | head -20 || true

echo
echo "--- shim log ---"
tail -n 80 "$LOGDIR/property_service_ack_shim.fixed.log" 2>/dev/null || true

echo
echo "--- init log tail ---"
tail -n 120 "$LOGDIR/init.second_stage.fixed.log" 2>/dev/null || true
