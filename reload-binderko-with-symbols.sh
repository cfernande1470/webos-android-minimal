USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
KO=$SIDE/binder.ko

sym() {
  name="$1"
  val="$(awk -v n="$name" '$3 == n { print "0x"$1; exit }' /proc/kallsyms)"
  if [ -z "$val" ] || echo "$val" | grep -q '^0x0*$'; then
    echo "MISSING:$name"
    return 1
  fi
  echo "$val"
}

echo "--- stop android users ---"
killall -9 app_process64 zygote_socket_wrap servicemanager hwservicemanager vndservicemanager service 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f zygote_socket_wrap 2>/dev/null || true
sleep 1

echo
echo "--- resolve kernel symbols ---"
SYM_ZAP_PAGE_RANGE="$(sym zap_page_range)" || exit 1
SYM_PUT_FILES_STRUCT="$(sym put_files_struct)" || exit 1
SYM_GET_VM_AREA="$(sym get_vm_area)" || exit 1
SYM_FD_INSTALL="$(sym __fd_install)" || exit 1
SYM_CLOSE_FD="$(sym __close_fd)" || exit 1
SYM_MAP_KERNEL_RANGE="$(sym map_kernel_range_noflush)" || exit 1
SYM_LOCK_TASK_SIGHAND="$(sym __lock_task_sighand)" || exit 1
SYM_GET_FILES_STRUCT="$(sym get_files_struct)" || exit 1
SYM_ALLOC_FD="$(sym __alloc_fd)" || exit 1

cat <<EOS
sym_zap_page_range=$SYM_ZAP_PAGE_RANGE
sym_put_files_struct=$SYM_PUT_FILES_STRUCT
sym_get_vm_area=$SYM_GET_VM_AREA
sym___fd_install=$SYM_FD_INSTALL
sym___close_fd=$SYM_CLOSE_FD
sym_map_kernel_range_noflush=$SYM_MAP_KERNEL_RANGE
sym___lock_task_sighand=$SYM_LOCK_TASK_SIGHAND
sym_get_files_struct=$SYM_GET_FILES_STRUCT
sym___alloc_fd=$SYM_ALLOC_FD
EOS

echo
echo "--- unload old binder ---"
rmmod binder 2>/dev/null || true
sleep 1

echo
echo "--- load binder with symbols ---"
insmod "$KO" \
  sym_zap_page_range="$SYM_ZAP_PAGE_RANGE" \
  sym_put_files_struct="$SYM_PUT_FILES_STRUCT" \
  sym_get_vm_area="$SYM_GET_VM_AREA" \
  sym___fd_install="$SYM_FD_INSTALL" \
  sym___close_fd="$SYM_CLOSE_FD" \
  sym_map_kernel_range_noflush="$SYM_MAP_KERNEL_RANGE" \
  sym___lock_task_sighand="$SYM_LOCK_TASK_SIGHAND" \
  sym_get_files_struct="$SYM_GET_FILES_STRUCT" \
  sym___alloc_fd="$SYM_ALLOC_FD" \
  fd_path_mode=1 \
  proc_no_lock=1 \
  debug_mask=0 || exit 1

echo
echo "--- recreate binder nodes ---"
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

HOST_DEV_ID="$(stat -c '%d:%i' /dev)"
ROOTFS_DEV_ID="$(stat -c '%d:%i' "$ROOTFS/dev" 2>/dev/null || echo missing)"

if [ "$HOST_DEV_ID" != "$ROOTFS_DEV_ID" ]; then
  mknod "$ROOTFS/dev/binder" c 10 "$BINDER_MINOR"
  mknod "$ROOTFS/dev/hwbinder" c 10 "$HWBINDER_MINOR"
  mknod "$ROOTFS/dev/vndbinder" c 10 "$VNDBINDER_MINOR"
  chmod 666 "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"
fi

echo
echo "--- verify ---"
lsmod | grep binder || true
cat /proc/misc | grep -E 'binder|hwbinder|vndbinder' || true
ls -l /dev/binder /dev/hwbinder /dev/vndbinder
echo "RELOAD_BINDERKO_WITH_SYMBOLS_DONE"
