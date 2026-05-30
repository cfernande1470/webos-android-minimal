set -e

SRC="./build/linux-4.4.84/drivers/android/binder.c"

[ -f "$SRC" ] || {
  echo "ERROR: missing $SRC"
  exit 1
}

cp -a "$SRC" "$SRC.bak.afterprepare.$(date +%s)"

python3 - "$SRC" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

marker = "WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN"

if "BINDER_ENABLE_ONEWAY_SPAM_DETECTION" not in s:
    insert = """
#ifndef BINDER_ENABLE_ONEWAY_SPAM_DETECTION
#define BINDER_ENABLE_ONEWAY_SPAM_DETECTION 0x40046210
#endif
"""
    lines = s.splitlines(True)
    last_inc = max([i for i,l in enumerate(lines) if l.startswith("#include")] or [-1])
    lines.insert(last_inc + 1 if last_inc >= 0 else 0, insert + "\n")
    s = "".join(lines)

if marker not in s:
    m = re.search(r'(static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{)', s, re.S)
    if not m:
        m = re.search(r'(long\s+binder_ioctl\s*\([^)]*\)\s*\{)', s, re.S)
    if not m:
        raise SystemExit("ERROR: binder_ioctl function not found")

    guard = """
\t/* WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN */
\tif (cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION) {
\t\tpr_info("binder: WEBOS accept BINDER_ENABLE_ONEWAY_SPAM_DETECTION no-op\\n");
\t\treturn 0;
\t}
"""
    s = s[:m.end()] + guard + s[m.end():]

p.write_text(s)
PY

echo "--- verify source marker ---"
grep -nA10 -B5 'WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN\|BINDER_ENABLE_ONEWAY_SPAM_DETECTION' "$SRC"

echo "PATCH_BINDER_AFTER_PREPARE_DONE"
