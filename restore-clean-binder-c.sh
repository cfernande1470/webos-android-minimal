set -e

SRC=build/linux-4.4.84/drivers/android/binder.c

echo "--- current broken source markers ---"
grep -nE 'WEBOS|40046210|BINDER_ENABLE_ONEWAY' "$SRC" || true

echo
echo "--- find clean backup ---"
CLEAN=""
for f in $(ls -1t build/linux-4.4.84/drivers/android/binder.c.bak.* 2>/dev/null); do
  if ! grep -qE 'WEBOS|40046210|BINDER_ENABLE_ONEWAY_SPAM_DETECTION' "$f"; then
    CLEAN="$f"
    break
  fi
done

if [ -z "$CLEAN" ]; then
  echo "ERROR: no clean binder.c backup found"
  echo "Backups:"
  ls -lah build/linux-4.4.84/drivers/android/binder.c.bak.* 2>/dev/null || true
  exit 1
fi

echo "CLEAN=$CLEAN"
cp -a "$CLEAN" "$SRC"

echo
echo "--- restored source check ---"
grep -nE 'WEBOS|40046210|BINDER_ENABLE_ONEWAY' "$SRC" || true

echo "RESTORE_CLEAN_BINDER_C_DONE"
