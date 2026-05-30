USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libbinder.so"
PATCH="$OVRDIR/libbinder.ignore-spam-ioctl.so"

# Candidate:
# 0x89bd8 / 0x89be0 build ioctl 0x40046210
# 0x89be8 calls ioctl@plt
OFF_CALL=$((0x89be8))

mkdir -p "$OVRDIR"

echo "--- create cumulative libbinder patch copy ---"
cp "$TGT" "$PATCH" 2>/dev/null || dd if="$TGT" of="$PATCH" bs=1048576 2>/dev/null || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "libbinder ioctl spam call @ 0x89be8: "
od -An -tx1 -j "$OFF_CALL" -N 4 "$PATCH"

echo
echo "--- patch: bl ioctl@plt -> mov w0,#0 ---"
# AArch64 mov w0,#0 = 0x52800000 => 00 00 80 52
printf '\000\000\200\122' | dd of="$PATCH" bs=1 seek="$OFF_CALL" conv=notrunc 2>/dev/null

echo
echo "--- bind patched libbinder.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes ---"
echo -n "libbinder ioctl spam call @ 0x89be8: "
od -An -tx1 -j "$OFF_CALL" -N 4 "$TGT"

echo
echo "LIBBINDER_IGNORE_SPAM_IOCTL_OK"
