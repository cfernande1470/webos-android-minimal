#!/bin/sh
set -eu

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
LOGDIR="${LOGDIR:-$SIDE/logs}"

run_body() {
  say(){ printf '%s\n' "$*"; }

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

  wait_service_state() {
    name="$1"
    launcher_pid="$2"
    deadline="$3"
    while [ "$(date +%s)" -lt "$deadline" ]; do
      service_pid="$(pidof "$name" 2>/dev/null || true)"
      if [ -n "$service_pid" ]; then
        printf 'pid:%s\n' "$service_pid"
        return 0
      fi
      if ! kill -0 "$launcher_pid" 2>/dev/null; then
        rc=0
        wait "$launcher_pid" 2>/dev/null || rc=$?
        printf 'exit:%s\n' "$rc"
        return 0
      fi
      sleep 1
    done
    service_pid="$(pidof "$name" 2>/dev/null || true)"
    if [ -n "$service_pid" ]; then
      printf 'pid:%s\n' "$service_pid"
      return 0
    fi
    printf 'timeout\n'
    return 124
  }

  start_one() {
    label="$1"
    bin="$2"
    log="$LOGDIR/$label.log"
    pidfile="$SIDE/run/$label.pid"

    if [ ! -x "$ROOTFS$bin" ]; then
      say "$label: missing $bin"
      return 0
    fi

    pid="$(pidof "$(basename "$bin")" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      say "$label: already running ($pid)"
      printf '%s\n' "$pid" > "$pidfile"
      return 0
    fi

    : > "$log"
    nohup env -i $(service_env) chroot "$ROOTFS" "$bin" >"$log" 2>&1 &
    launcher_pid=$!
    deadline=$(( $(date +%s) + 20 ))
    if service_state="$(wait_service_state "$(basename "$bin")" "$launcher_pid" "$deadline")"; then
      case "$service_state" in
        pid:*)
          service_pid="${service_state#pid:}"
          printf '%s\n' "$service_pid" > "$pidfile"
          say "$label: alive ($service_pid)"
          return 0
          ;;
        exit:0)
          say "$label: exited cleanly"
          return 0
          ;;
        exit:*)
          say "$label: failed"
          tail -n 60 "$log" 2>/dev/null || true
          return 1
          ;;
      esac
    fi

    say "$label: still launching"
    tail -n 60 "$log" 2>/dev/null || true
    return 0
  }

  say "runtime.state: $(cat "$SIDE/run/runtime.state" 2>/dev/null || echo missing)"
  start_one memtrack "/vendor/bin/hw/android.hardware.memtrack@1.0-service"
  start_one power "/vendor/bin/hw/android.hardware.power@1.0-service.waydroid"
  start_one graphics_allocator_2_0 "/vendor/bin/hw/android.hardware.graphics.allocator@2.0-service"
  start_one graphics_allocator_4_0 "/vendor/bin/hw/android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa"
  start_one light "/vendor/bin/hw/android.hardware.light@2.0-service.waydroid"
}

if [ "${LOCAL_RUN:-0}" = 1 ]; then
  run_body
  exit 0
fi

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' LOGDIR='$LOGDIR' sh -s" <<'REMOTE'
set -eu

say(){ printf '%s\n' "$*"; }

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

wait_service_pid() {
  name="$1"
  launcher_pid="$2"
  deadline="$3"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    service_pid="$(pidof "$name" 2>/dev/null || true)"
    if [ -n "$service_pid" ]; then
      printf '%s\n' "$service_pid"
      return 0
    fi
    if ! kill -0 "$launcher_pid" 2>/dev/null; then
      wait "$launcher_pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
  done
  service_pid="$(pidof "$name" 2>/dev/null || true)"
  if [ -n "$service_pid" ]; then
    printf '%s\n' "$service_pid"
    return 0
  fi
  return 124
}

start_one() {
  label="$1"
  bin="$2"
  log="$LOGDIR/$label.log"
  pidfile="$SIDE/run/$label.pid"

  if [ ! -x "$ROOTFS$bin" ]; then
    say "$label: missing $bin"
    return 0
  fi

  pid="$(pidof "$(basename "$bin")" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    say "$label: already running ($pid)"
    printf '%s\n' "$pid" > "$pidfile"
    return 0
  fi

  : > "$log"
  nohup env -i $(service_env) chroot "$ROOTFS" "$bin" >"$log" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$pidfile"
  deadline=$(( $(date +%s) + 20 ))
  if service_state="$(wait_service_state "$(basename "$bin")" "$pid" "$deadline")"; then
    case "$service_state" in
      pid:*)
        service_pid="${service_state#pid:}"
        printf '%s\n' "$service_pid" > "$pidfile"
        say "$label: alive ($service_pid)"
        return 0
        ;;
      exit:0)
        say "$label: exited cleanly"
        return 0
        ;;
      exit:*)
        say "$label: failed"
        tail -n 60 "$log" 2>/dev/null || true
        return 1
        ;;
    esac
  fi

  say "$label: still launching"
  tail -n 60 "$log" 2>/dev/null || true
  return 0
}

say "runtime.state: $(cat "$SIDE/run/runtime.state" 2>/dev/null || echo missing)"
start_one memtrack "/vendor/bin/hw/android.hardware.memtrack@1.0-service"
start_one power "/vendor/bin/hw/android.hardware.power@1.0-service.waydroid"
start_one graphics_allocator_2_0 "/vendor/bin/hw/android.hardware.graphics.allocator@2.0-service"
start_one graphics_allocator_4_0 "/vendor/bin/hw/android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa"
start_one light "/vendor/bin/hw/android.hardware.light@2.0-service.waydroid"
REMOTE
