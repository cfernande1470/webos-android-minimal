ROOTFS=/media/internal/android-usb/android-rootfs
SIDE=/media/internal/android-usb/android-sidecar
LOGDIR=$SIDE/logs
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

echo "--- stop old zygote/system_server ---"
killall -9 app_process64 zygote_socket_wrap 2>/dev/null || true
pkill -9 -f app_process64 2>/dev/null || true
pkill -9 -f zygote_socket_wrap 2>/dev/null || true
sleep 1

echo "--- trace formats ---"
cat "$TR/events/signal/signal_generate/format" 2>/dev/null | sed -n '1,120p' || true
cat "$TR/events/sched/sched_process_exit/format" 2>/dev/null | sed -n '1,80p' || true

echo "--- reset tracing ---"
echo 0 > "$TR/tracing_on" 2>/dev/null || true
echo nop > "$TR/current_tracer" 2>/dev/null || true
echo > "$TR/trace" 2>/dev/null || true

for e in \
  "$TR/events/signal/signal_generate/enable" \
  "$TR/events/signal/signal_deliver/enable" \
  "$TR/events/sched/sched_process_exit/enable" \
  "$TR/events/oom/oom_kill/enable"
do
  [ -e "$e" ] && echo 1 > "$e" 2>/dev/null || true
done

# Filtrar solo SIGKILL si el kernel acepta el filtro.
if [ -e "$TR/events/signal/signal_generate/filter" ]; then
  echo 'sig == 9' > "$TR/events/signal/signal_generate/filter" 2>/dev/null || true
fi
if [ -e "$TR/events/signal/signal_deliver/filter" ]; then
  echo 'sig == 9' > "$TR/events/signal/signal_deliver/filter" 2>/dev/null || true
fi

echo "--- start tracing ---"
echo 1 > "$TR/tracing_on"

dmesg -c >/tmp/dmesg.before-sigkill-trace 2>/dev/null || true

echo "--- run zygote/system_server ---"
sh /tmp/try-zygote-start-system-server-v2.sh 2>/dev/null || true

sleep 4

echo 0 > "$TR/tracing_on"

echo "--- zygote log ---"
tail -160 "$LOGDIR/zygote64.start-system-server.log" 2>/dev/null || true

echo
echo "--- trace SIGKILL/system_server focused ---"
cat "$TR/trace" 2>/dev/null | grep -iE 'sig=9|signal_generate|signal_deliver|system_server|app_process|zygote|exit|oom|kill' | tail -300 || true

echo
echo "--- raw trace tail ---"
tail -300 "$TR/trace" 2>/dev/null || true

echo
echo "--- dmesg focused ---"
dmesg | grep -iE 'WEBOS accept|40046210|returned -22|binder_mmap|binder|system_server|zygote|killed|oom|fault|segv|fatal|avc|denied|property' | tail -240 || true

echo
echo "TRACE_SYSTEMSERVER_SIGKILL_DONE"
