USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar

killall -9 app_process64 zygote_socket_wrap servicemanager hwservicemanager vndservicemanager 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f zygote_socket_wrap 2>/dev/null || true
sleep 1

rmmod binder 2>/dev/null || true
sleep 1

insmod "$SIDE/binder.ko" || exit 1

rm -f /dev/binder /dev/hwbinder /dev/vndbinder
rm -f "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"

BINDER_MINOR="$(awk '$2=="binder"{print $1}' /proc/misc | head -1)"
HWBINDER_MINOR="$(awk '$2=="hwbinder"{print $1}' /proc/misc | head -1)"
VNDBINDER_MINOR="$(awk '$2=="vndbinder"{print $1}' /proc/misc | head -1)"

[ -n "$BINDER_MINOR" ] || BINDER_MINOR=53
[ -n "$HWBINDER_MINOR" ] || HWBINDER_MINOR=52
[ -n "$VNDBINDER_MINOR" ] || VNDBINDER_MINOR=51

mknod /dev/binder c 10 "$BINDER_MINOR"
mknod /dev/hwbinder c 10 "$HWBINDER_MINOR"
mknod /dev/vndbinder c 10 "$VNDBINDER_MINOR"
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder

mkdir -p "$ROOTFS/dev"
ln -sf /dev/binder "$ROOTFS/dev/binder"
ln -sf /dev/hwbinder "$ROOTFS/dev/hwbinder"
ln -sf /dev/vndbinder "$ROOTFS/dev/vndbinder"

lsmod | grep binder || true
cat /proc/misc | grep -E 'binder|hwbinder|vndbinder' || true
echo "RELOAD_BINDERKO_DONE"
