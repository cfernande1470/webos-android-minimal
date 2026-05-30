#!/usr/bin/env python3
import sys, struct
from pathlib import Path

if len(sys.argv) != 5:
    raise SystemExit("usage: patch-va.py input output hex_va hex_bytes")

inp = Path(sys.argv[1])
out = Path(sys.argv[2])
va = int(sys.argv[3], 16)
patch = bytes.fromhex(sys.argv[4])

data = bytearray(inp.read_bytes())

e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
e_phnum = struct.unpack_from("<H", data, 0x38)[0]

def va_to_off(addr):
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if struct.unpack_from("<I", data, off)[0] != 1:
            continue
        p_offset = struct.unpack_from("<Q", data, off + 0x08)[0]
        p_vaddr = struct.unpack_from("<Q", data, off + 0x10)[0]
        p_filesz = struct.unpack_from("<Q", data, off + 0x20)[0]
        if p_vaddr <= addr < p_vaddr + p_filesz:
            return p_offset + (addr - p_vaddr)
    raise SystemExit(f"VA 0x{addr:x} not found")

foff = va_to_off(va)
print(f"VA 0x{va:x} -> file offset 0x{foff:x}")
print("old:", data[foff:foff+len(patch)].hex(" "))
data[foff:foff+len(patch)] = patch
print("new:", data[foff:foff+len(patch)].hex(" "))
out.write_bytes(data)
print(out)
