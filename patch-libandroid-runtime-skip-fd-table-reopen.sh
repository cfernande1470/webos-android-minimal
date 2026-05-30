USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.skip-fd-table-reopen.so"

# Symbol:
# FileDescriptorTable::ReopenOrDetach(...) @ 0x1d4e80
OFF_REOPEN_TABLE=$((0x1d4e80))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "FileDescriptorTable::ReopenOrDetach entry @ 0x1d4e80: "
od -An -tx1 -j "$OFF_REOPEN_TABLE" -N 16 "$PATCH"

echo
echo "--- patch: FileDescriptorTable::ReopenOrDetach entry -> ret ---"
# AArch64 RET = 0xd65f03c0 => little endian c0 03 5f d6
printf '\300\003\137\326' | dd of="$PATCH" bs=1 seek="$OFF_REOPEN_TABLE" conv=notrunc 2>/dev/null

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes ---"
echo -n "storage abort call @ 0x1ca198: "
od -An -tx1 -j $((0x1ca198)) -N 4 "$TGT"
echo -n "SetTaskProfiles call @ 0x1ca1b0: "
od -An -tx1 -j $((0x1ca1b0)) -N 4 "$TGT"
echo -n "fd allow branch @ 0x1d3828: "
od -An -tx1 -j $((0x1d3828)) -N 4 "$TGT"
echo -n "fd failfn #2 @ 0x1d3a80: "
od -An -tx1 -j $((0x1d3a80)) -N 4 "$TGT"
echo -n "fd failfn #3 @ 0x1d3974: "
od -An -tx1 -j $((0x1d3974)) -N 4 "$TGT"
echo -n "ForkCommon fail @ 0x1c7820: "
od -An -tx1 -j $((0x1c7820)) -N 4 "$TGT"
echo -n "FD ReopenOrDetach fail @ 0x1d4124: "
od -An -tx1 -j $((0x1d4124)) -N 4 "$TGT"
echo -n "FileDescriptorTable::ReopenOrDetach entry @ 0x1d4e80: "
od -An -tx1 -j "$OFF_REOPEN_TABLE" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_SKIP_FD_TABLE_REOPEN_OK"
