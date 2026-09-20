### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09: cgroup2 early-init via BOOT nested ramdisk (Max / bootanimation style)
## Same path as "Disable Bootanimation" zip: split_boot → unpack_ramdisk → patch → repack → flash_boot
## init_boot is EMPTY on this device — do not use it.

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 cgroup2 early-init on BOOT ramdisk (Unisoc nested)
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
[ -f "$SRC/init.cgroup2_early.rc" ] && [ -f "$SRC/cgroup2_early_fix.sh" ] || abort "missing cgroup2/ sources"

ui_print "- slot=$SLOT"
ui_print "- Max/bootanim style: split_boot + unpack_ramdisk on boot (not init_boot)"

split_boot
unpack_ramdisk

# After unpack, live tree is $RAMDISK; zip overlay may be in rdtmp (same as bootanim fallback)
RD=$RAMDISK
[ -d "$RD" ] || RD=$AKHOME/ramdisk
ALT=$AKHOME/rdtmp

ui_print "- ramdisk top: $(ls "$RD" 2>/dev/null | head -20)"
if [ -d "$RD/system/etc/ramdisk" ]; then
  ui_print "- nested system/etc/ramdisk: $(ls "$RD/system/etc/ramdisk" 2>/dev/null | head -20)"
fi

# Copy inject into classic root + Unisoc nested path (+ rdtmp fallback like bootanim)
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

install_inject "$RD" || abort "ramdisk dir missing after unpack"
[ -d "$ALT" ] && install_inject "$ALT"

# Hook: add import to every init*.rc we can find (root or nested)
hook_import() {
  local root=$1 f
  [ -d "$root" ] || return 0
  for f in "$root"/init.rc "$root"/init*.rc "$root"/system/etc/ramdisk/init.rc "$root"/system/etc/ramdisk/init*.rc; do
    [ -f "$f" ] || continue
    ui_print "- hook import in $(echo "$f" | sed "s|^$AKHOME/||")"
    if ! grep -q "init.cgroup2_early.rc" "$f"; then
      if grep -q "import /init.environ.rc" "$f"; then
        sed -i '/import \/init.environ.rc/a import /init.cgroup2_early.rc' "$f"
      elif grep -q "^import " "$f"; then
        sed -i '0,/^import /s//import \/init.cgroup2_early.rc\n&/' "$f"
      else
        # Unisoc nested often uses relative imports — try both forms
        echo "import /init.cgroup2_early.rc" >> "$f"
        echo "import /system/etc/ramdisk/init.cgroup2_early.rc" >> "$f"
      fi
    fi
  done
}

hook_import "$RD"
[ -d "$ALT" ] && hook_import "$ALT"

# Magisk overlay.d early hook if Magisk ramdisk present
for base in "$RD" "$ALT"; do
  [ -d "$base" ] || continue
  if [ -d "$base/overlay.d" ] || [ -d "$base/.backup" ]; then
    ui_print "- Magisk-style ramdisk detected — add overlay.d early script"
    mkdir -p "$base/overlay.d/sbin"
    cp -f "$SRC/cgroup2_early_fix.sh" "$base/overlay.d/sbin/cgroup2_early_fix.sh"
    chmod 755 "$base/overlay.d/sbin/cgroup2_early_fix.sh"
    # Magisk executes *.rc under overlay.d
    cp -f "$SRC/init.cgroup2_early.rc" "$base/overlay.d/init.cgroup2_early.rc"
  fi
done

# Prove files landed
if [ ! -f "$RD/init.cgroup2_early.rc" ] && [ ! -f "$RD/system/etc/ramdisk/init.cgroup2_early.rc" ]; then
  abort "inject files missing after copy"
fi
ui_print "- inject files present in boot ramdisk"

# Keep ba98de94 cmdline hygiene on boot header
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"

ui_print "- repack_ramdisk + flash_boot (Image + patched BOOT ramdisk)"
repack_ramdisk
flash_boot

ui_print " "
ui_print "=== DONE: cgroup2 early-init on boot$SLOT ramdisk (bootanim path) ==="
ui_print "=== Verify: dmesg | grep cgroup2_early ; ls /sys/fs/cgroup/system ==="
ui_print " "

## End install
