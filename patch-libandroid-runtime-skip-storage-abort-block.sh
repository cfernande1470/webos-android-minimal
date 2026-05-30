USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.skip-storage-abort-block.so"

OFF_BLOCK=$((0x1ca16c))
OFF_STORAGE_BRANCH=$((0x1ca160))
OFF_TASK_CALL=$((0x1ca1b0))
OFF_TASK_TBZ=$((0x1ca208))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "block @ 0x1ca16c: "
od -An -tx1 -j "$OFF_BLOCK" -N 4 "$PATCH"
echo -n "storage branch @ 0x1ca160: "
od -An -tx1 -j "$OFF_STORAGE_BRANCH" -N 4 "$PATCH"
echo -n "task call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_TASK_CALL" -N 4 "$PATCH"
echo -n "task tbz @ 0x1ca208: "
od -An -tx1 -j "$OFF_TASK_TBZ" -N 4 "$PATCH"

echo
echo "--- patch: 0x1ca16c -> b 0x1ca19c ---"
# target - pc = 0x1ca19c - 0x1ca16c = 0x30
# imm26 = 0x30 / 4 = 0x0c
# b +0x30 = 0x1400000c => little endian 0c 00 00 14
printf '\014\000\000\024' | dd of="$PATCH" bs=1 seek="$OFF_BLOCK" conv=notrunc 2>/dev/null

echo
echo "--- bytes after ---"
echo -n "block @ 0x1ca16c should be 0c 00 00 14: "
od -An -tx1 -j "$OFF_BLOCK" -N 4 "$PATCH"

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes ---"
echo -n "block @ 0x1ca16c: "
od -An -tx1 -j "$OFF_BLOCK" -N 4 "$TGT"
echo -n "storage branch @ 0x1ca160: "
od -An -tx1 -j "$OFF_STORAGE_BRANCH" -N 4 "$TGT"
echo -n "task call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_TASK_CALL" -N 4 "$TGT"
echo -n "task tbz @ 0x1ca208: "
od -An -tx1 -j "$OFF_TASK_TBZ" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_SKIP_STORAGE_ABORT_BLOCK_OK"
