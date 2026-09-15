# anykernel-cgroup (ums9230 bpf) — optional

Primary fix is flashing Image from `7d1d311` (artifact
`kernel-Image-7d1d31113c518b1b5ade469b9e5b7d117eaa9bbe`).

Use this zip **only if** after that flash `/proc/cmdline` still shows
`memory` or `io` inside a bootloader-sourced `cgroup_disable=`.

1. Copy `anykernel.sh` into an AnyKernel3 tree (tools from ak3_541).
2. Place decompressed CI `Image` in the AK3 root.
3. Zip and flash — `patch_cmdline` rewrites the boot.img header.

See `docs/CGROUP-CMDLINE.md`.
