USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
TARGET=$ROOTFS/vendor/lib64/egl
STAGE=$USB/android-sidecar/egl-stage-mesa-only

echo "--- preparar EGL mesa-only tmpfs overlay ---"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true

umount "$TARGET" 2>/dev/null || true

rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "--- drivers originales / actuales ---"
ls -l "$TARGET" | grep -E "libEGL|libGLES" || true

# Copiar sólo Mesa desde el directorio real tras desmontar overlay previo.
cp -a "$TARGET/libEGL_mesa.so" "$STAGE"/ 2>/dev/null || true
cp -a "$TARGET/libGLESv1_CM_mesa.so" "$STAGE"/ 2>/dev/null || true
cp -a "$TARGET/libGLESv2_mesa.so" "$STAGE"/ 2>/dev/null || true

if [ ! -e "$STAGE/libEGL_mesa.so" ]; then
  echo "ERROR: no encuentro libEGL_mesa.so"
  exit 1
fi

mount -t tmpfs -o size=64m,mode=0755 tmpfs "$TARGET" || exit 1
cp -a "$STAGE"/. "$TARGET"/

cd "$TARGET" || exit 1

# Nombres genéricos
ln -sf libEGL_mesa.so libEGL.so
ln -sf libGLESv1_CM_mesa.so libGLESv1_CM.so
ln -sf libGLESv2_mesa.so libGLESv2.so

# Nombres por ro.board.platform=waydroid
ln -sf libEGL_mesa.so libEGL_waydroid.so
ln -sf libGLESv1_CM_mesa.so libGLESv1_CM_waydroid.so
ln -sf libGLESv2_mesa.so libGLESv2_waydroid.so

# Trampa deliberada: si el loader intenta angle por escaneo/alphabetical,
# que angle también apunte a Mesa.
ln -sf libEGL_mesa.so libEGL_angle.so
ln -sf libGLESv1_CM_mesa.so libGLESv1_CM_angle.so
ln -sf libGLESv2_mesa.so libGLESv2_angle.so

echo
echo "--- EGL overlay mesa-only final ---"
ls -l "$TARGET" | grep -E "libEGL|libGLES" || true

echo
echo "--- mount ---"
mount | grep "$TARGET" || true

echo
echo "--- propiedades Android ---"
echo "ro.hardware.egl=$(chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true)"
echo "ro.board.platform=$(chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true)"
echo "ro.zygote.disable_gl_preload=$(chroot "$ROOTFS" /system/bin/getprop ro.zygote.disable_gl_preload 2>/dev/null || true)"
