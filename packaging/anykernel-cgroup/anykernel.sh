### AnyKernel3 — bpf Image + A17-safe cgroup cmdline
## osm0sis @ xda-developers / Seuj09 ums9230

properties() { '
kernel.string=ums9230 bpf 5.4 + cgroup2 (memory/io free)
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

. tools/ak3-core.sh

## Boot install
split_boot

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"

# Cumulative cgroup_disable from Magisk/stock must not re-kill memory/io/cpuacct.
# Align boot.img field with unisoc_defconfig EXTEND string on bpf @ 7d1d311.
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset"

ui_print "- patched boot cmdline: cgroup_disable=pressure,net_prio cgroup_no_v1=cpu,cpuset"

flash_boot
## End boot install
