### AnyKernel3 — ba98de94 Image + boot ramdisk cgroup2 early-init
## osm0sis @ xda-developers / Seuj09 ums9230

properties() { '
kernel.string=ums9230 bpf ba98de94 + cgroup2 early-init rc
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

dump_boot

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"
ui_print "- inject init.cgroup2_early.rc + cgroup2_early_fix.sh"

[ -f $home/ramdisk/init.cgroup2_early.rc ] && cp -f $home/ramdisk/init.cgroup2_early.rc $ramdisk/init.cgroup2_early.rc
[ -f $home/ramdisk/cgroup2_early_fix.sh ] && cp -f $home/ramdisk/cgroup2_early_fix.sh $ramdisk/cgroup2_early_fix.sh
chmod 755 $ramdisk/cgroup2_early_fix.sh 2>/dev/null || true
chmod 644 $ramdisk/init.cgroup2_early.rc 2>/dev/null || true

if [ -f $ramdisk/init.rc ]; then
  backup_file $ramdisk/init.rc
  if grep -q "init.cgroup2_early.rc" $ramdisk/init.rc; then
    ui_print "- import already present"
  else
    if grep -q "import /init.environ.rc" $ramdisk/init.rc; then
      insert_line $ramdisk/init.rc "init.cgroup2_early.rc" after "import /init.environ.rc" "import /init.cgroup2_early.rc"
    elif grep -q "^import " $ramdisk/init.rc; then
      insert_line $ramdisk/init.rc "init.cgroup2_early.rc" after "^import " "import /init.cgroup2_early.rc"
    else
      echo "import /init.cgroup2_early.rc" >> $ramdisk/init.rc
    fi
    ui_print "- added import /init.cgroup2_early.rc"
  fi
else
  ui_print "WARNING: no init.rc in boot ramdisk"
fi

patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"

ui_print "- write_boot"
write_boot
