USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.force-taskprofiles-ok.so"

OFF_CALL=$((0x1ca1b0))
OFF_TBZ=$((0x1ca208))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_CALL" -N 4 "$PATCH"
echo -n "tbz  @ 0x1ca208: "
od -An -tx1 -j "$OFF_TBZ" -N 4 "$PATCH"

echo
echo "--- patch: SetTaskProfiles call -> mov w0,#1 ---"
# mov w0, #1 = 0x52800020 => little endian 20 00 80 52
printf '\040\000\200\122' | dd of="$PATCH" bs=1 seek="$OFF_CALL" conv=notrunc 2>/dev/null

echo "--- patch: tbz -> nop ---"
# nop = 0xd503201f => little endian 1f 20 03 d5
printf '\037\040\003\325' | dd of="$PATCH" bs=1 seek="$OFF_TBZ" conv=notrunc 2>/dev/null

echo
echo "--- bytes after ---"
echo -n "call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_CALL" -N 4 "$PATCH"
echo -n "tbz  @ 0x1ca208: "
od -An -tx1 -j "$OFF_TBZ" -N 4 "$PATCH"

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes ---"
echo -n "target call @ 0x1ca1b0: "
od -An -tx1 -j "$OFF_CALL" -N 4 "$TGT"
echo -n "target tbz  @ 0x1ca208: "
od -An -tx1 -j "$OFF_TBZ" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_FORCE_TASKPROFILES_OK"
