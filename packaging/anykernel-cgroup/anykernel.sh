### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09 ums9230: dump_boot/write_boot cgroup2 early-init (A17).
## Image = ba98de94 (cgroup_no_v1+memory). Inject sources live in cgroup2/ (NOT zip ramdisk/).

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

# Sources must NOT live under zip ramdisk/ — dump_boot moves that dir to rdtmp.
SRC=$AKHOME/cgroup2
if [ ! -f "$SRC/init.cgroup2_early.rc" ]; then
  ui_print "ERROR: missing cgroup2/init.cgroup2_early.rc in zip"
  abort "cgroup2 early-init rc missing"
fi
if [ ! -f "$SRC/cgroup2_early_fix.sh" ]; then
  ui_print "ERROR: missing cgroup2/cgroup2_early_fix.sh in zip"
  abort "cgroup2 early-init fix.sh missing"
fi

dump_boot

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"
ui_print "- cgroup2 early-init: inject into unpacked BOOT ramdisk"

if [ ! -d "$RAMDISK" ]; then
  ui_print "ERROR: dump_boot left no \$RAMDISK dir"
  abort "no unpacked ramdisk"
fi
if [ ! -f "$RAMDISK/init.rc" ]; then
  ui_print "ERROR: no init.rc in BOOT ramdisk — device may use init_boot"
  abort "no init.rc in boot ramdisk"
fi

cp -f "$SRC/init.cgroup2_early.rc" "$RAMDISK/init.cgroup2_early.rc"
cp -f "$SRC/cgroup2_early_fix.sh" "$RAMDISK/cgroup2_early_fix.sh"
chmod 755 "$RAMDISK/cgroup2_early_fix.sh"
chmod 644 "$RAMDISK/init.cgroup2_early.rc"

if [ ! -f "$RAMDISK/init.cgroup2_early.rc" ] || [ ! -f "$RAMDISK/cgroup2_early_fix.sh" ]; then
  ui_print "ERROR: inject copy into ramdisk failed"
  abort "cgroup2 inject copy failed"
fi
ui_print "- inject files present in ramdisk"

backup_file "$RAMDISK/init.rc"
if ! grep -q "init.cgroup2_early.rc" "$RAMDISK/init.rc"; then
  if grep -q "import /init.environ.rc" "$RAMDISK/init.rc"; then
    insert_line "$RAMDISK/init.rc" "init.cgroup2_early.rc" after "import /init.environ.rc" "import /init.cgroup2_early.rc"
  elif grep -q "^import " "$RAMDISK/init.rc"; then
    insert_line "$RAMDISK/init.rc" "init.cgroup2_early.rc" after "^import " "import /init.cgroup2_early.rc"
  else
    echo "import /init.cgroup2_early.rc" >> "$RAMDISK/init.rc"
  fi
fi
if grep -q "init.cgroup2_early.rc" "$RAMDISK/init.rc"; then
  ui_print "- verified import /init.cgroup2_early.rc in init.rc"
else
  ui_print "ERROR: import line missing after insert"
  abort "cgroup2 import verify failed"
fi

# Match ba98de94 cmdline hygiene (do NOT add quiet/mute_console/nowatchdog here)
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"

ui_print "- write_boot (Image + injected ramdisk)"
write_boot

## End boot install
