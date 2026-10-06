### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Seuj09: A17 ION / SELinux permissive TEST (bpf-a17-selinux-test)
## cgroup2 early-init + ion chown on BOOT nested ramdisk
## + androidboot.selinux=permissive on boot header cmdline (and vendor_boot/bootconfig if present)
## Same path as "Disable Bootanimation": split_boot → unpack_ramdisk → patch → repack → flash_boot
## init_boot is EMPTY on this device — do not use it.

### AnyKernel setup
properties() { '
kernel.string=AnyKernel3 cgroup2+ion + selinux=permissive TEST
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
ui_print "- permissive TEST: cgroup2 + ion + androidboot.selinux=permissive"
ui_print "- Max/bootanim style: split_boot + unpack_ramdisk on boot (not init_boot)"

rm -rf "$AKHOME/ramdisk"
mkdir -p "$AKHOME/ramdisk"

if [ -x "$BIN/magiskboot31" ]; then
  ui_print "- using tools/magiskboot31"
  magiskboot() { "$BIN/magiskboot31" "$@"; }
fi

split_boot
unpack_ramdisk

RD=$RAMDISK
[ -d "$RD" ] || RD=$AKHOME/ramdisk
ALT=$AKHOME/rdtmp

ui_print "- ramdisk top: $(ls "$RD" 2>/dev/null | tr '\n' ' ')"
if [ -d "$RD/system/etc/ramdisk" ]; then
  ui_print "- nested system/etc/ramdisk: $(ls "$RD/system/etc/ramdisk" 2>/dev/null | tr '\n' ' ')"
fi

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

hook_import() {
  local root=$1 f base src
  [ -d "$root" ] || return 0

  # install_inject() runs first and copies init.cgroup2_early.rc into this
  # tree, so the init*.rc glob below matches our OWN inject. That file does
  # not contain the string "init.cgroup2_early.rc", so the old guard fell
  # through to the append branch and wrote an import of itself into the file
  # being imported.
  #
  # AOSP init has no import cycle detection: ImportParser::ParseSection only
  # queues the path, and ImportParser::EndFile (called from Parser::ParseData
  # at T_EOF) runs parser_->ParseConfig() on it. Re-parsing the file re-queues
  # the same import, so a self-import recurses until the stack dies -- init
  # never reaches its triggers. Never hook the inject, at either path.
  for f in "$root"/init.rc "$root"/init*.rc "$root"/system/etc/ramdisk/init.rc "$root"/system/etc/ramdisk/init*.rc; do
    [ -f "$f" ] || continue
    base=${f##*/}
    [ "$base" = "init.cgroup2_early.rc" ] && continue

    # The import path is resolved by init at parse time, so it depends on
    # where this .rc sits in the ramdisk we are patching. There is no
    # resolve-relative-to-importing-file behaviour in init (ParseConfigFile
    # passes the string straight to ReadFileToString), so it must be absolute
    # and must match this file's own location.
    case $f in
      "$root"/system/etc/ramdisk/*) src=/system/etc/ramdisk/init.cgroup2_early.rc ;;
      *)                            src=/init.cgroup2_early.rc ;;
    esac

    # A missing import is non-fatal (ParseConfig only logs "Unable to read
    # config file"), but it is noise and it means the inject silently does
    # nothing. Only emit an import for a file we actually shipped here.
    [ -f "$root$src" ] || continue

    grep -qF "import $src" "$f" && continue

    ui_print "- hook import in $(echo "$f" | sed "s|^$AKHOME/||")"
    if grep -qF "import /init.environ.rc" "$f"; then
      sed -i "\|^import /init\.environ\.rc\$|a import $src" "$f"
    elif grep -q "^import " "$f"; then
      sed -i "0,/^import /s||import $src\n&|" "$f"
    else
      echo "import $src" >> "$f"
    fi
  done
}

hook_import "$RD"
[ -d "$ALT" ] && hook_import "$ALT"

for base in "$RD" "$ALT"; do
  [ -d "$base" ] || continue
  if [ -d "$base/overlay.d" ] || [ -d "$base/.backup" ]; then
    ui_print "- Magisk-style ramdisk detected — add overlay.d early script"
    mkdir -p "$base/overlay.d/sbin"
    cp -f "$SRC/cgroup2_early_fix.sh" "$base/overlay.d/sbin/cgroup2_early_fix.sh"
    chmod 755 "$base/overlay.d/sbin/cgroup2_early_fix.sh"
    cp -f "$SRC/init.cgroup2_early.rc" "$base/overlay.d/init.cgroup2_early.rc"
  fi
done

if [ ! -f "$RD/init.cgroup2_early.rc" ] && [ ! -f "$RD/system/etc/ramdisk/init.cgroup2_early.rc" ]; then
  abort "inject files missing after copy"
fi
if ! grep -q "chown system graphics /dev/ion" "$SRC/init.cgroup2_early.rc"; then
  abort "ion chown missing from inject rc"
fi
ui_print "- inject files present in boot ramdisk (cgroup2 + ion)"

# ba98de94 cmdline hygiene + SELinux permissive TEST
patch_cmdline "cgroup_disable" "cgroup_disable=pressure,net_prio"
patch_cmdline "cgroup_no_v1" "cgroup_no_v1=cpu,cpuset,blkio,io,memory"

# SELinux permissive TEST — two independent knobs, because they are enforced
# by different code:
#  - enforcing=0        kernel side, security/selinux/hooks.c enforcing_setup()
#                       (needs CONFIG_SECURITY_SELINUX_DEVELOP=y). Sets the
#                       boot default. init's 2nd-stage SelinuxSetEnforcement()
#                       may still flip it back on a user build.
#  - androidboot.selinux  userspace, system/core/init/selinux.cpp
#                       StatusFromProperty(); a no-op unless init was built
#                       with ALLOW_PERMISSIVE_SELINUX=1 (userdebug/eng).
# Patch both so the test does not depend on the GSI's build variant.
  patch_cmdline "androidboot.selinux" "androidboot.selinux=permissive"
  patch_cmdline "enforcing" "enforcing=0"
ui_print "- patched BOOT header cmdline: enforcing=0 + androidboot.selinux=permissive"

# Header v4 bootconfig (if magiskboot unpacked a bootconfig blob into SPLITIMG)
if [ -f "$SPLITIMG/bootconfig" ]; then
  if ! grep -q "androidboot.selinux" "$SPLITIMG/bootconfig"; then
    echo "androidboot.selinux = \"permissive\"" >> "$SPLITIMG/bootconfig"
    ui_print "- appended androidboot.selinux to BOOT bootconfig"
  else
    sed -i 's/androidboot\.selinux.*/androidboot.selinux = "permissive"/' "$SPLITIMG/bootconfig"
    ui_print "- updated androidboot.selinux in BOOT bootconfig"
  fi
else
  ui_print "- no BOOT bootconfig file after unpack (cmdline-only path)"
fi

ui_print "- repack_ramdisk + flash_boot (Image + patched BOOT ramdisk)"
repack_ramdisk
flash_boot

# Also try vendor_boot when present (hdr v3/v4 often keeps androidboot.* there).
# flash_boot prefers AKHOME/Image as kernel — move it aside so we only rewrite cmdline.
VB=
for p in /dev/block/by-name/vendor_boot$SLOT /dev/block/bootdevice/by-name/vendor_boot$SLOT; do
  [ -e "$p" ] && VB=$p && break
done
if [ -n "$VB" ]; then
  ui_print "- vendor_boot$SLOT present — patch androidboot.selinux there too"
  mv -f "$AKHOME/Image" "$AKHOME/Image.bootkeep"
  block=vendor_boot
  is_slot_device=1
  ramdisk_compression=auto
  patch_vbmeta_flag=auto
  reset_ak
  split_boot
  patch_cmdline "androidboot.selinux" "androidboot.selinux=permissive"
  patch_cmdline "enforcing" "enforcing=0"
  ui_print "- patched vendor_boot header cmdline: enforcing=0 + androidboot.selinux=permissive"
  if [ -f "$SPLITIMG/bootconfig" ]; then
    if ! grep -q "androidboot.selinux" "$SPLITIMG/bootconfig"; then
      echo "androidboot.selinux = \"permissive\"" >> "$SPLITIMG/bootconfig"
      ui_print "- appended androidboot.selinux to vendor_boot bootconfig"
    else
      sed -i 's/androidboot\.selinux.*/androidboot.selinux = "permissive"/' "$SPLITIMG/bootconfig"
      ui_print "- updated androidboot.selinux in vendor_boot bootconfig"
    fi
  else
    ui_print "- no vendor_boot bootconfig file after unpack"
  fi
  flash_boot
  mv -f "$AKHOME/Image.bootkeep" "$AKHOME/Image"
else
  ui_print "- no vendor_boot partition — BOOT cmdline/bootconfig only"
fi

ui_print " "
ui_print "=== DONE: permissive TEST (cgroup2 + ion + selinux=permissive) ==="
ui_print "=== Verify: getenforce ; cat /proc/cmdline | tr ' ' '\\n' | grep selinux ==="
ui_print " "

## End install
