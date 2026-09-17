### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09: cgroup2 early-init on init_boot — robust magiskboot unpack
## skip_boot_image present → do not rewrite boot (Image already flashed)

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 cgroup2 early-init A17 (init_boot unpack hardened)
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
MB31=$AKHOME/tools/magiskboot31
PATCHED_PART=""

[ -f "$SRC/init.cgroup2_early.rc" ] && [ -f "$SRC/cgroup2_early_fix.sh" ] || abort "cgroup2 inject sources missing"
chmod 755 "$MB" 2>/dev/null
chmod 755 "$MB31" 2>/dev/null

ui_print "- slot=$SLOT"

## Optional: skip boot Image rewrite (Jeus already flashed ba98de94)
if [ -f "$AKHOME/skip_boot_image" ]; then
  ui_print "- skip_boot_image: NOT rewriting boot$SLOT (Image already on device)"
else
  ui_print "- boot$SLOT: flash Image"
  split_boot
  patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
  patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"
  flash_boot
  ui_print "- boot$SLOT: Image written"
fi

find_init_boot() {
  ls /dev/block/by-name/init_boot$SLOT /dev/block/bootdevice/by-name/init_boot$SLOT 2>/dev/null | head -1
}

hex64() {
  od -An -tx1 -N64 "$1" 2>/dev/null | tr -s ' \n' ' '
}

# Try magiskboot unpack with diagnostics; returns 0 on success in $work
try_unpack() {
  local bin=$1 img=$2 work=$3
  local ec
  rm -rf "$work"
  mkdir -p "$work"
  cd "$work"
  ui_print "- trying $($bin 2>/dev/null | head -1 || echo magiskboot) unpack -h"
  "$bin" unpack -h "$img" >"$AKHOME/ib-unpack.log" 2>&1
  ec=$?
  ui_print "- unpack -h exit=$ec"
  if [ "$ec" = 0 ] && [ -f ramdisk.cpio ]; then
    return 0
  fi
  ui_print "- retry unpack without -h"
  rm -f kernel kernel_dtb ramdisk.cpio* dtb header extra recovery_dtbo 2>/dev/null
  "$bin" unpack "$img" >"$AKHOME/ib-unpack.log" 2>&1
  ec=$?
  ui_print "- unpack exit=$ec"
  cat "$AKHOME/ib-unpack.log"
  [ "$ec" = 0 ] && [ -f ramdisk.cpio ] && return 0
  # empty-kernel / chromeos code 2 sometimes still extracts
  [ -f ramdisk.cpio ] && return 0
  return 1
}

extract_rd() {
  local work=$1 rd=$2
  rm -rf "$rd"
  mkdir -p "$rd"
  cd "$rd"
  if EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < "$work/ramdisk.cpio" 2>"$AKHOME/ib-cpio.log"; then
    return 0
  fi
  ui_print "- cpio failed; magiskboot decompress then cpio"
  "$MB" decompress "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio" 2>/dev/null \
    || "$MB31" decompress "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio" 2>/dev/null \
    || cp "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio"
  rm -rf "$rd"/*
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < "$work/ramdisk-raw.cpio" 2>>"$AKHOME/ib-cpio.log"
}

inject_init_boot_explicit() {
  local ib work img out rd
  ib=$(find_init_boot)
  [ -n "$ib" ] || abort "no init_boot$SLOT block device"
  ui_print "- init_boot device: $ib"

  work=$AKHOME/ibwork
  img=$AKHOME/init_boot.img
  out=$AKHOME/init_boot-new.img
  rm -rf "$work" "$img" "$out"
  mkdir -p "$work"

  ui_print "- dd → init_boot.img"
  dd if="$ib" of="$img" bs=4096
  ui_print "- size=$(wc -c < "$img") bytes"
  ui_print "- first64:$(hex64 "$img")"

  # Primary: Magisk 30.7 magiskboot; fallback: 31.0
  if ! try_unpack "$MB" "$img" "$work"; then
    ui_print "- Magisk30 magiskboot failed — try Magisk31"
    if [ -x "$MB31" ] && try_unpack "$MB31" "$img" "$work"; then
      MB=$MB31
      ui_print "- Magisk31 unpack OK"
    else
      ui_print "ERROR: magiskboot cannot unpack this init_boot"
      ui_print "Paste this log + adb pull init_boot$SLOT"
      ui_print "----- unpack log -----"
      cat "$AKHOME/ib-unpack.log" 2>/dev/null
      ui_print "----------------------"
      abort "init_boot unpack failed"
    fi
  fi
  ui_print "- unpack OK; files: $(ls "$work")"

  rd=$work/rd
  extract_rd "$work" "$rd" || abort "init_boot cpio extract failed"
  if [ ! -f "$rd/init.rc" ]; then
    ui_print "ERROR: no init.rc in init_boot ramdisk"
    ui_print "- entries: $(ls "$rd" | head -30)"
    abort "init_boot missing init.rc"
  fi

  cp -f "$SRC/init.cgroup2_early.rc" "$rd/init.cgroup2_early.rc"
  cp -f "$SRC/cgroup2_early_fix.sh" "$rd/cgroup2_early_fix.sh"
  chmod 755 "$rd/cgroup2_early_fix.sh"
  chmod 644 "$rd/init.cgroup2_early.rc"

  if ! grep -q "init.cgroup2_early.rc" "$rd/init.rc"; then
    if grep -q "import /init.environ.rc" "$rd/init.rc"; then
      sed -i '/import \/init.environ.rc/a import /init.cgroup2_early.rc' "$rd/init.rc"
    elif grep -q "^import " "$rd/init.rc"; then
      sed -i '0,/^import /s//import \/init.cgroup2_early.rc\n&/' "$rd/init.rc"
    else
      echo "import /init.cgroup2_early.rc" >> "$rd/init.rc"
    fi
  fi
  grep -q "init.cgroup2_early.rc" "$rd/init.rc" || abort "import missing"
  ui_print "- OK: inject + import"

  cd "$rd"
  find . | cpio -H newc -o > "$work/ramdisk.cpio" || abort "cpio repack failed"

  cd "$work"
  ui_print "- magiskboot repack"
  if ! "$MB" repack "$img" "$out" >"$AKHOME/ib-repack.log" 2>&1; then
    cat "$AKHOME/ib-repack.log"
    abort "init_boot repack failed"
  fi
  ui_print "- dd init_boot-new.img → $ib"
  dd if="$out" of="$ib" bs=4096
  sync

  ui_print "- prove re-dump"
  rm -rf "$work/prove"
  mkdir -p "$work/prove"
  dd if="$ib" of="$AKHOME/init_boot-prove.img" bs=4096
  try_unpack "$MB" "$AKHOME/init_boot-prove.img" "$work/prove" || abort "prove unpack failed"
  extract_rd "$work/prove" "$work/prove/rd" || abort "prove cpio failed"
  if grep -q "cgroup2_early" "$work/prove/rd/init.rc" && [ -f "$work/prove/rd/init.cgroup2_early.rc" ]; then
    ui_print "- PROVE OK: cgroup2_early on init_boot$SLOT"
    PATCHED_PART="init_boot$SLOT"
  else
    abort "prove failed"
  fi
}

[ -n "$(find_init_boot)" ] || abort "no init_boot$SLOT"
inject_init_boot_explicit

ui_print " "
ui_print "=== DONE early-init=$PATCHED_PART ==="
ui_print " "

## End install
