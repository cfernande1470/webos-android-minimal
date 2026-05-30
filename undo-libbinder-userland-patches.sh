ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- stop android users ---"
killall -9 app_process64 zygote_socket_wrap servicemanager hwservicemanager vndservicemanager 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f zygote_socket_wrap 2>/dev/null || true
sleep 1

echo
echo "--- unmount libbinder bind mounts ---"
for f in $(find "$ROOTFS" -type f \( -name 'libbinder.so' -o -name 'libbinder_ndk.so' -o -name 'libbinder_rpc_unstable.so' \) 2>/dev/null); do
  while mount | grep -q " $f "; do
    echo "umount $f"
    umount "$f" 2>/dev/null || break
  done
done

echo
echo "--- remaining libbinder mounts ---"
mount | grep -E 'libbinder|vndk' || true

echo
echo "UNDO_LIBBINDER_USERLAND_PATCHES_DONE"
