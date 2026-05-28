#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KVER="${KVER:-4.4.84}"
LOCALVERSION="${LOCALVERSION:--229.1.kavir.2}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
KDIR="$ROOT/build/linux-$KVER"

mkdir -p build dist

if [ ! -d "$KDIR" ]; then
  cd build
  curl -L --fail -o "linux-$KVER.tar.xz" \
    "https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-$KVER.tar.xz"
  tar -xf "linux-$KVER.tar.xz"
  cd "$ROOT"
fi

cd "$KDIR"

cp "$ROOT/kernel/config-lg-c1-o20-4.4.84" .config
cp "$ROOT/kernel/binder.c" drivers/android/binder.c
cp "$ROOT/kernel/binder_webos_exports.h" drivers/android/binder_webos_exports.h

# Repo mínimo: no dependemos de Kconfig ni del Makefile Android original.
# Forzamos que Binder se compile como módulo.
cat > drivers/android/Makefile <<'MAKEFILE'
ccflags-y += -I$(src)
obj-m += binder.o
MAKEFILE

python3 - <<PY
from pathlib import Path

p = Path(".config")
s = p.read_text(errors="ignore")

def set_line(key, val):
    global s
    out = []
    seen = False
    for line in s.splitlines():
        if line.startswith(key + "=") or line == f"# {key} is not set":
            if not seen:
                out.append(f"{key}={val}")
                seen = True
            continue
        out.append(line)
    if not seen:
        out.append(f"{key}={val}")
    s = "\n".join(out) + "\n"

set_line("CONFIG_ANDROID", "y")
set_line("CONFIG_ANDROID_BINDER_IPC", "m")
set_line("CONFIG_ANDROID_BINDER_DEVICES", '"binder,hwbinder,vndbinder"')
set_line("CONFIG_LOCALVERSION", "\"" + "${LOCALVERSION}" + "\"")
s = s.replace("CONFIG_LOCALVERSION_AUTO=y", "# CONFIG_LOCALVERSION_AUTO is not set")
p.write_text(s)
PY

make ARCH=arm64 HOSTCFLAGS="-fcommon" olddefconfig

# Kernel 4.4 trae un dtc antiguo que rompe con GCC moderno por doble yylloc.
# Lo dejamos parcheado dentro del árbol descargado, no en el sistema.
if [ -f scripts/dtc/dtc-lexer.l ]; then
  sed -i '/YYLTYPE yylloc;/d' scripts/dtc/dtc-lexer.l
fi
if [ -f scripts/dtc/dtc-lexer.lex.c ]; then
  sed -i '/YYLTYPE yylloc;/d' scripts/dtc/dtc-lexer.lex.c
fi
rm -f scripts/dtc/*.o scripts/dtc/dtc scripts/dtc/dtc-lexer.lex.c scripts/dtc/dtc-parser.tab.c scripts/dtc/dtc-parser.tab.h

make ARCH=arm64 HOSTCFLAGS="-fcommon" prepare scripts
make ARCH=arm64 M=drivers/android \
  HOSTCFLAGS="-fcommon" \
  KCFLAGS="-Wno-error -Wno-error=unused-variable -Wno-error=unused-function" \
  modules -j"$JOBS"

KO="$KDIR/drivers/android/binder.ko"
test -f "$KO"

if command -v modinfo >/dev/null 2>&1; then
  modinfo "$KO" || true
fi

LC_ALL=C grep -a -q hwbinder "$KO"
LC_ALL=C grep -a -q vndbinder "$KO"

cp "$KO" "$ROOT/dist/binder.ko"
ls -lh "$ROOT/dist/binder.ko"
