set -e

SRC="./build/linux-4.4.84/drivers/android/binder.c"

[ -f "$SRC" ] || {
  echo "ERROR: missing $SRC"
  find ./build -type f -name binder.c 2>/dev/null
  exit 1
}

echo "SRC=$SRC"
cp -a "$SRC" "$SRC.bak.early.$(date +%s)"

echo
echo "--- ensure define ---"
if ! grep -q 'BINDER_ENABLE_ONEWAY_SPAM_DETECTION' "$SRC"; then
  python3 - "$SRC" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

insert = """
#ifndef BINDER_ENABLE_ONEWAY_SPAM_DETECTION
#define BINDER_ENABLE_ONEWAY_SPAM_DETECTION _IOW('b', 16, __u32)
#endif
"""

last_inc = -1
lines = s.splitlines(True)
for i, line in enumerate(lines):
    if line.startswith("#include"):
        last_inc = i

lines.insert(last_inc + 1 if last_inc >= 0 else 0, insert + "\n")
p.write_text("".join(lines))
PY
else
  echo "define already present"
fi

echo
echo "--- insert early return in binder_ioctl ---"
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
import re

p = Path(sys.argv[1])
s = p.read_text()

marker = "WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN"
if marker in s:
    print("early return already present")
    raise SystemExit(0)

m = re.search(r'(static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{)', s, re.S)
if not m:
    m = re.search(r'(long\s+binder_ioctl\s*\([^)]*\)\s*\{)', s, re.S)

if not m:
    raise SystemExit("ERROR: binder_ioctl function not found")

guard = """
#ifdef BINDER_ENABLE_ONEWAY_SPAM_DETECTION
\t/* WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN */
\tif (cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION) {
\t\tpr_info("binder: WEBOS accept BINDER_ENABLE_ONEWAY_SPAM_DETECTION no-op\\n");
\t\treturn 0;
\t}
#endif
"""

s = s[:m.end()] + guard + s[m.end():]
p.write_text(s)
print("inserted early return")
PY

echo
echo "--- patched source check ---"
grep -nA14 -B6 'WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN\|BINDER_ENABLE_ONEWAY_SPAM_DETECTION\|binder_ioctl' "$SRC" | head -160

echo
echo "PATCH_BINDERKO_EARLY_RETURN_SPAM_DONE"
