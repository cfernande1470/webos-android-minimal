#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
LOGDIR="${LOGDIR:-$SIDE/logs}"
OUTPUT="${OUTPUT:-android-sidecar-logs-$(date -u +%Y%m%dT%H%M%SZ).tar.gz}"

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' LOGDIR='$LOGDIR' sh -s" <<'REMOTE' > "$OUTPUT"
set -eu

tmp="$(mktemp -d /tmp/webos-android-minimal-logs.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/android-sidecar/logs" "$tmp/android-sidecar/run"

if [ -d "$LOGDIR" ]; then
  cp -a "$LOGDIR"/. "$tmp/android-sidecar/logs/" 2>/dev/null || true
fi

if [ -d "$SIDE/run" ]; then
  cp -a "$SIDE/run"/. "$tmp/android-sidecar/run/" 2>/dev/null || true
fi

{
  echo "USB=$USB"
  echo "ROOTFS=$ROOTFS"
  echo "SIDE=$SIDE"
  echo
  echo "--- runtime.state ---"
  cat "$SIDE/run/runtime.state" 2>/dev/null || true
  echo
  echo "--- pidof snapshot ---"
  for n in property_service_ack_shim servicemanager hwservicemanager vndservicemanager zygote64 app_process64 system_server zygote_socket_wrap \
    android.hardware.memtrack@1.0-service android.hardware.power@1.0-service.waydroid \
    android.hardware.graphics.allocator@2.0-service android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa \
    android.hardware.graphics.composer@2.1-service android.hardware.sensors@1.0-service.waydroid \
    android.hardware.light@2.0-service.waydroid; do
    p="$(pidof "$n" 2>/dev/null || true)"
    [ -n "$p" ] && echo "$n: $p"
  done
  echo
  echo "--- mounts ---"
  cat /proc/mounts
  echo
  echo "--- partitions ---"
  cat /proc/partitions
} > "$tmp/android-sidecar/run/host-snapshot.txt"

tar -C "$tmp" -czf - android-sidecar
REMOTE
