# A16/A17 cgroup cmdline (bpf) — flash + verify

## Status

- Defconfig tip: `7d1d31113c51` on `bpf`
- Build (use this Image): https://github.com/Seuj09/android_kernel_ums9230/actions/runs/34955877246
- **Artifact name:** `kernel-Image-7d1d31113c518b1b5ade469b9e5b7d117eaa9bbe` (~13.1 MiB xz)
- Docs/AnyKernel helper tip: `385f78d` — optional packaging only
- UFFD P0 remains in tree; do not reopen Block A

## What changed in the Image (defconfig)

`unisoc_defconfig` keeps `CONFIG_CMDLINE_EXTEND=y` (not FORCE). Built-in string is now:

```text
cgroup_disable=pressure,net_prio cgroup_no_v1=cpu,cpuset
```

Removed from disable list: `memory`, `io`, `cpuacct`.

On Jeus’s device the bad `cgroup_disable=…memory,io…` came from the **old built-in CONFIG_CMDLINE**, not the boot.img header. Flashing this Image alone is enough for the primary fix.

## Flash order (Jeus) — primary

1. Download artifact **`kernel-Image-7d1d31113c518b1b5ade469b9e5b7d117eaa9bbe`** from run [34955877246](https://github.com/Seuj09/android_kernel_ums9230/actions/runs/34955877246).
2. Decompress: `xz -d -k kernel-Image-….xz` → `Image` (or whatever the artifact expands to).
3. Keep a **backup** of the current boot/Image (A13 risk below).
4. Flash with your usual AnyKernel / Magisk kernel install that **only replaces the kernel payload** (no need to rewrite cmdline unless step 6 applies).
5. Reboot A17 GSI.
6. **Optional Magisk/boot.img strip:** after boot, `grep cgroup_disable /proc/cmdline`. If the bootloader/header still contributes `memory` or `io` in `cgroup_disable=`, then use `packaging/anykernel-cgroup/` (`patch_cmdline`) or Magisk unpack/edit/repack. Otherwise skip.

## Optional AnyKernel zip (only if header also bad)

1. Start from AnyKernel3 tree with `tools/` (e.g. ak3_541).
2. Copy `packaging/anykernel-cgroup/anykernel.sh` over `anykernel.sh`.
3. Place the decompressed `Image` from the artifact in the AK3 root.
4. Zip → flash in Magisk/recovery. Installer runs `patch_cmdline` then `flash_boot`.

## Verify after boot

```sh
grep cgroup /proc/cmdline
# expect built-in: cgroup_disable=pressure,net_prio  and  cgroup_no_v1=cpu,cpuset
# must NOT list memory or io in cgroup_disable=

cat /proc/cgroups
# memory and io rows: enabled == 1

ls /sys/fs/cgroup/system 2>/dev/null || ls /sys/fs/cgroup
getprop sys.boot_completed   # expect 1
logcat -d | grep -E 'createProcessGroup|libprocessgroup|netd' | tail -40
# no createProcessGroup ENOENT / netd cgroup attach EBADF loops
```

## A13 risk

`cgroup_no_v1=cpu,cpuset` can break vendor A13 paths that still expect legacy `/dev/cpuset` / `/dev/cpuctl`. Keep a backup Image; smoke A13 once after the A17 check. If A13 regresses, prefer slot/backup restore over FORCE.

## Out of scope

- UFFD / Block A DONTUNMAP
- `CONFIG_CMDLINE_FORCE=y` (only if Image + optional header clean still fails)
- `cgroup_disable=all`
