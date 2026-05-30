USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/zygote_socket_wrap

mkdir -p "$LOGDIR"

echo "--- cleanup old zygotes/wrappers ---"
killall -9 ptrace_bt_wrap ptrace_fatal_msg_wrap app_process64 2>/dev/null || true
sleep 1
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary" 2>/dev/null || true

echo
echo "--- sanity patches ---"
TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
echo -n "storage abort call @ 0x1ca198, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1ca198)) -N 4 "$TGT"
echo -n "SetTaskProfiles call @ 0x1ca1b0, should be 20 00 80 52: "
od -An -tx1 -j $((0x1ca1b0)) -N 4 "$TGT"
echo -n "SetTaskProfiles tbz @ 0x1ca208, should be 1f 20 03 d5: "
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

if [ -z "$BOOTCLASSPATH" ]; then
  BOOTCLASSPATH="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/system/framework/framework.jar:/system/framework/ext.jar:/system/framework/framework-graphics.jar"
fi

[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

echo "BOOTCLASSPATH length: ${#BOOTCLASSPATH}"
echo "SYSTEMSERVERCLASSPATH length: ${#SYSTEMSERVERCLASSPATH}"

LOG="$LOGDIR/zygote64.start-system-server.log"
: > "$LOG"

echo
echo "--- start zygote + system_server ---"

LD_PATH="/system/lib64:/system_ext/lib64:/product/lib64"
LD_PATH="$LD_PATH:/apex/com.android.art/lib64"
LD_PATH="$LD_PATH:/apex/com.android.runtime/lib64"
LD_PATH="$LD_PATH:/apex/com.android.runtime/lib64/bionic"
LD_PATH="$LD_PATH:/apex/com.android.i18n/lib64"

for d in "$ROOTFS"/apex/*/lib64; do
  [ -d "$d" ] || continue
  rel="${d#$ROOTFS}"
  case ":$LD_PATH:" in
    *":$rel:"*) ;;
    *) LD_PATH="$LD_PATH:$rel" ;;
  esac
done

LD_PATH="$LD_PATH:/vendor/lib64:/odm/lib64"

echo "--- LD_PATH ---"
echo "$LD_PATH"

nohup env -i \
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
  LD_LIBRARY_PATH="$LD_PATH" \
  "$WRAP" \
    "$ROOTFS" \
    "$ROOTFS/dev/socket/zygote" \
    "$ROOTFS/dev/socket/usap_pool_primary" \
    /system/bin/app_process64 \
      -verbose:class \
      -Xzygote \
      /system/bin --zygote \
      --socket-name=zygote \
      --abi-list=arm64-v8a \
      start-system-server \
  >"$LOG" 2>&1 &

sleep 8

echo
echo "--- pids ---"
pidof app_process64 || true

echo
echo "--- android-ish scan ---"
for D in /proc/[0-9]*; do
  PID="${D#/proc/}"
  COMM="$(cat "$D/comm" 2>/dev/null || true)"
  CMD="$(tr '\0' ' ' < "$D/cmdline" 2>/dev/null || true)"
  case "$COMM $CMD" in
    *app_process*|*zygote*|*system_server*)
      echo "PID=$PID COMM=$COMM CMD=$CMD"
      sed -n '1,8p' "$D/status" 2>/dev/null | sed 's/^/  /'
      ;;
  esac
done

echo
echo "--- sockets ---"
ls -l "$ROOTFS/dev/socket" | grep -E 'zygote|usap' || true

echo
echo "--- log tail ---"
tail -n 250 "$LOG"
