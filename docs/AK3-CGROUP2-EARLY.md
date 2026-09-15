# AK3 cgroup2 early-init (boot ramdisk)

**Primary path** (replaces Magisk/ReSukiSU module): flash AnyKernel3 zip that injects
`init.cgroup2_early.rc` into BOOT ramdisk + Image `ba98de94`.

Sources: `packaging/anykernel-cgroup/`

Rebuild zip:
```sh
cd packaging/anykernel-cgroup
./pack.sh /path/to/kernel-Image-ba98de94….xz
```

Release asset (when published): `AnyKernel3-ums9230-cgroup2-early-ba98de94.zip`
