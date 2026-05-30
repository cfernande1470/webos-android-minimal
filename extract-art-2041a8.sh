set -e

DIR=zygote-symbols-post-binder
ART="$DIR/libart.so.real"

mkdir -p "$DIR"

echo "--- refresh libart from TV ---"
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/apex/com.android.art/lib64/libart.so "$ART"

echo
echo "--- file info ---"
file "$ART"
aarch64-linux-gnu-readelf -h "$ART" | grep -E 'Type:|Machine:|Entry|Class'

echo
echo "--- addr2line ---"
aarch64-linux-gnu-addr2line -f -C -e "$ART" 0x2041a8 0x2041f8 || true

echo
echo "--- nearest dynamic symbols ---"
aarch64-linux-gnu-readelf -Ws "$ART" 2>/dev/null | \
  awk '$2 ~ /^[0-9a-fA-F]+$/ {print "0x"$2, $4, $8}' | \
  sort -k1,1 | \
  awk '$1 <= "0x00000000002041f8" {last=$0} END{print last}' || true

echo
echo "--- objdump around 0x2041a8 ---"
aarch64-linux-gnu-objdump -d -C \
  --start-address=0x203f80 \
  --stop-address=0x204360 \
  "$ART" || true

echo
echo "--- strings near possible ART runtime keywords ---"
strings "$ART" | grep -iE 'quick|interpreter|invoke|jni|thread|suspend|stack|shadow|entrypoint|checkpoint|mutator|zygote' | head -200

echo
echo "EXTRACT_ART_2041A8_DONE"
