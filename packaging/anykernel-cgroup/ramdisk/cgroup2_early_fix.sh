#!/system/bin/sh
CG=/sys/fs/cgroup
LOG=/dev/kmsg
log() { echo "cgroup2_early: $*" >"$LOG" 2>/dev/null || true; }
mkdir -p "$CG" 2>/dev/null || true
need_remount=0
if [ ! -f "$CG/cgroup.controllers" ]; then
  need_remount=1
elif grep -qs " $CG " /proc/mounts; then
  grep -qs "cgroup2 $CG\| $CG cgroup2" /proc/mounts || need_remount=1
fi
if [ "$need_remount" = 1 ]; then
  log "remounting cgroup2 on $CG"
  if grep -qs " $CG " /proc/mounts; then
    umount "$CG" 2>/dev/null || umount -l "$CG" 2>/dev/null || true
  fi
  mount -t cgroup2 -o rw,nosuid,nodev,noexec,relatime none "$CG" 2>/dev/null \
    || mount -t cgroup2 none "$CG" 2>/dev/null \
    || { log "mount FAILED"; exit 0; }
fi
[ -f "$CG/cgroup.controllers" ] || { log "no cgroup.controllers"; exit 0; }
enable_dir() {
  _d=$1
  mkdir -p "$_d" 2>/dev/null || true
  [ -f "$_d/cgroup.controllers" ] || return 0
  _avail=$(cat "$_d/cgroup.controllers")
  _line=""
  for _c in cpuset cpu io memory pids; do
    case " $_avail " in
      *" $_c "*) _line="$_line +$_c" ;;
    esac
  done
  _line=$(echo "$_line" | sed 's/^ //')
  [ -n "$_line" ] || return 0
  echo "$_line" >"$_d/cgroup.subtree_control" 2>/dev/null \
    || {
      for _c in cpuset cpu io memory pids; do
        case " $_avail " in *" $_c "*) echo "+$_c" >"$_d/cgroup.subtree_control" 2>/dev/null || true ;; esac
      done
    }
  log "subtree $_d: $(cat "$_d/cgroup.subtree_control" 2>/dev/null)"
}
enable_dir "$CG"
mkdir -p "$CG/apps" "$CG/system"
chown system:system "$CG/apps" "$CG/system" 2>/dev/null || true
chmod 0755 "$CG/apps" "$CG/system" 2>/dev/null || true
enable_dir "$CG/apps"
enable_dir "$CG/system"
log "done"
exit 0
