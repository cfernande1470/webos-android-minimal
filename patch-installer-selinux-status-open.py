#!/usr/bin/env python3
import struct
from pathlib import Path

IN = Path("pulled/installd")
OUT = Path("pulled/installd.no-selinux-status-open")

# VA del BL selinux_status_open@plt según tu objdump:
VA = 0x5d608

# AArch64:
# original esperado: bl 0x60860 => 94 00 0c 96 en objdump, little-endian bytes 96 0c 00 94
# reemplazo: mov w0, #0 => 52800000, little-endian bytes 00 00 80 52
PATCH = bytes.fromhex("00008052")

data = bytearray(IN.read_bytes())

if data[:4] != b"\x7fELF":
    raise SystemExit("not an ELF")

is_64 = data[4] == 2
is_le = data[5] == 1
if not is_64 or not is_le:
    raise SystemExit("expected ELF64 little-endian")

# ELF64 header
e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
e_phnum = struct.unpack_from("<H", data, 0x38)[0]

def va_to_off(va: int) -> int:
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from("<I", data, off + 0x00)[0]
        if p_type != 1:  # PT_LOAD
            continue
        p_offset = struct.unpack_from("<Q", data, off + 0x08)[0]
        p_vaddr = struct.unpack_from("<Q", data, off + 0x10)[0]
        p_filesz = struct.unpack_from("<Q", data, off + 0x20)[0]
        if p_vaddr <= va < p_vaddr + p_filesz:
            return p_offset + (va - p_vaddr)
    raise SystemExit(f"VA 0x{va:x} not mapped by PT_LOAD")

foff = va_to_off(VA)
old = bytes(data[foff:foff+4])

print(f"VA 0x{VA:x} -> file offset 0x{foff:x}")
print(f"old bytes: {old.hex(' ')}")

# No abortamos si no coincide, pero lo mostramos claramente.
data[foff:foff+4] = PATCH
OUT.write_bytes(data)

print(f"patched bytes: {PATCH.hex(' ')}")
print(f"wrote: {OUT}")
