USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
WRAP=$USB/android-sidecar/zygote_socket_wrap
ENVFILE=$ROOTFS/data/system/environ/classpath
EGLDIR=$ROOTFS/vendor/lib64/egl

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

echo "--- comprobar overlay mesa ---"
ls -l "$EGLDIR" | grep -E "libEGL|libGLES" || true

echo
echo "--- propiedades relevantes ---"
chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.zygote.disable_gl_preload 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.vendor.api_level 2>/dev/null || true

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

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

echo
echo "--- existe strace ---"
command -v strace || true

echo
echo "--- start zygote mesa diagnostic ---"

RUNNER=""
if command -v strace >/dev/null 2>&1; then
  RUNNER="strace -ff -tt -s 256 -o $LOGDIR/zygote64.mesa.strace"
else
  echo "WARN: no hay strace en host; sigo sin strace"
fi

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  LD_DEBUG=1 \
  EGL_LOG_LEVEL=debug \
  MESA_DEBUG=1 \
  LIBGL_DEBUG=verbose \
  LIBGL_ALWAYS_SOFTWARE=true \
  MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
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
  $RUNNER \
  "$WRAP" \
    "$ROOTFS" \
    "$ROOTFS/dev/socket/zygote" \
    "$ROOTFS/dev/socket/usap_pool_primary" \
    /system/bin/app_process64 \
      -Xzygote \
      /system/bin --zygote \
      --socket-name=zygote \
      --abi-list=arm64-v8a \
  >"$LOGDIR/zygote64.mesa.diagnostic.log" 2>&1 &

sleep 8

echo
echo "--- pid ---"
pidof app_process64 || true

echo
echo "--- zygote log ---"
tail -n 250 "$LOGDIR/zygote64.mesa.diagnostic.log"

echo
echo "--- strace files ---"
ls -lt "$LOGDIR"/zygote64.mesa.strace* 2>/dev/null | head || true

echo
echo "--- strace abort/context ---"
for f in $(ls -t "$LOGDIR"/zygote64.mesa.strace* 2>/dev/null | head -5); do
  echo "### $f"
  grep -E "SIGABRT|tgkill|abort|libEGL|libGLES|mesa|dri|llvmpipe|swrast|ion|dri/render|kgsl|mali|openat|access|ENOENT|EACCES|EPERM" "$f" | tail -120
done

echo
echo "--- linker / deps mesa ---"
for so in \
  /vendor/lib64/egl/libEGL_mesa.so \
  /vendor/lib64/egl/libGLESv2_mesa.so \
  /vendor/lib64/egl/libGLESv1_CM_mesa.so
do
  echo "### $so"
  chroot "$ROOTFS" /system/bin/linker64 --list "$so" 2>&1 || true
done

echo
echo "--- buscar dri/mesa extras ---"
find "$ROOTFS/vendor/lib64" "$ROOTFS/system/lib64" -maxdepth 3 \
  \( -name "*dri*" -o -name "*swrast*" -o -name "*llvmpipe*" -o -name "*gallium*" -o -name "*drm*" -o -name "*gbm*" \) \
  -print 2>/dev/null | sort

echo
echo "--- final pid ---"
pidof app_process64 || true
