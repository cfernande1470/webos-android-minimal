USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs

SRC="$ROOTFS/data/local/tmp/libprocessgroup.stub.so"
TGT="$ROOTFS/system/lib64/libprocessgroup.so"

echo "--- sanity ---"
ls -l "$SRC" || exit 1
ls -l "$TGT" || exit 1

echo
echo "--- unmount previous libprocessgroup override ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

echo
echo "--- bind stub over libprocessgroup.so ---"
mount --bind "$SRC" "$TGT" || exit 1

echo
echo "--- mount check ---"
mount | grep " $TGT " || true

echo
echo "--- final target check ---"
ls -l "$TGT"
echo "LIBPROCESSGROUP_STUB_OK"
