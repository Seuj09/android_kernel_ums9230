# anykernel-cgroup (ums9230 bpf)

1. Copy this folder’s `anykernel.sh` over a stock AnyKernel3 tree (e.g. tools from `ak3_541`).
2. Place decompressed CI `Image` (from Actions artifact `kernel-Image-7d1d311…`) in the AK3 root.
3. Zip and flash in Magisk / recovery.
4. On install, `patch_cmdline` rewrites the **boot.img** header so Magisk/stock
   `cgroup_disable=…memory,io…` cannot undo the kernel EXTEND string.

See `docs/CGROUP-CMDLINE.md`.
