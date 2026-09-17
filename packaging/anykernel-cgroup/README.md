# AnyKernel3 — ba98de94 Image + cgroup2 early-init (A17)

## What it does

1. **boot$SLOT** — `split_boot`/`flash_boot` kernel Image (+ cmdline hygiene)
2. **init_boot$SLOT** — dump to **`init_boot.img`** (not leftover `boot.img`),
   `magiskboot unpack` → inject `init.cgroup2_early.rc` → repack → write back,
   then re-dump prove.

GSI: `init.rc` lives on **init_boot**, not boot.

## Flash (ReSukiSU / Magisk AK3 or TWRP)

Re-download zip. If Magisk owns init_boot, flash Magisk first, then this zip.
Boot Image can already be on device; zip still re-flashes Image then patches init_boot.

## Verify

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
```
