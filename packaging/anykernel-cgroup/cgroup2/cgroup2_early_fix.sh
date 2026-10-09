#!/system/bin/sh
# Best-effort cgroup2 apps/system setup; logs every step to /dev/kmsg.
CG=/sys/fs/cgroup
log() { echo "cgroup2_early: $*" > /dev/kmsg 2>/dev/null || true; }

# One-line "mode owner group context path" for a device node (or its absence).
# $1 = node path. Explicitly flags when ls cannot show a label, so "no
# tcontext visible" can never be mistaken for "node missing" -- that
# distinction is the whole mislabel-vs-skew question. Newlines are collapsed
# so every datum matches `dmesg | grep cgroup2_early`; a bare multi-line
# $(...) would leave continuation lines prefix-less and invisible to that
# grep.
ion_stat() {
  _n=${1:-/dev/ion}
  if [ ! -e "$_n" ]; then echo "absent"; return 0; fi
  _s=$(ls -lZ "$_n" 2>/dev/null || ls -l "$_n" 2>/dev/null || echo "stat-failed")
  case "$_s" in *"u:object_r:"*) ;; *) _s="$_s [NO -Z LABEL]";; esac
  echo "$_s" | tr '\n' '|'
}

# $1=full (default): cgroup setup + ion diag. $1=reassert: cgroup setup only.
MODE=${1:-full}
log "fix.sh start mode=$MODE"
# Prove the netbpfload override took (set in the .rc at early-init). A stock
# AOSP GSI ignores this property entirely, so only the kernel-side value here
# is evidence -- netbpfload's own logcat is the real verdict.
log "kver_override=$(getprop ro.bpf.kver_override 2>/dev/null) uname=$(uname -r 2>/dev/null)"

mkdir_cg() {
  _p=$1
  if [ -d "$_p" ]; then
    log "mkdir $_p exists"
    return 0
  fi
  mkdir -p "$_p"
  _rc=$?
  if [ "$_rc" -eq 0 ]; then
    log "mkdir $_p OK"
    return 0
  fi
  log "mkdir $_p FAILED rc=$_rc parent=$(ls -ld "$(dirname "$_p")" 2>/dev/null | tr '\n' ' ')"
  return "$_rc"
}

mkdir_cg "$CG"

# cgroup.controllers is the live cgroup2 root. Never umount it: umount
# drops apps/ and system/, and A17 zygote then FatalError's on
# createProcessGroup -> /sys/fs/cgroup/system/uid_1000 (ENOENT).
# Only tear down a non-cgroup2 overlay (empty tmpfs, wrong fstype).
if [ -f "$CG/cgroup.controllers" ]; then
  log "cgroup2 already mounted"
else
  log "no cgroup.controllers — mounting cgroup2"
  if grep -qs " $CG " /proc/mounts; then
    umount "$CG" 2>/dev/null || umount -l "$CG" 2>/dev/null || true
    log "umount overlay at $CG"
  fi
  if mount -t cgroup2 -o rw,nosuid,nodev,noexec,relatime none "$CG" 2>/dev/null \
    || mount -t cgroup2 none "$CG" 2>/dev/null; then
    log "mount cgroup2 OK"
  else
    log "mount cgroup2 FAILED"
    exit 0
  fi
fi

[ -f "$CG/cgroup.controllers" ] || { log "still no controllers — exit"; exit 0; }
log "controllers=$(cat "$CG/cgroup.controllers" 2>/dev/null)"

enable_dir() {
  _d=$1
  mkdir_cg "$_d" || true
  log "enable_dir $_d"
  [ -f "$_d/cgroup.controllers" ] || { log "$_d missing cgroup.controllers"; return 0; }
  _avail=$(cat "$_d/cgroup.controllers" 2>/dev/null)
  for _c in cpuset cpu io memory pids; do
    case " $_avail " in
      *" $_c "*)
        if echo "+$_c" >"$_d/cgroup.subtree_control" 2>/dev/null; then
          log "$_d +$_c OK"
        else
          log "$_d +$_c FAIL"
        fi
        ;;
      *) log "$_d $_c unavailable" ;;
    esac
  done
}

enable_dir "$CG"

mkdir_cg "$CG/apps"
mkdir_cg "$CG/system"
chown system:system "$CG/apps" "$CG/system" 2>/dev/null || chown 1000:1000 "$CG/apps" "$CG/system" 2>/dev/null || true
chmod 0755 "$CG/apps" "$CG/system" 2>/dev/null || true
log "chown/chmod apps+system"

enable_dir "$CG/apps"
enable_dir "$CG/system"

if [ -d "$CG/apps" ] && [ -d "$CG/system" ]; then
  log "done apps=$(ls -ld "$CG/apps" 2>/dev/null) system=$(ls -ld "$CG/system" 2>/dev/null)"
else
  log "FAILED apps/system missing after setup"
fi

if [ "$MODE" != "full" ]; then
  log "reassert complete"
  exit 0
fi

# A17 graphics-allocator diagnostics.
#
# Why this is a background monitor rather than a one-shot dump: this script is
# exec'd from `on init`, which runs long before the HIDL allocator HAL is
# registered with hwservicemanager. A one-shot `ps -Z` here would always find
# nothing and we would lose the one datum that identifies the fix. So poll in
# the background until the allocator appears (or we give up), then record:
#
#   - the allocator's actual scontext   (stale vendor .rc seclabel puts it in
#     a domain lacking hal_graphics_allocator -> the platform allow never
#     applies; the leading hypothesis now that the rule itself is verified)
#   - /dev/ion's actual label + mode    (tcontext; mislabel vs policy skew)
#   - any avc: denied lines             (the authoritative answer)
#   - enforcement at failure + cmdline  (reconstructs the permissive-window
#     story; see below)
#   - /sys/fs/selinux/policyvers        (A13-vendor vs A17-platform skew)
#
# Everything goes through log() -> /dev/kmsg so it lands in the dmesg ring and
# logd's kernel buffer, readable over adb while stuck at the logo:
#     adb shell dmesg | grep cgroup2_early
#
# A note on what the enforce snapshots can and cannot say. `on init` fires in
# SECOND-stage init; first stage ends with execv(init selinux_setup), i.e.
# LoadSelinuxPolicy -> SelinuxSetEnforcement happens BEFORE any of these reads.
# So neither read can observe the kernel-cmdline enforcing=0 window directly.
# But the window is still reconstructible, because the input side is provable:
# this kernel has CONFIG_SECURITY_SELINUX_DEVELOP=y, so enforcing=0 on the
# cmdline provably started the kernel permissive. If /proc/cmdline still shows
# enforcing=0 below while enforce-at-allocator reads 1, init re-asserted
# enforcement before the HAL ran.
#
# And one correction that matters more than the window: do NOT read
# "EACCES with no avc line" as "permissive, therefore DAC". The Sep-20 boot
# that produced the ion EACCES was enforcing (every avc line in it ends
# permissive=0), so the permissive half of this package was simply not in
# effect there. The DAC conclusion survives anyway, but for a different,
# mode-independent reason, verified in this tree (fs/namei.c
# inode_permission): sb -> do_inode_permission (DAC: uid/gid/mode) ->
# devcgroup -> security_inode_permission (SELinux) LAST. A DAC denial
# returns EACCES without SELinux ever being consulted -- no avc line, in
# either mode. (devcgroup sits between them and is silent too, but it
# defaults allow-all on Android, so it stays last on the suspect list.)
# So:
#   restrictive mode/owner + EACCES + no avc  -> DAC, whatever enforce says
#   permissive mode + EACCES                  -> also DAC (permissive cannot
#                                                deny), but only if enforce
#                                                actually reads 0 -- check it,
#                                                don't assume the patch held
#   enforcing + EACCES + avc line             -> SELinux, and the avc names
#                                                the fix (read its
#                                                permissive= field, not just
#                                                its presence)
#   enforcing + EACCES, no avc                -> ambiguous (dontaudit exists);
#                                                setenforce 0 via adb root is
#                                                the tiebreaker
#
# Zeroth check before any of the above: if `dmesg | grep cgroup2_early` comes
# back empty on the flashed build, this package is not landing at all (wrong
# slot/image, ramdisk unpack failure) -- meaning the chown never ran, which
# alone explains EACCES with no vendor-rule theory required. Confirm presence
# of these lines first; everything else is downstream of that observation.
#
# Bounded to ~60s so it cannot outlive a slow boot. Never blocks, never fails.
(
  _n=0
  _seen_avc=""
  while [ "$_n" -lt 120 ]; do
    _n=$((_n + 1))

    # Enforcement state: confirms enforcing=0 actually took effect, and
    # whether init re-asserted enforcement after this point.
    # Build variant decides whether the permissive cmdline can hold
    # (ALLOW_PERMISSIVE_SELINUX is debuggable-only), so record it: without
    # it, "enforce=1 later" cannot be told apart from "patch never applied".
    if [ "$_n" = 2 ]; then
      log "DIAG enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null || echo '?')"
      log "DIAG ion $(ion_stat /dev/ion)"
      log "DIAG sprd-ion $(ion_stat /dev/sprd_ion)"
      log "DIAG policyvers=$(cat /sys/fs/selinux/policyvers 2>/dev/null || echo '?')"
      log "DIAG build=$(getprop ro.build.type 2>/dev/null || echo ?):$(getprop ro.debuggable 2>/dev/null || echo ?)"
      # The whole vendor+odm ueventd chain hangs off these two import lines
      # in the GSI-owned /system/etc/ueventd.rc. If they are absent, NO
      # vendor rule (ion or otherwise) is ever read, whatever paths exist.
      # Resolving each target to present/MISSING closes the "does the chain
      # actually reach a rule" half; the legacy-gate question (pre-S paths
      # gated on first_api_level<33) is answered by whether the imports and
      # their targets exist at all.
      if [ -f /system/etc/ueventd.rc ]; then
        _imp=$(grep -E '^import ' /system/etc/ueventd.rc 2>/dev/null | sed 's/^import //' | tr '\n' ' ')
        log "DIAG ueventd-imports=$(echo "$_imp" | tr -s ' ' | tr ' ' '|')"
        for _t in $_imp; do
          if [ -e "$_t" ]; then
            log "DIAG ueventd-target OK $_t"
          else
            log "DIAG ueventd-target MISSING $_t"
          fi
        done
      else
        log "DIAG ueventd-imports (/system/etc/ueventd.rc not yet readable)"
      fi
    fi

    # Mirror AVC denials, de-duplicated so a repeated denial does not spam.
    # Full dmesg dump is the most expensive thing in this loop, so scan every
    # 4th pass (~2s); the ps poll below stays per-pass (cheap, /proc-based).
    if [ $((_n % 4)) = 0 ]; then
      _av=$(dmesg 2>/dev/null | grep -E 'avc: *denied' | tail -5)
      if [ -n "$_av" ] && [ "$_av" != "$_seen_avc" ]; then
        _seen_avc=$_av
        echo "$_av" | while IFS= read -r _l; do log "AVC| $_l"; done
      fi
    fi

    # The allocator HAL. Once present, its scontext is what we came for.
    # Try several ps spellings: toybox's -Z support and flag combining have
    # varied across Android versions, and a miss here costs us the whole
    # diagnosis, so fall back rather than assume one form works.
    _ps=$(ps -AZ 2>/dev/null | grep -E 'graphics\.alloc' | head -2)
    [ -z "$_ps" ] && _ps=$(ps -A -Z 2>/dev/null | grep -E 'graphics\.alloc' | head -2)
    [ -z "$_ps" ] && _ps=$(ps -e -Z 2>/dev/null | grep -E 'graphics\.alloc' | head -2)
    [ -z "$_ps" ] && _ps=$(ps 2>/dev/null | grep -E 'graphics\.alloc' | head -2)
    if [ -n "$_ps" ]; then
      log "DIAG allocator: $(echo "$_ps" | tr '\n' '|')"
      log "DIAG enforce-at-allocator=$(cat /sys/fs/selinux/enforce 2>/dev/null || echo '?')"
      log "DIAG cmdline=$(tr ' ' '\n' < /proc/cmdline 2>/dev/null | grep -E '^(androidboot\.selinux|enforcing)=' | tr '\n' ' ')"
      log "DIAG ion-now $(ion_stat /dev/ion)"
      log "DIAG sprd-ion-now $(ion_stat /dev/sprd_ion)"
      # What the LOADED POLICY says the label should be, vs what ion_stat
      # showed it is. A mismatch here proves labeling divergence (stale
      # vendor file_contexts vs platform), independent of any denial.
      # Best effort: restorecon may simply not ship on the GSI.
      if [ -x /system/bin/restorecon ]; then
        _rc=$(/system/bin/restorecon -n -v /dev/ion 2>&1); _rce=$?
        [ -z "$_rc" ] && _rc="(no output: label already matches policy, rc=$_rce)"
        log "DIAG restorecon-n $(echo "$_rc" | tr '\n' '|')"
      else
        log "DIAG restorecon-n (no /system/bin/restorecon)"
      fi
      log "DIAG ion-open: $(dmesg 2>/dev/null | grep -E 'ion_open|obtain ion' | tail -3 | tr '\n' '|')"
      break
    fi

    sleep 0.5
  done
  [ "$_n" -ge 120 ] && log "DIAG allocator never appeared within 60s"
) &

# ION DAC fallback: re-applies the vendor ownership/mode as a safety net.
# Verified on this vendor: the merged vendor ueventd.rc carries
# "/dev/ion 0666 system graphics", all 26 ueventd files checked with no
# override, so ueventd already creates the node 0666 -- these chowns are a
# confirmed no-op on a normal boot, kept only for timing variants (node
# appearing after our triggers) at zero cost when absent. DAC is ruled OUT
# as the failure: with 0666 in place, open() cannot fail on mode/owner.
# The live question is the LABEL (see monitor above): A17 plat has no
# /dev/ion entry, so without a vendor or ODM file_contexts line the node
# falls back to generic `device`, where every ion_device allow is inert.
#
# Both ion nodes are handled: /dev/ion (in-tree core, always present) and
# /dev/sprd_ion (external sprd-ion.ko when built and loaded; in-tree copy
# is off). The wait below is /dev/ion only -- the .rc's on device-added
# trigger is the event-driven path for both, with zero cost when absent.
#
# Mode is deliberately 0666, matching this vendor's stock behavior
# (A13: 0666 system:graphics). 0660 would suffice if the HAL's uid is in
# graphics, but stock parity wins for a bringup test: it removes DAC from
# the suspect list entirely rather than narrowing it.
#
# Bound is deliberately short (~2s max). This runs under init's `on init`
# exec, which is synchronous and blocks the action thread, so a long stall
# delays every other on-init command. ueventd coldboot normally has the node
# already; if it does not, the rc's on device-added trigger is the primary
# path and this is only the fast-path fallback.
#
# Note: chown/chmod are permitted (init has setattr on dev_type via
# private/init.te), but chcon to ion_device is NOT -- there is no
# relabelto rule for ion_device in AOSP, so a relabel attempt would be
# denied in enforcing mode. DAC only; the label is ueventd's job.
# (The 2s wait above is /dev/ion only; sprd_ion relies on the rc trigger.)
_t=0
while [ ! -e /dev/ion ] && [ "$_t" -lt 20 ]; do
  sleep 0.1 2>/dev/null || sleep 1
  _t=$((_t + 1))
done
if [ -e /dev/ion ]; then
  chown system:graphics /dev/ion 2>/dev/null || chown 1000:1003 /dev/ion 2>/dev/null || true
  chmod 0666 /dev/ion 2>/dev/null || true
  log "ion $(ls -l /dev/ion 2>/dev/null)"
else
  log "ion /dev/ion missing after wait"
fi
exit 0
