USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
PATCH="$OVRDIR/libandroid_runtime.nop-set-sched-policy.so"

# call set_sched_policy(pid=0, policy=w22) @ 0x1ccde4
OFF_SET_SCHED=$((0x1ccde4))

mkdir -p "$OVRDIR"

echo "--- create cumulative patch copy from current target ---"
cp "$TGT" "$PATCH" 2>/dev/null || dd if="$TGT" of="$PATCH" bs=1048576 2>/dev/null || exit 1
chmod 644 "$PATCH"

echo
echo "--- bytes before ---"
echo -n "set_sched_policy call @ 0x1ccde4: "
od -An -tx1 -j "$OFF_SET_SCHED" -N 8 "$PATCH"

echo
echo "--- patch: set_sched_policy call -> mov w0,#0 ---"
# AArch64 mov w0,#0 = 0x52800000 => 00 00 80 52
# Así w23 recibe 0 y salta por la rama de éxito.
printf '\000\000\200\122' | dd of="$PATCH" bs=1 seek="$OFF_SET_SCHED" conv=notrunc 2>/dev/null

echo
echo "--- bind patched libandroid_runtime.so ---"
while mount | grep -q " $TGT "; do
  umount "$TGT" 2>/dev/null || break
done

mount --bind "$PATCH" "$TGT" || exit 1

echo
echo "--- verify target bytes ---"
echo -n "storage abort @ 0x1ca198: "
od -An -tx1 -j $((0x1ca198)) -N 4 "$TGT"

echo -n "SetTaskProfiles call @ 0x1ca1b0: "
od -An -tx1 -j $((0x1ca1b0)) -N 4 "$TGT"

echo -n "SetTaskProfiles tbz @ 0x1ca208: "
od -An -tx1 -j $((0x1ca208)) -N 4 "$TGT"

echo -n "FileDescriptorTable::ReopenOrDetach @ 0x1d4e80: "
od -An -tx1 -j $((0x1d4e80)) -N 4 "$TGT"

echo -n "_set_seccomp_filter @ 0x1d9afc: "
od -An -tx1 -j $((0x1d9afc)) -N 8 "$TGT"

echo -n "set_sched_policy call @ 0x1ccde4: "
od -An -tx1 -j "$OFF_SET_SCHED" -N 4 "$TGT"

echo
echo "LIBANDROID_RUNTIME_NOP_SET_SCHED_POLICY_OK"
