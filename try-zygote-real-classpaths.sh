USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LOGDIR=$USB/android-sidecar/logs
WRAP=$USB/android-sidecar/zygote_socket_wrap
PROBE=$USB/android-sidecar/zygote_probe
LC=$ROOTFS/linkerconfig/ld.config.txt

mkdir -p "$LOGDIR" "$ROOTFS/dev/socket" "$ROOTFS/linkerconfig"

echo "--- stop old zygote ---"
killall app_process64 2>/dev/null || true
killall zygote_socket_wrap 2>/dev/null || true
rm -f "$ROOTFS/dev/socket/zygote" "$ROOTFS/dev/socket/usap_pool_primary"

echo
echo "--- rebuild linkerconfig with all apex namespaces ---"

APEX_NAMES=""
APEX_SEARCH=""
for d in "$ROOTFS"/apex/com.android.*; do
  [ -d "$d" ] || continue
  b="${d##*/}"
  ns="$(echo "$b" | tr . _)"
  APEX_NAMES="${APEX_NAMES:+$APEX_NAMES,}$ns"
  APEX_SEARCH="$APEX_SEARCH:/apex/$b/\${LIB}"
done

write_links() {
  from="$1"
  targets="$2"
  echo "namespace.$from.links = $targets" >> "$LC"
  OLDIFS="$IFS"
  IFS=,
  for t in $targets; do
    [ -n "$t" ] && echo "namespace.$from.link.$t.allow_all_shared_libs = true" >> "$LC"
  done
  IFS="$OLDIFS"
}

write_section() {
  section="$1"

  cat >> "$LC" <<SEC

[$section]
additional.namespaces = system,$APEX_NAMES

namespace.default.isolated = false
namespace.default.visible = true
namespace.default.search.paths = /apex/com.android.runtime/\${LIB}/bionic:/system/\${LIB}:/system_ext/\${LIB}:/product/\${LIB}:/vendor/\${LIB}$APEX_SEARCH
SEC
  write_links default "system,$APEX_NAMES"

  cat >> "$LC" <<SEC

namespace.system.isolated = false
namespace.system.visible = true
namespace.system.search.paths = /system/\${LIB}:/system_ext/\${LIB}:/product/\${LIB}:/vendor/\${LIB}:/apex/com.android.runtime/\${LIB}/bionic$APEX_SEARCH
SEC
  write_links system "default,$APEX_NAMES"

  for d in "$ROOTFS"/apex/com.android.*; do
    [ -d "$d" ] || continue
    b="${d##*/}"
    ns="$(echo "$b" | tr . _)"

    cat >> "$LC" <<SEC

namespace.$ns.isolated = false
namespace.$ns.visible = true
namespace.$ns.search.paths = /apex/$b/\${LIB}:/apex/com.android.runtime/\${LIB}/bionic:/system/\${LIB}:/system_ext/\${LIB}:/product/\${LIB}:/vendor/\${LIB}
SEC
    write_links "$ns" "default,system"
  done
}

cp -a "$LC" "$LC.bak.realclasspath.$(date +%s)" 2>/dev/null || true

cat > "$LC" <<HEAD
dir.system = /system/bin
dir.system = /system/xbin
dir.runtime = /apex/com.android.runtime/bin
dir.art = /apex/com.android.art/bin
HEAD

write_section system
write_section runtime
write_section art

chmod 644 "$LC"

echo "--- classpath sources ---"
find "$ROOTFS" -path "*/classpaths/*" -o -name "*classpath*" 2>/dev/null | sort

echo
echo "--- build BOOTCLASSPATH from .pb ---"

BCP=""
DEXBCP=""
SYSCP=""

for f in \
  "$ROOTFS/system/etc/classpaths/bootclasspath.pb" \
  "$ROOTFS/system_ext/etc/classpaths/bootclasspath.pb" \
  "$ROOTFS/product/etc/classpaths/bootclasspath.pb" \
  "$ROOTFS/apex/com.android.art/etc/classpaths/bootclasspath.pb"
do
  [ -f "$f" ] || continue
  x="$(strings "$f" | grep -E '^/(apex|system|system_ext|product)/.*\.jar$' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')"
  [ -n "$x" ] && BCP="${BCP:+$BCP:}$x"
done

for f in \
  "$ROOTFS/system/etc/classpaths/dex2oatbootclasspath.pb" \
  "$ROOTFS/system_ext/etc/classpaths/dex2oatbootclasspath.pb" \
  "$ROOTFS/product/etc/classpaths/dex2oatbootclasspath.pb" \
  "$ROOTFS/apex/com.android.art/etc/classpaths/dex2oatbootclasspath.pb"
do
  [ -f "$f" ] || continue
  x="$(strings "$f" | grep -E '^/(apex|system|system_ext|product)/.*\.jar$' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')"
  [ -n "$x" ] && DEXBCP="${DEXBCP:+$DEXBCP:}$x"
done

for f in \
  "$ROOTFS/system/etc/classpaths/systemserverclasspath.pb" \
  "$ROOTFS/system_ext/etc/classpaths/systemserverclasspath.pb" \
  "$ROOTFS/product/etc/classpaths/systemserverclasspath.pb"
do
  [ -f "$f" ] || continue
  x="$(strings "$f" | grep -E '^/(apex|system|system_ext|product)/.*\.jar$' | awk '!seen[$0]++' | tr '\n' ':' | sed 's/:$//')"
  [ -n "$x" ] && SYSCP="${SYSCP:+$SYSCP:}$x"
done

if [ -z "$BCP" ]; then
  echo "WARN: no bootclasspath.pb usable; fallback amplio"
  BCP="/apex/com.android.art/javalib/core-oj.jar:/apex/com.android.art/javalib/core-libart.jar:/apex/com.android.conscrypt/javalib/conscrypt.jar:/apex/com.android.art/javalib/okhttp.jar:/apex/com.android.art/javalib/bouncycastle.jar:/apex/com.android.art/javalib/apache-xml.jar:/apex/com.android.i18n/javalib/core-icu4j.jar:/system/framework/framework.jar:/system/framework/ext.jar:/system/framework/framework-graphics.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/ims-common.jar"
fi

[ -z "$DEXBCP" ] && DEXBCP="$BCP"

echo "--- BOOTCLASSPATH entries ---"
echo "$BCP" | tr ':' '\n' | nl -ba

echo
echo "--- check entries exist ---"
OLDIFS="$IFS"
IFS=:
for j in $BCP; do
  if [ -e "$ROOTFS$j" ]; then
    echo "OK   $j"
  else
    echo "MISS $j"
  fi
done
IFS="$OLDIFS"

APEX_LD="$(find "$ROOTFS/apex" -mindepth 2 -maxdepth 2 -type d -name lib64 2>/dev/null | sed "s#^$ROOTFS##" | tr "\n" ":")"
LD_PATH="/apex/com.android.runtime/lib64/bionic:/system/lib64:/system_ext/lib64:/product/lib64:/vendor/lib64:$APEX_LD"

cat > "$LOGDIR/zygote64.realclasspath.env.log" <<ENV
LD_CONFIG_FILE=/linkerconfig/ld.config.txt
LD_PATH=$LD_PATH
BOOTCLASSPATH=$BCP
DEX2OATBOOTCLASSPATH=$DEXBCP
SYSTEMSERVERCLASSPATH=$SYSCP
ENV

echo
echo "--- start zygote ---"

nohup env -i \
  PATH=/system/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin \
  LD_CONFIG_FILE=/linkerconfig/ld.config.txt \
  LD_LIBRARY_PATH="$LD_PATH" \
  BOOTCLASSPATH="$BCP" \
  DEX2OATBOOTCLASSPATH="$DEXBCP" \
  SYSTEMSERVERCLASSPATH="$SYSCP" \
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
  >"$LOGDIR/zygote64.realclasspath.log" 2>&1 &

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
tail -n 300 "$LOGDIR/zygote64.realclasspath.log"

if [ -n "$PID" ] && [ -x "$PROBE" ]; then
  echo
  echo "--- query abi list ---"
  "$PROBE" "$ROOTFS/dev/socket/zygote" || true

  echo
  echo "--- log after probe ---"
  tail -n 300 "$LOGDIR/zygote64.realclasspath.log"
fi

echo
echo "--- final pid ---"
pidof app_process64 || true
