ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar

echo "--- stop android users/managers ---"
killall -9 app_process64 zygote_socket_wrap servicemanager hwservicemanager vndservicemanager service 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f zygote_socket_wrap 2>/dev/null || true
sleep 1

echo
echo "--- current libbinder mounts ---"
mount | grep -E 'libbinder|overrides-libbinder' || true

echo
echo "--- unmount libbinder bind mounts by known files ---"
find "$ROOTFS" -type f \( \
  -name 'libbinder.so' -o \
  -name 'libbinder_ndk.so' -o \
  -name 'libbinder_rpc_unstable.so' \
\) 2>/dev/null | while read -r f; do
  while mount | grep -q " $f "; do
    echo "umount $f"
    umount "$f" 2>/dev/null || break
  done
done

echo
echo "--- unmount any remaining override mounts from /proc/mounts ---"
awk '{print $2}' /proc/mounts | grep -E 'libbinder|overrides-libbinder' | sort -r | while read -r m; do
  m="$(printf '%s\n' "$m" | sed 's#\\040# #g')"
  echo "umount $m"
  umount "$m" 2>/dev/null || true
done

echo
echo "--- final libbinder mounts ---"
mount | grep -E 'libbinder|overrides-libbinder' || true

echo
echo "--- libbinder files now visible ---"
find "$ROOTFS" -type f \( \
  -name 'libbinder.so' -o \
  -name 'libbinder_ndk.so' -o \
  -name 'libbinder_rpc_unstable.so' \
\) -exec ls -l {} \; 2>/dev/null | head -120

echo
echo "CLEAN_LIBBINDER_USERLAND_OVERRIDES_DONE"
