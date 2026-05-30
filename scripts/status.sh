#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
LOGDIR="${LOGDIR:-$SIDE/logs}"

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' LOGDIR='$LOGDIR' sh -s" <<'REMOTE'
set -eu

say(){ printf '%s\n' "$*"; }
state_file="$SIDE/run/runtime.state"

show_pidfile() {
  label="$1"
  file="$2"
  if [ ! -s "$file" ]; then
    say "$label: missing"
    return 0
  fi

  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    say "$label: $pid"
  else
    say "$label: stale(${pid:-?})"
  fi
}

say "runtime.state: $(cat "$state_file" 2>/dev/null || echo missing)"
say "--- pid files ---"
show_pidfile property_service_ack_shim "$SIDE/run/property_service_ack_shim.pid"
show_pidfile servicemanager "$SIDE/run/servicemanager.pid"
show_pidfile hwservicemanager "$SIDE/run/hwservicemanager.pid"
show_pidfile vndservicemanager "$SIDE/run/vndservicemanager.pid"
show_pidfile zygote_socket_wrap "$SIDE/run/zygote_socket_wrap.pid"
show_pidfile zygote64 "$SIDE/run/zygote64.pid"
show_pidfile system_server "$SIDE/run/system_server.pid"

say "--- live pids ---"
for n in property_service_ack_shim servicemanager hwservicemanager vndservicemanager zygote64 app_process64 system_server zygote_socket_wrap; do
  p="$(pidof "$n" 2>/dev/null || true)"
  [ -n "$p" ] && say "$n: $p"
done

say "--- sockets ---"
for s in \
  "$ROOTFS/dev/socket/property_service" \
  "$ROOTFS/dev/socket/zygote" \
  "$ROOTFS/dev/socket/usap_pool_primary"
do
  if [ -S "$s" ]; then
    say "$s: present"
  else
    say "$s: missing"
  fi
done

say "--- logs ---"
for f in \
  "$LOGDIR/property_service_ack_shim.log" \
  "$LOGDIR/servicemanager.log" \
  "$LOGDIR/hwservicemanager.log" \
  "$LOGDIR/vndservicemanager.log" \
  "$LOGDIR/zygote64.start-system-server.log" \
  "$LOGDIR/zygote-system-server-launch.out"
do
  [ -f "$f" ] && say "$f"
done
REMOTE
