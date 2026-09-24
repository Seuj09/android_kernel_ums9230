# cgroup2 + ion + selinux=permissive TEST (bpf-a17-selinux-test)

Diagnostic AnyKernel3 for A17 GSI stuck at logo (ION / SurfaceFlinger theory).

Same BOOT nested Unisoc ramdisk inject as bpf, plus:
- `patch_cmdline androidboot.selinux=permissive` on boot header
- bootconfig append/update if present
- vendor_boot cmdline/bootconfig if that partition exists

Ion DAC chown/chmod triggers match bpf enforcing.

## Caveats
User builds may ignore `androidboot.selinux`. This branch is TEST-only;
keep `bpf` for day-to-day enforcing flashes.
