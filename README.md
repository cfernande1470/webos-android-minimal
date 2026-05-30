# webos-android-minimal

Minimal Android USB sidecar bootstrap for rooted LG webOS TVs.

This repository is the cleaned-up continuation of the earlier [`webos-dirty-binder`](https://github.com/cfernande1470/webos-dirty-binder) experiments. The old repository was intentionally noisy: it kept staged Binder FD probes, smoke tests, debug tags, multiple intermediate scripts, and a long trail of kernel-patch milestones. This repository keeps only the pieces needed to reproduce the currently validated result:

```text
binder
hwbinder
vndbinder

vndservicemanager: alive
servicemanager: alive
hwservicemanager: alive
zygote64: alive
system_server: alive

FINAL_USB_3DOMAIN_BINDER_OK
FINAL_ANDROID_ZYGOTE_SYSTEM_SERVER_OK
FINAL_USB_INSTALL_OK
```

The current goal is not to boot a full Android UI yet. The goal is to bring up the minimum Android 13 userspace foundation on top of the existing webOS kernel:

- compile a compatible Binder kernel module for the LG webOS 4.4 kernel;
- load Binder without replacing the TV kernel, rootfs, TV service partitions, or boot chain;
- create the three Android Binder domains: `/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`;
- assemble an Android rootfs from Waydroid arm64 system/vendor images on USB storage;
- fix Android dynamic linker/APEX visibility inside the chroot;
- generate linkerconfig and property-area state far enough for the service managers;
- start the real Android `servicemanager`, `hwservicemanager`, and `vndservicemanager`;
- patch the known webOS/Android runtime blockers and launch `zygote64` with `system_server`.

## Safety warning

This project is for rooted LG webOS development devices only.

Do **not** overwrite system partitions such as kernel, rootfs, TV service, boot, recovery, or webOS application partitions. The installer is designed to work from USB storage and runtime mounts only.

The default USB mountpoint used by this repo is:

```text
/media/internal/android-usb
```

That path is used only as a persistent mountpoint. The script verifies that the actual filesystem mounted there is the selected USB block device, normally `/dev/sda1`. The Android images, rootfs, data, cache, logs, sidecar binaries, and Binder module all live on the USB filesystem.

## Tested setup

Validated target:

```text
LG webOS TV
Linux 4.4.84-229.1.kavir.2
aarch64
```

Latest full install validation:

```text
2026-05-30
TV_IP=192.168.2.121
USB=/media/internal/android-usb
ANDROID_USB_PART=/dev/sda1
FORMAT_USB=0
```

Validated control host:

```text
NanoPi R3S
Debian/Ubuntu-like userspace
SSH access to root@TV_IP
```

Validated Android userspace image family:

```text
Waydroid Android 13 arm64-only system image
Waydroid Android 13 arm64-only vendor image
```

## Repository layout

```text
kernel/
  binder.c
  binder_webos_exports.h
  config-lg-c1-o20-4.4.84

src/
  property_service_ack_shim.c
  zygote_socket_wrap.c

scripts/
  build-binder.sh
  build-property-shim.sh
  build-zygote-socket-wrap.sh
  binder-registry-smoke.sh
  clean-mounts.sh
  collect-logs.sh
  probe-services.sh
  smoke-hal-services.sh
  status.sh
  stop.sh
  restart.sh

install.sh
.gitignore
README.md
```

### `kernel/binder.c`

A vendored Binder source file based on the working final state from the earlier experimental repository.

The old project generated this file through many staged patches and injectors. This minimal repo does not replay those patch stages. It keeps the final known-good source directly, so a clean clone can build the module without pulling the old project.

### `kernel/binder_webos_exports.h`

Small compatibility header used by the Binder module to call non-exported kernel functions via symbol addresses passed at `insmod` time.

The installer resolves the required addresses from `/proc/kallsyms` on the TV and passes them into the module as parameters.

### `scripts/build-binder.sh`

Downloads Linux `4.4.84`, applies the saved LG/webOS kernel config, installs the vendored Binder source, and builds only `drivers/android/binder.ko`.

It also patches the old kernel `dtc` build issue seen with modern GCC toolchains by removing the duplicate `yylloc` definition and using `HOSTCFLAGS=-fcommon`.

The output module is:

```text
dist/binder.ko
```

### `src/property_service_ack_shim.c`

Minimal static aarch64 helper that creates `/dev/socket/property_service` inside the Android rootfs.

This is not a full Android property service implementation. It understands the Android `PROP_MSG_SETPROP` and `PROP_MSG_SETPROP2` socket protocols, returns Android property-service status codes, and writes the accepted property state to:

```text
android-sidecar/run/property_service.props
```

That is enough for the current service-manager bring-up path, especially the `hwservicemanager.ready` property write, and gives the next debugging step a concrete property snapshot. It still does not update Android's shared `/dev/__properties__` property area.

### `src/zygote_socket_wrap.c`

Small static aarch64 helper that creates the host-side `zygote` and `usap_pool_primary` sockets, passes them to Android as `ANDROID_SOCKET_*` file descriptors, then chroots and execs `/system/bin/app_process64`.

This avoids depending on webOS init socket activation for zygote.

### `patch-libandroid-runtime-zssystemserver.sh`

Runtime compatibility patcher for the Android userspace libraries used by zygote and `system_server`.

The installer copies this script to the USB sidecar and runs it against the mounted Android rootfs. The current validated flow patches the known blockers in `libandroid_runtime.so` and `libprocessgroup.so`. `libandroid_servers.so` is left unmodified by default because the current runtime starts cleanly without that patch; `PATCH_ANDROID_SERVERS=1` keeps the old override available if needed again.

### `try-zygote-start-system-server-v2.sh`

Launch script copied to the USB sidecar. It prepares the zygote/system_server environment, starts the property-service ACK shim, filters VNDK paths out of the zygote/system_server `LD_LIBRARY_PATH`, uses `zygote_socket_wrap`, and verifies that both `zygote64` and `system_server` stay alive.

### `install.sh`

Single entry point. It builds the module and helper binaries, optionally formats the USB partition, downloads/extracts Android images, mounts the Android rootfs, loads Binder, creates the three device nodes, fixes APEX/linker visibility, prepares linkerconfig/property state, starts the three Android service managers, patches the Android runtime and processgroup libraries for the current TV kernel/userspace constraints, and starts `zygote64` plus `system_server`.

## Quick start

Install local build dependencies on the control host:

```bash
sudo apt-get update
sudo apt-get install -y \
  curl xz-utils bc bison flex libssl-dev libelf-dev \
  make gcc git python3 unzip openssh-client
```

Clone and run:

```bash
git clone git@github.com:cfernande1470/webos-android-minimal.git
cd webos-android-minimal

TV_IP=192.168.2.121 \
USB=/media/internal/android-usb \
ANDROID_USB_PART=/dev/sda1 \
FORMAT_USB=1 \
CONFIRM_FORMAT_USB=YES \
./install.sh
```

This path is destructive for the selected USB partition. The validated run formatted `/dev/sda1` as ext4, mounted it at `/media/internal/android-usb`, downloaded the Waydroid Android 13 arm64-only system/vendor images, and completed with `zygote64` plus `system_server` alive.

Expected final result:

```text
FINAL_USB_3DOMAIN_BINDER_OK
FINAL_ANDROID_ZYGOTE_SYSTEM_SERVER_OK
FINAL_USB_INSTALL_OK
```

To run again without reformatting the USB:

```bash
TV_IP=192.168.2.121 \
USB=/media/internal/android-usb \
ANDROID_USB_PART=/dev/sda1 \
FORMAT_USB=0 \
./install.sh
```

## USB formatting guard

Formatting is disabled unless both variables are present:

```bash
FORMAT_USB=1
CONFIRM_FORMAT_USB=YES
```

The script refuses to format arbitrary paths. It only accepts USB-like block devices such as:

```text
/dev/sda
/dev/sda1
/dev/sdb
/dev/sdb1
```

It also checks that the selected mountpoint is actually backed by the selected USB device before writing Android files.

## Current boot flow

High-level flow:

```text
control host
  ├── build Linux 4.4.84 Binder module
  ├── build static property_service_ack_shim
  └── SSH to TV
        ├── optionally format USB ext4
        ├── mount USB at /media/internal/android-usb
        ├── copy binder.ko, property shim, zygote wrapper, and launch/patch scripts
        ├── download Android system/vendor images to USB
        ├── extract system.img and vendor.img
        ├── mount system/vendor/rootfs/data/cache/proc/sys/dev
        ├── resolve non-exported kernel symbols from /proc/kallsyms
        ├── insmod binder.ko with symbol parameters
        ├── create /dev/binder, /dev/hwbinder, /dev/vndbinder
        ├── mount Android APEX/linker paths correctly
        ├── generate linkerconfig
        ├── seed Android property area enough for bring-up
        ├── start property socket ACK shim
        ├── start vndservicemanager
        ├── start servicemanager
        ├── start hwservicemanager
        ├── bind-mount patched Android runtime/server/processgroup libraries
        └── start zygote64 with system_server
```

## Binder module notes

The TV kernel already contains enough Binder-era infrastructure to make this possible, but not in a directly reusable Android form. The module therefore uses a small set of runtime symbol parameters for non-exported kernel helpers:

```text
sym_get_vm_area
sym_map_kernel_range_noflush
sym_zap_page_range
sym___alloc_fd
sym___fd_install
sym___close_fd
sym_get_files_struct
sym_put_files_struct
sym___lock_task_sighand
```

The installer resolves these on the TV with `/proc/kallsyms` and passes them to `insmod`.

The module exposes:

```text
/dev/binder
/dev/hwbinder
/dev/vndbinder
```

These correspond to the three Android Binder domains used by:

```text
/system/bin/servicemanager
/system/bin/hwservicemanager
/vendor/bin/vndservicemanager
```

## Binder FD transfer fix

A major milestone from the earlier repository was real `BINDER_TYPE_FD` support.

The important rule discovered during the FD work was that Binder FD installation must target Binder's target process file table directly. The successful path uses the Binder target process state rather than `current->files` or a task-derived file table.

Conceptually:

```c
file = fget(fp->handle);
target_fd = __alloc_fd(target_proc->files, 0, 1024, O_CLOEXEC);
__fd_install(target_proc->files, target_fd, file);
fp->handle = target_fd;
```

This is why the module still has an internal `fd_path_mode` module parameter. It is no longer a public staged-debug workflow; it is simply the selected file-descriptor transfer path used by the working module.

The old repository carried this history as staged FD probes, smoke tests, and debug labels. This repository keeps the working implementation and removes those development harnesses from the normal install path.

## APEX/linker issue and fix

Android 13 binaries use:

```text
/system/bin/linker64 -> /apex/com.android.runtime/bin/linker64
```

If `/apex` is missing, empty, or accidentally covered by `tmpfs`, chroot execution fails with a misleading error:

```text
chroot: can't execute '/system/bin/toybox': No such file or directory
```

The file exists, but its interpreter does not.

The installer now ensures that `/apex/com.android.runtime/bin/linker64` is visible before starting Android binaries. It validates this with a minimal `toybox true` check and rechecks APEX again immediately before starting the service managers.

## Property service shim

The current property-service support is intentionally small.

`property_service_ack_shim` creates:

```text
/dev/socket/property_service
```

inside the Android rootfs, accepts Android 13 property-set socket messages, validates the basic property name/value shape, returns the same numeric success/error codes used by Android init's property service, and records accepted writes in:

```text
/media/internal/android-usb/android-sidecar/run/property_service.props
```

This is enough for the current service-manager baseline, but it is not a complete Android property service. A future milestone should replace this shim with either:

- a minimal write-through property service that updates Android's shared property area; or
- a controlled mini-init that owns property service and service lifecycle correctly.

## What is working now

The current clean installer validates:

```text
USB ext4 storage
optional USB formatting with explicit confirmation
Android system.img/vendor.img download and extraction
Android rootfs assembly on USB
/system mount
/vendor mount
/apex visibility for Android linker
/data on USB
/cache on USB
/proc mount
/sys mount
/dev bind/device preparation
binder.ko build and load
/dev/binder
/dev/hwbinder
/dev/vndbinder
/system/bin/servicemanager alive
/system/bin/hwservicemanager alive
/vendor/bin/vndservicemanager alive
zygote64 alive
system_server alive
```

The latest validated run also confirmed the generated Android classpaths from the mounted image metadata:

```text
BOOTCLASSPATH generated length: 1624
SYSTEMSERVERCLASSPATH generated length: 792
```

A successful run ends with:

```text
--- android services ---
vndservicemanager: <pid>
servicemanager: <pid>
hwservicemanager: <pid>
FINAL_USB_3DOMAIN_BINDER_OK

ZYGOTE_SYSTEM_SERVER_OK
FINAL_ANDROID_ZYGOTE_SYSTEM_SERVER_OK

FINAL_USB_INSTALL_OK
```

## What this repository intentionally removed

The old experimental repository was useful for discovery, but it had accumulated many intermediate artifacts. This minimal repo removes the normal dependency on:

- staged Binder FD debug scripts;
- smoke-test harnesses;
- repeated patch injectors;
- legacy `dirty` naming;
- intermediate milestone tags in output;
- artifact fallback logic;
- `/tmp/android-usb` as the default persistent path.

The default persistent mountpoint is now:

```text
/media/internal/android-usb
```

## Relationship to other repositories

### Previous Binder research repository

```text
https://github.com/cfernande1470/webos-dirty-binder
```

That repository documents the discovery path: Binder mmap, FD passing, three Binder domains, linkerconfig, property-area probing, and early HAL experiments.

This repository is the cleaned installer-first result extracted from that research.

### Wayland/webOS app repository

```text
https://github.com/cfernande1470/webos-wayland
```

The Wayland project proves the native webOS app/display side: SAM-launched native app, Wayland surface creation, input, and EGL/GLES rendering on the TV compositor.

Long term, the Android sidecar work here and the native Wayland work there can converge into a controlled Android-on-webOS app experiment: Android services and framework components running as a sidecar, with rendering/input integrated through the already working webOS/Wayland path.

## Milestones reached

### 1. Binder module builds outside the TV

The control host can build `binder.ko` for the LG webOS kernel version:

```text
4.4.84-229.1.kavir.2
```

The build is isolated to `drivers/android/binder.ko`.

### 2. Non-exported kernel symbols are resolved at load time

The module no longer requires kernel partition changes. The installer reads `/proc/kallsyms` and passes the required addresses into `insmod`.

### 3. Binder mmap works

The Binder memory mapping path works far enough for real Android service-manager processes to start.

### 4. Real Binder FD transfer works

The FD path was fixed by installing received FDs into `target_proc->files`.

### 5. Binder multi-device works

The module exposes:

```text
/dev/binder
/dev/hwbinder
/dev/vndbinder
```

### 6. Android rootfs on USB works

Android system and vendor images are downloaded and mounted from USB. `/data` and `/cache` also live on USB.

### 7. Android APEX/linker visibility works

The installer keeps `/apex/com.android.runtime/bin/linker64` visible and validates it before launching Android binaries.

### 8. Three Android service managers are alive

The final validated service baseline is:

```text
vndservicemanager
servicemanager
hwservicemanager
```

## Future milestones

### M1: Replace property ACK shim

Implement a real minimal Android property-service bridge or mini-init-managed property service.

Current state: Android property socket protocol shim with a sidecar property snapshot.

Desired state:

```text
setprop/getprop behavior compatible enough for broader Android services
persistent property area lifecycle
clean shutdown/restart
```

Remaining M1 gap: update Android's shared `/dev/__properties__` area so `getprop` observes property writes directly, instead of only recording them in the sidecar snapshot.

### M2: Make Android init lifecycle explicit

Current script uses only enough Android init behavior to seed property/linker state.

First step:

- persist runtime phase markers and pid files so start, stop, and restart are observable without guessing;
- keep the current controlled bring-up path, then tighten restart semantics before adding a larger init supervisor.

`status.sh`, `stop.sh`, and `restart.sh` now cover that first step.

Future work:

- controlled mini-init;
- bounded Android init phases;
- service supervision;
- deterministic stop/restart scripts.

### M3: HAL bring-up beyond service managers

Next low-risk HAL/service probes:

```text
memtrack
graphics allocator / mapper
power
sensors stub behavior
input-related services
```

Each HAL should be tested as a bounded process first, not as part of a full Android boot.

`probe-services.sh` is the first diagnostic for this lane.
`smoke-hal-services.sh` is the first bounded HAL launch test for this lane.

Graphics and UI are not the final target in this repo. The compositor path should move to the separate [`webos-wayland`](https://github.com/cfernande1470/webos-wayland/) project and a native webOS app named `android` that either launches the Android sidecar or serves as an APK compatibility layer on webOS.

Current probe baseline:

- `service list` returns cleanly;
- `cmd -l` returns cleanly where available;
- `lshal` is not yet a stable probe on this image;
- the current runtime does not yet expose the targeted `memtrack`, `power`, `graphics`, or `input` strings in the probe output.

Current HAL smoke baseline:

- `memtrack`, `power`, `graphics.allocator@2.0`, `graphics.allocator@4.0`, and `light` can be launched and stay resident on the current runtime;
- `sensors` exits cleanly as a bounded probe;
- `graphics.composer@2.1` is not part of the Android sidecar baseline; that path belongs to the separate Wayland/webOS app work.

### M4: Binder service registration checks

Add clean diagnostics for:

```text
service list
hwservice list
vndservice list
addService/getService smoke
FD transfer smoke against real servicemanager
```

These should be optional diagnostics, not part of the default installer.

Current state:

- `service list` and `service check SERVICE` are stable on the current image;
- `service call manager 1 s16 activity_task` is a working getService smoke against the real servicemanager;
- `vndservice list` and `lshal` remain optional diagnostics because they time out on this image and are not stable enough to gate the install path here.

`scripts/binder-registry-smoke.sh` is the dedicated M4 probe.

### M5: Replace runtime binary patches with source-level fixes

The installer currently uses bounded bind-mount patches for the TV-specific blockers found during zygote/system_server bring-up:

```text
libandroid_runtime.so
libprocessgroup.so
task profile/runtime abort paths
file-descriptor allowlist/reopen paths
seccomp filter helpers
power stats / stats / memtrack startup blockers
```

`libandroid_servers.so` is no longer part of the default patch path.

This is acceptable for reproducing the current milestone, but it should eventually become a cleaner compatibility layer or documented source-level Android userspace patch set. The first cleanup step is already done: `libandroid_servers.so` no longer needs a patch in the default path on the current image.

### M6: Android UI path through native webOS Wayland

Wayland/EGL already works in the separate [`webos-wayland`](https://github.com/cfernande1470/webos-wayland/) repository. A future UI milestone should investigate how Android rendering can be bridged to the webOS app lifecycle instead of trying to draw from an unmanaged SSH-launched process.

The webOS application should be called `android`. It can either launch the Android sidecar on demand or act as the compatibility layer that exposes APK installation and Android-side services inside the webOS app lifecycle.

Possible directions:

- Android sidecar services only;
- native webOS host app for display/input;
- controlled surface bridge;
- later SurfaceFlinger experiments only after the service/HAL baseline is ready.

Any concrete Wayland/EGL compositor work belongs in [`webos-wayland`](https://github.com/cfernande1470/webos-wayland/), not in this repository.

### M7: Packaging and recovery

Add:

```text
./scripts/status.sh
./scripts/stop.sh
./scripts/restart.sh
./scripts/clean-mounts.sh
./scripts/collect-logs.sh
```

`status.sh`, `stop.sh`, `restart.sh`, `clean-mounts.sh`, and `collect-logs.sh` now exist as the first operational split-out scripts.

## Troubleshooting

### `chroot: can't execute ... No such file or directory`

Check the Android linker:

```bash
ssh root@192.168.2.121 '
ROOT=/media/internal/android-usb/android-rootfs
ls -l "$ROOT/system/bin/linker64"
ls -l "$ROOT/apex/com.android.runtime/bin/linker64"
chroot "$ROOT" /system/bin/toybox true && echo TOYBOX_OK || echo TOYBOX_FAIL
'
```

If `/apex/com.android.runtime/bin/linker64` is missing, APEX is not mounted correctly.

### Service managers exit quickly

Check logs:

```bash
ssh root@192.168.2.121 '
LOGDIR=/media/internal/android-usb/android-sidecar/logs
for f in vndservicemanager servicemanager hwservicemanager property_service_ack_shim; do
  echo "### $f"
  cat "$LOGDIR/$f.log" 2>/dev/null || true
done
'
```

### USB mountpoint is wrong

Check that `/media/internal/android-usb` is backed by the USB device:

```bash
ssh root@192.168.2.121 'grep android-usb /proc/mounts && df -h /media/internal/android-usb'
```

Expected:

```text
/dev/sda1 /media/internal/android-usb ext4 ...
```

### Reboot to clear stale mounts

During development, stale loop mounts can make debugging confusing. A reboot clears them:

```bash
ssh root@192.168.2.121 'sync; reboot'
```

Then rerun the installer.

## Development notes

The repository is intentionally minimal, but not yet production-polished.

Keep generated files out of Git:

```text
build/
dist/
*.img
*.zip
```

Use:

```bash
git status
```

before pushing.

## GitHub

Repository:

```text
git@github.com:cfernande1470/webos-android-minimal.git
```

Push to `main`:

```bash
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin git@github.com:cfernande1470/webos-android-minimal.git
git push -u origin main
```

## License

No license has been selected yet.

Add a `LICENSE` file before treating this as a reusable open-source project. MIT is a reasonable default for the shell/C userspace helper portions, but the vendored Linux Binder-derived source follows the kernel licensing constraints indicated by the source/module metadata.
