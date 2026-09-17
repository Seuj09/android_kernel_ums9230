# AnyKernel3 — ba98de94 Image + cgroup2 early-init (A17)

`dump_boot` → inject → `write_boot` for Unisoc **BOOT** (not init_boot).

Inject sources live in zip `cgroup2/` (not `ramdisk/`) so AK3 unpack does not
eat them. Uses `$AKHOME` / `$RAMDISK` (not legacy `$home` / `$ramdisk`).

## CRITICAL: Image-only wipes the inject

Do **not** flash Image-only after this for A17. Re-flash this full zip after any
Image update.

## Flash

1. TWRP / OrangeFox → install this zip on **boot**
2. Reboot A17 GSI

## Verify

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
```
