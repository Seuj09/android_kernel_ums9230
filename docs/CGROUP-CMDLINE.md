# A16/A17 cgroup cmdline (bpf) — flash + verify

## Status

- Tip: `7d1d31113c51` on `bpf`
- Build: https://github.com/Seuj09/android_kernel_ums9230/actions/runs/34955877246
- Artifact: `kernel-Image-7d1d31113c518b1b5ade469b9e5b7d117eaa9bbe`
- UFFD P0 (`vm_userfaultfd_ctx` set/clear) remains in tree; do not reopen Block A.

## What changed in the Image (defconfig)

`unisoc_defconfig` still uses `CONFIG_CMDLINE_EXTEND=y` (not FORCE). Built-in string is now:

```text
cgroup_disable=pressure,net_prio cgroup_no_v1=cpu,cpuset
```

Removed from disable list: `memory`, `io`, `cpuacct`.

## Why Magisk / boot.img still matters

EXTEND **concatenates** bootloader/`boot.img` cmdline with the built-in string.
`cgroup_disable=` is cumulative: if Magisk/stock header still has
`cgroup_disable=pressure,memory,io,cpuacct,net_prio`, then **memory/io stay off**
even with the new Image.

So when packing/flashing this Image into boot:

1. Prefer AnyKernel `patch_cmdline` (see `packaging/anykernel-cgroup/`).
2. Or Magisk unpack → edit header cmdline → repack (same edits).

Target boot.img cmdline field:

- Replace any `cgroup_disable=…` with `cgroup_disable=pressure,net_prio`
- Ensure `cgroup_no_v1=cpu,cpuset` is present (add if missing)
- Do **not** use `cgroup_disable=all`
- Do **not** strip DTS/androidboot.* tokens

## Flash (Jeus)

1. Download artifact `kernel-Image-7d1d311…` from the Actions run above; decompress to `Image`.
2. Flash via AnyKernel zip built from `packaging/anykernel-cgroup` (patches cmdline + installs Image), **or** Magisk Install → Select and Patch a File after manually fixing cmdline on a working boot.img and then replacing the kernel payload.
3. Reboot A17 (and smoke A13 on the other slot / backup Image if dual-boot testing).

## Verify after boot

```sh
# memory/io must NOT be disabled
grep cgroup /proc/cmdline
# expect: cgroup_disable=pressure,net_prio  and  cgroup_no_v1=cpu,cpuset
# must NOT list memory or io in cgroup_disable=

cat /proc/cgroups
# memory and io rows: enabled == 1

ls /sys/fs/cgroup/system 2>/dev/null || ls /sys/fs/cgroup
# unified hierarchy should exist; uid_* / system trees OK for GSI

getprop sys.boot_completed   # expect 1
logcat -d | grep -E 'createProcessGroup|libprocessgroup|netd' | tail -40
# no createProcessGroup ENOENT / netd cgroup attach EBADF loops
```

A13 smoke: boot stock-ish A13 once; watch for memcg/perf regressions. If A13 needs legacy memcg off, use Magisk-only cmdline for the A17 slot rather than FORCE.

## Out of scope

- UFFD / Block A DONTUNMAP
- `CONFIG_CMDLINE_FORCE=y` (only if EXTEND + clean boot.img still fails)
