# AnyKernel3 — ba98de94 Image + cgroup2 early-init (A17)

Jeus Max-style AK3 (`dump_boot` → inject → `write_boot`) for Unisoc **BOOT**
(not init_boot). Primary path — **not** Magisk/TWRP update-binary module.

## Image

- **SHA class:** `ba98de94` (`cgroup_no_v1=…,memory`, UFFD kept)
- Packed Image is the ba98de94-class build (5.4.302-Helix+)
- Do **not** flash Image-only for A17 cgroup fix

## CRITICAL: Image-only wipes the inject

Flashing an Image-only AnyKernel3 (`split_boot` + `flash_boot` only) **replaces
BOOT and drops** `init.cgroup2_early.rc` / import. For A17 always flash **this
full zip**. After any later Image update: **re-flash this zip** (or rebuild with
`./pack.sh` + new Image then flash).

## Flash

1. TWRP / OrangeFox → install `AnyKernel3-ums9230-cgroup2-early-ba98de94.zip`
2. If Magisk: reinstall Magisk after this zip (or flash zip then Magisk)
3. Reboot A17 GSI

## Rebuild zip

```sh
cd packaging/anykernel-cgroup
./pack.sh /path/to/Image   # or Image.xz from ba98de94-class CI
```

## Verify (Jeus A17 smoke)

```sh
dmesg | grep cgroup2_early
ls -la /sys/fs/cgroup/system /sys/fs/cgroup/apps
# expect: no createProcessGroup(1000,0) failed
getprop sys.boot_completed   # expect 1
```

Expect kmsg lines like `cgroup2_early: begin`, `mkdir apps done`, `early-init complete`.
