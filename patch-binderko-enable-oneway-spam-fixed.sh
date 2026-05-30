set -e

SRC="./build/linux-4.4.84/drivers/android/binder.c"

if [ ! -f "$SRC" ]; then
  echo "ERROR: not found: $SRC"
  echo
  echo "--- candidates ---"
  find ./build ./src ./drivers -type f -name 'binder.c' 2>/dev/null || true
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
echo "--- locate binder_ioctl ---"
grep -nE 'binder_ioctl|switch.*cmd|case BINDER_' "$SRC" | head -120

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

m = re.search(r'static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{', s)
if not m:
    m = re.search(r'long\s+binder_ioctl\s*\([^)]*\)\s*\{', s)
if not m:
    raise SystemExit("ERROR: binder_ioctl not found in binder.c")

start = m.start()

# Buscar el switch(cmd) dentro de binder_ioctl.
sw = re.search(r'switch\s*\(\s*cmd\s*\)\s*\{', s[start:])
if not sw:
    raise SystemExit("ERROR: switch(cmd) not found in binder_ioctl")

switch_start = start + sw.start()

# Encontrar default dentro del switch de binder_ioctl.
default = s.find("\n\tdefault:", switch_start)
indent = "\t"
if default < 0:
    default = s.find("\n        default:", switch_start)
    indent = "        "
if default < 0:
    raise SystemExit("ERROR: default case not found in binder_ioctl switch")

case = f"""
{indent}case BINDER_ENABLE_ONEWAY_SPAM_DETECTION:
{indent}\t/*
{indent}\t * Android 12/13 libbinder may enable oneway spam detection.
{indent}\t * This 4.4 webOS Binder backport does not implement it.
{indent}\t * Accept as no-op instead of returning -EINVAL.
{indent}\t */
{indent}\tret = 0;
{indent}\tbreak;
"""

s = s[:default] + case + s[default:]
p.write_text(s)
print("inserted case before binder_ioctl default")
PY

echo
echo "--- patched area ---"
grep -nA12 -B10 'BINDER_ENABLE_ONEWAY_SPAM_DETECTION' "$SRC"

echo
echo "PATCH_BINDERKO_ENABLE_ONEWAY_SPAM_FIXED_DONE"
