# cgroup2 early-init — BOOT nested ramdisk (Max / bootanimation path)

Same AnyKernel flow as the “Disable Bootanimation” zip:

`split_boot` → `unpack_ramdisk` → patch → `repack_ramdisk` → `flash_boot`

**Not** `init_boot` (empty/zeros on this device).

Injects `init.cgroup2_early.rc` + `cgroup2_early_fix.sh` into:
- ramdisk root
- `system/etc/ramdisk/` (Unisoc nested)
- Magisk `overlay.d/` if present

Also appends `import` lines to any `init*.rc` found.

## Flash

Re-download zip. Flash with ReSukiSU/Magisk AK3 or TWRP on **boot**.

## Verify (A17)

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
```
