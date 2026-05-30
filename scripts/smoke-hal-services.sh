#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
PROBEDIR="${PROBEDIR:-$SIDE/probes}"
LOGDIR="${LOGDIR:-$SIDE/logs}"

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' PROBEDIR='$PROBEDIR' LOGDIR='$LOGDIR' sh -s" <<'REMOTE'
set -eu

say(){ printf '%s\n' "$*"; }
mkdir -p "$PROBEDIR"

service_env() {
  cat <<'EOF'
PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
ANDROID_ROOT=/system
ANDROID_DATA=/data
ANDROID_STORAGE=/storage
ANDROID_RUNTIME_ROOT=/apex/com.android.runtime
ANDROID_ART_ROOT=/apex/com.android.art
ANDROID_I18N_ROOT=/apex/com.android.i18n
ANDROID_TZDATA_ROOT=/apex/com.android.tzdata
LD_LIBRARY_PATH=/vendor/lib64:/odm/lib64:/system/lib64:/system_ext/lib64:/product/lib64:/apex/com.android.runtime/lib64:/apex/com.android.runtime/lib64/bionic:/apex/com.android.art/lib64:/apex/com.android.i18n/lib64
EOF
}

wait_pid() {
  pid="$1"
  deadline="$2"
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      return 124
    fi
    sleep 1
  done
  wait "$pid"
}

probe_one() {
  label="$1"
  bin="$2"
  log="$PROBEDIR/$label.log"
  say "== $label =="

  if [ ! -x "$ROOTFS$bin" ]; then
    say "$label: missing $bin"
    return 0
  fi

  if pidof "$(basename "$bin")" >/dev/null 2>&1; then
    say "$label: already running"
    return 0
  fi

  : > "$log"
  nohup env -i $(service_env) chroot "$ROOTFS" "$bin" >"$log" 2>&1 &
  pid=$!
  deadline=$(( $(date +%s) + 20 ))

  if wait_pid "$pid" "$deadline"; then
    say "$label: exited cleanly"
    tail -n 30 "$log" 2>/dev/null || true
    return 0
  fi

  rc=$?
  if [ "$rc" -eq 124 ]; then
    say "$label: alive after timeout"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
    fi
    tail -n 30 "$log" 2>/dev/null || true
    return 0
  fi

  say "$label: failed"
  tail -n 30 "$log" 2>/dev/null || true
}

say "runtime.state: $(cat "$SIDE/run/runtime.state" 2>/dev/null || echo missing)"
probe_one memtrack "/vendor/bin/hw/android.hardware.memtrack@1.0-service"
probe_one power "/vendor/bin/hw/android.hardware.power@1.0-service.waydroid"
probe_one graphics_allocator_2_0 "/vendor/bin/hw/android.hardware.graphics.allocator@2.0-service"
probe_one graphics_allocator_4_0 "/vendor/bin/hw/android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa"
probe_one sensors "/vendor/bin/hw/android.hardware.sensors@1.0-service.waydroid"
probe_one light "/vendor/bin/hw/android.hardware.light@2.0-service.waydroid"
REMOTE
