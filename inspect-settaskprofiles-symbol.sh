set -eu

mkdir -p zygote-symbols
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libandroid_runtime.so zygote-symbols/libandroid_runtime.so
scp root@$TV_IP:/media/internal/android-usb/android-rootfs/system/lib64/libprocessgroup.so zygote-symbols/libprocessgroup.so

echo "--- undefined/dynamic symbols in libandroid_runtime ---"
readelf -Ws zygote-symbols/libandroid_runtime.so | c++filt | grep -i 'SetTaskProfiles\|TaskProfiles\|set task' || true

echo
echo "--- relocations in libandroid_runtime ---"
readelf -rW zygote-symbols/libandroid_runtime.so | c++filt | grep -i 'SetTaskProfiles\|TaskProfiles' || true

echo
echo "--- exported symbols in libprocessgroup ---"
readelf -Ws zygote-symbols/libprocessgroup.so | c++filt | grep -i 'SetTaskProfiles\|TaskProfiles' || true

echo
echo "--- shim exported symbols ---"
readelf -Ws libzygote_taskprofiles_shim.so | c++filt | grep -i 'SetTaskProfiles\|TaskProfiles' || true
