ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- verify fd-table skip patch ---"
echo -n "FileDescriptorTable::ReopenOrDetach entry @ 0x1d4e80: "
od -An -tx1 -j $((0x1d4e80)) -N 4 "$ROOTFS/system/lib64/libandroid_runtime.so"

echo
echo "--- binder device nodes ---"
ls -l /dev/binder /dev/hwbinder /dev/vndbinder /dev/binderfs 2>/dev/null
find /dev -maxdepth 2 -iname '*binder*' -ls 2>/dev/null

echo
echo "--- binder filesystem / mounts ---"
grep -i binder /proc/filesystems 2>/dev/null
mount | grep -i binder 2>/dev/null

echo
echo "--- binder kernel/module state ---"
lsmod | grep -i binder 2>/dev/null
dmesg | grep -iE 'binder|ashmem|selinux|avc|audit' | tail -120

echo
echo "--- android service manager processes ---"
ps -ef | grep -E 'servicemanager|hwservicemanager|vndservicemanager|zygote|app_process' | grep -v grep

echo
echo "--- android service manager binaries ---"
ls -l \
  "$ROOTFS/system/bin/servicemanager" \
  "$ROOTFS/system/bin/hwservicemanager" \
  "$ROOTFS/system/bin/vndservicemanager" \
  2>/dev/null

echo
echo "--- binder debugfs if available ---"
for f in \
  /sys/kernel/debug/binder/state \
  /sys/kernel/debug/binder/proc \
  /sys/kernel/debug/binder/stats \
  /dev/binderfs/binder_logs/state \
  /dev/binderfs/binder_logs/proc \
  /dev/binderfs/binder_logs/stats
do
  if [ -e "$f" ]; then
    echo "### $f"
    cat "$f" 2>/dev/null | head -160
  fi
done

echo
echo "BINDER_POST_FD_DIAG_DONE"
