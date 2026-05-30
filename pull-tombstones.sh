ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- tombstones ---"
find "$ROOTFS/data/tombstones" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -5

LAST="$(find "$ROOTFS/data/tombstones" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"
if [ -n "$LAST" ]; then
  echo
  echo "--- latest tombstone: $LAST ---"
  cat "$LAST" | head -260
else
  echo "NO_TOMBSTONE_FOUND"
fi
