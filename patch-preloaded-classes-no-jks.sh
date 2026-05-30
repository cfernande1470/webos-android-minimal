USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

mkdir -p "$OVRDIR"

echo "--- localizar preloaded-classes ---"
SRC=""
for f in \
  "$ROOTFS/system/etc/preloaded-classes" \
  "$ROOTFS/system/etc/preloaded-classes-denylist"
do
  [ -f "$f" ] && echo "FOUND $f"
done

SRC="$ROOTFS/system/etc/preloaded-classes"

if [ ! -f "$SRC" ]; then
  echo "ERROR: no existe $SRC"
  find "$ROOTFS/system" -name '*preload*classes*' -o -name 'preloaded-classes' 2>/dev/null
  exit 1
fi

echo
echo "--- buscar AnchorCertificates ---"
grep -n 'sun.security.util.AnchorCertificates' "$SRC" || true

echo
echo "--- desmontar override previo si existe ---"
while mount | grep -q " $SRC "; do
  umount "$SRC" 2>/dev/null || break
done

OUT="$OVRDIR/preloaded-classes.no-jks"

echo
echo "--- crear override filtrado ---"
grep -v '^sun\.security\.util\.AnchorCertificates$' "$SRC" > "$OUT"

echo "original lines: $(wc -l < "$SRC")"
echo "patched  lines: $(wc -l < "$OUT")"

echo
echo "--- comprobar filtrado ---"
grep -n 'sun.security.util.AnchorCertificates' "$OUT" && {
  echo "ERROR: sigue presente"
  exit 1
} || echo "OK: AnchorCertificates eliminado"

echo
echo "--- bind mount override ---"
mount --bind "$OUT" "$SRC" || {
  echo "ERROR: bind mount falló"
  exit 1
}

echo
echo "--- mount check ---"
mount | grep " $SRC " || true

echo
echo "--- final check desde rootfs ---"
grep -n 'sun.security.util.AnchorCertificates' "$SRC" || echo "OK final: no AnchorCertificates"
