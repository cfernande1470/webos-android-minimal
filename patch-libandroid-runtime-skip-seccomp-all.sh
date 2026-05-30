USB="${USB:-/media/internal/android-usb}"
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.skip-seccomp-all.so"

# _install_setuidgid_filter(unsigned int, unsigned int) @ 0x1d99fc
OFF_SETUIDGID=$((0x1d99fc))
# _set_seccomp_filter(FilterType) @ 0x1d9afc
OFF_SECCOMP=$((0x1d9afc))

mkdir -p "$OVRDIR"

echo "--- create cumulative patch copy from current target ---"
cp "$TGT" "$PATCH" 2>/dev/null || dd if="$TGT" of="$PATCH" bs=1048576 2>/dev/null || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "_install_setuidgid_filter entry @ 0x1d99fc: "
od -An -tx1 -j "$OFF_SETUIDGID" -N 8 "$PATCH"
echo -n "_set_seccomp_filter entry @ 0x1d9afc: "
od -An -tx1 -j "$OFF_SECCOMP" -N 8 "$PATCH"

echo
echo "--- patch: seccomp helpers -> return true ---"
# AArch64:
# mov w0, #1  = 0x52800020 => 20 00 80 52
# ret         = 0xd65f03c0 => c0 03 5f d6
printf '\040\000\200\122\300\003\137\326' | dd of="$PATCH" bs=1 seek="$OFF_SETUIDGID" conv=notrunc 2>/dev/null
printf '\040\000\200\122\300\003\137\326' | dd of="$PATCH" bs=1 seek="$OFF_SECCOMP" conv=notrunc 2>/dev/null

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
echo -n "ForkCommon fail @ 0x1c7820: "
od -An -tx1 -j $((0x1c7820)) -N 4 "$TGT"
echo -n "FileDescriptorTable::ReopenOrDetach entry @ 0x1d4e80: "
od -An -tx1 -j $((0x1d4e80)) -N 4 "$TGT"
echo -n "_install_setuidgid_filter entry @ 0x1d99fc: "
od -An -tx1 -j "$OFF_SETUIDGID" -N 8 "$TGT"
echo -n "_set_seccomp_filter entry @ 0x1d9afc: "
od -An -tx1 -j "$OFF_SECCOMP" -N 8 "$TGT"

echo
echo "LIBANDROID_RUNTIME_SKIP_SECCOMP_ALL_OK"
