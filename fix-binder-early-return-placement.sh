set -e

SRC="./build/linux-4.4.84/drivers/android/binder.c"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

cp -a "$SRC" "$SRC.bak.fixplace.$(date +%s)"

python3 - "$SRC" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

# 1) Ensure numeric define.
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

# 2) Remove old misplaced block.
s = re.sub(
    r'\n#ifdef BINDER_ENABLE_ONEWAY_SPAM_DETECTION\n'
    r'\t/\* WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN \*/\n'
    r'\tif \(cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION\) \{\n'
    r'\t\tpr_info\("binder: WEBOS accept BINDER_ENABLE_ONEWAY_SPAM_DETECTION no-op\\n"\);\n'
    r'\t\treturn 0;\n'
    r'\t\}\n'
    r'#endif\n',
    '\n',
    s,
)

s = re.sub(
    r'\n\t/\* WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN \*/\n'
    r'\tif \(cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION\) \{\n'
    r'\t\tpr_info\("binder: WEBOS accept BINDER_ENABLE_ONEWAY_SPAM_DETECTION no-op\\n"\);\n'
    r'\t\treturn 0;\n'
    r'\t\}\n',
    '\n',
    s,
)

# 3) Insert after declarations, before first executable binder_ioctl code.
m = re.search(r'static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{', s, re.S)
if not m:
    raise SystemExit("binder_ioctl not found")

start = m.end()

anchors = [
    "\n\tbinder_selftest_alloc(",
    "\n\ttrace_binder_ioctl(",
    "\n\tret = wait_event_interruptible(",
]

pos = -1
for a in anchors:
    pos = s.find(a, start)
    if pos >= 0:
        break

if pos < 0:
    raise SystemExit("could not find insertion anchor in binder_ioctl")

guard = """
#ifdef BINDER_ENABLE_ONEWAY_SPAM_DETECTION
\t/* WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN */
\tif (cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION) {
\t\tpr_info("binder: WEBOS accept BINDER_ENABLE_ONEWAY_SPAM_DETECTION no-op\\n");
\t\treturn 0;
\t}
#endif
"""

s = s[:pos] + guard + s[pos:]
p.write_text(s)
PY

echo "--- verify placement ---"
grep -nA18 -B12 'WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN\|BINDER_ENABLE_ONEWAY_SPAM_DETECTION\|static long binder_ioctl' "$SRC" | head -220

echo "FIX_BINDER_EARLY_RETURN_PLACEMENT_DONE"
