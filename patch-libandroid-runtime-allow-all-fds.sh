USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.allow-all-fds.so"

OFF_FD_ALLOW=$((0x1d3828))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "fd allow branch @ 0x1d3828: "
od -An -tx1 -j "$OFF_FD_ALLOW" -N 4 "$PATCH"

echo
echo "--- patch: tbnz IsAllowed result -> unconditional branch to 0x1d387c ---"
# Original at 0x1d3828:
#   tbnz w0,#0,0x1d387c
# We force:
#   b 0x1d387c
# delta = 0x1d387c - 0x1d3828 = 0x54
# imm26 = 0x54 / 4 = 0x15
# encoding = 0x14000015 => little endian 15 00 00 14
printf '\025\000\000\024' | dd of="$PATCH" bs=1 seek="$OFF_FD_ALLOW" conv=notrunc 2>/dev/null

echo
echo "--- bytes after ---"
echo -n "fd allow branch @ 0x1d3828 should be 15 00 00 14: "
od -An -tx1 -j "$OFF_FD_ALLOW" -N 4 "$PATCH"

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
echo -n "SetTaskProfiles tbz @ 0x1ca208: "
od -An -tx1 -j $((0x1ca208)) -N 4 "$TGT"
echo -n "fd allow branch @ 0x1d3828: "
od -An -tx1 -j "$OFF_FD_ALLOW" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_ALLOW_ALL_FDS_OK"
