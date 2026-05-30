set -eu

mkdir -p zygote-symbols

echo "--- pull libs if missing ---"
[ -f zygote-symbols/libandroid_runtime.so.real ] || \
  scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libandroid_runtime.so \
    zygote-symbols/libandroid_runtime.so.real

[ -f zygote-symbols/libart.so ] || \
  scp root@$TV_IP:/media/internal/android-usb/android-rootfs/apex/com.android.art/lib64/libart.so \
    zygote-symbols/libart.so

echo
echo "--- caller around 0x1ca180: abort happens inside call at 0x1ca198 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1ca160 \
  --stop-address=0x1ca1c0 \
  zygote-symbols/libandroid_runtime.so.real

echo
echo "--- callee around 0x1cd7b0 / abort return 0x1cd934 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1cd780 \
  --stop-address=0x1cd980 \
  zygote-symbols/libandroid_runtime.so.real

echo
echo "--- nearby strings likely referenced by callee ---"
strings -a -tx zygote-symbols/libandroid_runtime.so.real \
  | awk '$1 >= "64000" && $1 <= "76000" {print}' \
  | grep -iE 'zygote|register|native|method|class|failed|fatal|JNI|FindClass|GetMethod|SetTask|profile' \
  | head -200

echo
echo "--- libart FatalError symbols ---"
readelf -Ws zygote-symbols/libart.so \
  | c++filt \
  | grep -iE 'JNI<.*FatalError|FatalError|JniAbort|Runtime::Abort' \
  | head -80
