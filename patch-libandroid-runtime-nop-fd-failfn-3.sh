USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.nop-fd-failfn-3.so"

OFF_FD_FAIL3=$((0x1d3974))

mkdir -p "$OVRDIR"

echo "--- create patch copy from current target ---"
cp "$TGT" "$PATCH" || exit 1
chmod 644 "$PATCH"

echo
echo "--- surrounding bytes before ---"
od -An -tx1 -j $((0x1d3940)) -N 96 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "fd failfn #3 call @ 0x1d3974: "
BYTES="$(od -An -tx1 -j "$OFF_FD_FAIL3" -N 4 "$PATCH" | tr -d ' \n')"
echo "$BYTES"

if [ "$BYTES" != "00013fd6" ]; then
  echo "WARN: expected blr x8 bytes 00 01 3f d6 at 0x1d3974"
  echo "Refusing to patch. Run:"
  echo "aarch64-linux-gnu-objdump -d -C --start-address=0x1d3940 --stop-address=0x1d39a0 zygote-symbols/libandroid_runtime.so.real"
  exit 1
fi

echo
echo "--- patch: fail_fn call @ 0x1d3974 -> nop ---"
# AArch64 NOP = 0xd503201f => little endian 1f 20 03 d5
printf '\037\040\003\325' | dd of="$PATCH" bs=1 seek="$OFF_FD_FAIL3" conv=notrunc 2>/dev/null

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
od -An -tx1 -j $((0x1d3a80)) -N 4 "$TGT"
echo -n "fd failfn #3 @ 0x1d3974: "
od -An -tx1 -j "$OFF_FD_FAIL3" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_NOP_FD_FAILFN_3_OK"
