#!/system/bin/sh
# Best-effort cgroup2 apps/system setup; logs every step to /dev/kmsg.
CG=/sys/fs/cgroup
log() { echo "cgroup2_early: $*" > /dev/kmsg 2>/dev/null || true; }

# One-line "mode owner group context path" for /dev/ion (or its absence).
# Explicitly flags when ls cannot show a label, so "no tcontext visible" can
# never be mistaken for "node missing" -- that distinction is the whole
# mislabel-vs-skew question. Newlines are collapsed so every datum matches
# `dmesg | grep cgroup2_early`; a bare multi-line $(...) would leave
# continuation lines prefix-less and invisible to that grep.
ion_stat() {
  if [ ! -e /dev/ion ]; then echo "absent"; return 0; fi
  _s=$(ls -lZ /dev/ion 2>/dev/null || ls -l /dev/ion 2>/dev/null || echo "stat-failed")
  case "$_s" in *"u:object_r:"*) ;; *) _s="$_s [NO -Z LABEL]";; esac
  echo "$_s" | tr '\n' '|'
}

log "fix.sh start"

mkdir -p "$CG" 2>/dev/null || true
log "mkdir -p $CG"

need_remount=0
if [ ! -f "$CG/cgroup.controllers" ]; then
  need_remount=1
  log "no cgroup.controllers — need mount"
elif ! grep -qs "cgroup2 $CG\| $CG cgroup2" /proc/mounts; then
  need_remount=1
  log "not cgroup2 fstype — need remount"
else
  log "cgroup2 already mounted"
fi

if [ "$need_remount" = 1 ]; then
  log "remounting cgroup2"
  if grep -qs " $CG " /proc/mounts; then
    umount "$CG" 2>/dev/null || umount -l "$CG" 2>/dev/null || true
    log "umount old $CG"
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
  mkdir -p "$_d" 2>/dev/null || true
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

mkdir -p "$CG/apps" "$CG/system" 2>/dev/null || true
log "mkdir apps+system"
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
# enforcement before the HAL ran. The three-way read at the bottom is then:
#   enforce=0 + fail            -> not SELinux, look at HIDL-vs-AIDL
#   enforce=1 + fail + avc line -> SELinux, and the avc names the fix
#   enforce=1 + fail, no avc    -> ambiguous (dontaudit exists); setenforce 0
#                                  via adb root is the tiebreaker
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
      log "DIAG ion $(ion_stat)"
      log "DIAG policyvers=$(cat /sys/fs/selinux/policyvers 2>/dev/null || echo '?')"
      log "DIAG build=$(getprop ro.build.type 2>/dev/null || echo ?):$(getprop ro.debuggable 2>/dev/null || echo ?)"
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
      log "DIAG ion-now $(ion_stat)"
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

# ION DAC fallback: vendor ueventd.rc often creates /dev/ion AFTER the .rc
# early-init chown (0660 or root-only), overwriting it. The .rc
# device-added trigger should catch it, but if it misses, allocator@4.0
# dies with "ion_open failed Permission denied" -> SF RenderEngine abort
# loop. So wait for the node here (runs on `on init`, after coldboot)
# and force 0666. Best-effort, never fails boot.
#
# Only /dev/ion: sprd_ion.c exists but CONFIG_ION_SPRD is not set, so
# /dev/sprd_ion can never appear. Waiting on it would burn the full timeout
# on every boot for nothing.
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
#
# No loop: only /dev/ion exists in this tree. sprd_ion.c is present but
# CONFIG_ION_SPRD is not set, so /dev/sprd_ion can never appear -- there is
# nothing to wait on and nothing to chown.
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
