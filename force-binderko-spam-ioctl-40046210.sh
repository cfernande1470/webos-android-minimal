set -e

SRC="./build/linux-4.4.84/drivers/android/binder.c"

[ -f "$SRC" ] || {
  echo "ERROR: missing $SRC"
  exit 1
}

cp -a "$SRC" "$SRC.bak.force40046210.$(date +%s)"

python3 - "$SRC" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

# Elimina bloques previos mal colocados.
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

# Fuerza el valor exacto aunque el header tenga otro define.
force_define = """
#undef BINDER_ENABLE_ONEWAY_SPAM_DETECTION
#define BINDER_ENABLE_ONEWAY_SPAM_DETECTION 0x40046210U
"""

if "0x40046210U" not in s:
    lines = s.splitlines(True)
    last_inc = max([i for i,l in enumerate(lines) if l.startswith("#include")] or [-1])
    lines.insert(last_inc + 1 if last_inc >= 0 else 0, force_define + "\n")
    s = "".join(lines)

# Localiza binder_ioctl.
m = re.search(r'static\s+long\s+binder_ioctl\s*\([^)]*\)\s*\{', s, re.S)
if not m:
    m = re.search(r'long\s+binder_ioctl\s*\([^)]*\)\s*\{', s, re.S)
if not m:
    raise SystemExit("ERROR: binder_ioctl not found")

start = m.end()

# Inserta después de declaraciones, antes del primer código típico.
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
    raise SystemExit("ERROR: insertion anchor not found")

guard = """
\t/* WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN */
\tif (cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION) {
\t\tpr_info("binder: WEBOS accept ioctl 0x40046210 no-op\\n");
\t\treturn 0;
\t}
"""

s = s[:pos] + guard + s[pos:]
p.write_text(s)
PY

echo "--- verify patched source ---"
grep -nA18 -B12 '0x40046210\|WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN\|binder_ioctl' "$SRC" | head -220

echo
echo "--- force rebuild object ---"
rm -f build/linux-4.4.84/drivers/android/binder.o
rm -f build/linux-4.4.84/drivers/android/binder.ko
rm -f build/linux-4.4.84/drivers/android/binder.mod.o
rm -f build/linux-4.4.84/drivers/android/binder.mod.c

cd build/linux-4.4.84

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M=drivers/android modules \
  2>&1 | tee ../../build-binder-force40046210.log

cd ../..

cp build/linux-4.4.84/drivers/android/binder.ko dist/binder.ko

echo
echo "--- verify marker in ko ---"
strings dist/binder.ko | grep -E 'WEBOS accept ioctl 0x40046210|ONEWAY_SPAM|40046210' || {
  echo "ERROR: marker missing in dist/binder.ko"
  exit 1
}

ls -lh dist/binder.ko

echo
echo "FORCE_BINDERKO_SPAM_IOCTL_40046210_DONE"
