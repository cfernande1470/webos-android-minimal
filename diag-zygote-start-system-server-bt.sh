USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap
PTRACE=$SIDE/bin/ptrace_bt_wrap

mkdir -p "$LOGDIR"

echo "--- hard cleanup old android zygotes/wrappers ---"
killall -9 ptrace_bt_wrap ptrace_fatal_msg_wrap 2>/dev/null || true

for P in $(pidof app_process64 2>/dev/null || true); do
  echo "kill pidof app_process64 PID=$P"
  kill -9 "$P" 2>/dev/null || true
done

for D in /proc/[0-9]*; do
  P="${D#/proc/}"
  CMD="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null || true)"
  case "$CMD" in
    zygote64*|*"/system/bin/app_process64 -Xzygote"*)
      echo "kill zygote-like PID=$P CMD=$CMD"
      kill -9 "$P" 2>/dev/null || true
      ;;
  esac
done

sleep 1
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary" 2>/dev/null || true

echo
echo "--- sanity files ---"
ls -l "$PTRACE" || exit 1
ls -l "$WRAP" || exit 1
ls -l "$ROOTFS/linkerconfig/ld.config.txt" || exit 1

echo
echo "--- sanity patches ---"
TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
echo -n "abort call @ 0x1ca198: "
od -An -tx1 -j $((0x1ca198)) -N 4 "$TGT"
echo -n "task call  @ 0x1ca1b0: "
od -An -tx1 -j $((0x1ca1b0)) -N 4 "$TGT"
echo -n "task tbz   @ 0x1ca208: "
od -An -tx1 -j $((0x1ca208)) -N 4 "$TGT"

echo
echo "--- classpath ---"
ENVFILE="$ROOTFS/data/system/environ/classpath"

BOOTCLASSPATH="$(sed -n \
  -e 's/^[[:space:]]*export[[:space:]]\+BOOTCLASSPATH[[:space:]]\+//p' \
  -e 's/^[[:space:]]*BOOTCLASSPATH=//p' \
  "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"')"

DEX2OATBOOTCLASSPATH="$(sed -n \
  -e 's/^[[:space:]]*export[[:space:]]\+DEX2OATBOOTCLASSPATH[[:space:]]\+//p' \
  -e 's/^[[:space:]]*DEX2OATBOOTCLASSPATH=//p' \
  "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"')"

SYSTEMSERVERCLASSPATH="$(sed -n \
  -e 's/^[[:space:]]*export[[:space:]]\+SYSTEMSERVERCLASSPATH[[:space:]]\+//p' \
  -e 's/^[[:space:]]*SYSTEMSERVERCLASSPATH=//p' \
  "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"')"

[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

echo "BOOTCLASSPATH length: ${#BOOTCLASSPATH}"
echo "SYSTEMSERVERCLASSPATH length: ${#SYSTEMSERVERCLASSPATH}"

LOG="$LOGDIR/zygote64.start-system-server.bt.log"
: > "$LOG"

echo
echo "--- ptrace start-system-server zygote ---"
env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  BOOTCLASSPATH="$BOOTCLASSPATH" \
  DEX2OATBOOTCLASSPATH="$DEX2OATBOOTCLASSPATH" \
  SYSTEMSERVERCLASSPATH="$SYSTEMSERVERCLASSPATH" \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  ANDROID_I18N_ROOT=/apex/com.android.i18n \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  "$PTRACE" \
  "$WRAP" \
    "$ROOTFS" \
    "$ROOTFS/dev/socket/zygote" \
    "$ROOTFS/dev/socket/usap_pool_primary" \
    /system/bin/app_process64 \
      -Xzygote \
      /system/bin --zygote \
      --socket-name=zygote \
      --abi-list=arm64-v8a \
      start-system-server \
  >"$LOG" 2>&1

echo
echo "--- important ---"
grep -nE 'CRASH|pc=|owners|frame chain|file_off=|Fatal|Exception|signal|system_server|zygote|Runtime|abort' "$LOG" | head -160 || true

echo
echo "--- tail ---"
tail -n 180 "$LOG"

echo
echo "--- remaining android-ish ---"
for D in /proc/[0-9]*; do
  P="${D#/proc/}"
  COMM="$(cat "$D/comm" 2>/dev/null || true)"
  CMD="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null || true)"
  case "$COMM $CMD" in
    *app_process*|*zygote*|*system_server*)
      echo "PID=$P COMM=$COMM CMD=$CMD"
      ;;
  esac
done
