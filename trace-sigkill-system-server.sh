set -e

echo "--- enable signal/sched tracing on TV ---"
ssh root@$TV_IP 'sh -s' <<'EOS'
set -x

# Montar debugfs/tracing si hace falta
mkdir -p /sys/kernel/debug
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true

TR=/sys/kernel/debug/tracing
if [ ! -d "$TR" ]; then
  TR=/sys/kernel/tracing
fi

echo "TR=$TR"

if [ ! -d "$TR" ]; then
  echo "NO_TRACING_DIR"
  exit 0
fi

echo 0 > "$TR/tracing_on" 2>/dev/null || true
echo > "$TR/trace" 2>/dev/null || true

# Desactivar todo
find "$TR/events" -name enable -exec sh -c 'echo 0 > "$1" 2>/dev/null || true' _ {} \;

# Activar eventos útiles
for e in \
  "$TR/events/signal/signal_generate/enable" \
  "$TR/events/signal/signal_deliver/enable" \
  "$TR/events/sched/sched_process_exit/enable" \
  "$TR/events/sched/sched_process_free/enable"
do
  if [ -e "$e" ]; then
    echo 1 > "$e"
    echo "enabled $e"
  else
    echo "missing $e"
  fi
done

echo 1 > "$TR/tracing_on"
echo "TRACE_SIGKILL_ARMED"
EOS

echo
echo "--- run normal zygote/system_server ---"
ssh root@$TV_IP 'sh -s' < try-zygote-start-system-server-v2.sh || true

sleep 2

echo
echo "--- collect trace ---"
ssh root@$TV_IP 'sh -s' <<'EOS' | tee trace-sigkill-system-server.out
TR=/sys/kernel/debug/tracing
[ -d "$TR" ] || TR=/sys/kernel/tracing

echo "--- tracing dir ---"
echo "$TR"

if [ ! -d "$TR" ]; then
  echo "NO_TRACING_DIR"
  exit 0
fi

echo 0 > "$TR/tracing_on" 2>/dev/null || true

echo
echo "--- interesting trace lines ---"
grep -iE 'system_server|app_process|zygote|signal|sig=9|sig=11|kill|sched_process_exit|sched_process_free' "$TR/trace" | tail -300 || true

echo
echo "--- raw trace tail ---"
tail -300 "$TR/trace" || true

echo
echo "--- current android-ish pids ---"
ps -ef | grep -E 'app_process|zygote|system_server|servicemanager|property_service_ack|tombstone' | grep -v grep || true

echo
echo "TRACE_SIGKILL_SYSTEM_SERVER_DONE"
EOS
