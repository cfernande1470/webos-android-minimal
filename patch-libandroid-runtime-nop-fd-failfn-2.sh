USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.nop-fd-failfn-2.so"

OFF_FD_FAIL2=$((0x1d3a80))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "fd failfn #2 call @ 0x1d3a80: "
BYTES="$(od -An -tx1 -j "$OFF_FD_FAIL2" -N 4 "$PATCH" | tr -d ' \n')"
echo "$BYTES"

if [ "$BYTES" != "00013fd6" ]; then
  echo "WARN: expected blr x8 bytes 00 01 3f d6 at 0x1d3a80"
  echo "--- surrounding bytes ---"
  od -An -tx1 -j $((0x1d3a60)) -N 64 "$PATCH"
  echo "Refusing to patch; run disasm around 0x1d3a40-0x1d3aa0"
  exit 1
fi

echo
echo "--- patch: fail_fn call @ 0x1d3a80 -> nop ---"
# AArch64 NOP = 0xd503201f => little endian 1f 20 03 d5
printf '\037\040\003\325' | dd of="$PATCH" bs=1 seek="$OFF_FD_FAIL2" conv=notrunc 2>/dev/null

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
od -An -tx1 -j $((0x1d3828)) -N 4 "$TGT"
echo -n "fd failfn #2 @ 0x1d3a80: "
od -An -tx1 -j "$OFF_FD_FAIL2" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_NOP_FD_FAILFN_2_OK"
