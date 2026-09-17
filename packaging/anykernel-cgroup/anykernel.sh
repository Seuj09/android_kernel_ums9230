### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09 ums9230: Image → boot; cgroup2 early-init → init_boot (GSI).
## BOOT ramdisk often has NO init.rc — detect and patch the partition that does.

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
PATCHED_PART=""

if [ ! -f "$SRC/init.cgroup2_early.rc" ] || [ ! -f "$SRC/cgroup2_early_fix.sh" ]; then
  ui_print "ERROR: missing cgroup2/ inject sources in zip"
  abort "cgroup2 inject sources missing"
fi

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"
ui_print "- slot=$SLOT"
ui_print "- boot$SLOT: split_boot + flash_boot (Image only)"

split_boot
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"
flash_boot
ui_print "- boot$SLOT: Image written"

## —— helpers ——
has_init_boot() {
  [ -e "/dev/block/by-name/init_boot$SLOT" ] || [ -e "/dev/block/bootdevice/by-name/init_boot$SLOT" ]
}

ramdisk_has_init_rc() {
  [ -f "$RAMDISK/init.rc" ] || ls "$RAMDISK"/init*.rc >/dev/null 2>&1
}

cgroup2_inject() {
  local target=$1
  ui_print "- patching ramdisk on partition: $target$SLOT"

  if [ ! -d "$RAMDISK" ]; then
    ui_print "ERROR: no unpacked ramdisk after dump_boot ($target$SLOT)"
    abort "no unpacked ramdisk ($target$SLOT)"
  fi
  if ! ramdisk_has_init_rc; then
    ui_print "ERROR: no init.rc (or init*.rc) in $target$SLOT ramdisk"
    return 1
  fi
  # Prefer classic init.rc as import root
  if [ ! -f "$RAMDISK/init.rc" ]; then
    ui_print "ERROR: found init*.rc but no init.rc on $target$SLOT — cannot import safely"
    return 1
  fi

  cp -f "$SRC/init.cgroup2_early.rc" "$RAMDISK/init.cgroup2_early.rc"
  cp -f "$SRC/cgroup2_early_fix.sh" "$RAMDISK/cgroup2_early_fix.sh"
  chmod 755 "$RAMDISK/cgroup2_early_fix.sh"
  chmod 644 "$RAMDISK/init.cgroup2_early.rc"

  if [ ! -f "$RAMDISK/init.cgroup2_early.rc" ] || [ ! -f "$RAMDISK/cgroup2_early_fix.sh" ]; then
    ui_print "ERROR: inject copy failed on $target$SLOT"
    abort "cgroup2 inject copy failed ($target$SLOT)"
  fi

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
    ui_print "ERROR: import line missing in init.rc on $target$SLOT"
    abort "cgroup2 import verify failed ($target$SLOT)"
  fi
  ui_print "- OK: init.cgroup2_early.rc + import present in $target$SLOT init.rc"

  write_boot
  ui_print "- OK: wrote $target$SLOT"

  # Prove: re-dump same partition and grep (recovery-visible)
  ui_print "- prove: re-dump $target$SLOT and grep cgroup2_early"
  block=$target
  is_slot_device=1
  ramdisk_compression=auto
  patch_vbmeta_flag=auto
  reset_ak
  dump_boot
  if grep -q "cgroup2_early" "$RAMDISK/init.rc" 2>/dev/null && [ -f "$RAMDISK/init.cgroup2_early.rc" ]; then
    ui_print "- PROVE OK: cgroup2_early found in $target$SLOT ramdisk"
    PATCHED_PART="$target$SLOT"
  else
    ui_print "ERROR: prove failed — cgroup2_early not in re-dumped $target$SLOT"
    abort "post-write prove failed ($target$SLOT)"
  fi
  return 0
}

setup_target() {
  block=$1
  is_slot_device=1
  ramdisk_compression=auto
  patch_vbmeta_flag=auto
  reset_ak
}

## —— 2) Detect which ramdisk has init.rc ——
# Prefer init_boot when present (GSI). Else try boot.
if has_init_boot; then
  ui_print "- detected init_boot$SLOT — will inject there (boot is Image-only)"
  setup_target init_boot
  dump_boot
  if ramdisk_has_init_rc; then
    cgroup2_inject init_boot || abort "init_boot$SLOT inject failed"
  else
    ui_print "ERROR: init_boot$SLOT has no init.rc either"
    abort "init_boot$SLOT missing init.rc"
  fi
else
  ui_print "- no init_boot$SLOT — probing boot$SLOT ramdisk"
  setup_target boot
  dump_boot
  if ramdisk_has_init_rc; then
    cgroup2_inject boot || abort "boot$SLOT inject failed"
  else
    ui_print "ERROR: boot$SLOT ramdisk has no init.rc and no init_boot partition"
    ui_print "Cannot install cgroup2 early-init on this layout"
    abort "no init.rc target (boot/init_boot)"
  fi
fi

ui_print " "
ui_print "=== cgroup2 early-init DONE ==="
ui_print "=== Image: boot$SLOT | ramdisk inject: $PATCHED_PART ==="
ui_print " "

## End install
