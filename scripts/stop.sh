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
state_file="$SIDE/run/runtime.state"

kill_pidfile() {
  file="$1"
  if [ ! -s "$file" ]; then
    return 0
  fi

  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
}

kill_name() {
  name="$1"
  pids="$(pidof "$name" 2>/dev/null || true)"
  [ -n "$pids" ] && kill $pids 2>/dev/null || true
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
}

say "--- stopping android sidecar ---"
kill_name system_server
kill_name zygote64
kill_name app_process64
kill_name app_process
kill_name servicemanager
kill_name hwservicemanager
kill_name vndservicemanager
kill_name property_service_ack_shim
kill_name zygote_socket_wrap
kill_name android.hardware.memtrack@1.0-service
kill_name android.hardware.power@1.0-service.waydroid
kill_name android.hardware.graphics.allocator@2.0-service
kill_name android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa
kill_name android.hardware.graphics.composer@2.1-service
kill_name android.hardware.sensors@1.0-service.waydroid
kill_name android.hardware.light@2.0-service.waydroid

kill_pidfile "$SIDE/run/system_server.pid"
kill_pidfile "$SIDE/run/zygote64.pid"
kill_pidfile "$SIDE/run/zygote_socket_wrap.pid"
kill_pidfile "$SIDE/run/servicemanager.pid"
kill_pidfile "$SIDE/run/hwservicemanager.pid"
kill_pidfile "$SIDE/run/vndservicemanager.pid"
kill_pidfile "$SIDE/run/property_service_ack_shim.pid"

sleep 1
kill_name system_server
kill_name zygote64
kill_name app_process64
kill_name app_process
kill_name servicemanager
kill_name hwservicemanager
kill_name vndservicemanager
kill_name property_service_ack_shim
kill_name zygote_socket_wrap
kill_name android.hardware.memtrack@1.0-service
kill_name android.hardware.power@1.0-service.waydroid
kill_name android.hardware.graphics.allocator@2.0-service
kill_name android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa
kill_name android.hardware.graphics.composer@2.1-service
kill_name android.hardware.sensors@1.0-service.waydroid
kill_name android.hardware.light@2.0-service.waydroid

rm -f \
  "$SIDE/run/property_service_ack_shim.pid" \
  "$SIDE/run/servicemanager.pid" \
  "$SIDE/run/hwservicemanager.pid" \
  "$SIDE/run/vndservicemanager.pid" \
  "$SIDE/run/zygote_socket_wrap.pid" \
  "$SIDE/run/zygote64.pid" \
  "$SIDE/run/system_server.pid" 2>/dev/null || true

rm -f \
  "$ROOTFS/dev/socket/property_service" \
  "$ROOTFS/dev/socket/zygote" \
  "$ROOTFS/dev/socket/usap_pool_primary" \
  /dev/socket/property_service 2>/dev/null || true

for mp in $(awk -v p="$ROOTFS/" '$2 ~ "^"p {print $2}' /proc/mounts | sort -r); do
  umount -l "$mp" 2>/dev/null || true
done

for mp in $(awk -v p="$SIDE/" '$2 ~ "^"p {print $2}' /proc/mounts | sort -r); do
  umount -l "$mp" 2>/dev/null || true
done

printf 'phase=stopped\n' > "$state_file"
say "stopped"
REMOTE
