### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09: cgroup2 early-init — probe boot/vendor_boot (init_boot often EMPTY/zeros on this device)

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 cgroup2 early-init (probe boot/vendor_boot)
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

[ -f "$SRC/init.cgroup2_early.rc" ] && [ -f "$SRC/cgroup2_early_fix.sh" ] || abort "cgroup2 sources missing"
chmod 755 "$MB" "$MB31" 2>/dev/null
ui_print "- slot=$SLOT"

if [ -f "$AKHOME/skip_boot_image" ]; then
  ui_print "- skip_boot_image: not rewriting boot Image"
else
  split_boot
  patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
  patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"
  flash_boot
  ui_print "- boot$SLOT Image written"
fi

byname() {
  # $1 = partition name without slot
  ls /dev/block/by-name/$1$SLOT /dev/block/bootdevice/by-name/$1$SLOT 2>/dev/null | head -1
}

is_all_zeros_header() {
  # first 64 bytes all 0 → empty/unprovisioned
  local h
  h=$(od -An -tx1 -N64 "$1" 2>/dev/null | tr -d ' \n')
  [ -n "$h" ] && [ "$(echo "$h" | tr -d '0')" = "" ]
}

hex64() { od -An -tx1 -N64 "$1" 2>/dev/null | tr -s ' \n' ' '; }

try_unpack() {
  local bin=$1 img=$2 work=$3 ec
  rm -rf "$work"; mkdir -p "$work"; cd "$work"
  "$bin" unpack -h "$img" >"$AKHOME/ib-unpack.log" 2>&1; ec=$?
  [ "$ec" = 0 ] && [ -f ramdisk.cpio ] && return 0
  rm -f kernel kernel_dtb ramdisk.cpio* dtb header extra recovery_dtbo 2>/dev/null
  "$bin" unpack "$img" >"$AKHOME/ib-unpack.log" 2>&1; ec=$?
  ui_print "- unpack exit=$ec ($(basename "$bin"))"
  [ -f ramdisk.cpio ] && return 0
  return 1
}

extract_rd() {
  local work=$1 rd=$2
  rm -rf "$rd"; mkdir -p "$rd"; cd "$rd"
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < "$work/ramdisk.cpio" 2>/dev/null && return 0
  "$MB" decompress "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio" 2>/dev/null \
    || "$MB31" decompress "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio" 2>/dev/null \
    || cp "$work/ramdisk.cpio" "$work/ramdisk-raw.cpio"
  rm -rf "$rd"/* 
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -idm < "$work/ramdisk-raw.cpio"
}

inject_into_img() {
  # $1=partname (boot|vendor_boot) $2=blockdev
  local part=$1 dev=$2 work img out rd
  work=$AKHOME/rdwork_$part
  img=$AKHOME/${part}.img
  out=$AKHOME/${part}-new.img
  rm -rf "$work" "$img" "$out"
  mkdir -p "$work"

  ui_print "- probing $part$SLOT ($dev)"
  dd if="$dev" of="$img" bs=4096
  ui_print "- $part.img size=$(wc -c < "$img") first64:$(hex64 "$img")"

  if is_all_zeros_header "$img"; then
    ui_print "- SKIP $part$SLOT: header all zeros (empty)"
    return 1
  fi

  if ! try_unpack "$MB" "$img" "$work"; then
    if [ -x "$MB31" ] && try_unpack "$MB31" "$img" "$work"; then
      MB=$MB31
    else
      ui_print "- SKIP $part$SLOT: magiskboot unpack failed"
      return 1
    fi
  fi
  [ -f "$work/ramdisk.cpio" ] || { ui_print "- SKIP $part$SLOT: no ramdisk.cpio"; return 1; }

  rd=$work/rd
  extract_rd "$work" "$rd" || { ui_print "- SKIP $part$SLOT: cpio extract failed"; return 1; }

  if [ ! -f "$rd/init.rc" ]; then
    ui_print "- SKIP $part$SLOT: no init.rc (has: $(ls "$rd" 2>/dev/null | head -15))"
    return 1
  fi
  ui_print "- FOUND init.rc on $part$SLOT — injecting"

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
  grep -q "init.cgroup2_early.rc" "$rd/init.rc" || abort "import insert failed on $part"

  cd "$rd"
  find . | cpio -H newc -o > "$work/ramdisk.cpio" || abort "cpio repack failed"
  cd "$work"
  "$MB" repack "$img" "$out" >"$AKHOME/ib-repack.log" 2>&1 || {
    cat "$AKHOME/ib-repack.log"; abort "repack failed on $part"
  }
  ui_print "- writing $part-new.img → $dev"
  dd if="$out" of="$dev" bs=4096
  sync
  PATCHED_PART="$part$SLOT"
  ui_print "- OK injected $PATCHED_PART"
  return 0
}

# Survey + try inject: skip empty init_boot; prefer partitions that unpack + have init.rc
ui_print "- hard-stop: do not require init_boot (often zeros on this device)"

IB=$(byname init_boot)
if [ -n "$IB" ]; then
  dd if="$IB" of="$AKHOME/init_boot_probe.img" bs=4096 count=16 2>/dev/null
  ui_print "- init_boot$SLOT probe first64:$(hex64 "$AKHOME/init_boot_probe.img")"
  if is_all_zeros_header "$AKHOME/init_boot_probe.img"; then
    ui_print "- init_boot$SLOT is EMPTY (zeros) — skipping forever this zip"
  else
    if inject_into_img init_boot "$IB"; then
      ui_print "=== DONE early-init=$PATCHED_PART ==="
      exit 0
    }
  fi
else
  ui_print "- no init_boot$SLOT node"
fi

VB=$(byname vendor_boot)
[ -n "$VB" ] && inject_into_img vendor_boot "$VB" && {
  ui_print "=== DONE early-init=$PATCHED_PART ==="
  exit 0
}

BB=$(byname boot)
[ -n "$BB" ] && inject_into_img boot "$BB" && {
  ui_print "=== DONE early-init=$PATCHED_PART ==="
  exit 0
}

ui_print "ERROR: no flashable ramdisk with init.rc (init_boot empty; vendor_boot/boot no init.rc)"
ui_print "Next: runtime find + ReSukiSU earliest module (timing risk vs zygote)"
ui_print "Run on device and paste:"
ui_print "  ls -l /dev/block/by-name/"
ui_print "  find /system /system_ext /vendor /odm /product -name 'init.rc' 2>/dev/null | head"
abort "no init.rc ramdisk target"
