# cgroup2 early-init — boot nested + vendor_boot probe

Jeus survey: **init_boot = zeros (dead)**. **boot** has ANDROID! + nested
ramdisk. **vendor_boot** is live VNDRBOOT 100MB.

1. Primary: Max/bootanimation path on **boot** (`split_boot` /
   `unpack_ramdisk` / inject `system/etc/ramdisk/` / `flash_boot`)
2. Secondary: probe **vendor_boot** for `init.rc` / first_stage; inject only
   if found (non-fatal if unpack fails)
3. Never touch **init_boot**

## Verify (A17)

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
```
