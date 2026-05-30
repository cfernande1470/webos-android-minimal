USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
LC=$ROOTFS/linkerconfig/ld.config.txt

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket" "$ROOTFS/linkerconfig"

echo "--- backup linkerconfig ---"
cp -a "$LC" "$LC.bak.art.$(date +%s)" 2>/dev/null || true

if ! grep -q '^\[art\]' "$LC" 2>/dev/null; then
  cat >> "$LC" <<'LC_EOF'

[art]
additional.namespaces = system,com_android_art,com_android_i18n,com_android_runtime,com_android_conscrypt,com_android_media,com_android_vndk_current

namespace.default.isolated = false
namespace.default.visible = true
namespace.default.search.paths = /apex/com.android.art/${LIB}:/apex/com.android.i18n/${LIB}:/apex/com.android.runtime/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}:/system_ext/${LIB}:/product/${LIB}:/vendor/${LIB}:/apex/com.android.conscrypt/${LIB}:/apex/com.android.media/${LIB}:/apex/com.android.vndk.current/${LIB}
namespace.default.links = system,com_android_art,com_android_i18n,com_android_runtime,com_android_conscrypt,com_android_media,com_android_vndk_current
namespace.default.link.system.allow_all_shared_libs = true
namespace.default.link.com_android_art.allow_all_shared_libs = true
namespace.default.link.com_android_i18n.allow_all_shared_libs = true
namespace.default.link.com_android_runtime.allow_all_shared_libs = true
namespace.default.link.com_android_conscrypt.allow_all_shared_libs = true
namespace.default.link.com_android_media.allow_all_shared_libs = true
namespace.default.link.com_android_vndk_current.allow_all_shared_libs = true

namespace.system.isolated = false
namespace.system.visible = true
namespace.system.search.paths = /system/${LIB}:/system_ext/${LIB}:/product/${LIB}:/vendor/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/apex/com.android.vndk.current/${LIB}
namespace.system.links = default,com_android_art,com_android_i18n,com_android_runtime,com_android_conscrypt,com_android_media,com_android_vndk_current
namespace.system.link.default.allow_all_shared_libs = true
namespace.system.link.com_android_art.allow_all_shared_libs = true
namespace.system.link.com_android_i18n.allow_all_shared_libs = true
namespace.system.link.com_android_runtime.allow_all_shared_libs = true
namespace.system.link.com_android_conscrypt.allow_all_shared_libs = true
namespace.system.link.com_android_media.allow_all_shared_libs = true
namespace.system.link.com_android_vndk_current.allow_all_shared_libs = true

namespace.com_android_art.isolated = false
namespace.com_android_art.visible = true
namespace.com_android_art.search.paths = /apex/com.android.art/${LIB}:/apex/com.android.i18n/${LIB}:/apex/com.android.runtime/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}:/system_ext/${LIB}
namespace.com_android_art.links = default,system,com_android_i18n,com_android_runtime
namespace.com_android_art.link.default.allow_all_shared_libs = true
namespace.com_android_art.link.system.allow_all_shared_libs = true
namespace.com_android_art.link.com_android_i18n.allow_all_shared_libs = true
namespace.com_android_art.link.com_android_runtime.allow_all_shared_libs = true

namespace.com_android_i18n.isolated = false
namespace.com_android_i18n.visible = true
namespace.com_android_i18n.search.paths = /apex/com.android.i18n/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
namespace.com_android_i18n.links = default,system,com_android_art
namespace.com_android_i18n.link.default.allow_all_shared_libs = true
namespace.com_android_i18n.link.system.allow_all_shared_libs = true
namespace.com_android_i18n.link.com_android_art.allow_all_shared_libs = true

namespace.com_android_runtime.isolated = false
namespace.com_android_runtime.visible = true
namespace.com_android_runtime.search.paths = /apex/com.android.runtime/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
namespace.com_android_runtime.links = default,system,com_android_art
namespace.com_android_runtime.link.default.allow_all_shared_libs = true
namespace.com_android_runtime.link.system.allow_all_shared_libs = true
namespace.com_android_runtime.link.com_android_art.allow_all_shared_libs = true

namespace.com_android_conscrypt.isolated = false
namespace.com_android_conscrypt.visible = true
namespace.com_android_conscrypt.search.paths = /apex/com.android.conscrypt/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
namespace.com_android_conscrypt.links = default,system,com_android_art,com_android_i18n
namespace.com_android_conscrypt.link.default.allow_all_shared_libs = true
namespace.com_android_conscrypt.link.system.allow_all_shared_libs = true
namespace.com_android_conscrypt.link.com_android_art.allow_all_shared_libs = true
namespace.com_android_conscrypt.link.com_android_i18n.allow_all_shared_libs = true

namespace.com_android_media.isolated = false
namespace.com_android_media.visible = true
namespace.com_android_media.search.paths = /apex/com.android.media/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}:/system_ext/${LIB}
namespace.com_android_media.links = default,system,com_android_art
namespace.com_android_media.link.default.allow_all_shared_libs = true
namespace.com_android_media.link.system.allow_all_shared_libs = true
namespace.com_android_media.link.com_android_art.allow_all_shared_libs = true

namespace.com_android_vndk_current.isolated = false
namespace.com_android_vndk_current.visible = true
namespace.com_android_vndk_current.search.paths = /apex/com.android.vndk.current/${LIB}:/system/${LIB}:/vendor/${LIB}:/system_ext/${LIB}
namespace.com_android_vndk_current.links = default,system
namespace.com_android_vndk_current.link.default.allow_all_shared_libs = true
namespace.com_android_vndk_current.link.system.allow_all_shared_libs = true
LC_EOF
fi

chmod 644 "$LC"

echo "--- comprobar secciones ---"
grep -nE "^\[system\]|^\[runtime\]|^\[art\]|namespace.com_android_art.visible|additional.namespaces" "$LC" | head -120

echo
echo "--- comprobar ZygoteInit dentro de framework.jar ---"
if command -v unzip >/dev/null 2>&1; then
  unzip -l "$ROOTFS/system/framework/framework.jar" | grep -F "com/android/internal/os/ZygoteInit" || true
else
  strings "$ROOTFS/system/framework/framework.jar" | grep -F "ZygoteInit" | head || true
fi

echo
echo "--- probar dex2oat64 ya con seccion [art] ---"
APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  ANDROID_ROOT=/system \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  chroot "$ROOTFS" /apex/com.android.art/bin/dex2oat64 --help \
  >"$LOGDIR/dex2oat64.help.log" 2>&1 || true

tail -n 40 "$LOGDIR/dex2oat64.help.log"

echo
echo "--- arrancar zygote con bootclasspath explicito ---"

killall app_process64 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

BCP=""
for j in \
  /apex/com.android.art/javalib/core-oj.jar \
  /apex/com.android.art/javalib/core-libart.jar \
  /apex/com.android.i18n/javalib/core-icu4j.jar \
  /apex/com.android.conscrypt/javalib/conscrypt.jar \
  /apex/com.android.media/javalib/updatable-media.jar \
  /system/framework/framework.jar \
  /system/framework/ext.jar \
  /system/framework/framework-graphics.jar \
  /system/framework/telephony-common.jar \
  /system/framework/voip-common.jar \
  /system/framework/ims-common.jar \
  /system/framework/apache-xml.jar \
  /system/framework/bouncycastle.jar \
  /system/framework/okhttp.jar \
  /system/framework/org.apache.http.legacy.jar
do
  [ -f "$ROOTFS$j" ] && BCP="${BCP:+$BCP:}$j"
done

cat > "$LOGDIR/zygote64.v2.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BCP
ENV

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  BOOTCLASSPATH="$BCP" \
  DEX2OATBOOTCLASSPATH="$BCP" \
  ANDROID_ROOT=/system \
  ANDROID_DATA=/data \
  ANDROID_STORAGE=/storage \
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  ANDROID_ART_ROOT=/apex/com.android.art \
  ANDROID_I18N_ROOT=/apex/com.android.i18n \
  ANDROID_TZDATA_ROOT=/apex/com.android.tzdata \
  chroot "$ROOTFS" /system/bin/app_process64 \
    -Xzygote \
    "-Xbootclasspath:$BCP" \
    "-Xbootclasspath-locations:$BCP" \
    /system/bin --zygote \
    --socket-name=zygote \
    --abi-list=arm64-v8a \
  >"$LOGDIR/zygote64.v2.log" 2>&1 &

sleep 6

PID="$(pidof app_process64 || true)"

echo "--- pid ---"
echo "$PID"

echo
echo "--- status ---"
if [ -n "$PID" ]; then
  grep -E "Name|State|Pid|PPid|Threads" /proc/$PID/status
fi

echo
echo "--- sockets rootfs ---"
ls -l "$ROOTFS/dev/socket/" | grep -E "zygote|usap" || true

echo
echo "--- log ---"
tail -n 260 "$LOGDIR/zygote64.v2.log"

echo
echo "--- cmdline ---"
if [ -n "$PID" ]; then
  tr "\0" " " < /proc/$PID/cmdline
  echo
fi
