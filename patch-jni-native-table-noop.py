#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: patch-jni-native-table-noop.py input.so output.so")

inp = Path(sys.argv[1])
out = Path(sys.argv[2])
data = bytearray(inp.read_bytes())

# ELF headers
e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
e_phnum = struct.unpack_from("<H", data, 0x38)[0]

segments = []
for i in range(e_phnum):
    off = e_phoff + i * e_phentsize
    p_type = struct.unpack_from("<I", data, off)[0]
    if p_type != 1:
        continue
    p_offset = struct.unpack_from("<Q", data, off + 0x08)[0]
    p_vaddr = struct.unpack_from("<Q", data, off + 0x10)[0]
    p_filesz = struct.unpack_from("<Q", data, off + 0x20)[0]
    flags = struct.unpack_from("<I", data, off + 0x04)[0]
    segments.append((p_offset, p_vaddr, p_filesz, flags))

def off_to_va(foff):
    for p_offset, p_vaddr, p_filesz, flags in segments:
        if p_offset <= foff < p_offset + p_filesz:
            return p_vaddr + (foff - p_offset)
    raise RuntimeError(f"file offset 0x{foff:x} not mapped")

def va_to_off(va):
    for p_offset, p_vaddr, p_filesz, flags in segments:
        if p_vaddr <= va < p_vaddr + p_filesz:
            return p_offset + (va - p_vaddr)
    raise RuntimeError(f"VA 0x{va:x} not mapped")

def read_cstr_at_off(foff):
    end = data.find(b"\x00", foff)
    if end < 0:
        return None
    try:
        return data[foff:end].decode("utf-8", "replace")
    except Exception:
        return None

# nombres JNI esperables en PowerManagerService
wanted_prefixes = (
    "nativeInit",
    "nativeAcquireSuspendBlocker",
    "nativeReleaseSuspendBlocker",
    "nativeSetAutoSuspend",
    "nativeSetInteractive",
    "nativeSetPowerMode",
    "nativeSetPowerBoost",
    "nativeForceSuspend",
)

# busca offsets de strings native*
string_hits = []
for prefix in wanted_prefixes:
    start = 0
    needle = prefix.encode() + b"\x00"
    while True:
        idx = data.find(needle, start)
        if idx < 0:
            break
        string_hits.append((prefix, idx, off_to_va(idx)))
        start = idx + 1

if not string_hits:
    print("NO native PowerManagerService strings found")
    out.write_bytes(data)
    sys.exit(1)

print("=== string hits ===")
for name, off, va in string_hits:
    print(f"{name}: off=0x{off:x} va=0x{va:x}")

# patch: mov x0,#0 ; ret
patch = bytes.fromhex("00 00 80 d2 c0 03 5f d6")

patched = set()

print("=== candidate JNINativeMethod entries ===")
for name, str_off, str_va in string_hits:
    ptr = struct.pack("<Q", str_va)

    start = 0
    while True:
        ref_off = data.find(ptr, start)
        if ref_off < 0:
            break
        start = ref_off + 1

        # JNINativeMethod layout: name ptr, signature ptr, fn ptr
        if ref_off + 24 > len(data):
            continue

        sig_va = struct.unpack_from("<Q", data, ref_off + 8)[0]
        fn_va = struct.unpack_from("<Q", data, ref_off + 16)[0]

        try:
            sig_off = va_to_off(sig_va)
            fn_off = va_to_off(fn_va)
        except Exception:
            continue

        sig = read_cstr_at_off(sig_off)
        if not sig or not sig.startswith("("):
            continue

        print(f"{name}: entry_off=0x{ref_off:x} entry_va=0x{off_to_va(ref_off):x} sig={sig} fn_va=0x{fn_va:x} fn_off=0x{fn_off:x}")

        if fn_va not in patched:
            old = data[fn_off:fn_off+len(patch)]
            print(f"  patch fn 0x{fn_va:x}: old={old.hex(' ')} new={patch.hex(' ')}")
            data[fn_off:fn_off+len(patch)] = patch
            patched.add(fn_va)

if not patched:
    print("NO_FUNCTIONS_PATCHED")
    out.write_bytes(data)
    sys.exit(1)

out.write_bytes(data)
print(f"WROTE {out}")
print(f"patched_count={len(patched)}")
