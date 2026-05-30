ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
OVR=$SIDE/overrides-env-files

echo "--- stop zygote/system_server only ---"
killall -9 app_process64 system_server zygote_socket_wrap 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f system_server 2>/dev/null || true
sleep 1

mkdir -p "$OVR"

echo
echo "--- unmount previous env overrides ---"
mount | grep "$OVR" | awk '{print $3}' | sort -r | while read -r m; do
  echo "umount $m"
  umount "$m" 2>/dev/null || true
done

echo
echo "--- overlay vendor/etc with writable copy ---"
while mount | grep -q " $ROOTFS/vendor/etc "; do
  umount "$ROOTFS/vendor/etc" 2>/dev/null || break
done

rm -rf "$OVR/vendor_etc"
mkdir -p "$OVR/vendor_etc"

if [ -d "$ROOTFS/vendor/etc" ]; then
  cp -a "$ROOTFS/vendor/etc/." "$OVR/vendor_etc/" 2>/dev/null || true
fi

touch "$OVR/vendor_etc/public.libraries.txt"
chmod 644 "$OVR/vendor_etc/public.libraries.txt"

mount -o bind "$OVR/vendor_etc" "$ROOTFS/vendor/etc"

echo
echo "--- bind-fix empty XML files ---"
find "$ROOTFS/system/etc" "$ROOTFS/system_ext/etc" "$ROOTFS/product/etc" "$ROOTFS/vendor/etc" \
  -type f -name '*.xml' -size 0 2>/dev/null | while read -r f; do

  rel="${f#$ROOTFS/}"
  dst="$OVR/files/$rel"
  mkdir -p "$(dirname "$dst")"

  echo "fix empty xml by bind: $f"
  printf '<permissions>\n</permissions>\n' > "$dst"
  chmod 644 "$dst"

  while mount | grep -q " $f "; do
    umount "$f" 2>/dev/null || break
  done

  mount -o bind "$dst" "$f"
done

echo
echo "--- verify mounts ---"
mount | grep "$OVR" || true

echo
echo "--- verify files ---"
ls -l "$ROOTFS/vendor/etc/public.libraries.txt" 2>/dev/null || true
find "$ROOTFS/system/etc" "$ROOTFS/system_ext/etc" "$ROOTFS/product/etc" "$ROOTFS/vendor/etc" \
  -type f -name '*.xml' -size 0 2>/dev/null -print || true

echo
echo "FIX_SYSTEMSERVER_ENV_READONLY_WITH_BINDS_DONE"
