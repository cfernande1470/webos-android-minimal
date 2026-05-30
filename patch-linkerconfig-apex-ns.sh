USB=/media/internal/android-usb
ROOTFS=$USB/android-rootfs
LC=$ROOTFS/linkerconfig/ld.config.txt

mkdir -p "$ROOTFS/linkerconfig"
[ -f "$LC" ] && cp -a "$LC" "$LC.bak.$(date +%s)"

cat > "$LC" <<'LC_EOF'
dir.system = /system/bin
dir.system = /system/xbin
dir.runtime = /apex/com.android.runtime/bin
dir.art = /apex/com.android.art/bin

[system]
additional.namespaces = system,com_android_art,com_android_i18n,com_android_runtime,com_android_conscrypt,com_android_media,com_android_vndk_current

namespace.default.isolated = false
namespace.default.visible = true
namespace.default.search.paths = /apex/com.android.runtime/${LIB}/bionic:/system/${LIB}:/system_ext/${LIB}:/product/${LIB}:/vendor/${LIB}:/apex/com.android.art/${LIB}:/apex/com.android.i18n/${LIB}:/apex/com.android.runtime/${LIB}:/apex/com.android.conscrypt/${LIB}:/apex/com.android.media/${LIB}:/apex/com.android.vndk.current/${LIB}
namespace.default.links = system,com_android_art,com_android_i18n,com_android_runtime,com_android_conscrypt,com_android_media,com_android_vndk_current
namespace.default.link.system.allow_all_shared_libs = true
namespace.default.link.com_android_art.allow_all_shared_libs = true
namespace.default.link.com_android_i18n.allow_all_shared_libs = true
namespace.default.link.com_android_runtime.allow_all_shared_libs = true
namespace.default.link.com_android_conscrypt.allow_all_shared_libs = true
namespace.default.link.com_android_media.allow_all_shared_libs = true
namespace.default.link.com_android_vndk_current.allow_all_shared_libs = true

namespace.system.isolated = false
namespace.system.visible = true
namespace.system.search.paths = /system/${LIB}:/system_ext/${LIB}:/product/${LIB}:/vendor/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/apex/com.android.vndk.current/${LIB}
namespace.system.links = default,com_android_art,com_android_i18n,com_android_runtime,com_android_conscrypt,com_android_media,com_android_vndk_current
namespace.system.link.default.allow_all_shared_libs = true
namespace.system.link.com_android_art.allow_all_shared_libs = true
namespace.system.link.com_android_i18n.allow_all_shared_libs = true
namespace.system.link.com_android_runtime.allow_all_shared_libs = true
namespace.system.link.com_android_conscrypt.allow_all_shared_libs = true
namespace.system.link.com_android_media.allow_all_shared_libs = true
namespace.system.link.com_android_vndk_current.allow_all_shared_libs = true

namespace.com_android_art.isolated = false
namespace.com_android_art.visible = true
namespace.com_android_art.search.paths = /apex/com.android.art/${LIB}:/apex/com.android.i18n/${LIB}:/apex/com.android.runtime/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}:/system_ext/${LIB}
namespace.com_android_art.links = default,system,com_android_i18n,com_android_runtime
namespace.com_android_art.link.default.allow_all_shared_libs = true
namespace.com_android_art.link.system.allow_all_shared_libs = true
namespace.com_android_art.link.com_android_i18n.allow_all_shared_libs = true
namespace.com_android_art.link.com_android_runtime.allow_all_shared_libs = true

namespace.com_android_i18n.isolated = false
namespace.com_android_i18n.visible = true
namespace.com_android_i18n.search.paths = /apex/com.android.i18n/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
namespace.com_android_i18n.links = default,system,com_android_art
namespace.com_android_i18n.link.default.allow_all_shared_libs = true
namespace.com_android_i18n.link.system.allow_all_shared_libs = true
namespace.com_android_i18n.link.com_android_art.allow_all_shared_libs = true

namespace.com_android_runtime.isolated = false
namespace.com_android_runtime.visible = true
namespace.com_android_runtime.search.paths = /apex/com.android.runtime/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
namespace.com_android_runtime.links = default,system,com_android_art
namespace.com_android_runtime.link.default.allow_all_shared_libs = true
namespace.com_android_runtime.link.system.allow_all_shared_libs = true
namespace.com_android_runtime.link.com_android_art.allow_all_shared_libs = true

namespace.com_android_conscrypt.isolated = false
namespace.com_android_conscrypt.visible = true
namespace.com_android_conscrypt.search.paths = /apex/com.android.conscrypt/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
namespace.com_android_conscrypt.links = default,system,com_android_art,com_android_i18n
namespace.com_android_conscrypt.link.default.allow_all_shared_libs = true
namespace.com_android_conscrypt.link.system.allow_all_shared_libs = true
namespace.com_android_conscrypt.link.com_android_art.allow_all_shared_libs = true
namespace.com_android_conscrypt.link.com_android_i18n.allow_all_shared_libs = true

namespace.com_android_media.isolated = false
namespace.com_android_media.visible = true
namespace.com_android_media.search.paths = /apex/com.android.media/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}:/system_ext/${LIB}
namespace.com_android_media.links = default,system,com_android_art
namespace.com_android_media.link.default.allow_all_shared_libs = true
namespace.com_android_media.link.system.allow_all_shared_libs = true
namespace.com_android_media.link.com_android_art.allow_all_shared_libs = true

namespace.com_android_vndk_current.isolated = false
namespace.com_android_vndk_current.visible = true
namespace.com_android_vndk_current.search.paths = /apex/com.android.vndk.current/${LIB}:/system/${LIB}:/vendor/${LIB}:/system_ext/${LIB}
namespace.com_android_vndk_current.links = default,system
namespace.com_android_vndk_current.link.default.allow_all_shared_libs = true
namespace.com_android_vndk_current.link.system.allow_all_shared_libs = true

[runtime]
additional.namespaces = system,com_android_art,com_android_i18n,com_android_runtime
namespace.default.isolated = false
namespace.default.visible = true
namespace.default.search.paths = /apex/com.android.runtime/${LIB}/bionic:/apex/com.android.runtime/${LIB}:/system/${LIB}
namespace.system.isolated = false
namespace.system.visible = true
namespace.system.search.paths = /system/${LIB}:/system_ext/${LIB}:/product/${LIB}:/vendor/${LIB}
namespace.com_android_art.isolated = false
namespace.com_android_art.visible = true
namespace.com_android_art.search.paths = /apex/com.android.art/${LIB}:/apex/com.android.i18n/${LIB}:/system/${LIB}
namespace.com_android_i18n.isolated = false
namespace.com_android_i18n.visible = true
namespace.com_android_i18n.search.paths = /apex/com.android.i18n/${LIB}:/system/${LIB}
namespace.com_android_runtime.isolated = false
namespace.com_android_runtime.visible = true
namespace.com_android_runtime.search.paths = /apex/com.android.runtime/${LIB}:/apex/com.android.runtime/${LIB}/bionic:/system/${LIB}
LC_EOF

chmod 644 "$LC"

echo "--- namespaces clave ---"
grep -nE "additional.namespaces|namespace.com_android_art|namespace.system.visible|namespace.default.links" "$LC" | head -80
