USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

SRC="$ROOTFS/system/etc/preloaded-classes"
OUT="$OVRDIR/preloaded-classes.empty"

mkdir -p "$OVRDIR"

echo "--- preloaded-classes source ---"
ls -l "$SRC" || exit 1
echo "original lines: $(wc -l < "$SRC" 2>/dev/null || echo 0)"

echo
echo "--- desmontar override previo ---"
while mount | grep -q " $SRC "; do
  umount "$SRC" 2>/dev/null || break
done

echo
echo "--- crear override vacío ---"
: > "$OUT"
chmod 644 "$OUT"
ls -l "$OUT"

echo
echo "--- bind mount empty preloaded-classes ---"
mount --bind "$OUT" "$SRC" || exit 1

echo
echo "--- check final ---"
mount | grep " $SRC " || true
echo "final lines: $(wc -l < "$SRC")"
