set -e

DIR=zygote-symbols-post-binder
LIB="$DIR/libbinder.so.real"

mkdir -p "$DIR"

echo "--- refresh libbinder from TV ---"
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libbinder.so "$LIB"

echo
echo "--- search ioctl constant 0x40046210 in libbinder ---"
python3 - <<'PY'
from pathlib import Path

p = Path("zygote-symbols-post-binder/libbinder.so.real")
b = p.read_bytes()

patterns = {
    "little32_40046210": bytes.fromhex("10620440"),
    "movz_6210_piece": bytes.fromhex("001",) if False else b"",
}

needle = bytes.fromhex("10620440")
hits = []
start = 0
while True:
    i = b.find(needle, start)
    if i < 0:
        break
    hits.append(i)
    start = i + 1

print("raw little-endian hits:", [hex(x) for x in hits])

# Busca también instrucciones AArch64 que puedan construir 0x6210 / 0x4004 cerca de ioctl@plt.
for off in range(0, len(b) - 4, 4):
    w = int.from_bytes(b[off:off+4], "little")
    # movz/movk wide immediate hacia registros w0-w7 aprox.
    if (w & 0x7f800000) in (0x52800000, 0x72800000):
        imm16 = (w >> 5) & 0xffff
        if imm16 in (0x6210, 0x4004, 0x46210 & 0xffff):
            print("wide-imm candidate", hex(off), hex(w), "imm16", hex(imm16))
PY

echo
echo "--- disassemble all ioctl@plt callers approx ---"
aarch64-linux-gnu-objdump -d -C "$LIB" | grep -n -B8 -A12 'ioctl@plt' | head -360

echo
echo "FIND_BINDER_SPAM_IOCTL_DONE"
