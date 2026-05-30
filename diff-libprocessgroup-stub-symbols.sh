set -eu

mkdir -p zygote-symbols
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libandroid_runtime.so zygote-symbols/libandroid_runtime.so.real
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/data/local/tmp/libprocessgroup.stub.so zygote-symbols/libprocessgroup.stub.so

# Si el target /system/lib64/libprocessgroup.so está bind-mounteado, copiamos el original desde
# el backup local previo si existe. Si no existe, intenta desmontar temporalmente sería peligroso,
# así que usamos el libprocessgroup.so que ya copiaste antes en zygote-symbols si está.
if [ -f zygote-symbols/libprocessgroup.so ]; then
  ORIG=zygote-symbols/libprocessgroup.so
else
  echo "WARN: falta zygote-symbols/libprocessgroup.so original; ejecuta esto sólo si lo tienes de antes."
  ORIG=
fi

readelf -Ws zygote-symbols/libandroid_runtime.so.real \
  | awk '$7=="UND"{print $8}' \
  | sed 's/@.*//' \
  | sort -u > zygote-symbols/runtime.und

readelf -Ws zygote-symbols/libprocessgroup.stub.so \
  | awk '$4=="FUNC" && $7!="UND"{print $8}' \
  | sed 's/@.*//' \
  | sort -u > zygote-symbols/stub.def

echo "--- runtime undefined symbols matching processgroup-ish names ---"
grep -E 'ProcessGroup|ProcessProfiles|TaskProfiles|Cgroup|Memcg|sched|cpuset|cpusets|schedboost|policy' \
  zygote-symbols/runtime.und || true

echo
echo "--- still missing from current stub, processgroup-ish only ---"
comm -23 zygote-symbols/runtime.und zygote-symbols/stub.def \
  | grep -E 'ProcessGroup|ProcessProfiles|TaskProfiles|Cgroup|Memcg|sched|cpuset|cpusets|schedboost|policy' || true
