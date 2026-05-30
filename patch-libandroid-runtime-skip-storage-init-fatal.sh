USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.skip-storage-init-fatal.so"

OFF=$((0x1ca160))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before @ 0x1ca160 ---"
od -An -tx1 -j "$OFF" -N 16 "$PATCH"

echo
echo "--- patch: force branch to 0x1ca19c ---"
# AArch64: b +0x3c
# encoding: 0x1400000f => little endian 0f 00 00 14
printf '\017\000\000\024' | dd of="$PATCH" bs=1 seek="$OFF" conv=notrunc 2>/dev/null

echo
echo "--- bytes after @ 0x1ca160 ---"
od -An -tx1 -j "$OFF" -N 16 "$PATCH"

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes @ 0x1ca160 ---"
od -An -tx1 -j "$OFF" -N 16 "$TGT"

echo
echo "LIBANDROID_RUNTIME_SKIP_STORAGE_INIT_FATAL_OK"
