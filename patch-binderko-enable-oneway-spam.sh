set -e

echo "--- find binder source ---"
SRC="$(find . -type f \( -name 'binder.c' -o -name '*binder*.c' \) \
  | grep -E '/drivers/android/binder\.c$|/binder\.c$|binder' \
  | head -1)"

if [ -z "$SRC" ]; then
  echo "ERROR: binder source not found"
  exit 1
fi

echo "SRC=$SRC"

cp -a "$SRC" "$SRC.bak.$(date +%s)"

echo
echo "--- ensure ioctl define exists ---"
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

# Ponerlo después de includes si no existe.
marker = "#include"
lines = s.splitlines(True)
last_inc = -1
for i, line in enumerate(lines):
    if line.startswith("#include"):
        last_inc = i

if last_inc >= 0:
    lines.insert(last_inc + 1, insert + "\n")
else:
    lines.insert(0, insert + "\n")

p.write_text("".join(lines))
PY
else
  echo "define already present"
fi

echo
echo "--- add ioctl case in binder_ioctl switch ---"
python3 - "$SRC" <<'PY'
from pathlib import Path
import sys
import re

p = Path(sys.argv[1])
s = p.read_text()

if "case BINDER_ENABLE_ONEWAY_SPAM_DETECTION:" in s:
    print("case already present")
    raise SystemExit(0)

# Insertar antes del primer default: dentro de binder_ioctl.
m = re.search(r'(static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{)', s)
if not m:
    m = re.search(r'(binder_ioctl\s*\([^)]*\)\s*\{)', s)

if not m:
    raise SystemExit("ERROR: binder_ioctl not found")

start = m.start()
default = s.find("\n\tdefault:", start)
indent = "\t"

if default < 0:
    default = s.find("\n        default:", start)
    indent = "        "

if default < 0:
    raise SystemExit("ERROR: default case after binder_ioctl not found")

case = f"""
{indent}case BINDER_ENABLE_ONEWAY_SPAM_DETECTION:
{indent}\t/*
{indent}\t * Android 12/13 libbinder may enable oneway spam detection.
{indent}\t * This minimal webOS binder backport does not implement it.
{indent}\t * Treat it as supported/no-op instead of returning -EINVAL.
{indent}\t */
{indent}\tret = 0;
{indent}\tbreak;
"""

s = s[:default] + case + s[default:]
p.write_text(s)
print("inserted case before binder_ioctl default")
PY

echo
echo "--- show patched area ---"
grep -nA8 -B8 'BINDER_ENABLE_ONEWAY_SPAM_DETECTION' "$SRC"

echo
echo "PATCH_BINDERKO_ENABLE_ONEWAY_SPAM_DONE"
