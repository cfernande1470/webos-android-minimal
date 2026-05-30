#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' sh -s" <<'REMOTE'
set -eu

say(){ printf '%s\n' "$*"; }

clean_under() {
  base="$1"
  awk -v p="$base/" '$2 ~ "^"p {print $2}' /proc/mounts | sort -r | while read -r mp; do
    [ -n "$mp" ] || continue
    umount -l "$mp" 2>/dev/null || true
  done
}

say "--- cleaning mounts under ROOTFS ---"
clean_under "$ROOTFS"

say "--- cleaning mounts under SIDE ---"
clean_under "$SIDE"

say "--- cleaning direct socket mounts ---"
for m in \
  "$ROOTFS/dev/socket/property_service" \
  "$ROOTFS/dev/socket/zygote" \
  "$ROOTFS/dev/socket/usap_pool_primary" \
  "$ROOTFS/linkerconfig" \
  "$ROOTFS/apex" \
  "$ROOTFS/dev" \
  "$ROOTFS/sys" \
  "$ROOTFS/proc" \
  "$ROOTFS/data" \
  "$ROOTFS/cache" \
  "$ROOTFS/system" \
  "$ROOTFS/vendor" \
  "$ROOTFS/system/lib64/libandroid_runtime.so" \
  "$ROOTFS/system/lib64/libandroid_servers.so" \
  "$ROOTFS/system/lib64/libprocessgroup.so" \
  "$ROOTFS/system/etc/preloaded-classes" \
  "$ROOTFS/system/etc/prop.default" \
  "$ROOTFS/system/build.prop" \
  "$ROOTFS/vendor/build.prop"
do
  umount -l "$m" 2>/dev/null || true
done

say "clean-mounts done"
REMOTE
