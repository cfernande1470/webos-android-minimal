set -e

SRC=build/linux-4.4.84/drivers/android/binder.c
cp -a "$SRC" "$SRC.bak.switchcase.$(date +%s)"

python3 - "$SRC" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

if "WEBOS_ANDROID_BINDER_SPAM_IOCTL_CASE" in s:
    print("already patched")
    p.write_text(s)
    raise SystemExit(0)

m = re.search(r'static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{', s, re.S)
if not m:
    m = re.search(r'long\s+binder_ioctl\s*\([^)]*\)\s*\{', s, re.S)
if not m:
    raise SystemExit("ERROR: binder_ioctl not found")

start = m.end()
sw = re.search(r'switch\s*\(\s*cmd\s*\)\s*\{', s[start:], re.S)
if not sw:
    raise SystemExit("ERROR: switch(cmd) not found inside binder_ioctl")

switch_start = start + sw.end()

# Brace-count to find this switch's body end; find its default inside this region.
depth = 1
i = switch_start
while i < len(s) and depth:
    if s[i] == "{":
        depth += 1
    elif s[i] == "}":
        depth -= 1
    i += 1

switch_body_end = i
body = s[switch_start:switch_body_end]

dm = re.search(r'\n(\t+)default\s*:', body)
if not dm:
    raise SystemExit("ERROR: default not found in binder_ioctl switch(cmd)")

insert_at = switch_start + dm.start()
indent = dm.group(1)

case = f"""
{indent}case 0x40046210U: /* WEBOS_ANDROID_BINDER_SPAM_IOCTL_CASE */
{indent}\tpr_info("binder: WEBOS accept ioctl 0x40046210 no-op\\n");
{indent}\tret = 0;
{indent}\tbreak;
"""

s = s[:insert_at] + case + s[insert_at:]
p.write_text(s)
PY

echo "--- verify patched case ---"
grep -nA12 -B8 'WEBOS_ANDROID_BINDER_SPAM_IOCTL_CASE\|switch.*cmd\|binder_ioctl' "$SRC" | head -220

echo "PATCH_BINDER_SWITCH_CASE_40046210_DONE"
