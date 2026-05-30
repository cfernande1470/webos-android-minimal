set -e

LIB=zygote-symbols-post-binder/libbinder.so.real

echo "--- libbinder around 0x89b80..0x89c20 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x89b80 \
  --stop-address=0x89c40 \
  "$LIB"

echo
echo "--- bytes around call ---"
od -An -tx1 -j $((0x89bd0)) -N 40 "$LIB"

echo
echo "DUMP_LIBBINDER_SPAM_SITE_DONE"
