### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09 ums9230: Jeus Max-style AK3 + dump_boot/write_boot cgroup2 early-init.
## Image = ba98de94 (cgroup_no_v1+memory). NOT Image-only — inject lives in BOOT ramdisk.

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 Max + cgroup2 early-init A17 (ba98de94)
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
'; } # end properties

### AnyKernel install

BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

. tools/ak3-core.sh

## Start boot install — dump_boot required (split_boot/flash_boot alone WIPES inject)

dump_boot

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"
ui_print "- cgroup2 early-init: inject init.cgroup2_early.rc + fix.sh"

# Require inject sources in zip
if [ ! -f $home/ramdisk/init.cgroup2_early.rc ]; then
  ui_print "ERROR: missing ramdisk/init.cgroup2_early.rc in zip"
  abort "cgroup2 early-init rc missing"
fi
if [ ! -f $home/ramdisk/cgroup2_early_fix.sh ]; then
  ui_print "ERROR: missing ramdisk/cgroup2_early_fix.sh in zip"
  abort "cgroup2 early-init fix.sh missing"
fi

cp -f $home/ramdisk/init.cgroup2_early.rc $ramdisk/init.cgroup2_early.rc
cp -f $home/ramdisk/cgroup2_early_fix.sh $ramdisk/cgroup2_early_fix.sh
chmod 755 $ramdisk/cgroup2_early_fix.sh
chmod 644 $ramdisk/init.cgroup2_early.rc

# Verify copies landed in unpacked BOOT ramdisk
if [ ! -f $ramdisk/init.cgroup2_early.rc ] || [ ! -f $ramdisk/cgroup2_early_fix.sh ]; then
  ui_print "ERROR: inject copy into ramdisk failed"
  abort "cgroup2 inject copy failed"
fi
ui_print "- inject files present in ramdisk"

if [ -f $ramdisk/init.rc ]; then
  backup_file $ramdisk/init.rc
  if ! grep -q "init.cgroup2_early.rc" $ramdisk/init.rc; then
    if grep -q "import /init.environ.rc" $ramdisk/init.rc; then
      insert_line $ramdisk/init.rc "init.cgroup2_early.rc" after "import /init.environ.rc" "import /init.cgroup2_early.rc"
    elif grep -q "^import " $ramdisk/init.rc; then
      insert_line $ramdisk/init.rc "init.cgroup2_early.rc" after "^import " "import /init.cgroup2_early.rc"
    else
      echo "import /init.cgroup2_early.rc" >> $ramdisk/init.rc
    fi
  fi
  if grep -q "init.cgroup2_early.rc" $ramdisk/init.rc; then
    ui_print "- verified import /init.cgroup2_early.rc in init.rc"
  else
    ui_print "ERROR: import line missing after insert"
    abort "cgroup2 import verify failed"
  fi
else
  ui_print "ERROR: no init.rc in BOOT ramdisk — cannot inject"
  abort "no init.rc in boot ramdisk"
fi

# Match ba98de94 cmdline hygiene (do NOT add quiet/mute_console/nowatchdog here)
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"

ui_print "- write_boot (Image + injected ramdisk)"
write_boot

## End boot install
