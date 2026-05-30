set -e

SRC=build/linux-4.4.84/drivers/android/binder.c
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

cp -a "$SRC" "$SRC.bak.fixundeclared.$(date +%s)"

python3 - "$SRC" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

s = s.replace(
    "case BINDER_ENABLE_ONEWAY_SPAM_DETECTION:",
    "case 0x40046210U:"
)

s = s.replace(
    "cmd == BINDER_ENABLE_ONEWAY_SPAM_DETECTION",
    "cmd == 0x40046210U"
)

# También evitar que un #ifdef deje código fuera si quedó de intentos previos.
s = s.replace("#ifdef BINDER_ENABLE_ONEWAY_SPAM_DETECTION\n", "")
s = s.replace("#endif\n\t/* WEBOS_ANDROID", "\t/* WEBOS_ANDROID")

p.write_text(s)
PY

echo "--- remaining symbol refs ---"
grep -n 'BINDER_ENABLE_ONEWAY_SPAM_DETECTION' "$SRC" || true

echo
echo "--- WEBOS case area ---"
grep -nA12 -B10 'WEBOS_ANDROID_BINDER_SPAM_IOCTL_CASE\|WEBOS_ANDROID_ONEWAY_SPAM_EARLY_RETURN\|0x40046210' "$SRC" | head -220

echo "FIX_BINDER_UNDECLARED_SPAM_SYMBOL_DONE"
