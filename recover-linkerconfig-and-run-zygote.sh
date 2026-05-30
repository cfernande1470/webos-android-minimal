USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs

mkdir -p "$LOGDIR"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true

echo "--- recover /apex ---"
i=0
while [ $i -lt 10 ] && [ ! -x "$ROOTFS/apex/com.android.runtime/bin/linker64" ]; do
  awk -v t="$ROOTFS/apex" '$2 == t {print $0}' /proc/mounts | tail -1
  umount "$ROOTFS/apex" 2>/dev/null || break
  i=$((i + 1))
done

ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" || {
  echo "ERROR: /apex runtime linker missing"
  exit 1
}

echo
echo "--- linkerconfig mounts before ---"
mount | grep " $ROOTFS/linkerconfig " || true

echo
echo "--- cleanup /linkerconfig tmpfs layers ---"
i=0
while [ $i -lt 10 ]; do
  TOP="$(awk -v t="$ROOTFS/linkerconfig" '$2 == t {print $0}' /proc/mounts | tail -1)"
  [ -n "$TOP" ] || break
  echo "umount linkerconfig layer: $TOP"
  umount "$ROOTFS/linkerconfig" 2>/dev/null || break
  i=$((i + 1))
done

mkdir -p "$ROOTFS/linkerconfig"

echo
echo "--- mount fresh /linkerconfig tmpfs ---"
mount -t tmpfs -o mode=0755,size=16m tmpfs "$ROOTFS/linkerconfig" || true
mkdir -p "$ROOTFS/linkerconfig"

echo
echo "--- generar linkerconfig ---"
if [ -x "$ROOTFS/apex/com.android.runtime/bin/linkerconfig" ]; then
  chroot "$ROOTFS" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig \
    >"$LOGDIR/linkerconfig.generate.log" 2>&1 || true
elif [ -x "$ROOTFS/system/bin/linkerconfig" ]; then
  chroot "$ROOTFS" /system/bin/linkerconfig --target /linkerconfig \
    >"$LOGDIR/linkerconfig.generate.log" 2>&1 || true
else
  echo "ERROR: no encuentro linkerconfig binary"
fi

echo "--- linkerconfig generate log ---"
cat "$LOGDIR/linkerconfig.generate.log" 2>/dev/null || true

echo
echo "--- linkerconfig result ---"
ls -la "$ROOTFS/linkerconfig" || true
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || true
head -40 "$ROOTFS/linkerconfig/ld.config.txt" 2>/dev/null || true

echo
echo "--- chroot sanity with LD_CONFIG_FILE ---"
chroot "$ROOTFS" /system/bin/sh -c '
echo CHROOT_OK
/system/bin/getprop ro.hardware.egl
/system/bin/getprop ro.board.platform
/system/bin/getprop ro.zygote.disable_gl_preload
/system/bin/getprop ro.vendor.api_level
' 2>&1

echo
echo "--- run zygote ---"
