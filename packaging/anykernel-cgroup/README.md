# cgroup2 early-init + ion chown — BOOT nested ramdisk (Max / bootanimation path)

Same AnyKernel flow as the “Disable Bootanimation” zip:

`split_boot` → `unpack_ramdisk` → patch → `repack_ramdisk` → `flash_boot`

**Not** `init_boot` (empty/zeros on this device).

Injects `init.cgroup2_early.rc` + `cgroup2_early_fix.sh` into:
- ramdisk root
- `system/etc/ramdisk/` (Unisoc nested)
- Magisk `overlay.d/` if present

Also appends `import` lines to any `init*.rc` found.

`init.cgroup2_early.rc` includes DAC belt-and-braces for `/dev/ion` and
`/dev/sprd_ion` (`chown system graphics` / `chmod 0666`) on early-init,
device-added, init, post-fs-data, and boot.

**bpf (default):** enforcing — no `androidboot.selinux=permissive`.
**bpf-a17-selinux-test:** permissive TEST cmdline (see that branch's anykernel.sh).

## Pack (CI / local)

```sh
./pack.sh /path/to/Image [output.zip]
```

## Flash

Flash with ReSukiSU/Magisk AK3 or TWRP on **boot**.

## Verify (A17)

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps /dev/ion /dev/sprd_ion
getprop sys.boot_completed
```
