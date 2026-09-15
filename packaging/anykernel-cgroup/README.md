# AnyKernel3 (Jeus every-build template) + cgroup2 early-init

Based on Jeus’s usual Max Kernel AK3 zip (`split_boot`/`flash_boot`), with the
only behavioral change required for cgroup2: **`dump_boot` → inject rc → `write_boot`**
so BOOT ramdisk gets `init.cgroup2_early.rc`. Still patches **boot** (Unisoc), not init_boot.

## Flash

1. Put `Image` (ba98de94) in this folder if rebuilding: `./pack.sh Image.xz`
2. Flash `AnyKernel3-ums9230-cgroup2-early-ba98de94.zip` in TWRP like any other AK3.
3. Reboot A17.

## Verify

```sh
ls -ld /sys/fs/cgroup/apps /sys/fs/cgroup/system
cat /sys/fs/cgroup/cgroup.subtree_control
getprop sys.boot_completed
logcat -d | grep createProcessGroup | tail -20
```
