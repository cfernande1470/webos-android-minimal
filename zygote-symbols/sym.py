import subprocess, sys, re, os

targets = {
    "libandroid_runtime.so": [0x1cd934, 0x1ca19c],
    "libart.so": [0x60a740, 0x4be390],
    "libbase.so": [0x16eac, 0x16454],
    "libc.so": [0x8aa00, 0x8a9d4],
    "boot-framework.oat": [0x1b1268],
}

def read_symbols(path):
    try:
        out = subprocess.check_output(["readelf", "-Ws", path], text=True, errors="replace")
    except Exception as e:
        print(f"readelf failed for {path}: {e}")
        return []

    syms = []
    for line in out.splitlines():
        # Num: Value Size Type Bind Vis Ndx Name
        parts = line.split()
        if len(parts) < 8:
            continue
        try:
            value = int(parts[1], 16)
            size = int(parts[2], 10)
        except Exception:
            continue
        typ = parts[3]
        name = parts[7]
        if typ in ("FUNC", "OBJECT", "NOTYPE") and value:
            syms.append((value, size, typ, name))
    syms.sort()
    return syms

def nearest(syms, addr):
    best = None
    for s in syms:
        if s[0] <= addr:
            best = s
        else:
            break
    return best

for fn, addrs in targets.items():
    path = os.path.join("zygote-symbols", fn)
    if not os.path.exists(path):
        continue

    print(f"\n===== {fn} =====")
    syms = read_symbols(path)

    for addr in addrs:
        print(f"\n--- addr/file_off 0x{addr:x} ---")
        b = nearest(syms, addr)
        if b:
            val, size, typ, name = b
            print(f"nearest: 0x{val:x} + 0x{addr-val:x} size={size} type={typ} name={name}")
        else:
            print("nearest: <none>")

        for tool in ("llvm-addr2line", "aarch64-linux-gnu-addr2line", "addr2line"):
            try:
                out = subprocess.check_output(
                    [tool, "-f", "-C", "-e", path, hex(addr)],
                    text=True,
                    errors="replace"
                ).strip()
                print(f"{tool}:\n{out}")
                break
            except Exception:
                pass
