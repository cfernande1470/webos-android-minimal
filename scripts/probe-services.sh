#!/usr/bin/env bash
set -Eeuo pipefail

TV_IP="${TV_IP:-192.168.2.121}"
TV_USER="${TV_USER:-root}"

USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
LOGDIR="${LOGDIR:-$SIDE/logs}"
OUTDIR="${OUTDIR:-$SIDE/probes}"

ssh "$TV_USER@$TV_IP" \
  "USB='$USB' ROOTFS='$ROOTFS' SIDE='$SIDE' LOGDIR='$LOGDIR' OUTDIR='$OUTDIR' sh -s" <<'REMOTE'
set -eu

say(){ printf '%s\n' "$*"; }
mkdir -p "$OUTDIR"

probe() {
  name="$1"
  shift
  out="$OUTDIR/$name.log"
  if [ "$#" -eq 0 ]; then
    return 0
  fi

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
      tail -n 20 "$out" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done

  if wait "$pid"; then
    say "$name: ok"
  else
    say "$name: fail"
    tail -n 40 "$out" 2>/dev/null || true
  fi
}

say "runtime.state: $(cat "$SIDE/run/runtime.state" 2>/dev/null || echo missing)"
say "--- available probes ---"

if [ -x "$ROOTFS/system/bin/service" ]; then
  probe service-list chroot "$ROOTFS" /system/bin/service list
else
  say "service-list: missing"
fi

if [ -x "$ROOTFS/system/bin/lshal" ]; then
  probe lshal-system chroot "$ROOTFS" /system/bin/lshal
elif [ -x "$ROOTFS/apex/com.android.vndk.current/bin/lshal" ]; then
  probe lshal-vndk chroot "$ROOTFS" /apex/com.android.vndk.current/bin/lshal
elif [ -x "$ROOTFS/apex/com.android.hardware.biometrics.face/bin/lshal" ]; then
  probe lshal-apex chroot "$ROOTFS" /apex/com.android.hardware.biometrics.face/bin/lshal
else
  say "lshal: missing"
fi

if [ -x "$ROOTFS/system/bin/cmd" ]; then
  probe cmd-list chroot "$ROOTFS" /system/bin/cmd -l
else
  say "cmd: missing"
fi

say "--- key substrings ---"
for name in memtrack power graphics input; do
  if grep -RIn "$name" "$OUTDIR" >/dev/null 2>&1; then
    say "$name: present in probe output"
    grep -RIn "$name" "$OUTDIR" | head -n 20 || true
  else
    say "$name: absent"
  fi
done
REMOTE
