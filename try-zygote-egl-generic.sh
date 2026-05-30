USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
WRAP=$USB/android-sidecar/zygote_socket_wrap
PROBE=$USB/android-sidecar/zygote_probe
ENVFILE=$ROOTFS/data/system/environ/classpath

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket" "$ROOTFS/vendor/lib64/egl"

killall -9 app_process64 2>/dev/null || true
killall -9 zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

echo "--- EGL drivers disponibles ---"
find "$ROOTFS/vendor/lib64/egl" "$ROOTFS/system/lib64/egl" \
  -maxdepth 1 -type f -name "*.so" 2>/dev/null | sort || true

EGLDIR="$ROOTFS/vendor/lib64/egl"

link_chroot_abs() {
  SRC="$1"
  DST="$2"
  CHROOT_SRC="${SRC#$ROOTFS}"
  if [ ! -e "$EGLDIR/$DST" ]; then
    ln -sf "$CHROOT_SRC" "$EGLDIR/$DST"
    echo "LINK $DST -> $CHROOT_SRC"
  else
    echo "KEEP $DST"
  fi
}

echo
echo "--- preparar driver EGL generico si falta ---"

# 1) Preferir driver combinado libGLES_*.so
COMBINED=""
for pref in swiftshader angle mesa minigbm emulation android; do
  for dir in "$ROOTFS/vendor/lib64/egl" "$ROOTFS/system/lib64/egl"; do
    f="$dir/libGLES_$pref.so"
    [ -e "$f" ] && COMBINED="$f" && break
  done
  [ -n "$COMBINED" ] && break
done

if [ -z "$COMBINED" ]; then
  for f in "$ROOTFS/vendor/lib64/egl"/libGLES_*.so "$ROOTFS/system/lib64/egl"/libGLES_*.so; do
    [ -e "$f" ] && COMBINED="$f" && break
  done
fi

if [ -n "$COMBINED" ]; then
  link_chroot_abs "$COMBINED" libGLES.so
else
  echo "No hay libGLES_*.so combinado; pruebo driver split"

  SPLIT_SUFFIX=""
  for dir in "$ROOTFS/vendor/lib64/egl" "$ROOTFS/system/lib64/egl"; do
    for e in "$dir"/libEGL_*.so; do
      [ -e "$e" ] || continue
      b="$(basename "$e")"
      s="${b#libEGL_}"
      s="${s%.so}"
      [ -e "$dir/libGLESv1_CM_$s.so" ] && [ -e "$dir/libGLESv2_$s.so" ] && {
        SPLIT_SUFFIX="$s"
        SPLIT_DIR="$dir"
        break
      }
    done
    [ -n "$SPLIT_SUFFIX" ] && break
  done

  if [ -n "$SPLIT_SUFFIX" ]; then
    link_chroot_abs "$SPLIT_DIR/libEGL_$SPLIT_SUFFIX.so" libEGL.so
    link_chroot_abs "$SPLIT_DIR/libGLESv1_CM_$SPLIT_SUFFIX.so" libGLESv1_CM.so
    link_chroot_abs "$SPLIT_DIR/libGLESv2_$SPLIT_SUFFIX.so" libGLESv2.so
  else
    echo "WARN: no he encontrado driver EGL/GLES utilizable"
  fi
fi

echo
echo "--- EGL generico final ---"
ls -l "$ROOTFS/vendor/lib64/egl" | grep -E "libGLES|libEGL" || true

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

if [ -z "$BOOTCLASSPATH" ]; then
  echo "WARN: sin BOOTCLASSPATH de derive_classpath; fallback manual"
  BOOTCLASSPATH="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/system/framework/framework.jar:/system/framework/ext.jar:/system/framework/framework-graphics.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar"
fi

[ -z "$DEX2OATBOOTCLASSPATH" ] && DEX2OATBOOTCLASSPATH="$BOOTCLASSPATH"

echo
echo "--- propiedades vistas desde Android ---"
chroot "$ROOTFS" /system/bin/getprop ro.hardware.egl 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.board.platform 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.zygote.disable_gl_preload 2>/dev/null || true
chroot "$ROOTFS" /system/bin/getprop ro.vendor.api_level 2>/dev/null || true

cat > "$LOGDIR/zygote64.egl-generic.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BOOTCLASSPATH
DEX2OATBOOTCLASSPATH=$DEX2OATBOOTCLASSPATH
SYSTEMSERVERCLASSPATH=$SYSTEMSERVERCLASSPATH
ENV

echo
echo "--- start zygote con EGL generico ---"

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.sdkext/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
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
  >"$LOGDIR/zygote64.egl-generic.log" 2>&1 &

sleep 8

PID="$(pidof app_process64 || true)"

echo
echo "--- pid ---"
echo "$PID"

echo
echo "--- status ---"
if [ -n "$PID" ]; then
  grep -E "Name|State|Pid|PPid|Threads" /proc/$PID/status
fi

echo
echo "--- sockets ---"
ls -l "$ROOTFS/dev/socket/" | grep -E "zygote|usap" || true

echo
echo "--- log ---"
tail -n 300 "$LOGDIR/zygote64.egl-generic.log"

if [ -n "$PID" ] && [ -x "$PROBE" ]; then
  echo
  echo "--- query abi list ---"
  "$PROBE" "$ROOTFS/dev/socket/zygote" || true

  echo
  echo "--- log after probe ---"
  tail -n 300 "$LOGDIR/zygote64.egl-generic.log"
fi

echo
echo "--- tombstones ---"
ls -lt "$ROOTFS/data/tombstones" 2>/dev/null | head || true
LATEST="$(ls -t "$ROOTFS/data/tombstones"/tombstone_* 2>/dev/null | head -1)"
[ -n "$LATEST" ] && {
  echo "--- latest tombstone: $LATEST ---"
  grep -E "Abort message|signal|backtrace|pid:|name:|libEGL|app_process|zygote" "$LATEST" | head -120 || true
}

echo
echo "--- dmesg tail ---"
dmesg | tail -n 80 || true

echo
echo "--- final pid ---"
pidof app_process64 || true
