USB="${USB:-/media/internal/android-usb}"
ROOTFS="${ROOTFS:-$USB/android-rootfs}"
SIDE="${SIDE:-$USB/android-sidecar}"
LOGDIR="${LOGDIR:-$SIDE/logs}"
WRAP="${WRAP:-$SIDE/bin/zygote_socket_wrap}"

mkdir -p "$LOGDIR" "$SIDE/run"
runtime_state(){ printf 'phase=%s\n' "$1" > "$SIDE/run/runtime.state"; }

echo "--- cleanup old zygotes/wrappers ---"
runtime_state cleanup
killall -9 ptrace_bt_wrap ptrace_fatal_msg_wrap app_process64 zygote64 system_server zygote_socket_wrap 2>/dev/null || true
for name in zygote64 app_process64 system_server app_process zygote_socket_wrap; do
  pids="$(pidof "$name" 2>/dev/null || true)"
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
done
sleep 1
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary" 2>/dev/null || true

echo
echo "--- property service shim ---"
runtime_state property-shim
mkdir -p "$ROOTFS/dev/socket" /dev/socket
killall property_service_ack_shim property_servic 2>/dev/null || true
sleep 1
killall -9 property_service_ack_shim property_servic 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/property_service" /dev/socket/property_service 2>/dev/null || true
nohup "$SIDE/bin/property_service_ack_shim" \
  "$ROOTFS/dev/socket/property_service" \
  "$SIDE/run/property_service.props" \
  "$ROOTFS/dev/__properties__/u:object_r:default_prop:s0" \
  </dev/null >"$LOGDIR/property_service_ack_shim.log" 2>&1 &
echo $! > "$SIDE/run/property_service_ack_shim.pid"
sleep 1
ls -l "$ROOTFS/dev/socket/property_service" || exit 1
chroot "$ROOTFS" /system/bin/setprop webos.test ok 2>/dev/null \
  || exit 1

echo
echo "--- sanity patches ---"
runtime_state patching
TGT="$ROOTFS/system/lib64/libandroid_runtime.so"
echo -n "storage abort call @ 0x1ca198, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1ca198)) -N 4 "$TGT"
echo -n "SetTaskProfiles call @ 0x1ca1b0, should be 20 00 80 52: "
od -An -tx1 -j $((0x1ca1b0)) -N 4 "$TGT"
echo -n "SetTaskProfiles tbz @ 0x1ca208, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1ca208)) -N 4 "$TGT"
echo -n "fd allow branch @ 0x1d3828, should be 15 00 00 14: "
od -An -tx1 -j $((0x1d3828)) -N 4 "$TGT"
echo -n "fd failfn #2 @ 0x1d3a80, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1d3a80)) -N 4 "$TGT"
echo -n "fd failfn #3 @ 0x1d3974, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1d3974)) -N 4 "$TGT"
echo -n "ForkCommon fail @ 0x1c7820, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1c7820)) -N 4 "$TGT"
echo -n "FD ReopenOrDetach fail @ 0x1d4124, should be 1f 20 03 d5: "
od -An -tx1 -j $((0x1d4124)) -N 4 "$TGT"
echo -n "FileDescriptorTable::ReopenOrDetach @ 0x1d4e80, should be c0 03 5f d6: "
od -An -tx1 -j $((0x1d4e80)) -N 4 "$TGT"
echo -n "_install_setuidgid_filter @ 0x1d99fc, should be 20 00 80 52 c0 03 5f d6: "
od -An -tx1 -j $((0x1d99fc)) -N 8 "$TGT"
echo -n "_set_seccomp_filter @ 0x1d9afc, should be 20 00 80 52 c0 03 5f d6: "
od -An -tx1 -j $((0x1d9afc)) -N 8 "$TGT"

echo
echo "--- classpath ---"
runtime_state classpath
ENVFILE="$ROOTFS/data/system/environ/classpath"

if [ ! -s "$ENVFILE" ]; then
  echo "classpath env missing; running derive_classpath" >&2
  mkdir -p "$ROOTFS/data/system/environ"

  if [ -x "$ROOTFS/system/bin/derive_classpath" ]; then
    chroot "$ROOTFS" /system/bin/derive_classpath /data/system/environ/classpath \
      >"$LOGDIR/derive_classpath.launcher.log" 2>&1 || true
  elif [ -x "$ROOTFS/apex/com.android.runtime/bin/derive_classpath" ]; then
    chroot "$ROOTFS" /apex/com.android.runtime/bin/derive_classpath /data/system/environ/classpath \
      >"$LOGDIR/derive_classpath.launcher.log" 2>&1 || true
  fi
fi

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

filter_classpath() {
  IN="$1"
  OUT=""
  OLDIFS="$IFS"
  IFS=:
  for P in $IN; do
    [ -n "$P" ] || continue
    if [ -e "$ROOTFS$P" ]; then
      if [ -n "$OUT" ]; then
        OUT="$OUT:$P"
      else
        OUT="$P"
      fi
    else
      echo "drop missing classpath entry: $P" >&2
    fi
  done
  IFS="$OLDIFS"
  printf '%s' "$OUT"
}

BOOTCLASSPATH="$(filter_classpath "$BOOTCLASSPATH")"
DEX2OATBOOTCLASSPATH="$(filter_classpath "$DEX2OATBOOTCLASSPATH")"
SYSTEMSERVERCLASSPATH="$(filter_classpath "$SYSTEMSERVERCLASSPATH")"

echo "BOOTCLASSPATH length: ${#BOOTCLASSPATH}"
echo "SYSTEMSERVERCLASSPATH length: ${#SYSTEMSERVERCLASSPATH}"

LOG="$LOGDIR/zygote64.start-system-server.log"
: > "$LOG"

echo
echo "--- start zygote + system_server ---"
runtime_state start

LD_PATH="/system/lib64:/system_ext/lib64:/product/lib64"
LD_PATH="$LD_PATH:/apex/com.android.art/lib64"
LD_PATH="$LD_PATH:/apex/com.android.runtime/lib64"
LD_PATH="$LD_PATH:/apex/com.android.runtime/lib64/bionic"
LD_PATH="$LD_PATH:/apex/com.android.i18n/lib64"

for d in "$ROOTFS"/apex/*/lib64; do
  [ -d "$d" ] || continue
  rel="${d#$ROOTFS}"

  # system_server must not see vendor/VNDK libbinder first.
  # Mixing system libbinder and VNDK libbinder causes:
  #   Parcel Expecting header VNDR but found SYST. Mixing copies of libbinder?
  case "$rel" in
    /apex/com.android.vndk.current/lib64|/apex/com.android.vndk.v*/lib64)
      echo "skip VNDK from zygote/system_server LD_PATH: $rel" >&2
      continue
      ;;
  esac

  case ":$LD_PATH:" in
    *":$rel:"*) ;;
    *) LD_PATH="$LD_PATH:$rel" ;;
  esac
done

# Do not add /vendor/lib64 or /odm/lib64 to system_server LD_LIBRARY_PATH.
# Vendor processes/managers get their own linker namespace separately.
# LD_PATH="$LD_PATH:/vendor/lib64:/odm/lib64"

echo "--- LD_PATH ---"
echo "$LD_PATH"

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  LD_PRELOAD=/apex/com.android.art/lib64/libart.so \
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
  >"$LOG" 2>&1 &
echo $! > "$SIDE/run/zygote_socket_wrap.pid"

i=0
while [ "$i" -lt 45 ]; do
  pidof system_server >/dev/null 2>&1 && break
  i=$((i + 1))
  sleep 1
done

pidof zygote64 >/dev/null 2>&1 && pidof zygote64 > "$SIDE/run/zygote64.pid" || true
pidof system_server >/dev/null 2>&1 && pidof system_server > "$SIDE/run/system_server.pid" || true
runtime_state complete

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

if ! pidof zygote64 >/dev/null 2>&1 && ! pidof app_process64 >/dev/null 2>&1; then
  echo "ERROR: zygote64 no quedó vivo"
  exit 1
fi

if ! pidof system_server >/dev/null 2>&1; then
  echo "ERROR: system_server no quedó vivo"
  exit 1
fi

echo
echo "ZYGOTE_SYSTEM_SERVER_OK"
