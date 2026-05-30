ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- current nodes ---"
ls -l /dev/binder /dev/hwbinder /dev/vndbinder 2>/dev/null || true
ls -l "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder" 2>/dev/null || true

echo
echo "--- misc minors ---"
cat /proc/misc | grep -E 'binder|hwbinder|vndbinder' || true

BINDER_MINOR="$(awk '$2=="binder"{print $1}' /proc/misc | head -1)"
HWBINDER_MINOR="$(awk '$2=="hwbinder"{print $1}' /proc/misc | head -1)"
VNDBINDER_MINOR="$(awk '$2=="vndbinder"{print $1}' /proc/misc | head -1)"

[ -n "$BINDER_MINOR" ] || BINDER_MINOR=53
[ -n "$HWBINDER_MINOR" ] || HWBINDER_MINOR=52
[ -n "$VNDBINDER_MINOR" ] || VNDBINDER_MINOR=51

echo "binder minor=$BINDER_MINOR hwbinder minor=$HWBINDER_MINOR vndbinder minor=$VNDBINDER_MINOR"

echo
echo "--- remove bad symlinks/nodes ---"
rm -f /dev/binder /dev/hwbinder /dev/vndbinder
rm -f "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"

echo
echo "--- create host /dev binder nodes ---"
mknod /dev/binder c 10 "$BINDER_MINOR"
mknod /dev/hwbinder c 10 "$HWBINDER_MINOR"
mknod /dev/vndbinder c 10 "$VNDBINDER_MINOR"
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder

echo
echo "--- check whether ROOTFS/dev is same as host /dev ---"
HOST_DEV_ID="$(stat -c '%d:%i' /dev)"
ROOTFS_DEV_ID="$(stat -c '%d:%i' "$ROOTFS/dev" 2>/dev/null || echo missing)"
echo "host_dev=$HOST_DEV_ID"
echo "rootfs_dev=$ROOTFS_DEV_ID"

if [ "$HOST_DEV_ID" = "$ROOTFS_DEV_ID" ]; then
  echo "ROOTFS/dev is same as /dev; skip duplicate nodes"
else
  echo "--- create real rootfs /dev binder nodes ---"
  mkdir -p "$ROOTFS/dev"
  mknod "$ROOTFS/dev/binder" c 10 "$BINDER_MINOR"
  mknod "$ROOTFS/dev/hwbinder" c 10 "$HWBINDER_MINOR"
  mknod "$ROOTFS/dev/vndbinder" c 10 "$VNDBINDER_MINOR"
  chmod 666 "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"
fi

echo
echo "--- final nodes ---"
ls -l /dev/binder /dev/hwbinder /dev/vndbinder
ls -l "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder" 2>/dev/null || true

echo
echo "FIX_BINDER_DEVNODES_DONE"
