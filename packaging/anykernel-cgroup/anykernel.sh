### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09 ums9230: Image on boot + cgroup2 early-init on init_boot (GSI).
## Boot ramdisk often has NO init.rc — inject must target init_boot.

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 Max + cgroup2 early-init A17 (ba98de94 / init_boot)
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

## —— 1) BOOT: flash kernel Image only ——
block=boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto

. tools/ak3-core.sh

SRC=$AKHOME/cgroup2
if [ ! -f "$SRC/init.cgroup2_early.rc" ] || [ ! -f "$SRC/cgroup2_early_fix.sh" ]; then
  ui_print "ERROR: missing cgroup2/ inject sources in zip"
  abort "cgroup2 inject sources missing"
fi

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"
ui_print "- boot: split_boot + flash_boot (Image)"

split_boot
# ba98de94-class cmdline hygiene on boot header (built-in CMDLINE also has this)
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"
flash_boot

## —— 2) INIT_BOOT (or BOOT fallback): inject early-init ——
cgroup2_inject() {
  ui_print "- inject init.cgroup2_early.rc + fix.sh into $1 ramdisk"

  if [ ! -d "$RAMDISK" ]; then
    ui_print "ERROR: no unpacked ramdisk dir after dump_boot ($1)"
    abort "no unpacked ramdisk"
  fi
  if [ ! -f "$RAMDISK/init.rc" ]; then
    ui_print "ERROR: no init.rc in $1 ramdisk"
    return 1
  fi

  cp -f "$SRC/init.cgroup2_early.rc" "$RAMDISK/init.cgroup2_early.rc"
  cp -f "$SRC/cgroup2_early_fix.sh" "$RAMDISK/cgroup2_early_fix.sh"
  chmod 755 "$RAMDISK/cgroup2_early_fix.sh"
  chmod 644 "$RAMDISK/init.cgroup2_early.rc"

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
  if ! grep -q "init.cgroup2_early.rc" "$RAMDISK/init.rc"; then
    ui_print "ERROR: import line missing after insert ($1)"
    abort "cgroup2 import verify failed"
  fi
  ui_print "- verified import on $1"
  write_boot
  return 0
}

# Prefer init_boot when the partition exists (GSI / hdr v3+)
if [ -e "/dev/block/by-name/init_boot$SLOT" ] || [ -e "/dev/block/bootdevice/by-name/init_boot$SLOT" ]; then
  ui_print "- init_boot$SLOT present — injecting there (boot has no init.rc)"
  block=init_boot
  is_slot_device=1
  ramdisk_compression=auto
  patch_vbmeta_flag=auto
  reset_ak
  dump_boot
  cgroup2_inject init_boot || abort "init_boot inject failed"
else
  ui_print "- no init_boot partition — trying BOOT ramdisk inject"
  block=boot
  is_slot_device=1
  ramdisk_compression=auto
  patch_vbmeta_flag=auto
  reset_ak
  dump_boot
  if [ -f "$RAMDISK/init.rc" ]; then
    cgroup2_inject boot || abort "boot inject failed"
  else
    ui_print "ERROR: boot ramdisk has no init.rc and no init_boot partition"
    ui_print "Cannot install cgroup2 early-init on this layout"
    abort "no init.rc target (boot/init_boot)"
  fi
fi

ui_print "- done (Image on boot + cgroup2 early-init on ramdisk partition)"

## End install
