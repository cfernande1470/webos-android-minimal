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

ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" || {
  echo "ERROR: no veo /apex/com.android.runtime/bin/linker64"
  exit 1
}

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
echo "--- capturar APEX reales como bind sources ---"
for d in "$ROOTFS"/apex/com.android.*; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  mkdir -p "$BINDROOT/$name"
  mount --bind "$d" "$BINDROOT/$name" || {
    echo "WARN: no pude bindear $d"
    continue
  }
  echo "$name" >> "$NAMES"
  echo "APEX $name"
done

grep -q '^com.android.art$' "$NAMES" || { echo "ERROR: falta com.android.art"; cat "$NAMES"; exit 1; }
grep -q '^com.android.runtime$' "$NAMES" || { echo "ERROR: falta com.android.runtime"; cat "$NAMES"; exit 1; }

echo
echo "--- montar /apex overlay escribible ---"
mount -t tmpfs -o mode=0755,size=128m tmpfs "$ROOTFS/apex" || {
  echo "ERROR: no pude montar tmpfs en /apex"
  exit 1
}

while read name; do
  [ -n "$name" ] || continue
  mkdir -p "$ROOTFS/apex/$name"
  mount --bind "$BINDROOT/$name" "$ROOTFS/apex/$name" || {
    echo "ERROR: no pude montar /apex/$name"
    exit 1
  }
done < "$NAMES"

get_manifest_field() {
  file="$1"
  key="$2"
  if [ -f "$file" ]; then
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -1
  fi
}

get_manifest_num() {
  file="$1"
  key="$2"
  if [ -f "$file" ]; then
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$file" | head -1
  fi
}

echo
echo "--- crear /apex/apex-info-list.xml Android 13 compatible ---"
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<apex-info-list>'

  while read name; do
    [ -n "$name" ] || continue

    MANIFEST="$ROOTFS/apex/$name/apex_manifest.json"

    VERSION="$(get_manifest_num "$MANIFEST" version)"
    [ -n "$VERSION" ] || VERSION=1

    VERSION_NAME="$(get_manifest_field "$MANIFEST" versionName)"
    [ -n "$VERSION_NAME" ] || VERSION_NAME="$VERSION"

    PRE=""
    if [ -e "$ROOTFS/system/apex/$name" ]; then
      PRE="/system/apex/$name"
    elif [ -e "$ROOTFS/system/apex/$name.apex" ]; then
      PRE="/system/apex/$name.apex"
    elif [ -e "$ROOTFS/system/system/apex/$name" ]; then
      PRE="/system/system/apex/$name"
    elif [ -e "$ROOTFS/system/system/apex/$name.apex" ]; then
      PRE="/system/system/apex/$name.apex"
    else
      PRE="/apex/$name"
    fi

    SHARED="false"
    case "$name" in
      com.android.vndk.current) SHARED="true" ;;
    esac

    echo "  <apex-info moduleName=\"$name\" modulePath=\"/apex/$name\" preinstalledModulePath=\"$PRE\" versionCode=\"$VERSION\" versionName=\"$VERSION_NAME\" isFactory=\"true\" isActive=\"true\" lastUpdateMillis=\"0\" provideSharedApexLibs=\"$SHARED\"/>"
  done < "$NAMES"

  echo '</apex-info-list>'
} > "$ROOTFS/apex/apex-info-list.xml"

ls -l "$ROOTFS/apex/apex-info-list.xml"
grep 'com.android.art' "$ROOTFS/apex/apex-info-list.xml"
grep 'com.android.runtime' "$ROOTFS/apex/apex-info-list.xml"
grep 'com.android.vndk.current' "$ROOTFS/apex/apex-info-list.xml" || true

echo
echo "--- validar rutas preinstalledModulePath ---"
sed -n 's/.*moduleName="\([^"]*\)".*preinstalledModulePath="\([^"]*\)".*/\1 \2/p' "$ROOTFS/apex/apex-info-list.xml" | while read n p; do
  if [ -e "$ROOTFS$p" ]; then
    echo "OK   $n $p"
  else
    echo "MISS $n $p"
  fi
done | head -80

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

echo "--- ejecutar linkerconfig ---"
if [ -x "$ROOTFS/apex/com.android.runtime/bin/linkerconfig" ]; then
  chroot "$ROOTFS" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig \
    >"$LOGDIR/linkerconfig.apexinfo.v3.log" 2>&1
  RC=$?
elif [ -x "$ROOTFS/system/bin/linkerconfig" ]; then
  chroot "$ROOTFS" /system/bin/linkerconfig --target /linkerconfig \
    >"$LOGDIR/linkerconfig.apexinfo.v3.log" 2>&1
  RC=$?
else
  echo "ERROR: no encuentro linkerconfig"
  exit 1
fi

echo
echo "--- linkerconfig rc/log ---"
echo "rc=$RC"
cat "$LOGDIR/linkerconfig.apexinfo.v3.log" 2>/dev/null || true

if [ "$RC" != "0" ]; then
  echo
  echo "--- dmesg linkerconfig/apex tail ---"
  dmesg | grep -E 'linkerconfig|apex|libc|Fatal|abort|Abort' | tail -120 || true
  exit 1
fi

echo
echo "--- comprobar ld.config.txt ---"
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || exit 1

echo
echo "--- comprobar namespaces APEX ---"
grep -n 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" | head -20 || {
  echo "ERROR: falta namespace com_android_art"
  exit 1
}

grep -n 'com_android_runtime' "$ROOTFS/linkerconfig/ld.config.txt" | head -20 || true
grep -n 'com_android_conscrypt' "$ROOTFS/linkerconfig/ld.config.txt" | head -10 || true
grep -n 'com_android_i18n' "$ROOTFS/linkerconfig/ld.config.txt" | head -10 || true

echo
echo "--- sanity getprop ---"
chroot "$ROOTFS" /system/bin/sh -c '
echo "ro.hardware.egl=$(/system/bin/getprop ro.hardware.egl)"
echo "ro.board.platform=$(/system/bin/getprop ro.board.platform)"
echo "ro.zygote.disable_gl_preload=$(/system/bin/getprop ro.zygote.disable_gl_preload)"
echo "ro.vendor.api_level=$(/system/bin/getprop ro.vendor.api_level)"
'

echo
echo "--- OK: linkerconfig con namespaces APEX ---"
