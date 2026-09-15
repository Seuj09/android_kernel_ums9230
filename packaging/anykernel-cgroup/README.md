# AnyKernel3 — cgroup2 early-init (boot ramdisk)

Replaces Magisk/ReSukiSU module path. Injects `init.cgroup2_early.rc` into **BOOT**
ramdisk (Unisoc, not init_boot) and flashes Image `ba98de94`.

## Zip

`AnyKernel3-ums9230-cgroup2-early-ba98de94.zip`

## Flash (Jeus)

1. Flash zip in TWRP (or any AK3-compatible installer).
2. Reboots with new Image + ramdisk early-init.
3. No Magisk module step.

## Verify

```sh
ls -ld /sys/fs/cgroup/apps /sys/fs/cgroup/system
cat /sys/fs/cgroup/cgroup.subtree_control
getprop sys.boot_completed
logcat -d | grep -E 'createProcessGroup|cgroup2_early|ActivateControllers' | tail -40
```

No further cgroup_no_v1 / UFFD. If ActivateControllers EBUSY → cgroups.json overlay next.
