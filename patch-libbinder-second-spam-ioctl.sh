USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides-libbinder-spam

mkdir -p "$OVRDIR"

for TGT in \
  "$ROOTFS/system/lib64/libbinder.so" \
  "$ROOTFS/apex/com.android.vndk.v33/lib64/libbinder.so" \
  "$ROOTFS/apex/com.android.vndk.current/lib64/libbinder.so" \
  "$ROOTFS/system/apex/com.android.vndk.current/lib64/libbinder.so"
do
  [ -f "$TGT" ] || continue

  PATCH="$OVRDIR/$(echo "$TGT" | tr '/:' '__').second.so"
  echo
  echo "### $TGT"

  cp "$TGT" "$PATCH" 2>/dev/null || dd if="$TGT" of="$PATCH" bs=1048576 2>/dev/null || continue
  chmod 644 "$PATCH"

  for OFF in 0x8a238 0x89be8 0x8659c; do
    size=$(wc -c < "$PATCH")
    [ "$size" -gt $((OFF+4)) ] || continue

    echo -n "before $OFF: "
    od -An -tx1 -j $((OFF)) -N 4 "$PATCH"

    # mov w0,#0
    printf '\000\000\200\122' | dd of="$PATCH" bs=1 seek=$((OFF)) conv=notrunc 2>/dev/null

    echo -n "after  $OFF: "
    od -An -tx1 -j $((OFF)) -N 4 "$PATCH"
  done

  while mount | grep -q " $TGT "; do
    umount "$TGT" 2>/dev/null || break
  done

  mount --bind "$PATCH" "$TGT" || exit 1
  mount | grep " $TGT " || true
done

echo
echo "PATCH_LIBBINDER_SECOND_SPAM_IOCTL_DONE"
