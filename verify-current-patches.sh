ROOTFS=/media/internal/android-usb/android-rootfs
TGT="$ROOTFS/system/lib64/libandroid_runtime.so"

echo "--- current critical patches ---"
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

echo
echo "VERIFY_CURRENT_PATCHES_DONE"
