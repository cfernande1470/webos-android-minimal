USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs

echo "--- 0. current libandroid_runtime patches ---"
echo -n "FileDescriptorTable::ReopenOrDetach @ 0x1d4e80: "
od -An -tx1 -j $((0x1d4e80)) -N 4 "$ROOTFS/system/lib64/libandroid_runtime.so"
echo -n "storage abort @ 0x1ca198: "
od -An -tx1 -j $((0x1ca198)) -N 4 "$ROOTFS/system/lib64/libandroid_runtime.so"
echo -n "SetTaskProfiles call @ 0x1ca1b0: "
od -An -tx1 -j $((0x1ca1b0)) -N 4 "$ROOTFS/system/lib64/libandroid_runtime.so"

echo
echo "--- 1. binder nodes ---"
ls -l /dev/binder /dev/hwbinder /dev/vndbinder 2>&1
stat /dev/binder /dev/hwbinder /dev/vndbinder 2>&1

echo
echo "--- 2. binder module ---"
lsmod | grep -i binder || true
grep -i binder /proc/devices /proc/misc 2>/dev/null || true

echo
echo "--- 3. service managers process/root/fds ---"
for name in servicemanager hwservicemanager vndservicemanager; do
  echo
  echo "### $name"
  PIDS="$(pidof $name 2>/dev/null || true)"
  echo "pids=$PIDS"
  for p in $PIDS; do
    echo "--- pid $p ---"
    tr '\0' ' ' < /proc/$p/cmdline; echo
    echo -n "exe: "; readlink /proc/$p/exe 2>/dev/null || true
    echo -n "root: "; readlink /proc/$p/root 2>/dev/null || true
    echo -n "cwd: "; readlink /proc/$p/cwd 2>/dev/null || true
    echo "status:"
    grep -E 'Name|State|Pid|PPid|Uid|Gid|Cap|NoNewPrivs|Seccomp' /proc/$p/status 2>/dev/null || true
    echo "fds:"
    for f in /proc/$p/fd/*; do
      printf "%s -> " "$f"
      readlink "$f" 2>/dev/null || true
    done | grep -E 'binder|socket|ashmem|log|dev|null|pipe' || true
  done
done

echo
echo "--- 4. try binder client: /system/bin/service list ---"
env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/service list
echo "service_list_rc=$?"

echo
echo "--- 5. try binder client: cmd -l, may fail if system_server is not up ---"
if [ -x "$ROOTFS/system/bin/cmd" ]; then
  env -i \
    PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
    ANDROID_ROOT=/system \
    ANDROID_DATA=/data \
    ANDROID_STORAGE=/storage \
    ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
    ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
    ANDROID_ART_ROOT=/apex/com.android.art \
    LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
    chroot "$ROOTFS" /system/bin/cmd -l
  echo "cmd_l_rc=$?"
else
  echo "no /system/bin/cmd"
fi

echo
echo "--- 6. tombstones before rerun ---"
find "$ROOTFS/data/tombstones" -maxdepth 1 -type f -ls 2>/dev/null || true

echo
echo "--- 7. recent kernel binder messages before rerun ---"
dmesg | grep -iE 'binder|servicemanager|avc|selinux|audit|ashmem' | tail -120 || true

echo
echo "BINDER_DEEPER_DONE"
