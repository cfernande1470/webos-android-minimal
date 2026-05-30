ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
ZLOG=$LOGDIR/zygote64.start-system-server.log
mkdir -p "$LOGDIR"

TR=""
for p in /sys/kernel/debug/tracing /sys/kernel/tracing; do
  [ -d "$p" ] && TR="$p" && break
done

if [ -z "$TR" ]; then
  mkdir -p /sys/kernel/debug
  mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
  [ -d /sys/kernel/debug/tracing ] && TR=/sys/kernel/debug/tracing
fi

[ -n "$TR" ] || {
  echo "ERROR: tracing fs not found"
  exit 1
}

echo "TR=$TR"

echo "--- stop old android bits ---"
killall -9 app_process64 zygote_socket_wrap 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f zygote_socket_wrap 2>/dev/null || true
sleep 1

echo "--- reset trace ---"
echo 0 > "$TR/tracing_on" 2>/dev/null || true
echo nop > "$TR/current_tracer" 2>/dev/null || true
echo 16384 > "$TR/buffer_size_kb" 2>/dev/null || true
echo > "$TR/trace" 2>/dev/null || true

# Quita filtros viejos.
for f in \
  "$TR/events/signal/signal_generate/filter" \
  "$TR/events/signal/signal_deliver/filter" \
  "$TR/events/sched/sched_process_exit/filter"
do
  [ -e "$f" ] && echo 0 > "$f" 2>/dev/null || true
done

# Activa solo eventos útiles.
for e in "$TR/events"/*/*/enable; do
  echo 0 > "$e" 2>/dev/null || true
done

for e in \
  "$TR/events/signal/signal_generate/enable" \
  "$TR/events/signal/signal_deliver/enable" \
  "$TR/events/sched/sched_process_exit/enable" \
  "$TR/events/sched/sched_process_free/enable" \
  "$TR/events/oom/oom_kill/enable"
do
  [ -e "$e" ] && echo 1 > "$e" 2>/dev/null || true
done

echo "--- trace event formats ---"
cat "$TR/events/signal/signal_generate/format" 2>/dev/null | sed -n '1,100p' || true
cat "$TR/events/sched/sched_process_exit/format" 2>/dev/null | sed -n '1,80p' || true

echo "--- clear old zygote log ---"
: > "$ZLOG" 2>/dev/null || true
dmesg -c >/tmp/dmesg.before-sigkill-clean 2>/dev/null || true

echo "--- start tracing ---"
echo 1 > "$TR/tracing_on"

echo "--- run zygote script in background ---"
/tmp/try-zygote-start-system-server-v2.sh >"$LOGDIR/trace-clean-try.out" 2>"$LOGDIR/trace-clean-try.err" &
RUNPID=$!
echo "runpid=$RUNPID"

TARGET=""
for i in $(seq 1 80); do
  if grep -q 'exited due to signal 9' "$ZLOG" 2>/dev/null; then
    TARGET="$(grep -oE 'Process [0-9]+ exited due to signal 9' "$ZLOG" | tail -1 | awk '{print $2}')"
    echo "detected_killed_pid=$TARGET"
    break
  fi

  # También intenta capturar un system_server vivo antes de morir.
  LIVE="$(pidof system_server 2>/dev/null || true)"
  [ -n "$LIVE" ] && echo "live_system_server_pid=$LIVE"

  sleep 0.1
done

sleep 0.3
echo 0 > "$TR/tracing_on"

echo "--- killed pid ---"
echo "TARGET=$TARGET"

echo "--- zygote log ---"
cat "$ZLOG" 2>/dev/null || true

echo
echo "--- try stdout tail ---"
tail -120 "$LOGDIR/trace-clean-try.out" 2>/dev/null || true

echo
echo "--- try stderr tail ---"
tail -120 "$LOGDIR/trace-clean-try.err" 2>/dev/null || true

echo
echo "--- full trace matches target/sig/system_server ---"
if [ -n "$TARGET" ]; then
  grep -nE "pid=$TARGET|target_pid=$TARGET| $TARGET |-$TARGET |system_server|signal_generate|signal_deliver|sig=9|oom_kill|sched_process_exit" "$TR/trace" 2>/dev/null | head -1000 || true
else
  grep -nE "system_server|signal_generate|signal_deliver|sig=9|oom_kill|sched_process_exit" "$TR/trace" 2>/dev/null | head -1000 || true
fi

echo
echo "--- trace around signal_generate ---"
grep -n 'signal_generate' "$TR/trace" 2>/dev/null | head -200 || true

echo
echo "--- trace around sched_process_exit ---"
grep -nE 'sched_process_exit.*(system_server|app_process|zygote)|sched_process_exit' "$TR/trace" 2>/dev/null | head -400 || true

echo
echo "--- dmesg focused ---"
dmesg | grep -iE 'WEBOS accept|40046210|returned -22|binder_mmap|binder|system_server|zygote|killed|oom|fault|segv|fatal|avc|denied|property' | tail -260 || true

echo
echo "TRACE_SYSTEMSERVER_SIGKILL_CLEAN_DONE"
