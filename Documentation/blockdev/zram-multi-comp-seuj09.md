# ZRAM multi-compression (Seuj09 / ums9230)

## Why

Primary compressor stays **lz4kd** (fast, good enough for hot pages).
With `CONFIG_ZRAM_MULTI_COMP`, idle and/or huge pages can be **recompressed**
with a slower but denser algorithm (typically **zstd**) to shrink zsmalloc
usage without paying zstd on every swap-in/out of hot pages.

`CONFIG_ZRAM_MEMORY_TRACKING` is enabled because idle recompression depends
on idle page marking / access-time tracking (`/sys/kernel/debug/zram/zramX/block_state`
and the `idle` sysfs knob).

## Defconfig

- `CONFIG_ZRAM=y`
- `CONFIG_ZRAM_DEF_COMP_LZ4KD=y` / `CONFIG_ZRAM_DEF_COMP="lz4kd"`
- `CONFIG_ZRAM_MULTI_COMP=y`
- `CONFIG_ZRAM_MEMORY_TRACKING=y`
- `CONFIG_ZRAM_WRITEBACK=y`
- HybridSwap (`CONFIG_HYBRIDSWAP*`) preserved; multi-comp is wired into both
  the built-in `drivers/block/zram/zram_drv.c` (Image) and the HybridSwap
  `hyb` module copy under `drivers/block/zram/hybridswap/`.

There is no `ZRAM_DEF_RECOMP_*` Kconfig on this tree; set the secondary
algorithm via sysfs after boot (or from `mmd` / init.rc).

## Sysfs setup examples

```sh
# Secondary (recompress) algorithm at priority 1
echo "algo=zstd priority=1" > /sys/block/zram0/recomp_algorithm

# Optional: more secondaries at priority 2/3
# echo "algo=lz4hc priority=2" > /sys/block/zram0/recomp_algorithm

# Mark cold pages idle, then recompress them
echo all > /sys/block/zram0/idle
echo "type=idle" > /sys/block/zram0/recompress

# Or only pages the primary failed to compress (huge)
echo "type=huge algo=zstd" > /sys/block/zram0/recompress

# Idle or huge, with a minimum compressed size threshold (bytes)
echo "type=huge_idle threshold=3000" > /sys/block/zram0/recompress
```

Verify:

```sh
cat /sys/block/zram0/comp_algorithm      # primary, should highlight lz4kd
cat /sys/block/zram0/recomp_algorithm    # secondary list
# debugfs (MEMORY_TRACKING): look for 'r' (recompressed) / 'n' (incompressible)
cat /sys/kernel/debug/zram/zram0/block_state | head
```

## Userspace / AOSP mmd

On AOSP, **mmd** (or similar memory daemons) typically drives idle/huge
recompress via these sysfs nodes. Without mmd, userspace must manually
`echo idle/huge` into `/sys/block/zram0/recompress` (after configuring
`recomp_algorithm`).

## HybridSwap notes

- CI / AnyKernel builds **Image** only: the active in-kernel zram is
  `drivers/block/zram/zram_drv.c` (built-in).
- FreeYond HybridSwap also builds `drivers/block/zram/hybridswap/` as
  module `hyb.ko` (own zram_drv + hybridswapd). MULTI_COMP was ported
  there too so hooks (`hybridswap_track` / `untrack` / writeback) stay
  intact if `hyb` is packaged/loaded.
- Do not load `hyb.ko` on top of built-in zram without a packaging change;
  both register the `"zram"` blkdev.

## Upstream donor

Sergey Senozhatsky multi-stream series (Linux 6.2 era) /
android15-6.6 `drivers/block/zram`, adapted for Android 5.4 APIs
(`zs_malloc` returns 0 on failure; dedup `zram_entry_*` on the built-in path).
