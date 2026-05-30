ROOTFS=/media/internal/android-usb/android-rootfs

echo "--- current mounts libbinder ---"
mount | grep -E 'libbinder|overrides-libbinder' || true

echo
echo "--- managers pids ---"
ps -ef | grep -E 'servicemanager|hwservicemanager|vndservicemanager' | grep -v grep || true

echo
echo "--- managers libbinder maps ---"
for p in $(pidof servicemanager hwservicemanager vndservicemanager 2>/dev/null); do
  echo
  echo "=== PID $p ==="
  tr '\0' ' ' < /proc/$p/cmdline; echo
  grep -E 'libbinder|libutils|libcutils|libprocessgroup' /proc/$p/maps || true
done

echo
echo "--- system/vender libbinder candidates ---"
for f in \
  "$ROOTFS/system/lib64/libbinder.so" \
  "$ROOTFS/apex/com.android.vndk.current/lib64/libbinder.so" \
  "$ROOTFS/apex/com.android.vndk.v33/lib64/libbinder.so" \
  "$ROOTFS/system/apex/com.android.vndk.current/lib64/libbinder.so"
do
  [ -f "$f" ] || continue
  echo
  echo "=== $f ==="
  ls -l "$f"
  strings "$f" | grep -E 'SYST|VNDR|Mixing copies|Expecting header' | head -20 || true
done

echo
echo "INSPECT_BINDER_MAPS_DONE"
