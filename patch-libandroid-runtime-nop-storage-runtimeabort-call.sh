USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.nop-storage-runtimeabort-call.so"

OFF_ABORT_CALL=$((0x1ca198))
OFF_STORAGE_BRANCH=$((0x1ca160))
OFF_STORAGE_BLOCK=$((0x1ca16c))
OFF_TASK_CALL=$((0x1ca1b0))
OFF_TASK_TBZ=$((0x1ca208))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "abort call @ 0x1ca198: "
od -An -tx1 -j "$OFF_ABORT_CALL" -N 4 "$PATCH"
echo -n "storage branch @ 0x1ca160: "
od -An -tx1 -j "$OFF_STORAGE_BRANCH" -N 4 "$PATCH"
echo -n "storage block @ 0x1ca16c: "
od -An -tx1 -j "$OFF_STORAGE_BLOCK" -N 4 "$PATCH"
echo -n "task call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_TASK_CALL" -N 4 "$PATCH"
echo -n "task tbz @ 0x1ca208: "
od -An -tx1 -j "$OFF_TASK_TBZ" -N 4 "$PATCH"

echo
echo "--- patch: RuntimeAbort call @ 0x1ca198 -> nop ---"
# AArch64 NOP = 0xd503201f => little endian 1f 20 03 d5
printf '\037\040\003\325' | dd of="$PATCH" bs=1 seek="$OFF_ABORT_CALL" conv=notrunc 2>/dev/null

echo
echo "--- bytes after ---"
echo -n "abort call @ 0x1ca198 should be 1f 20 03 d5: "
od -An -tx1 -j "$OFF_ABORT_CALL" -N 4 "$PATCH"

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes ---"
echo -n "abort call @ 0x1ca198: "
od -An -tx1 -j "$OFF_ABORT_CALL" -N 4 "$TGT"
echo -n "storage branch @ 0x1ca160: "
od -An -tx1 -j "$OFF_STORAGE_BRANCH" -N 4 "$TGT"
echo -n "storage block @ 0x1ca16c: "
od -An -tx1 -j "$OFF_STORAGE_BLOCK" -N 4 "$TGT"
echo -n "task call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_TASK_CALL" -N 4 "$TGT"
echo -n "task tbz @ 0x1ca208: "
od -An -tx1 -j "$OFF_TASK_TBZ" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_NOP_STORAGE_RUNTIMEABORT_CALL_OK"
