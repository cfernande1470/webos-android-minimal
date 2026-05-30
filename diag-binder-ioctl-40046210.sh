ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- kernel binder symbols/options ---"
uname -a
lsmod | grep -i binder || true
modinfo binder 2>/dev/null || true

echo
echo "--- binder device stats ---"
ls -l /dev/binder /dev/hwbinder /dev/vndbinder 2>/dev/null || true
cat /proc/misc 2>/dev/null | grep -i binder || true
cat /proc/devices 2>/dev/null | grep -i binder || true

echo
echo "--- binder debug, if any ---"
for f in \
  /sys/kernel/debug/binder/state \
  /sys/kernel/debug/binder/stats \
  /sys/kernel/debug/binder/proc \
  /dev/binderfs/binder_logs/state \
  /dev/binderfs/binder_logs/stats \
  /dev/binderfs/binder_logs/proc
do
  if [ -e "$f" ]; then
    echo
    echo "### $f"
    cat "$f" 2>/dev/null | head -260
  fi
done

echo
echo "--- service list test ---"
env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  ANDROID_ART_ROOT=/apex/com.android.art \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  chroot "$ROOTFS" /system/bin/service list 2>&1 | head -120
echo "service_list_rc=$?"

echo
echo "DIAG_BINDER_IOCTL_40046210_DONE"
