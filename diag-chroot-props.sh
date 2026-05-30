USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs

echo "--- binaries ---"
for f in \
  "$ROOTFS/system/bin/sh" \
  "$ROOTFS/system/bin/getprop" \
  "$ROOTFS/system/bin/init" \
  "$ROOTFS/system/bin/app_process64" \
  "$ROOTFS/apex/com.android.runtime/bin/linker64" \
  "$ROOTFS/system/bin/linker64"
do
  ls -l "$f" 2>/dev/null || echo "MISS $f"
done

echo
echo "--- chroot sh sanity ---"
chroot "$ROOTFS" /system/bin/sh -c 'echo CHROOT_SH_OK; id; ls -ld /dev /dev/__properties__ /dev/socket 2>/dev/null' ; echo "rc=$?"

echo
echo "--- getprop raw ---"
chroot "$ROOTFS" /system/bin/getprop 2>&1 | head -40
echo "rc=${PIPESTATUS:-$?}"

echo
echo "--- getprop specific with rc ---"
for p in ro.board.platform ro.vendor.api_level ro.product.cpu.abilist64 ro.zygote.disable_gl_preload ro.hardware.egl; do
  echo "### $p"
  chroot "$ROOTFS" /system/bin/getprop "$p" 2>&1
  echo "rc=$?"
done

echo
echo "--- property area files ---"
ls -la "$ROOTFS/dev/__properties__" 2>/dev/null | head -60 || true

echo
echo "--- property files content ---"
for f in \
  "$ROOTFS/system/build.prop" \
  "$ROOTFS/vendor/build.prop" \
  "$ROOTFS/system/etc/prop.default" \
  "$ROOTFS/vendor/default.prop"
do
  echo "### $f"
  [ -f "$f" ] && grep -E 'ro\.board\.platform|ro\.vendor\.api_level|ro\.product\.cpu\.abilist64|ro\.zygote\.disable_gl_preload|ro\.hardware\.egl' "$f" || echo "missing"
done

echo
echo "--- current mounts relevant ---"
mount | grep -E "$ROOTFS|build.prop|__properties__|egl" || true

echo
echo "--- last init dmesg ---"
dmesg | grep -E 'init:|property|build.prop|SetupMountNamespaces|Created socket' | tail -120 || true
