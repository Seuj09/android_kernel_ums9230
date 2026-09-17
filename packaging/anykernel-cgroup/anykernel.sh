### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09 A17 cgroup2 early-init:
##  1) BOOT nested ramdisk (Max/bootanimation path) — primary
##  2) vendor_boot if it has init.rc / first_stage — secondary (non-fatal)
##  NEVER touch init_boot (8MB zeros on this device)

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 cgroup2 early-init (boot nested + vendor_boot probe)
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

BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

. tools/ak3-core.sh

SRC=$AKHOME/cgroup2
MB=$AKHOME/tools/magiskboot
[ -f "$SRC/init.cgroup2_early.rc" ] && [ -f "$SRC/cgroup2_early_fix.sh" ] || abort "missing cgroup2/ sources"
chmod 755 "$MB" 2>/dev/null

ui_print "- slot=$SLOT"
ui_print "- NEVER touching init_boot (empty/zeros on this device)"

byname() {
  ls /dev/block/by-name/$1$SLOT /dev/block/bootdevice/by-name/$1$SLOT 2>/dev/null | head -1
}

install_inject() {
  local root=$1
  [ -d "$root" ] || return 1
  mkdir -p "$root/system/etc/ramdisk"
  cp -f "$SRC/init.cgroup2_early.rc" "$root/init.cgroup2_early.rc"
  cp -f "$SRC/cgroup2_early_fix.sh" "$root/cgroup2_early_fix.sh"
  cp -f "$SRC/init.cgroup2_early.rc" "$root/system/etc/ramdisk/init.cgroup2_early.rc"
  cp -f "$SRC/cgroup2_early_fix.sh" "$root/system/etc/ramdisk/cgroup2_early_fix.sh"
  chmod 755 "$root/cgroup2_early_fix.sh" "$root/system/etc/ramdisk/cgroup2_early_fix.sh"
  chmod 644 "$root/init.cgroup2_early.rc" "$root/system/etc/ramdisk/init.cgroup2_early.rc"
  return 0
}

# Patches init*.rc imports; echoes "1" if any rc was found/touched, else "0"
hook_import() {
  local root=$1 f hooked=0
  [ -d "$root" ] || { echo 0; return 0; }
  for f in "$root"/init.rc "$root"/init*.rc \
           "$root"/system/etc/ramdisk/init.rc "$root"/system/etc/ramdisk/init*.rc \
           "$root"/first_stage_ramdisk/init.rc "$root"/first_stage_ramdisk/system/etc/init/*.rc; do
    [ -f "$f" ] || continue
    hooked=1
    ui_print "- hook import: $(echo "$f" | sed "s|^$AKHOME/||")"
    if ! grep -q "cgroup2_early" "$f"; then
      if grep -q "import /init.environ.rc" "$f"; then
        sed -i '/import \/init.environ.rc/a import /init.cgroup2_early.rc' "$f"
      elif grep -q "^import " "$f"; then
        sed -i '0,/^import /s//import \/init.cgroup2_early.rc\n&/' "$f"
      else
        echo "import /init.cgroup2_early.rc" >> "$f"
        echo "import /system/etc/ramdisk/init.cgroup2_early.rc" >> "$f"
      fi
    fi
  done
  echo $hooked
  return 0
}

## ——— 1) BOOT: Max/bootanimation path ———
ui_print "- [1] boot$SLOT: split_boot + unpack_ramdisk (nested system/etc/ramdisk)"
split_boot
unpack_ramdisk

RD=$RAMDISK
[ -d "$RD" ] || RD=$AKHOME/ramdisk
ALT=$AKHOME/rdtmp

ui_print "- boot ramdisk top: $(ls "$RD" 2>/dev/null | head -20)"
if [ -d "$RD/system/etc/ramdisk" ]; then
  ui_print "- nested: $(ls "$RD/system/etc/ramdisk" 2>/dev/null | head -20)"
else
  ui_print "- no system/etc/ramdisk yet — will create"
fi

install_inject "$RD" || abort "boot ramdisk dir missing"
[ -d "$ALT" ] && install_inject "$ALT"

BOOT_HOOKED=0
[ "$(hook_import "$RD")" = "1" ] && BOOT_HOOKED=1
[ -d "$ALT" ] && [ "$(hook_import "$ALT")" = "1" ] && BOOT_HOOKED=1

for base in "$RD" "$ALT"; do
  [ -d "$base" ] || continue
  if [ -d "$base/overlay.d" ] || [ -d "$base/.backup" ]; then
    ui_print "- Magisk overlay.d on boot — add early rc"
    mkdir -p "$base/overlay.d/sbin"
    cp -f "$SRC/cgroup2_early_fix.sh" "$base/overlay.d/sbin/cgroup2_early_fix.sh"
    chmod 755 "$base/overlay.d/sbin/cgroup2_early_fix.sh"
    cp -f "$SRC/init.cgroup2_early.rc" "$base/overlay.d/init.cgroup2_early.rc"
    BOOT_HOOKED=1
  fi
done

[ -f "$RD/init.cgroup2_early.rc" ] || [ -f "$RD/system/etc/ramdisk/init.cgroup2_early.rc" ] \
  || abort "boot inject copy failed"

patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"
ui_print "- boot$SLOT: repack_ramdisk + flash_boot"
repack_ramdisk
flash_boot
ui_print "- boot$SLOT: Image + nested ramdisk written (hooked=$BOOT_HOOKED)"

## ——— 2) vendor_boot probe (non-fatal; never uses aborting dump_boot) ———
VB=$(byname vendor_boot)
VENDOR_DONE=0
if [ -n "$VB" ]; then
  ui_print "- [2] probe vendor_boot$SLOT ($VB) for init.rc / first_stage"
  VIMG=$AKHOME/vendor_boot.img
  VWORK=$AKHOME/vbwork
  VOUT=$AKHOME/vendor_boot-new.img
  rm -rf "$VWORK" "$VIMG" "$VOUT"
  mkdir -p "$VWORK"
  dd if="$VB" of="$VIMG" bs=4096
  ui_print "- vendor_boot.img size=$(wc -c < "$VIMG")"
  cd "$VWORK"
  if ! "$MB" unpack -h "$VIMG" >"$AKHOME/vb-unpack.log" 2>&1 \
     && ! "$MB" unpack "$VIMG" >"$AKHOME/vb-unpack.log" 2>&1; then
    ui_print "- vendor_boot unpack failed — leave untouched (not fatal)"
    ui_print "- $(head -5 "$AKHOME/vb-unpack.log" 2>/dev/null)"
  else
    VRD=""
    if [ -f ramdisk.cpio ]; then
      mkdir -p rd && cd rd
      EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < ../ramdisk.cpio 2>/dev/null && VRD=$VWORK/rd
      cd "$VWORK"
    fi
    for d in "$VWORK" "$VWORK/rd" "$VWORK/vendor_ramdisk" "$VWORK/ramdisk" \
             "$VWORK"/vendor_ramdisk_* "$VWORK"/ramdisk_*; do
      [ -d "$d" ] || continue
      if [ -f "$d/init.rc" ] || ls "$d"/init*.rc >/dev/null 2>&1 \
         || [ -d "$d/first_stage_ramdisk" ] \
         || ls "$d"/system/etc/init/*.rc >/dev/null 2>&1; then
        VRD=$d
        break
      fi
    done
    if [ -n "$VRD" ]; then
      ui_print "- vendor_boot has init/first_stage at ${VRD#$AKHOME/} — injecting"
      install_inject "$VRD"
      hook_import "$VRD" >/dev/null
      if [ -d "$VRD/first_stage_ramdisk" ]; then
        install_inject "$VRD/first_stage_ramdisk"
        hook_import "$VRD/first_stage_ramdisk" >/dev/null
      fi
      if [ -f "$VWORK/ramdisk.cpio" ] && [ -d "$VWORK/rd" ]; then
        cd "$VWORK/rd"
        find . | cpio -H newc -o > "$VWORK/ramdisk.cpio"
        cd "$VWORK"
        if "$MB" repack "$VIMG" "$VOUT" >"$AKHOME/vb-repack.log" 2>&1; then
          dd if="$VOUT" of="$VB" bs=4096
          sync
          VENDOR_DONE=1
          ui_print "- vendor_boot$SLOT: written"
        else
          ui_print "- vendor_boot repack failed — leave untouched"
          ui_print "- $(head -5 "$AKHOME/vb-repack.log" 2>/dev/null)"
        fi
      else
        ui_print "- vendor_boot layout not single ramdisk.cpio — leave untouched (probe only)"
        ui_print "- vb top: $(ls "$VWORK" 2>/dev/null | head -15)"
      fi
    else
      ui_print "- vendor_boot$SLOT: no init.rc/first_stage — leave untouched"
      ui_print "- vb top: $(ls "$VWORK" 2>/dev/null | head -15)"
    fi
  fi
  cd "$AKHOME"
else
  ui_print "- no vendor_boot$SLOT node"
fi

ui_print " "
ui_print "=== DONE boot$SLOT nested ramdisk + vendor_boot_injected=$VENDOR_DONE ==="
ui_print "=== Verify: dmesg|grep cgroup2_early ; ls /sys/fs/cgroup/system ==="
ui_print " "

## End install
