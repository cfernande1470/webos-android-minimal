set -e

DIR=zygote-symbols-post-binder

echo "--- libandroid_runtime around 0x1c7414 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1c7300 \
  --stop-address=0x1c7520 \
  "$DIR/libandroid_runtime.so.real" || true

echo
echo "--- libandroid_runtime around 0x1cce84 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1ccd80 \
  --stop-address=0x1ccf80 \
  "$DIR/libandroid_runtime.so.real" || true

echo
echo "--- libandroid_runtime around 0x1c9710 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1c9600 \
  --stop-address=0x1c9840 \
  "$DIR/libandroid_runtime.so.real" || true

echo
echo "--- libart around 0x4be390 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x4be200 \
  --stop-address=0x4be500 \
  "$DIR/libart.so.real" || true

echo
echo "--- libbase around 0x16454 and 0x16eac ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x16380 \
  --stop-address=0x17040 \
  "$DIR/libbase.so.real" || true

echo
echo "--- nearest libandroid_runtime symbols ---"
for off in 0x1c7414 0x1cce84 0x1c9710; do
  echo "### $off"
  aarch64-linux-gnu-nm -anC "$DIR/libandroid_runtime.so.real" 2>/dev/null | \
    awk -v OFF="$off" '
      $1 ~ /^[0-9a-fA-F]+$/ {
        v=strtonum("0x"$1);
        o=strtonum(OFF);
        if (v <= o) last=$0;
      }
      END {print last}
    ' || true
done

echo
echo "--- nearest libart symbol ---"
aarch64-linux-gnu-nm -anC "$DIR/libart.so.real" 2>/dev/null | \
  awk '$1 ~ /^[0-9a-fA-F]+$/ && strtonum("0x"$1) <= strtonum("0x4be390") {last=$0} END{print last}' || true

echo
echo "SYMBOLIZE_AFTER_SECCOMP_SKIP_DONE"
