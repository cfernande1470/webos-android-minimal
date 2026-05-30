USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
SIDE=$USB/android-sidecar
OVRDIR=$SIDE/overrides

mkdir -p "$OVRDIR"

CG="$OVRDIR/cgroups.minimal.json"
TP="$OVRDIR/task_profiles.minimal.json"

cat > "$CG" <<'JSON'
{
  "Cgroups": [],
  "Cgroups2": {
    "Path": "/sys/fs/cgroup",
    "Mode": "0755",
    "UID": "root",
    "GID": "root",
    "Controllers": []
  }
}
JSON

cat > "$TP" <<'JSON'
{
  "Attributes": [],
  "Profiles": []
}
JSON

chmod 644 "$CG" "$TP"

unbind_one() {
  T="$1"
  while mount | grep -q " $T "; do
    umount "$T" 2>/dev/null || break
  done
}

bind_if_exists() {
  SRC="$1"
  TGT="$2"
  [ -f "$TGT" ] || return 0

  echo "--- override $TGT ---"
  unbind_one "$TGT"
  mount --bind "$SRC" "$TGT" || {
    echo "ERROR bind $SRC -> $TGT"
    exit 1
  }
  mount | grep " $TGT " || true
}

echo "--- existing cgroup/profile files ---"
find "$ROOTFS/system/etc" "$ROOTFS/vendor/etc" "$ROOTFS/product/etc" "$ROOTFS/system_ext/etc" \
  \( -name 'cgroups*.json' -o -name 'task_profiles*.json' \) 2>/dev/null | sort

echo
echo "--- bind minimal cgroups/task_profiles over all existing files ---"

for f in $(find "$ROOTFS/system/etc" "$ROOTFS/vendor/etc" "$ROOTFS/product/etc" "$ROOTFS/system_ext/etc" \
  -name 'cgroups*.json' 2>/dev/null | sort); do
  bind_if_exists "$CG" "$f"
done

for f in $(find "$ROOTFS/system/etc" "$ROOTFS/vendor/etc" "$ROOTFS/product/etc" "$ROOTFS/system_ext/etc" \
  -name 'task_profiles*.json' 2>/dev/null | sort); do
  bind_if_exists "$TP" "$f"
done

echo
echo "--- final checks ---"
for f in \
  "$ROOTFS/system/etc/cgroups.json" \
  "$ROOTFS/system/etc/task_profiles.json" \
  "$ROOTFS/vendor/etc/cgroups.json" \
  "$ROOTFS/vendor/etc/task_profiles.json"
do
  [ -f "$f" ] || continue
  echo "### $f"
  sed -n '1,40p' "$f"
done

echo
echo "MINIMAL_TASK_PROFILES_OK"
