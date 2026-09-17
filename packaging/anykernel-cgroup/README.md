# AnyKernel3 — ba98de94 Image + cgroup2 early-init (A17)

## Why init_boot

On GSI / modern Unisoc layouts, **BOOT** often has the kernel only (no
`init.rc` in its ramdisk). The generic ramdisk with `init.rc` lives on
**`init_boot`**. This zip:

1. `split_boot` + `flash_boot` → Image onto **boot**
2. `dump_boot` + inject + `write_boot` → early-init onto **init_boot**
   (falls back to boot only if `init_boot` is missing and boot has `init.rc`)

## Flash

TWRP/OrangeFox → install this zip. Re-flash after Magisk if Magisk rewrites
init_boot.

## Verify (A17)

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
```
