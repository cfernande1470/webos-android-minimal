set -e

DIR=zygote-symbols-post-binder

echo "--- libbinder around 0xa4318 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0xa4200 \
  --stop-address=0xa4550 \
  "$DIR/libbinder.so.real" || true

echo
echo "--- nearest libbinder symbols ---"
aarch64-linux-gnu-nm -anC "$DIR/libbinder.so.real" 2>/dev/null | \
  awk '$1 ~ /^[0-9a-fA-F]+$/ && strtonum("0x"$1) <= strtonum("0xa4318") {last=$0} END{print last}' || true

echo
echo "--- libandroid_runtime around 0x1d9af0 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1d9900 \
  --stop-address=0x1d9e80 \
  "$DIR/libandroid_runtime.so.real" || true

echo
echo "--- libandroid_runtime around 0x1ccc88 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1ccb80 \
  --stop-address=0x1ccd80 \
  "$DIR/libandroid_runtime.so.real" || true

echo
echo "--- libandroid_runtime around 0x1c9710 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x1c9600 \
  --stop-address=0x1c9840 \
  "$DIR/libandroid_runtime.so.real" || true

echo
echo "--- libbase around 0x16eac ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x16d80 \
  --stop-address=0x17040 \
  "$DIR/libbase.so.real" || true

echo
echo "SYMBOLIZE_POST_BINDER_DONE"
