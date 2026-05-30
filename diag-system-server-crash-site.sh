set -eu

mkdir -p zygote-symbols

[ -f zygote-symbols/libandroid_runtime.so.real ] || \
  scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libandroid_runtime.so \
    zygote-symbols/libandroid_runtime.so.real

LIB=zygote-symbols/libandroid_runtime.so.real

echo "--- symbols around zygote native funcs ---"
readelf -Ws "$LIB" | c++filt | grep -iE \
  'ZygoteFailure|ForkCommon|nativeForkSystemServer|SpecializeCommon|SetCapabilities|DetachDescriptors|FileDescriptor|BlockSignal|RuntimeAbort' \
  | head -120 || true

echo
echo "--- disasm around #4 0x1c7414: FatalError caller ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1c7300 \
  --stop-address=0x1c7480 \
  "$LIB"

echo
echo "--- disasm around #5 0x1d386c ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1d36f0 \
  --stop-address=0x1d3920 \
  "$LIB"

echo
echo "--- disasm around #6 0x1d471c ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1d45c0 \
  --stop-address=0x1d47a0 \
  "$LIB"

echo
echo "--- disasm around #7 0x1c75fc ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1c74e0 \
  --stop-address=0x1c7660 \
  "$LIB"

echo
echo "--- disasm around #8 0x1c95a4 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1c9440 \
  --stop-address=0x1c9620 \
  "$LIB"

echo
echo "--- nearby zygote failure strings ---"
strings -a -tx "$LIB" \
  | awk '$1 >= "6a000" && $1 <= "76000" {print}' \
  | grep -iE 'failed|fail|zygote|system server|cap|setuid|setgid|setgroups|rlimit|fork|descriptor|/dev/null|signal|seccomp|selinux|mount|policy|sched|profile|permission|dumpable' \
  | head -240
