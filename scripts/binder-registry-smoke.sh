#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
PROBEDIR="${PROBEDIR:-$SIDE/probes/binder-registry}"

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' PROBEDIR='$PROBEDIR' sh -s" <<'REMOTE'
set -eu

say(){ printf '%s\n' "$*"; }
mkdir -p "$PROBEDIR"

probe() {
  name="$1"
  shift
  out="$PROBEDIR/$name.log"
  : > "$out"

  (
    "$@"
  ) >"$out" 2>&1 &
  pid=$!
  deadline=$(( $(date +%s) + 20 ))

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      say "$name: timeout"
      tail -n 40 "$out" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done

  if wait "$pid"; then
    say "$name: ok"
  else
    say "$name: fail"
    tail -n 60 "$out" 2>/dev/null || true
  fi
}

say "runtime.state: $(cat "$SIDE/run/runtime.state" 2>/dev/null || echo missing)"

if [ -x "$ROOTFS/system/bin/service" ]; then
  probe service-list chroot "$ROOTFS" /system/bin/service list
  probe service-check-manager chroot "$ROOTFS" /system/bin/service check manager
  probe service-check-activity_task chroot "$ROOTFS" /system/bin/service check activity_task
  probe service-check-appops chroot "$ROOTFS" /system/bin/service check appops
  probe service-check-uri_grants chroot "$ROOTFS" /system/bin/service check uri_grants
  probe service-call-get-activity_task chroot "$ROOTFS" /system/bin/service call manager 1 s16 activity_task
else
  say "service: missing"
fi

if [ -x "$ROOTFS/vendor/bin/vndservice" ]; then
  probe vndservice-list chroot "$ROOTFS" /vendor/bin/vndservice list
else
  say "vndservice: missing"
fi

if [ -x "$ROOTFS/system/bin/lshal" ]; then
  probe lshal-system chroot "$ROOTFS" /system/bin/lshal
elif [ -x "$ROOTFS/apex/com.android.vndk.current/bin/lshal" ]; then
  probe lshal-vndk chroot "$ROOTFS" /apex/com.android.vndk.current/bin/lshal
else
  say "lshal: missing"
fi

say "--- probe logs ---"
find "$PROBEDIR" -maxdepth 1 -type f | sort
REMOTE
