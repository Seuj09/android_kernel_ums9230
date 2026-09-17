# AK3 cgroup2 early-init (boot ramdisk) — A17

**Primary path** (not Magisk module): flash full AnyKernel3 zip that
`dump_boot` → injects `init.cgroup2_early.rc` + `cgroup2_early_fix.sh` →
`write_boot`, with Image **ba98de94** (`cgroup_no_v1` + memory, UFFD).

Sources: `packaging/anykernel-cgroup/`  
Branch: `bpf-cgroup2-early-a17` (off Seuj `bpf` tip)

## Do not Image-only

Image-only AK3 (`split_boot`/`flash_boot`) **wipes** the ramdisk inject.
Always flash the full cgroup2-early zip for A17; re-flash after Image updates.

## Rebuild

```sh
cd packaging/anykernel-cgroup
./pack.sh /path/to/ba98de94-class-Image.xz
```

## Verify

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
getprop sys.boot_completed
# no createProcessGroup(1000,0) failed in logcat/dmesg
```
