USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

SRC="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.skip-taskprofiles.so"
OFF=$((0x1ca208))

mkdir -p "$OVRDIR"

echo "--- restore original libprocessgroup, if stub bind is active ---"
TGT_PG="$ROOTFS/system/lib64/libprocessgroup.so"
while mount | grep -q " $TGT_PG "; do
  umount "$TGT_PG" 2>/dev/null || break
done

echo
echo "--- create patched libandroid_runtime copy ---"
ls -l "$SRC" || exit 1
cp "$SRC" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- check original bytes at 0x1ca208 ---"
BYTES="$(od -An -tx1 -j "$OFF" -N 4 "$PATCH" | tr -d ' \n')"
echo "bytes=$BYTES"

if [ "$BYTES" != "74020036" ]; then
  echo "ERROR: unexpected instruction bytes at 0x1ca208; refusing to patch"
  echo "Expected little-endian tbz: 74 02 00 36"
  exit 1
fi

echo
echo "--- patch tbz -> nop ---"
# AArch64 NOP = 0xd503201f => little endian 1f 20 03 d5
printf '\037\040\003\325' | dd of="$PATCH" bs=1 seek="$OFF" conv=notrunc 2>/dev/null

echo
echo "--- verify patched bytes ---"
BYTES2="$(od -An -tx1 -j "$OFF" -N 4 "$PATCH" | tr -d ' \n')"
echo "bytes=$BYTES2"

if [ "$BYTES2" != "1f2003d5" ]; then
  echo "ERROR: patch failed"
  exit 1
fi

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $SRC "; do
  umount "$SRC" 2>/dev/null || break
done

mount --bind "$PATCH" "$SRC" || exit 1

echo
echo "--- mount check ---"
mount | grep " $SRC " || true

echo
echo "LIBANDROID_RUNTIME_SKIP_TASKPROFILES_OK"
