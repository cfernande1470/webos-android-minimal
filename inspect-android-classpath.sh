USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs

echo "--- buscar init.environ.rc / BOOTCLASSPATH ---"
grep -R "BOOTCLASSPATH\|DEX2OATBOOTCLASSPATH\|SYSTEMSERVERCLASSPATH" \
  "$ROOTFS/system/etc/init" \
  "$ROOTFS/system/etc" \
  "$ROOTFS/vendor/etc/init" \
  "$ROOTFS/product/etc/init" \
  "$ROOTFS/system_ext/etc/init" \
  2>/dev/null | head -120

echo
echo "--- ficheros classpath ---"
find "$ROOTFS" -path "*classpaths*" -o -name "*classpath*" 2>/dev/null | sort

echo
echo "--- jars candidatos con ZygoteInit via unzip/classes.dex ---"
for f in $(find "$ROOTFS/system" "$ROOTFS/apex" -type f -name "*.jar" 2>/dev/null); do
  if command -v unzip >/dev/null 2>&1; then
    if unzip -p "$f" classes.dex 2>/dev/null | strings | grep -q "com/android/internal/os/ZygoteInit"; then
      echo "$f"
    fi
  elif command -v busybox >/dev/null 2>&1; then
    if busybox unzip -p "$f" classes.dex 2>/dev/null | strings | grep -q "com/android/internal/os/ZygoteInit"; then
      echo "$f"
    fi
  fi
done

echo
echo "--- jars con ZygoteInit via strings directo, por si dex no está comprimido ---"
find "$ROOTFS/system" "$ROOTFS/apex" -type f -name "*.jar" -exec sh -c '
  for f do
    strings "$f" 2>/dev/null | grep -q "ZygoteInit" && echo "$f"
  done
' sh {} + 2>/dev/null | sort | head -80

echo
echo "--- boot image files ---"
find "$ROOTFS/system/framework" "$ROOTFS/apex/com.android.art" -type f \
  \( -name "boot*.art" -o -name "boot*.oat" -o -name "boot*.vdex" \) \
  2>/dev/null | sort
