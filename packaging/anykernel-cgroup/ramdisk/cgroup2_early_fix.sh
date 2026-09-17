#!/system/bin/sh
# Best-effort cgroup2 apps/system setup; logs every step to /dev/kmsg.
CG=/sys/fs/cgroup
log() { echo "cgroup2_early: $*" > /dev/kmsg 2>/dev/null || true; }

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
exit 0
