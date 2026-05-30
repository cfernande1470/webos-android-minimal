USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
TARGET=$ROOTFS/vendor/lib64/egl
STAGE=$USB/android-sidecar/egl-stage
IMPL="${EGL_IMPL:-mesa}"

echo "--- preparar EGL tmpfs overlay ---"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true

umount "$TARGET" 2>/dev/null || true

rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "--- drivers originales ---"
ls -l "$TARGET" | grep -E "libEGL|libGLES" || true

cp -a "$TARGET"/*.so "$STAGE"/ 2>/dev/null || true

if [ ! -e "$STAGE/libEGL_${IMPL}.so" ]; then
  echo "WARN: no existe libEGL_${IMPL}.so; pruebo angle"
  IMPL=angle
fi

if [ ! -e "$STAGE/libEGL_${IMPL}.so" ]; then
  echo "ERROR: no hay driver EGL usable para mesa ni angle"
  exit 1
fi

echo "--- driver elegido: $IMPL ---"

mount -t tmpfs -o size=64m,mode=0755 tmpfs "$TARGET" || {
  echo "ERROR: no pude montar tmpfs sobre $TARGET"
  exit 1
}

cp -a "$STAGE"/. "$TARGET"/

cd "$TARGET" || exit 1

# Aliases por ro.board.platform=waydroid
ln -sf "libEGL_${IMPL}.so" "libEGL_waydroid.so"
ln -sf "libGLESv1_CM_${IMPL}.so" "libGLESv1_CM_waydroid.so"
ln -sf "libGLESv2_${IMPL}.so" "libGLESv2_waydroid.so"

# Aliases genéricos por si el loader cae a exact-name fallback
ln -sf "libEGL_${IMPL}.so" "libEGL.so"
ln -sf "libGLESv1_CM_${IMPL}.so" "libGLESv1_CM.so"
ln -sf "libGLESv2_${IMPL}.so" "libGLESv2.so"

echo
echo "--- EGL overlay final ---"
ls -l "$TARGET" | grep -E "libEGL|libGLES" || true

echo
echo "--- mount ---"
mount | grep "$TARGET" || true

echo
echo "--- propiedades Android ---"
chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true
