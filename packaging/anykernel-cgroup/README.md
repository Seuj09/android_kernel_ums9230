# cgroup2 early-init (probe boot / vendor_boot)

On this Unisoc/GSI device **init_boot can be 8MB of zeros** — not usable.
This zip skips empty init_boot and injects into the first of
`vendor_boot` / `boot` that magiskboot-unpacks **and** contains `init.rc`.

`skip_boot_image` = do not rewrite kernel Image.

If installer aborts with no target, paste:
```sh
ls -l /dev/block/by-name/
find /system /system_ext /vendor /odm /product -name 'init.rc' 2>/dev/null | head
```
