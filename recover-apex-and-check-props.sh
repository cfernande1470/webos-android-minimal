USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs

echo "--- cleanup userland android ---"
killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true

recover_apex() {
  echo
  echo "--- apex mounts before ---"
  mount | grep " $ROOTFS/apex " || true

  i=0
  while [ $i -lt 10 ]; do
    if [ -x "$ROOTFS/apex/com.android.runtime/bin/linker64" ]; then
      break
    fi

    TOP="$(awk -v t="$ROOTFS/apex" '$2 == t {print $0}' /proc/mounts | tail -1)"
    [ -n "$TOP" ] || break

    echo "umount apex layer: $TOP"
    umount "$ROOTFS/apex" 2>/dev/null || break
    i=$((i + 1))
  done

  if [ ! -x "$ROOTFS/apex/com.android.runtime/bin/linker64" ]; then
    if [ -x "$ROOTFS/system/apex/com.android.runtime/bin/linker64" ]; then
      echo "bind-mount $ROOTFS/system/apex -> $ROOTFS/apex"
      mkdir -p "$ROOTFS/apex"
      mount --bind "$ROOTFS/system/apex" "$ROOTFS/apex"
    fi
  fi

  echo
  echo "--- apex final ---"
  ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" 2>/dev/null || true
  ls -ld "$ROOTFS/apex/com.android.runtime" 2>/dev/null || true

  echo
  echo "--- apex mounts after ---"
  mount | grep " $ROOTFS/apex " || true

  [ -x "$ROOTFS/apex/com.android.runtime/bin/linker64" ]
}

recover_apex || {
  echo "ERROR: no pude recuperar /apex/com.android.runtime/bin/linker64"
  echo "--- busca linker64 ---"
  find "$ROOTFS" -path "*com.android.runtime/bin/linker64" -print 2>/dev/null
  exit 1
}

echo
echo "--- chroot sanity ---"
chroot "$ROOTFS" /system/bin/sh -c '
echo CHROOT_SH_OK
echo "sh=$0"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
echo "ro.product.cpu.abilist64=$(/system/bin/getprop ro.product.cpu.abilist64)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
'
echo "rc=$?"

echo
echo "--- system/build.prop current ---"
grep -E 'ro\.zygote\.disable_gl_preload|ro\.hardware\.egl' "$ROOTFS/system/build.prop" 2>/dev/null || true

echo
echo "--- vendor/build.prop current ---"
grep -E 'ro\.board\.platform|ro\.vendor\.api_level|ro\.product\.cpu\.abilist' "$ROOTFS/vendor/build.prop" 2>/dev/null || true
