USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
LOGDIR=$SIDE/logs
WRAP=$SIDE/bin/zygote_socket_wrap
PTRACE=$SIDE/bin/ptrace_fatal_msg_wrap
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"
killall -9 app_process64 zygote64 system_server zygote_socket_wrap ptrace_fatal_msg_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

read_env_var() {
  VAR="$1"
  sed -n \
    -e "s/^[[:space:]]*export[[:space:]]\+$VAR[[:space:]]\+//p" \
    -e "s/^[[:space:]]*$VAR=//p" \
    "$ENVFILE" 2>/dev/null | tail -1 | tr -d '"'
}

BOOTCLASSPATH="$(read_env_var BOOTCLASSPATH)"
DEX2OATBOOTCLASSPATH="$(read_env_var DEX2OATBOOTCLASSPATH)"
SYSTEMSERVERCLASSPATH="$(read_env_var SYSTEMSERVERCLASSPATH)"
[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

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

env -i \
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
  >"$LOGDIR/current-zygote-fatal.log" 2>&1

grep -n -E 'CRASH|Fatal signal|Zygote:|Runtime|failed|Failed|No such|Permission|END CRASH|pc=|frame chain|libandroid_runtime|libart' "$LOGDIR/current-zygote-fatal.log" | head -260 || true
tail -n 160 "$LOGDIR/current-zygote-fatal.log"
