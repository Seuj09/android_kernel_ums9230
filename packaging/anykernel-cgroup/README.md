# AnyKernel3 — ba98de94 Image + cgroup2 early-init (A17)

## Layout

| Partition | What this zip writes |
|-----------|----------------------|
| **boot** `_a`/`_b` | Kernel Image only (`split_boot`/`flash_boot`) |
| **init_boot** `_a`/`_b` | `init.cgroup2_early.rc` + import (when partition exists) |

GSI devices often have **no `init.rc` on boot** — inject goes to **init_boot**.
Installer prints which slot (`_a`/`_b`) and which partition was patched, then
re-dumps to prove `cgroup2_early` is present.

## Flash

1. Re-download the zip (do not use an old copy).
2. TWRP/OrangeFox → install on the **active** slot.
3. Confirm recovery can write `init_boot` (not only `boot`).
4. If Magisk/ReSukiSU rewrote `init_boot`, flash Magisk first, then this zip.

## Verify after reboot (A17)

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
```
