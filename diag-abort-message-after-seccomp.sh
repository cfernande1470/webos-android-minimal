ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- clear old tombstone listing marker ---"
date

echo
echo "--- run zygote/system_server once ---"
# No abortamos el script si falla.
sh /media/internal/android-usb/android-sidecar/try-zygote-start-system-server-v2.sh 2>&1 || true

echo
echo "--- android log files under rootfs ---"
find "$ROOTFS/data" "$ROOTFS/cache" "$ROOTFS/dev" \
  -maxdepth 4 -type f \
  \( -iname '*log*' -o -iname '*tombstone*' -o -iname '*crash*' \) \
  -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -80

echo
echo "--- tombstones ---"
find "$ROOTFS/data/tombstones" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -10

LAST="$(find "$ROOTFS/data/tombstones" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"
if [ -n "$LAST" ]; then
  echo
  echo "--- latest tombstone: $LAST ---"
  grep -nE 'pid:|name:|signal|Abort message|backtrace|#00|#01|#02|#03|#04|#05|#06|runtime|zygote|system_server|art|CheckJNI|FATAL|failed|Failed|error|Error' "$LAST" | head -220
else
  echo
  echo "NO_TOMBSTONE_FOUND"
fi

echo
echo "--- pmsg/logcat-ish files ---"
for f in \
  /sys/fs/pstore/console-ramoops \
  /sys/fs/pstore/pmsg-ramoops-0 \
  /sys/fs/pstore/pmsg-ramoops \
  /dev/pmsg0
do
  if [ -e "$f" ]; then
    echo "### $f"
    strings "$f" 2>/dev/null | grep -iE 'zygote|system_server|abort|fatal|art|runtime|failed|exception|selinux|avc' | tail -160
  fi
done

echo
echo "--- kernel recent ---"
dmesg | grep -iE 'zygote|system_server|abort|fatal|art|runtime|binder|selinux|avc|denied|seccomp' | tail -160 || true

echo
echo "DIAG_ABORT_MESSAGE_AFTER_SECCOMP_DONE"
