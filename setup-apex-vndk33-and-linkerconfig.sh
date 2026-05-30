USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
BINDROOT=$SIDE/apex-bindsrc
NAMES=$SIDE/apex-bindsrc.modules

mkdir -p "$LOGDIR" "$SIDE"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true

echo "--- recuperar /apex base visible ---"
i=0
while [ $i -lt 30 ] && [ ! -x "$ROOTFS/apex/com.android.runtime/bin/linker64" ]; do
  TOP="$(awk -v t="$ROOTFS/apex" '$2 == t {print $0}' /proc/mounts | tail -1)"
  [ -n "$TOP" ] || break
  echo "umount apex layer: $TOP"
  umount "$ROOTFS/apex" 2>/dev/null || break
  i=$((i + 1))
done

ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" || exit 1

echo
echo "--- limpiar bind sources anteriores ---"
awk -v p="$BINDROOT/" 'index($2,p)==1 {print $2}' /proc/mounts | sort -r | while read mp; do
  echo "umount $mp"
  umount "$mp" 2>/dev/null || true
done

rm -rf "$BINDROOT"
mkdir -p "$BINDROOT"
: > "$NAMES"

echo
echo "--- capturar APEX reales ---"
for d in "$ROOTFS"/apex/com.android.*; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  mkdir -p "$BINDROOT/$name"
  mount --bind "$d" "$BINDROOT/$name" || continue
  echo "$name" >> "$NAMES"
  echo "APEX $name"
done

grep -q '^com.android.vndk.current$' "$NAMES" || {
  echo "ERROR: falta com.android.vndk.current"
  cat "$NAMES"
  exit 1
}

echo
echo "--- crear alias bind source com.android.vndk.v33 -> current ---"
mkdir -p "$BINDROOT/com.android.vndk.v33"
mount --bind "$BINDROOT/com.android.vndk.current" "$BINDROOT/com.android.vndk.v33" || {
  echo "ERROR: no pude crear bind source vndk.v33"
  exit 1
}
echo "com.android.vndk.v33" >> "$NAMES"

echo
echo "--- montar /apex overlay ---"
mount -t tmpfs -o mode=0755,size=128m tmpfs "$ROOTFS/apex" || exit 1

while read name; do
  [ -n "$name" ] || continue
  mkdir -p "$ROOTFS/apex/$name"
  mount --bind "$BINDROOT/$name" "$ROOTFS/apex/$name" || {
    echo "ERROR: no pude montar /apex/$name"
    exit 1
  }
done < "$NAMES"

echo
echo "--- comprobar VNDK aliases ---"
ls -ld "$ROOTFS/apex/com.android.vndk.current" "$ROOTFS/apex/com.android.vndk.v33"
find "$ROOTFS/apex/com.android.vndk.v33" -maxdepth 2 -type f | head -20

echo
echo "--- crear apex-info-list.xml con current y v33 ---"
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<apex-info-list>'

  while read name; do
    [ -n "$name" ] || continue

    case "$name" in
      com.android.vndk.v33)
        PRE="/system/apex/com.android.vndk.current"
        SHARED="true"
        VERSION="33"
        VERSION_NAME="33"
        ;;
      com.android.vndk.current)
        PRE="/system/apex/com.android.vndk.current"
        SHARED="true"
        VERSION="33"
        VERSION_NAME="33"
        ;;
      *)
        if [ -e "$ROOTFS/system/apex/$name" ]; then
          PRE="/system/apex/$name"
        elif [ -e "$ROOTFS/system/apex/$name.apex" ]; then
          PRE="/system/apex/$name.apex"
        else
          PRE="/apex/$name"
        fi
        SHARED="false"
        VERSION="1"
        VERSION_NAME="1"
        ;;
    esac

    echo "  <apex-info moduleName=\"$name\" modulePath=\"/apex/$name\" preinstalledModulePath=\"$PRE\" versionCode=\"$VERSION\" versionName=\"$VERSION_NAME\" isFactory=\"true\" isActive=\"true\" lastUpdateMillis=\"0\" provideSharedApexLibs=\"$SHARED\"/>"
  done < "$NAMES"

  echo '</apex-info-list>'
} > "$ROOTFS/apex/apex-info-list.xml"

grep 'com.android.vndk' "$ROOTFS/apex/apex-info-list.xml"
grep 'com.android.art' "$ROOTFS/apex/apex-info-list.xml"

echo
echo "--- regenerar /linkerconfig ---"
i=0
while [ $i -lt 30 ]; do
  TOP="$(awk -v t="$ROOTFS/linkerconfig" '$2 == t {print $0}' /proc/mounts | tail -1)"
  [ -n "$TOP" ] || break
  echo "umount linkerconfig layer: $TOP"
  umount "$ROOTFS/linkerconfig" 2>/dev/null || break
  i=$((i + 1))
done

mkdir -p "$ROOTFS/linkerconfig"
mount -t tmpfs -o mode=0755,size=16m tmpfs "$ROOTFS/linkerconfig" || true

chroot "$ROOTFS" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig \
  >"$LOGDIR/linkerconfig.vndk33.log" 2>&1
RC=$?

echo
echo "--- linkerconfig rc/log ---"
echo "rc=$RC"
cat "$LOGDIR/linkerconfig.vndk33.log" 2>/dev/null || true

if [ "$RC" != "0" ]; then
  echo
  echo "--- dmesg linkerconfig tail ---"
  dmesg | grep -E 'linkerconfig|VNDK|LLNDK|undefined var|apex|Fatal|abort|Abort' | tail -120 || true
  exit 1
fi

echo
echo "--- comprobar ld.config.txt ---"
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || exit 1

echo
echo "--- comprobar variables/namespaces ---"
grep -n 'LLNDK_LIBRARIES_VENDOR' "$ROOTFS/linkerconfig/ld.config.txt" | head -20 || true
grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" | head -20 || {
  echo "ERROR: falta com_android_art"
  exit 1
}
grep -n 'com_android_vndk' "$ROOTFS/linkerconfig/ld.config.txt" | head -20 || true

echo
echo "--- sanity props ---"
chroot "$ROOTFS" /system/bin/sh -c '
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
'

echo
echo "--- OK linkerconfig vndk33 ---"
