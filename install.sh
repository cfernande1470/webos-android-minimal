#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="$USB/android-rootfs"
SIDE="$USB/android-sidecar"
LOGDIR="$SIDE/logs"

ANDROID_USB_PART="${ANDROID_USB_PART:-/dev/sda1}"
FORMAT_USB="${FORMAT_USB:-0}"
CONFIRM_FORMAT_USB="${CONFIRM_FORMAT_USB:-NO}"
PATCH_ANDROID_SERVERS="${PATCH_ANDROID_SERVERS:-0}"
PATCH_ANDROID_RUNTIME="${PATCH_ANDROID_RUNTIME:-1}"
PATCH_LIBPROCESSGROUP="${PATCH_LIBPROCESSGROUP:-1}"

SYSTEM_URL="${SYSTEM_URL:-https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64_only/lineage-20.0-20260403-VANILLA-waydroid_arm64_only-system.zip/download}"
VENDOR_URL="${VENDOR_URL:-https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_arm64_only/lineage-20.0-20260403-MAINLINE-waydroid_arm64_only-vendor.zip/download}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log(){ printf '\n== %s ==\n' "$*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
remote(){ ssh "$TV_USER@$TV_IP" "$@"; }

log "compilar binder.ko"
./scripts/build-binder.sh

log "compilar property shim"
./scripts/build-property-shim.sh

log "compilar zygote socket wrapper"
./scripts/build-zygote-socket-wrap.sh

KO="$ROOT/dist/binder.ko"
SHIM="$ROOT/build/property_service_ack_shim-aarch64-static"
ZYGOTE_WRAP="$ROOT/build/zygote_socket_wrap-aarch64-static"
RUNTIME_PATCH="$ROOT/patch-libandroid-runtime-zssystemserver.sh"
ZYGOTE_LAUNCH="$ROOT/try-zygote-start-system-server-v2.sh"

test -f "$KO" || die "no existe $KO"
test -f "$SHIM" || die "no existe $SHIM"
test -f "$ZYGOTE_WRAP" || die "no existe $ZYGOTE_WRAP"
test -f "$RUNTIME_PATCH" || die "no existe $RUNTIME_PATCH"
test -f "$ZYGOTE_LAUNCH" || die "no existe $ZYGOTE_LAUNCH"

log "validar scripts zygote/system_server reproducibles"

grep -q '0x1d4e80' "$RUNTIME_PATCH" \
  || die "$RUNTIME_PATCH no contiene patch 0x1d4e80"

if grep -Eq '0x1d41b8|0x1d41bc' "$RUNTIME_PATCH"; then
  die "$RUNTIME_PATCH contiene offsets malos 0x1d41b8/0x1d41bc"
fi

grep -q '\$ROOTFS/dev/socket/property_service' "$ZYGOTE_LAUNCH" \
  || die "$ZYGOTE_LAUNCH no usa ROOTFS/dev/socket/property_service"

grep -q 'skip VNDK from zygote/system_server LD_PATH' "$ZYGOTE_LAUNCH" \
  || die "$ZYGOTE_LAUNCH no filtra VNDK del LD_LIBRARY_PATH de system_server"

if grep -Eq '^LD_PATH="\$LD_PATH:/vendor/lib64:/odm/lib64"$' "$ZYGOTE_LAUNCH"; then
  die "$ZYGOTE_LAUNCH contamina system_server con /vendor/lib64:/odm/lib64"
fi

grep -Eq 'source ELF magic|refusing to patch|7f454c46' "$RUNTIME_PATCH" \
  || die "$RUNTIME_PATCH no parece idempotente/no valida ELF magic"


log "preparar USB"
ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ANDROID_USB_PART='$ANDROID_USB_PART' FORMAT_USB='$FORMAT_USB' CONFIRM_FORMAT_USB='$CONFIRM_FORMAT_USB' sh -s" <<'REMOTE'
set -eu

die(){ echo "ERROR: $*" >&2; exit 1; }
runtime_state(){ printf 'phase=%s\n' "$1" > "$SIDE/run/runtime.state"; }

SIDE="$USB/android-sidecar"
mkdir -p "$USB"
mkdir -p "$SIDE/run"
runtime_state prepare-usb

echo "--- block devices ---"
cat /proc/partitions || true

killall servicemanager 2>/dev/null || true
killall hwservicemanager 2>/dev/null || true
killall vndservicemanager 2>/dev/null || true
killall property_service_ack_shim property_servic 2>/dev/null || true
killall zygote64 2>/dev/null || true
killall app_process64 2>/dev/null || true
killall system_server 2>/dev/null || true
killall zygote_socket_wrap 2>/dev/null || true
killall -9 zygote64 app_process64 system_server zygote_socket_wrap 2>/dev/null || true
for name in zygote64 app_process64 system_server app_process zygote_socket_wrap; do
  pids="$(pidof "$name" 2>/dev/null || true)"
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
done

cleanup_android_mounts() {
  for base in /tmp/android-usb /mnt/android-usb /media/internal/android-usb "$USB"; do
    [ -n "$base" ] || continue
    for m in \
      "$base/android-rootfs/linkerconfig" \
      "$base/android-rootfs/system/etc/preloaded-classes" \
      "$base/android-rootfs/system/etc/prop.default" \
      "$base/android-rootfs/system/build.prop" \
      "$base/android-rootfs/system/lib64/libandroid_runtime.so" \
      "$base/android-rootfs/system/lib64/libandroid_servers.so" \
      "$base/android-rootfs/system/lib64/libprocessgroup.so" \
      "$base/android-rootfs/vendor/build.prop" \
      "$base/android-rootfs/apex" \
      "$base/android-rootfs/dev" \
      "$base/android-rootfs/sys" \
      "$base/android-rootfs/proc" \
      "$base/android-rootfs/cache" \
      "$base/android-rootfs/data" \
      "$base/android-rootfs/vendor" \
      "$base/android-rootfs/system" \
      "$base/android-mounts/vendor_raw" \
      "$base/android-mounts/system_raw" \
      "$base"
    do
      umount -l "$m" 2>/dev/null || true
    done
  done

  awk -v dev="$ANDROID_USB_PART" '$1==dev{print $2}' /proc/mounts | while read -r mp; do
    [ -n "$mp" ] && umount -l "$mp" 2>/dev/null || true
  done
}

cleanup_android_mounts
mkdir -p "$USB"

if [ "$FORMAT_USB" = "1" ]; then
  [ "$CONFIRM_FORMAT_USB" = "YES" ] || die "FORMAT_USB=1 requiere CONFIRM_FORMAT_USB=YES"

  case "$ANDROID_USB_PART" in
    /dev/sd[a-z]|/dev/sd[a-z][0-9]) ;;
    *) die "por seguridad solo formateo /dev/sdX o /dev/sdXN: $ANDROID_USB_PART" ;;
  esac

  [ -b "$ANDROID_USB_PART" ] || die "no existe $ANDROID_USB_PART"

  rootdev="$(awk '$2=="/"{print $1; exit}' /proc/mounts || true)"
  [ "$rootdev" != "$ANDROID_USB_PART" ] || die "$ANDROID_USB_PART parece rootfs"

  killall servicemanager 2>/dev/null || true
  killall hwservicemanager 2>/dev/null || true
  killall vndservicemanager 2>/dev/null || true
  killall property_service_ack_shim property_servic 2>/dev/null || true
  killall zygote64 2>/dev/null || true
  killall app_process64 2>/dev/null || true
  killall system_server 2>/dev/null || true
  killall zygote_socket_wrap 2>/dev/null || true
  killall -9 zygote64 app_process64 system_server zygote_socket_wrap 2>/dev/null || true
  for name in zygote64 app_process64 system_server app_process zygote_socket_wrap; do
    pids="$(pidof "$name" 2>/dev/null || true)"
    [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
  done

  for m in \
    "$USB/android-rootfs/linkerconfig" \
    "$USB/android-rootfs/system/etc/preloaded-classes" \
    "$USB/android-rootfs/system/etc/prop.default" \
    "$USB/android-rootfs/system/build.prop" \
    "$USB/android-rootfs/system/lib64/libandroid_runtime.so" \
    "$USB/android-rootfs/system/lib64/libandroid_servers.so" \
    "$USB/android-rootfs/system/lib64/libprocessgroup.so" \
    "$USB/android-rootfs/vendor/build.prop" \
    "$USB/android-rootfs/apex" \
    "$USB/android-rootfs/dev" \
    "$USB/android-rootfs/sys" \
    "$USB/android-rootfs/proc" \
    "$USB/android-rootfs/cache" \
    "$USB/android-rootfs/data" \
    "$USB/android-rootfs/vendor" \
    "$USB/android-rootfs/system" \
    "$USB/android-mounts/vendor_raw" \
    "$USB/android-mounts/system_raw" \
    "$USB"
  do
    umount -l "$m" 2>/dev/null || true
  done

  echo "FORMATEANDO $ANDROID_USB_PART"
  mkfs.ext4 -F -L ANDROIDUSB "$ANDROID_USB_PART"
fi

if ! grep -q " $USB " /proc/mounts; then
  mount "$ANDROID_USB_PART" "$USB"
fi

fs="$(awk -v mp="$USB" '$2==mp{print $3; exit}' /proc/mounts)"
dev="$(awk -v mp="$USB" '$2==mp{print $1; exit}' /proc/mounts)"

[ "$fs" = "ext4" ] || die "$USB debe ser ext4, es $fs"
[ "$dev" = "$ANDROID_USB_PART" ] || die "$USB no está montado desde $ANDROID_USB_PART, sino desde $dev"

case "$dev" in
  /dev/sd[a-z]|/dev/sd[a-z][0-9]) ;;
  *) die "$USB no parece USB /dev/sdX: $dev" ;;
esac

mkdir -p "$USB/android-sidecar/modules" "$USB/android-sidecar/bin" "$USB/android-sidecar/logs" "$USB/android-sidecar/run"
df -h "$USB"
REMOTE

log "copiar binarios"
remote "mkdir -p '$SIDE/modules' '$SIDE/bin' '$LOGDIR' '$SIDE/run'"
remote "cat > '$SIDE/modules/binder.ko'" < "$KO"
remote "cat > '$SIDE/bin/property_service_ack_shim' && chmod +x '$SIDE/bin/property_service_ack_shim'" < "$SHIM"
remote "cat > '$SIDE/bin/zygote_socket_wrap' && chmod +x '$SIDE/bin/zygote_socket_wrap'" < "$ZYGOTE_WRAP"
remote "cat > '$SIDE/bin/patch-libandroid-runtime-zssystemserver.sh' && chmod +x '$SIDE/bin/patch-libandroid-runtime-zssystemserver.sh'" < "$RUNTIME_PATCH"
remote "cat > '$SIDE/bin/try-zygote-start-system-server-v2.sh' && chmod +x '$SIDE/bin/try-zygote-start-system-server-v2.sh'" < "$ZYGOTE_LAUNCH"

log "instalar Android USB"
ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' LOGDIR='$LOGDIR' SYSTEM_URL='$SYSTEM_URL' VENDOR_URL='$VENDOR_URL' PATCH_ANDROID_SERVERS='$PATCH_ANDROID_SERVERS' PATCH_ANDROID_RUNTIME='$PATCH_ANDROID_RUNTIME' PATCH_LIBPROCESSGROUP='$PATCH_LIBPROCESSGROUP' sh -s" <<'REMOTE'
set -eu

die(){ echo "ERROR: $*" >&2; exit 1; }
log(){ printf '\n-- %s --\n' "$*"; }
runtime_state(){ printf 'phase=%s\n' "$1" > "$SIDE/run/runtime.state"; }

DOWN="$USB/android-downloads"
IMAGES="$USB/android-images"
MOUNTS="$USB/android-mounts"
DATA="$USB/android-data"
CACHE="$USB/android-cache"

mkdir -p "$DOWN" "$IMAGES" "$MOUNTS/system_raw" "$MOUNTS/vendor_raw" "$ROOTFS" "$DATA" "$CACHE" "$LOGDIR" "$SIDE/run"

download(){
  url="$1"
  out="$2"
  [ -f "$out" ] && { echo "SKIP $(basename "$out")"; return 0; }
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --retry 3 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
  else
    die "falta curl/wget en la TV"
  fi
}

extract_img(){
  zip="$1"
  img="$2"
  name="$3"
  [ -f "$img" ] && { echo "SKIP $(basename "$img")"; return 0; }
  rm -rf "$DOWN/extract-$name"
  mkdir -p "$DOWN/extract-$name"
  unzip -o "$zip" -d "$DOWN/extract-$name" >/dev/null
  found="$(find "$DOWN/extract-$name" -name "$name.img" -type f | head -n 1)"
  [ -n "$found" ] || die "no encuentro $name.img dentro de $zip"
  mv "$found" "$img"
  rm -rf "$DOWN/extract-$name"
}

log "imagenes"
download "$SYSTEM_URL" "$DOWN/system.zip"
download "$VENDOR_URL" "$DOWN/vendor.zip"
extract_img "$DOWN/system.zip" "$IMAGES/system.img" system
extract_img "$DOWN/vendor.zip" "$IMAGES/vendor.img" vendor
ls -lh "$IMAGES/system.img" "$IMAGES/vendor.img"

log "binder"
sym(){
  n="$1"
  awk -v n="$n" '$3==n{print "0x"$1; exit}' /proc/kallsyms
}

if ! grep -q ' binder$' /proc/misc || ! grep -q ' hwbinder$' /proc/misc || ! grep -q ' vndbinder$' /proc/misc; then
  rmmod binder 2>/dev/null || true

  ARGS=""
  for n in get_vm_area map_kernel_range_noflush zap_page_range __alloc_fd __fd_install __close_fd get_files_struct put_files_struct __lock_task_sighand; do
    v="$(sym "$n" || true)"
    [ -n "$v" ] || die "no encuentro símbolo kernel: $n"
    case "$n" in
      get_vm_area) p=sym_get_vm_area ;;
      map_kernel_range_noflush) p=sym_map_kernel_range_noflush ;;
      zap_page_range) p=sym_zap_page_range ;;
      __alloc_fd) p=sym___alloc_fd ;;
      __fd_install) p=sym___fd_install ;;
      __close_fd) p=sym___close_fd ;;
      get_files_struct) p=sym_get_files_struct ;;
      put_files_struct) p=sym_put_files_struct ;;
      __lock_task_sighand) p=sym___lock_task_sighand ;;
    esac
    ARGS="$ARGS $p=$v"
  done

  insmod "$SIDE/modules/binder.ko" $ARGS fd_path_mode=7 debug_mask=0
fi

grep -E 'binder|hwbinder|vndbinder' /proc/misc

minor(){
  n="$1"
  awk -v n="$n" '$2==n{print $1; exit}' /proc/misc
}

BINDER_MINOR="$(minor binder)"
HWBINDER_MINOR="$(minor hwbinder)"
VNDBINDER_MINOR="$(minor vndbinder)"

test -n "$BINDER_MINOR"
test -n "$HWBINDER_MINOR"
test -n "$VNDBINDER_MINOR"

rm -f /dev/binder /dev/hwbinder /dev/vndbinder
mknod /dev/binder c 10 "$BINDER_MINOR"
mknod /dev/hwbinder c 10 "$HWBINDER_MINOR"
mknod /dev/vndbinder c 10 "$VNDBINDER_MINOR"
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder

log "rootfs"
killall servicemanager 2>/dev/null || true
killall hwservicemanager 2>/dev/null || true
killall vndservicemanager 2>/dev/null || true
killall property_service_ack_shim property_servic 2>/dev/null || true
killall zygote64 2>/dev/null || true
killall app_process64 2>/dev/null || true
killall system_server 2>/dev/null || true
killall zygote_socket_wrap 2>/dev/null || true
killall -9 zygote64 app_process64 system_server zygote_socket_wrap 2>/dev/null || true
for name in zygote64 app_process64 system_server app_process zygote_socket_wrap; do
  pids="$(pidof "$name" 2>/dev/null || true)"
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
done

for m in \
  "$ROOTFS/linkerconfig" \
  "$ROOTFS/system/etc/preloaded-classes" \
  "$ROOTFS/system/etc/prop.default" \
  "$ROOTFS/system/build.prop" \
  "$ROOTFS/system/lib64/libandroid_runtime.so" \
  "$ROOTFS/system/lib64/libandroid_servers.so" \
  "$ROOTFS/system/lib64/libprocessgroup.so" \
  "$ROOTFS/vendor/build.prop" \
  "$ROOTFS/apex" \
  "$ROOTFS/dev" \
  "$ROOTFS/sys" \
  "$ROOTFS/proc" \
  "$ROOTFS/cache" \
  "$ROOTFS/data" \
  "$ROOTFS/vendor" \
  "$ROOTFS/system" \
  "$MOUNTS/vendor_raw" \
  "$MOUNTS/system_raw"
do
  umount -l "$m" 2>/dev/null || true
done

mkdir -p "$ROOTFS/system" "$ROOTFS/vendor" "$ROOTFS/apex" "$ROOTFS/data" "$ROOTFS/cache" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" "$ROOTFS/linkerconfig"
mkdir -p "$ROOTFS/mnt/user/0" "$ROOTFS/mnt/installer/0" "$ROOTFS/mnt/androidwritable/0" "$ROOTFS/mnt/pass_through/0" "$ROOTFS/storage"
mkdir -p "$MOUNTS/system_raw" "$MOUNTS/vendor_raw"

mount -o loop,ro "$IMAGES/system.img" "$MOUNTS/system_raw"
mount -o loop,ro "$IMAGES/vendor.img" "$MOUNTS/vendor_raw"

SYSTEM_SRC=""
VENDOR_SRC=""

if [ -f "$MOUNTS/system_raw/system/bin/servicemanager" ]; then
  SYSTEM_SRC="$MOUNTS/system_raw/system"
elif [ -f "$MOUNTS/system_raw/bin/servicemanager" ]; then
  SYSTEM_SRC="$MOUNTS/system_raw"
fi

if [ -f "$MOUNTS/vendor_raw/vendor/bin/vndservicemanager" ]; then
  VENDOR_SRC="$MOUNTS/vendor_raw/vendor"
elif [ -f "$MOUNTS/vendor_raw/bin/vndservicemanager" ]; then
  VENDOR_SRC="$MOUNTS/vendor_raw"
elif [ -f "$MOUNTS/system_raw/vendor/bin/vndservicemanager" ]; then
  VENDOR_SRC="$MOUNTS/system_raw/vendor"
fi

if [ -z "$SYSTEM_SRC" ]; then
  echo "--- system_raw layout ---"
  find "$MOUNTS/system_raw" -maxdepth 3 -type f \( -name servicemanager -o -name hwservicemanager \) -print || true
  find "$MOUNTS/system_raw" -maxdepth 2 -type d -print | head -n 80 || true
  die "no encuentro servicemanager/hwservicemanager en system.img"
fi

if [ -z "$VENDOR_SRC" ]; then
  echo "--- vendor_raw layout ---"
  find "$MOUNTS/vendor_raw" -maxdepth 4 -type f -name vndservicemanager -print || true
  find "$MOUNTS/vendor_raw" -maxdepth 2 -type d -print | head -n 80 || true
  die "no encuentro vndservicemanager en vendor.img"
fi

echo "SYSTEM_SRC=$SYSTEM_SRC"
echo "VENDOR_SRC=$VENDOR_SRC"

mount -o bind "$SYSTEM_SRC" "$ROOTFS/system"
mount -o bind "$VENDOR_SRC" "$ROOTFS/vendor"

echo "--- ensure Android /etc task profiles ---"
if [ -f "$ROOTFS/system/etc/task_profiles.json" ]; then
  if [ ! -e "$ROOTFS/etc" ]; then
    ln -s system/etc "$ROOTFS/etc"
  elif [ -L "$ROOTFS/etc" ]; then
    :
  elif [ -d "$ROOTFS/etc" ] && [ ! -f "$ROOTFS/etc/task_profiles.json" ]; then
    mount -o bind "$ROOTFS/system/etc" "$ROOTFS/etc" 2>/dev/null || mount --bind "$ROOTFS/system/etc" "$ROOTFS/etc"
  fi

  [ -f "$ROOTFS/etc/task_profiles.json" ] || die "/etc/task_profiles.json no visible"
  grep -q "SCHED_SP_TOP_APP" "$ROOTFS/etc/task_profiles.json" || die "SCHED_SP_TOP_APP no está en task_profiles.json"
  echo "OK /etc/task_profiles.json"
else
  die "falta $ROOTFS/system/etc/task_profiles.json"
fi

# BEGIN MINIMAL_APEX_SETUP
# Android 13 Waydroid suele traer APEX como paquetes .apex.
# /system/bin/linker64 apunta a /apex/com.android.runtime/bin/linker64,
# así que hay que montar apex_payload.img antes de ejecutar nada en chroot.
echo "--- apex ---"

awk -v p="$ROOTFS/apex/" '$2 ~ "^"p {print $2}' /proc/mounts | sort -r | while read -r m; do
  umount -l "$m" 2>/dev/null || true
done

umount -l "$ROOTFS/apex" 2>/dev/null || true
mkdir -p "$ROOTFS/apex" "$SIDE/apex-images"

if [ -x "$ROOTFS/system/apex/com.android.runtime/bin/linker64" ]; then
  :
  mount -o bind "$ROOTFS/system/apex" "$ROOTFS/apex"
else
  :

  apex_count=0

  for f in "$ROOTFS/system/apex"/*.apex; do
    [ -f "$f" ] || continue

    base="$(basename "$f" .apex)"
    name="${base%%@*}"
    img="$SIDE/apex-images/$name.img"
    mp="$ROOTFS/apex/$name"

    mkdir -p "$mp"

    if unzip -l "$f" 2>/dev/null | grep -q 'apex_payload.img'; then
      unzip -p "$f" apex_payload.img > "$img"
    else
      echo "WARN: $f no contiene apex_payload.img"
      continue
    fi

    umount -l "$mp" 2>/dev/null || true
    mount -o loop,ro "$img" "$mp"
    apex_count=$((apex_count + 1))
  done

  [ "$apex_count" -gt 0 ] || {
    echo "--- system/apex listing ---"
    find "$ROOTFS/system/apex" -maxdepth 2 -print | head -n 100 || true
    die "no se montó ningún paquete APEX"
  }
fi

ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" \
  || die "falta /apex/com.android.runtime/bin/linker64"

chroot "$ROOTFS" /apex/com.android.runtime/bin/linker64 /system/bin/toybox true >/dev/null 2>&1 \
  || die "toybox no arranca con linker explícito"

echo "ANDROID_APEX_OK"
# END MINIMAL_APEX_SETUP

log "zygote runtime overrides"
OVRDIR="$SIDE/overrides"
PROPDIR="$SIDE/prop-overrides"
mkdir -p "$OVRDIR" "$PROPDIR"

PRELOADED="$ROOTFS/system/etc/preloaded-classes"
if [ -f "$PRELOADED" ]; then
  while mount | grep -q " $PRELOADED "; do
    umount "$PRELOADED" 2>/dev/null || break
  done

  PRELOADED_PATCH="$OVRDIR/preloaded-classes.empty"
  : > "$PRELOADED_PATCH"
  chmod 644 "$PRELOADED_PATCH"
  mount --bind "$PRELOADED_PATCH" "$PRELOADED" \
    || die "no pude montar override de preloaded-classes"

  [ "$(wc -l < "$PRELOADED")" = "0" ] \
    || die "preloaded-classes no quedó vacío"

  echo "OK preloaded-classes vacío"
else
  die "falta $PRELOADED"
fi

PROP_TARGET=""
if [ -f "$ROOTFS/system/etc/prop.default" ]; then
  PROP_TARGET="$ROOTFS/system/etc/prop.default"
elif [ -f "$ROOTFS/system/build.prop" ]; then
  PROP_TARGET="$ROOTFS/system/build.prop"
else
  die "no encuentro prop.default/build.prop"
fi

while mount | grep -q " $PROP_TARGET "; do
  umount "$PROP_TARGET" 2>/dev/null || break
done

PROP_PATCH="$PROPDIR/$(basename "$PROP_TARGET").zygote"
cp "$PROP_TARGET" "$PROP_PATCH"
grep -v '^ro\.zygote\.disable_gl_preload=' "$PROP_PATCH" > "$PROP_PATCH.tmp" || true
grep -v '^ro\.hardware\.egl=' "$PROP_PATCH.tmp" > "$PROP_PATCH" || true
rm -f "$PROP_PATCH.tmp"

cat >> "$PROP_PATCH" <<'PROPS'

# webos-android-minimal zygote compatibility
ro.zygote.disable_gl_preload=true
ro.hardware.egl=mesa
PROPS

mount --bind "$PROP_PATCH" "$PROP_TARGET" \
  || die "no pude montar override de $(basename "$PROP_TARGET")"

echo "OK propiedades zygote override: $PROP_TARGET"

# /system/bin/linker64 apunta a /apex/com.android.runtime/bin/linker64.
# Por tanto /apex debe ser el apex real del system.img, no tmpfs.
umount -l "$ROOTFS/apex" 2>/dev/null || true
mkdir -p "$ROOTFS/apex"

if [ -d "$ROOTFS/system/apex/com.android.runtime" ]; then
  mount -o bind "$ROOTFS/system/apex" "$ROOTFS/apex"
else
  echo "--- apex debug ---"
  find "$ROOTFS/system" -maxdepth 4 -type d -name 'com.android.runtime' -print || true
  find "$ROOTFS/system" -maxdepth 2 -type d -name apex -print || true
  die "no encuentro /system/apex/com.android.runtime"
fi

test -e "$ROOTFS/apex/com.android.runtime/bin/linker64" \
  || die "falta /apex/com.android.runtime/bin/linker64"

mount -o bind "$DATA" "$ROOTFS/data"
mount -o bind "$CACHE" "$ROOTFS/cache"

echo "--- Android writable data/cache dirs ---"
mkdir -p \
  "$ROOTFS/data/dalvik-cache/arm64" \
  "$ROOTFS/data/dalvik-cache/arm" \
  "$ROOTFS/data/local/tmp" \
  "$ROOTFS/data/system" \
  "$ROOTFS/data/system/environ" \
  "$ROOTFS/data/system/users/0" \
  "$ROOTFS/data/misc" \
  "$ROOTFS/data/misc/profiles" \
  "$ROOTFS/data/misc/profiles/cur/0" \
  "$ROOTFS/data/misc/profiles/ref" \
  "$ROOTFS/data/user/0" \
  "$ROOTFS/data/data" \
  "$ROOTFS/cache/dalvik-cache" \
  "$ROOTFS/mnt/user/0" \
  "$ROOTFS/mnt/installer/0" \
  "$ROOTFS/mnt/androidwritable/0" \
  "$ROOTFS/mnt/pass_through/0" \
  "$ROOTFS/storage"

chmod 0771 "$ROOTFS/data" "$ROOTFS/data/dalvik-cache" "$ROOTFS/data/dalvik-cache/arm64" "$ROOTFS/data/dalvik-cache/arm" 2>/dev/null || true
chmod 0771 "$ROOTFS/data/system" "$ROOTFS/data/system/users" "$ROOTFS/data/system/users/0" 2>/dev/null || true
chmod 0771 "$ROOTFS/data/misc" "$ROOTFS/data/misc/profiles" "$ROOTFS/data/misc/profiles/cur" "$ROOTFS/data/misc/profiles/cur/0" "$ROOTFS/data/misc/profiles/ref" 2>/dev/null || true
chmod 1777 "$ROOTFS/data/local/tmp" 2>/dev/null || true
chmod 0770 "$ROOTFS/cache" "$ROOTFS/cache/dalvik-cache" 2>/dev/null || true
chmod 0755 "$ROOTFS/mnt" "$ROOTFS/mnt/user" "$ROOTFS/mnt/user/0" 2>/dev/null || true
chmod 0755 "$ROOTFS/mnt/installer" "$ROOTFS/mnt/installer/0" 2>/dev/null || true
chmod 0755 "$ROOTFS/mnt/androidwritable" "$ROOTFS/mnt/androidwritable/0" 2>/dev/null || true
chmod 0755 "$ROOTFS/mnt/pass_through" "$ROOTFS/mnt/pass_through/0" "$ROOTFS/storage" 2>/dev/null || true

ls -ld "$ROOTFS/data" "$ROOTFS/data/dalvik-cache" "$ROOTFS/data/dalvik-cache/arm64" "$ROOTFS/data/local/tmp" "$ROOTFS/storage" "$ROOTFS/mnt/user/0"

mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
mount -o bind /dev "$ROOTFS/dev"

mkdir -p "$ROOTFS/dev/socket"
rm -f "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"
mknod "$ROOTFS/dev/binder" c 10 "$BINDER_MINOR"
mknod "$ROOTFS/dev/hwbinder" c 10 "$HWBINDER_MINOR"
mknod "$ROOTFS/dev/vndbinder" c 10 "$VNDBINDER_MINOR"
chmod 666 "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"

log "property/linkerconfig"
runtime_state property-linkerconfig
rm -f "$ROOTFS/dev/socket/property_service" /dev/socket/property_service 2>/dev/null || true
nohup "$SIDE/bin/property_service_ack_shim" \
  "$ROOTFS/dev/socket/property_service" \
  </dev/null >"$LOGDIR/property_service_ack_shim.log" 2>&1 &
echo $! > "$SIDE/run/property_service_ack_shim.pid"

sleep 1
[ -S "$ROOTFS/dev/socket/property_service" ] || die "no se creó property_service socket"

mount -t tmpfs tmpfs "$ROOTFS/linkerconfig" 2>/dev/null || true

chroot "$ROOTFS" /system/bin/linkerconfig \
  >"$ROOTFS/linkerconfig/ld.config.txt" \
  2>"$LOGDIR/linkerconfig.stderr.log" || true

rm -rf "$ROOTFS/dev/__properties__" 2>/dev/null || true

chroot "$ROOTFS" /system/bin/init second_stage \
  >"$LOGDIR/init.second_stage.property.log" 2>&1 &

INITPID="$!"
sleep 5
kill "$INITPID" 2>/dev/null || true
sleep 1
kill -9 "$INITPID" 2>/dev/null || true

echo "--- apex-info/linkerconfig namespaces ---"
BINDROOT="$SIDE/apex-bindsrc"
NAMES="$SIDE/apex-bindsrc.modules"

awk -v p="$BINDROOT/" 'index($2,p)==1 {print $2}' /proc/mounts | sort -r | while read -r mp; do
  umount "$mp" 2>/dev/null || true
done

rm -rf "$BINDROOT"
mkdir -p "$BINDROOT"
: > "$NAMES"

for d in "$ROOTFS"/system/apex/com.android.*; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  mkdir -p "$BINDROOT/$name"
  mount --bind "$d" "$BINDROOT/$name" || continue
  echo "$name" >> "$NAMES"
done

grep -q '^com.android.art$' "$NAMES" || die "falta APEX com.android.art"
grep -q '^com.android.runtime$' "$NAMES" || die "falta APEX com.android.runtime"

umount -l "$ROOTFS/apex" 2>/dev/null || true
mount -t tmpfs -o mode=0755,size=128m tmpfs "$ROOTFS/apex"

while read -r name; do
  [ -n "$name" ] || continue
  mkdir -p "$ROOTFS/apex/$name"
  mount --bind "$BINDROOT/$name" "$ROOTFS/apex/$name"
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

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<apex-info-list>'
  while read -r name; do
    [ -n "$name" ] || continue
    MANIFEST="$ROOTFS/apex/$name/apex_manifest.json"
    VERSION="$(get_manifest_num "$MANIFEST" version)"
    [ -n "$VERSION" ] || VERSION=1
    VERSION_NAME="$(get_manifest_field "$MANIFEST" versionName)"
    [ -n "$VERSION_NAME" ] || VERSION_NAME="$VERSION"

    if [ -e "$ROOTFS/system/apex/$name" ]; then
      PRE="/system/apex/$name"
    elif [ -e "$ROOTFS/system/apex/$name.apex" ]; then
      PRE="/system/apex/$name.apex"
    else
      PRE="/apex/$name"
    fi

    SHARED=false
    [ "$name" = "com.android.vndk.current" ] && SHARED=true

    echo "  <apex-info moduleName=\"$name\" modulePath=\"/apex/$name\" preinstalledModulePath=\"$PRE\" versionCode=\"$VERSION\" versionName=\"$VERSION_NAME\" isFactory=\"true\" isActive=\"true\" lastUpdateMillis=\"0\" provideSharedApexLibs=\"$SHARED\"/>"
  done < "$NAMES"
  echo '</apex-info-list>'
} > "$ROOTFS/apex/apex-info-list.xml"

mkdir -p "$ROOTFS/product" "$ROOTFS/system_ext" "$ROOTFS/odm"
if [ -e "$ROOTFS/apex/com.android.vndk.current" ] && [ ! -e "$ROOTFS/apex/com.android.vndk.v33" ]; then
  ln -s com.android.vndk.current "$ROOTFS/apex/com.android.vndk.v33" 2>/dev/null || true
fi

while mount | grep -q " $ROOTFS/linkerconfig "; do
  umount "$ROOTFS/linkerconfig" 2>/dev/null || break
done

mkdir -p "$ROOTFS/linkerconfig"
mount -t tmpfs -o mode=0755,size=16m tmpfs "$ROOTFS/linkerconfig" || true

if [ -x "$ROOTFS/apex/com.android.runtime/bin/linkerconfig" ]; then
  chroot "$ROOTFS" /apex/com.android.runtime/bin/linkerconfig --target /linkerconfig \
    >"$LOGDIR/linkerconfig.apexinfo.log" 2>&1
elif [ -x "$ROOTFS/system/bin/linkerconfig" ]; then
  chroot "$ROOTFS" /system/bin/linkerconfig --target /linkerconfig \
    >"$LOGDIR/linkerconfig.apexinfo.log" 2>&1
else
  die "no encuentro linkerconfig"
fi

grep -q 'com_android_art' "$ROOTFS/linkerconfig/ld.config.txt" \
  || die "linkerconfig no generó namespace com_android_art"
grep -q 'libnativeloader.so' "$ROOTFS/linkerconfig/ld.config.txt" \
  || die "linkerconfig no expone libnativeloader.so"

echo "--- create Android classpaths ---"
mkdir -p "$ROOTFS/data/system/environ"
ENVFILE="$ROOTFS/data/system/environ/classpath"

BCP=""
DEX2OATBCP=""
SSCP=""

classpath_complete() {
  [ "${#BCP}" -gt 1000 ] && [ "${#SSCP}" -gt 100 ]
}

classpath_order_ok() {
  case "$BCP" in
    /apex/com.android.art/javalib/core-oj.jar:*) return 0 ;;
    *) return 1 ;;
  esac
}

reset_classpath_vars() {
  BCP=""
  DEX2OATBCP=""
  SSCP=""
}

read_envfile_var() {
  var="$1"
  file="$2"
  [ -f "$file" ] || return 1

  sed -n \
    -e "s/^[[:space:]]*export[[:space:]]\+$var[[:space:]]\+\(.*\)$/\1/p" \
    -e "s/^[[:space:]]*$var=\(.*\)$/\1/p" \
    "$file" | tail -1 | tr -d '"'
}

extract_init_var() {
  var="$1"

  for f in \
    "$ROOTFS/system/etc/init/hw/init.environ.rc" \
    "$ROOTFS/system/etc/init/init.environ.rc" \
    "$ROOTFS/system/etc/init/hw/init.rc" \
    "$ROOTFS/system/etc/init/init.rc" \
    "$ROOTFS/vendor/etc/init/hw/init.environ.rc" \
    "$ROOTFS/vendor/etc/init/init.environ.rc"
  do
    [ -f "$f" ] || continue
    val="$(read_envfile_var "$var" "$f" || true)"
    if [ -n "$val" ]; then
      echo "$val"
      return 0
    fi
  done

  return 1
}

classpath_from_pb() {
  out=""
  for f in "$@"; do
    [ -f "$f" ] || continue

    strings "$f" 2>/dev/null \
      | sed -n 's#^[^/]*\(/.*\.jar\)$#\1#p' \
      | sed 's#^//*#/#' \
      | while read -r rel; do
          [ -f "$ROOTFS$rel" ] && echo "$rel"
        done
  done | awk '
    !seen[$0]++ {
      if (out == "") out = $0;
      else out = out ":" $0;
    }
    END { print out }
  '
}

echo "--- existing classpath check ---"
if [ -s "$ENVFILE" ]; then
  BCP="$(read_envfile_var BOOTCLASSPATH "$ENVFILE" || true)"
  DEX2OATBCP="$(read_envfile_var DEX2OATBOOTCLASSPATH "$ENVFILE" || true)"
  SSCP="$(read_envfile_var SYSTEMSERVERCLASSPATH "$ENVFILE" || true)"

  if ! classpath_complete || ! classpath_order_ok; then
    echo "existing classpath unusable; regenerating"
    reset_classpath_vars
  fi
fi

if [ -z "$BCP" ] || [ -z "$SSCP" ]; then
  echo "--- classpath from init rc ---"
  BCP="$(extract_init_var BOOTCLASSPATH || true)"
  DEX2OATBCP="$(extract_init_var DEX2OATBOOTCLASSPATH || true)"
  SSCP="$(extract_init_var SYSTEMSERVERCLASSPATH || true)"

  if ! classpath_complete || ! classpath_order_ok; then
    echo "init rc classpath unusable; trying classpath protobufs"
    reset_classpath_vars
  fi
fi

if [ -z "$BCP" ] || [ -z "$SSCP" ]; then
  echo "--- classpath from /system/etc/classpaths/*.pb ---"

  echo "--- classpath pb files ---"
  find \
    "$ROOTFS/system/etc/classpaths" \
    "$ROOTFS/system_ext/etc/classpaths" \
    "$ROOTFS/product/etc/classpaths" \
    "$ROOTFS/apex" \
    -type f -name '*classpath*.pb' 2>/dev/null | sort || true

  BCP="$(classpath_from_pb \
    "$ROOTFS/apex/com.android.art/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/system/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/system_ext/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/product/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.i18n/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.conscrypt/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.adservices/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.appsearch/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.btservices/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.ipsec/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.media/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.mediaprovider/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.ondevicepersonalization/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.os.statsd/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.permission/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.scheduling/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.sdkext/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.tethering/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.uwb/etc/classpaths/bootclasspath.pb" \
    "$ROOTFS/apex/com.android.wifi/etc/classpaths/bootclasspath.pb")"

  DEX2OATBCP="$BCP"

  SSCP="$(classpath_from_pb \
    "$ROOTFS/system/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/system_ext/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/product/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.adservices/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.art/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.appsearch/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.btservices/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.media/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.os.statsd/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.permission/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.scheduling/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.tethering/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.uwb/etc/classpaths/systemserverclasspath.pb" \
    "$ROOTFS/apex/com.android.wifi/etc/classpaths/systemserverclasspath.pb")"
fi

[ -n "$DEX2OATBCP" ] || DEX2OATBCP="$BCP"

rm -f "$ENVFILE"
{
  echo "export BOOTCLASSPATH $BCP"
  echo "export DEX2OATBOOTCLASSPATH $DEX2OATBCP"
  echo "export SYSTEMSERVERCLASSPATH $SSCP"
} > "$ENVFILE"

echo "BOOTCLASSPATH generated length: ${#BCP}"
echo "SYSTEMSERVERCLASSPATH generated length: ${#SSCP}"

echo "--- classpath file ---"
cat "$ENVFILE"

[ "${#BCP}" -gt 1000 ] || die "BOOTCLASSPATH demasiado corto: ${#BCP}"
[ "${#SSCP}" -gt 100 ] || die "SYSTEMSERVERCLASSPATH demasiado corto: ${#SSCP}"
classpath_order_ok || die "BOOTCLASSPATH no empieza por ART core-oj.jar"

echo "$BCP" | grep -q '/system/framework/framework.jar' \
  || die "BOOTCLASSPATH no contiene framework.jar"
echo "$SSCP" | grep -q '/system/framework/services.jar' \
  || die "SYSTEMSERVERCLASSPATH no contiene services.jar"

log "service managers"
runtime_state service-managers




echo "--- apex listo ---"
if [ ! -x "$ROOTFS/apex/com.android.runtime/bin/linker64" ]; then
  echo "--- apex debug before managers ---"
  find "$ROOTFS/apex" -maxdepth 3 -print | head -n 120 || true
  die "no encuentro com.android.runtime antes de arrancar managers"
fi

ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" \
  || die "falta linker64 antes de managers"

chroot "$ROOTFS" /apex/com.android.runtime/bin/linker64 /system/bin/toybox true >/dev/null 2>&1 \
  || die "toybox no arranca justo antes de managers"

echo "--- managers ---"
ls -l "$ROOTFS/system/bin/servicemanager" || true
ls -l "$ROOTFS/system/bin/hwservicemanager" || true
ls -l "$ROOTFS/vendor/bin/vndservicemanager" || true
ls -l "$ROOTFS/apex/com.android.runtime/bin/linker64" || true

chroot "$ROOTFS" /system/bin/toybox true

nohup chroot "$ROOTFS" /system/bin/servicemanager \
  </dev/null >"$LOGDIR/servicemanager.log" 2>&1 &
echo $! > "$SIDE/run/servicemanager.pid"

sleep 2

nohup chroot "$ROOTFS" /system/bin/hwservicemanager \
  </dev/null >"$LOGDIR/hwservicemanager.log" 2>&1 &
echo $! > "$SIDE/run/hwservicemanager.pid"

sleep 2

nohup chroot "$ROOTFS" /vendor/bin/vndservicemanager \
  </dev/null >"$LOGDIR/vndservicemanager.log" 2>&1 &
echo $! > "$SIDE/run/vndservicemanager.pid"

sleep 5

echo "--- binder devices ---"
grep -E 'binder|hwbinder|vndbinder' /proc/misc
ls -l /dev/binder /dev/hwbinder /dev/vndbinder
ls -l "$ROOTFS/dev/binder" "$ROOTFS/dev/hwbinder" "$ROOTFS/dev/vndbinder"

echo "--- android services ---"
ok=1
for n in vndservicemanager servicemanager hwservicemanager; do
  if pidof "$n" >/dev/null 2>&1; then
    echo "$n: $(pidof "$n")"
  else
    echo "NO VIVO: $n"
    ok=0
  fi
done

if [ "$ok" != "1" ]; then
  echo "--- logs ---"
  tail -n 80 "$LOGDIR/vndservicemanager.log" 2>/dev/null || true
  tail -n 80 "$LOGDIR/servicemanager.log" 2>/dev/null || true
  tail -n 80 "$LOGDIR/hwservicemanager.log" 2>/dev/null || true
  die "algún service manager salió"
fi

echo FINAL_USB_3DOMAIN_BINDER_OK

log "zygote/system_server"
runtime_state zygote-system-server

echo "PATCH_ANDROID_SERVERS=$PATCH_ANDROID_SERVERS"

killall -9 zygote64 system_server app_process64 app_process property_service_ack_shim 2>/dev/null || true
for name in zygote64 app_process64 system_server app_process zygote_socket_wrap; do
  pids="$(pidof "$name" 2>/dev/null || true)"
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
done

RUNTIME_TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
while mount | grep -q " $RUNTIME_TGT "; do
  umount "$RUNTIME_TGT" 2>/dev/null || break
done

if [ "${PATCH_ANDROID_RUNTIME:-1}" = "1" ]; then
  echo -n "libandroid_runtime source ELF magic before patch: "
  od -An -tx1 -N 4 "$RUNTIME_TGT"

  USB="$USB" sh "$SIDE/bin/patch-libandroid-runtime-zssystemserver.sh" \
    >"$LOGDIR/patch-libandroid-runtime-zssystemserver.log" 2>&1 || {
      cat "$LOGDIR/patch-libandroid-runtime-zssystemserver.log" 2>/dev/null || true
      die "falló patch libandroid_runtime para zygote/system_server"
    }
else
  echo "--- skip libandroid_runtime patch (PATCH_ANDROID_RUNTIME=0; Codex minimal path) ---"
fi

if [ "${PATCH_LIBPROCESSGROUP:-1}" = "1" ]; then
  echo "--- patch libprocessgroup scheduling blockers ---"
  PG_TGT="$ROOTFS/system/lib64/libprocessgroup.so"
  PG_PATCH="$SIDE/overrides/libprocessgroup.sched.so"
  mkdir -p "$SIDE/overrides"

  while mount | grep -q " $PG_TGT "; do
    umount "$PG_TGT" 2>/dev/null || break
  done

  echo -n "libprocessgroup source ELF magic: "
  od -An -tx1 -N 4 "$PG_TGT"

  PG_MAGIC="$(od -An -tx1 -N 4 "$PG_TGT" | tr -d " \n")"
  if [ "$PG_MAGIC" != "7f454c46" ]; then
    die "source libprocessgroup.so no es ELF; refusing to patch"
  fi

  rm -f "$PG_PATCH"
  cp "$PG_TGT" "$PG_PATCH" \
    || die "no pude copiar libprocessgroup.so"
  chmod 644 "$PG_PATCH"

  patch_pg() {
    off="$1"
    bytes="$2"
    label="$3"
    echo -n "$label before @ $off: "
    od -An -tx1 -j "$((off))" -N 8 "$PG_PATCH"
    printf "$bytes" | dd of="$PG_PATCH" bs=1 seek="$((off))" conv=notrunc 2>/dev/null
    echo -n "$label after  @ $off: "
    od -An -tx1 -j "$((off))" -N 8 "$PG_PATCH"
  }

  # AArch64: mov w0,#1; ret for boolean success.
  patch_pg 0x2b4ac '\040\000\200\122\300\003\137\326' "SetProcessProfiles"
  patch_pg 0x2b4f4 '\040\000\200\122\300\003\137\326' "SetProcessProfilesCached"
  patch_pg 0x2b53c '\040\000\200\122\300\003\137\326' "SetTaskProfiles"
  patch_pg 0x34504 '\040\000\200\122\300\003\137\326' "TaskProfiles::SetProcessProfiles"
  patch_pg 0x34718 '\040\000\200\122\300\003\137\326' "TaskProfiles::SetTaskProfiles"

  # AArch64: mov w0,#0; ret for int success.
  patch_pg 0x2ec1c '\000\000\200\122\300\003\137\326' "set_cpuset_policy"
  patch_pg 0x2efb8 '\000\000\200\122\300\003\137\326' "set_sched_policy"

  mount --bind "$PG_PATCH" "$PG_TGT" \
    || die "no pude montar libprocessgroup parcheado"

  echo "LIBPROCESSGROUP_SCHED_OK"
else
  echo "--- skip libprocessgroup patch (PATCH_LIBPROCESSGROUP=0; Codex minimal path) ---"
fi

if [ "${PATCH_ANDROID_SERVERS:-0}" = "1" ]; then
echo "--- patch libandroid_servers zygote/system_server blockers ---"
SERVERS_TGT="$ROOTFS/system/lib64/libandroid_servers.so"
SERVERS_PATCH="$SIDE/overrides/libandroid_servers.zssystemserver.so"
mkdir -p "$SIDE/overrides"

while mount | grep -q " $SERVERS_TGT "; do
  umount "$SERVERS_TGT" 2>/dev/null || break
done

echo -n "libandroid_servers source ELF magic: "
od -An -tx1 -N 4 "$SERVERS_TGT"

SERVERS_MAGIC="$(od -An -tx1 -N 4 "$SERVERS_TGT" | tr -d " \\n")"
if [ "$SERVERS_MAGIC" != "7f454c46" ]; then
  die "source libandroid_servers.so no es ELF; refusing to patch"
fi

rm -f "$SERVERS_PATCH"
cp "$SERVERS_TGT" "$SERVERS_PATCH" \
  || die "no pude copiar libandroid_servers.so"
chmod 644 "$SERVERS_PATCH"

patch_servers() {
  off="$1"
  bytes="$2"
  label="$3"
  echo -n "$label before @ $off: "
  od -An -tx1 -j "$((off))" -N 16 "$SERVERS_PATCH"
  printf "$bytes" | dd of="$SERVERS_PATCH" bs=1 seek="$((off))" conv=notrunc 2>/dev/null
  echo -n "$label after  @ $off: "
  od -An -tx1 -j "$((off))" -N 16 "$SERVERS_PATCH"
}

# AArch64: mov w0,#0; ret; nop; nop
patch_servers 0x6ef00 '\000\000\200\122\300\003\137\326\037\040\003\325\037\040\003\325' "PowerStats nativeInit"

# AArch64: ret; nop; nop; nop
patch_servers 0x74c98 '\300\003\137\326\037\040\003\325\037\040\003\325\037\040\003\325' "IStatsService start"
patch_servers 0x74f1c '\300\003\137\326\037\040\003\325\037\040\003\325\037\040\003\325' "MemtrackProxyService start"

mount --bind "$SERVERS_PATCH" "$SERVERS_TGT" \
  || die "no pude montar libandroid_servers parcheado"

echo "LIBANDROID_SERVERS_ZSSYSTEMSERVER_OK"
else
  echo "--- skip libandroid_servers patch (PATCH_ANDROID_SERVERS=0; Codex minimal path) ---"
  SERVERS_TGT="$ROOTFS/system/lib64/libandroid_servers.so"
  while mount | grep -q " $SERVERS_TGT "; do
    umount "$SERVERS_TGT" 2>/dev/null || break
  done
fi

echo "--- preflight writable Android dirs ---"
for d in \
  "$ROOTFS/data/dalvik-cache/arm64" \
  "$ROOTFS/data/local/tmp" \
  "$ROOTFS/data/system" \
  "$ROOTFS/cache/dalvik-cache"
do
  [ -d "$d" ] || die "falta directorio requerido: $d"
done

USB="$USB" ROOTFS="$ROOTFS" SIDE="$SIDE" LOGDIR="$LOGDIR" \
  sh "$SIDE/bin/try-zygote-start-system-server-v2.sh" \
  >"$LOGDIR/zygote-system-server-launch.out" 2>&1 || {
    cat "$LOGDIR/zygote-system-server-launch.out" 2>/dev/null || true
    die "zygote/system_server no quedó vivo"
  }

cat "$LOGDIR/zygote-system-server-launch.out"

if ! pidof zygote64 >/dev/null 2>&1 && ! pidof app_process64 >/dev/null 2>&1; then
  die "zygote64 no quedó vivo tras el install"
fi

if ! pidof system_server >/dev/null 2>&1; then
  die "system_server no quedó vivo tras el install"
fi

echo FINAL_ANDROID_ZYGOTE_SYSTEM_SERVER_OK
runtime_state complete
REMOTE

echo
echo "FINAL_USB_INSTALL_OK"
