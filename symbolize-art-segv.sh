set -e

DIR=zygote-symbols-post-binder

mkdir -p "$DIR"

echo "--- refresh current libart/libandroid_runtime from TV ---"
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/apex/com.android.art/lib64/libart.so \
  "$DIR/libart.so.real"

scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libandroid_runtime.so \
  "$DIR/libandroid_runtime.current.so"

echo
echo "--- libart around pc=0x2041a8 lr=0x2041f8 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x204000 \
  --stop-address=0x204300 \
  "$DIR/libart.so.real" || true

echo
echo "--- nearest libart symbols ---"
for off in 0x2041a8 0x2041f8; do
  echo "### $off"
  aarch64-linux-gnu-nm -anC "$DIR/libart.so.real" 2>/dev/null | \
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
echo "--- libandroid_runtime current patch sanity ---"
for off in 0x1ca198 0x1ca1b0 0x1ca208 0x1ccde4 0x1d4e80 0x1d9afc; do
  echo -n "$off: "
  aarch64-linux-gnu-objdump -d -C \
    --start-address=$off \
    --stop-address=$((off+16)) \
    "$DIR/libandroid_runtime.current.so" | tail -n +8 | head -4 || true
done

echo
echo "SYMBOLIZE_ART_SEGV_DONE"
