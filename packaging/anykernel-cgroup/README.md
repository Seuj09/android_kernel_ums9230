# AnyKernel3 — cgroup2 early-init → init_boot (A17)

Hardened `magiskboot unpack` of device `init_boot` (exit code, 64-byte hex,
Magisk 30.7 + 31.0 fallbacks). `skip_boot_image` = do **not** rewrite boot
(Image already flashed).

If unpack still fails: paste installer log and
`adb pull /dev/block/by-name/init_boot_a init_boot_a.img` (or `_b`).
