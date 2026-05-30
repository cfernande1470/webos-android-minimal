ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- clear old tombstones ---"
rm -f "$ROOTFS/data/tombstones/"* 2>/dev/null || true
mkdir -p "$ROOTFS/data/tombstones"

echo
echo "--- tombstones before ---"
find "$ROOTFS/data/tombstones" -maxdepth 1 -type f -ls 2>/dev/null || true

echo
echo "COLLECT_NORMAL_TOMBSTONE_READY"
