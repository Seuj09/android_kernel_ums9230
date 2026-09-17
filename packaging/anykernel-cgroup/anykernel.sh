### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09: Image → boot; cgroup2 early-init → init_boot via explicit init_boot.img
## (do NOT reuse boot.img after flash_boot — magiskboot unpack must target init_boot dump)

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 Max + cgroup2 early-init A17 (init_boot.img)
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

block=boot
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto

. tools/ak3-core.sh

SRC=$AKHOME/cgroup2
MB=$AKHOME/tools/magiskboot
PATCHED_PART=""

[ -f "$SRC/init.cgroup2_early.rc" ] && [ -f "$SRC/cgroup2_early_fix.sh" ] || abort "cgroup2 inject sources missing"
[ -x "$MB" ] || chmod 755 "$MB"

ui_print "- $(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"
ui_print "- slot=$SLOT"

## 1) Kernel Image → boot$SLOT only
ui_print "- boot$SLOT: Image via split_boot/flash_boot"
split_boot
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"
flash_boot
ui_print "- boot$SLOT: Image written OK"

find_init_boot() {
  ls /dev/block/by-name/init_boot$SLOT /dev/block/bootdevice/by-name/init_boot$SLOT 2>/dev/null | head -1
}

## 2) Explicit init_boot.img path (never reuse leftover boot.img)
inject_init_boot_explicit() {
  local ib work img out rd
  ib=$(find_init_boot)
  if [ -z "$ib" ]; then
    ui_print "ERROR: init_boot$SLOT block device not found"
    abort "no init_boot$SLOT"
  fi
  ui_print "- init_boot device: $ib"

  work=$AKHOME/ibwork
  img=$AKHOME/init_boot.img
  out=$AKHOME/init_boot-new.img
  rm -rf "$work" "$img" "$out" "$AKHOME/boot.img"
  mkdir -p "$work"

  ui_print "- dumping $ib → init_boot.img (not boot.img)"
  dd if="$ib" of="$img" bs=4096
  ui_print "- init_boot.img size=$(wc -c < "$img") bytes"
  ui_print "- header: $(od -An -tx1 -N16 "$img" | tr -s ' ')"

  cd "$work"
  ui_print "- magiskboot unpack init_boot.img"
  if ! "$MB" unpack -h "$img" >"$AKHOME/ib-unpack.log" 2>&1; then
    ui_print "- unpack -h failed; retry without -h"
    rm -f kernel kernel_dtb ramdisk.cpio* header* 2>/dev/null
    if ! "$MB" unpack "$img" >"$AKHOME/ib-unpack.log" 2>&1; then
      ui_print "ERROR: magiskboot unpack init_boot.img failed"
      ui_print "----- unpack log -----"
      cat "$AKHOME/ib-unpack.log"
      ui_print "----------------------"
      abort "init_boot unpack failed"
    fi
  fi
  cat "$AKHOME/ib-unpack.log"
  ui_print "- unpack dir: $(ls -la "$work")"

  if [ ! -f ramdisk.cpio ]; then
    ui_print "ERROR: no ramdisk.cpio after unpack"
    abort "init_boot has no ramdisk.cpio"
  fi

  rd=$work/rd
  rm -rf "$rd"
  mkdir -p "$rd"
  cd "$rd"
  # raw cpio or compressed — magiskboot usually leaves uncompressed ramdisk.cpio
  if ! EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < "$work/ramdisk.cpio" 2>"$AKHOME/ib-cpio.log"; then
    ui_print "- cpio -i failed; try magiskboot decompress"
    "$MB" decompress "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio" 2>/dev/null || cp "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio"
    rm -rf "$rd"/*
    EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < "$work/ramdisk-raw.cpio" || {
      ui_print "ERROR: ramdisk cpio extract failed"
      cat "$AKHOME/ib-cpio.log"
      abort "init_boot cpio extract failed"
    }
  fi

  if [ ! -f "$rd/init.rc" ]; then
    ui_print "ERROR: no init.rc inside init_boot$SLOT ramdisk"
    ui_print "- top entries: $(ls "$rd" | head -20)"
    abort "init_boot ramdisk missing init.rc"
  fi

  cp -f "$SRC/init.cgroup2_early.rc" "$rd/init.cgroup2_early.rc"
  cp -f "$SRC/cgroup2_early_fix.sh" "$rd/cgroup2_early_fix.sh"
  chmod 755 "$rd/cgroup2_early_fix.sh"
  chmod 644 "$rd/init.cgroup2_early.rc"

  if ! grep -q "init.cgroup2_early.rc" "$rd/init.rc"; then
    if grep -q "import /init.environ.rc" "$rd/init.rc"; then
      # portable insert after environ import
      sed -i '/import \/init.environ.rc/a import /init.cgroup2_early.rc' "$rd/init.rc"
    elif grep -q "^import " "$rd/init.rc"; then
      sed -i '0,/^import /s//import \/init.cgroup2_early.rc\n&/' "$rd/init.rc"
    else
      echo "import /init.cgroup2_early.rc" >> "$rd/init.rc"
    fi
  fi
  grep -q "init.cgroup2_early.rc" "$rd/init.rc" || abort "import line missing in init.rc"
  [ -f "$rd/init.cgroup2_early.rc" ] || abort "rc file missing after copy"
  ui_print "- OK: inject + import in unpacked init_boot ramdisk"

  cd "$rd"
  find . | cpio -H newc -o > "$work/ramdisk.cpio.new" || abort "cpio repack failed"
  mv -f "$work/ramdisk.cpio.new" "$work/ramdisk.cpio"

  cd "$work"
  ui_print "- magiskboot repack → init_boot-new.img"
  if ! "$MB" repack "$img" "$out" >"$AKHOME/ib-repack.log" 2>&1; then
    ui_print "ERROR: magiskboot repack failed"
    cat "$AKHOME/ib-repack.log"
    abort "init_boot repack failed"
  fi
  [ -f "$out" ] || abort "init_boot-new.img missing"
  ui_print "- writing init_boot-new.img → $ib"
  dd if="$out" of="$ib" bs=4096
  ui_print "- sync"
  sync

  # Prove: re-dump and grep
  ui_print "- prove: re-dump init_boot and grep cgroup2_early"
  rm -rf "$work/prove" "$AKHOME/init_boot-prove.img"
  mkdir -p "$work/prove"
  dd if="$ib" of="$AKHOME/init_boot-prove.img" bs=4096
  cd "$work/prove"
  "$MB" unpack "$AKHOME/init_boot-prove.img" >/dev/null 2>&1 || abort "prove unpack failed"
  mkdir rd && cd rd && EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < ../ramdisk.cpio
  if grep -q "cgroup2_early" init.rc && [ -f init.cgroup2_early.rc ]; then
    ui_print "- PROVE OK: cgroup2_early in init_boot$SLOT"
    PATCHED_PART="init_boot$SLOT"
  else
    ui_print "ERROR: prove failed after write"
    abort "init_boot prove failed"
  fi
}

if [ -n "$(find_init_boot)" ]; then
  inject_init_boot_explicit
else
  ui_print "ERROR: no init_boot$SLOT — this device needs init_boot for GSI init.rc"
  abort "no init_boot partition"
fi

ui_print " "
ui_print "=== DONE: Image=boot$SLOT | early-init=$PATCHED_PART ==="
ui_print " "

## End install
