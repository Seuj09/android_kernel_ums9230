#!/system/bin/sh
# late_start service — re-assert apps/system if something raced post-fs-data.

CGROOT=/sys/fs/cgroup
LOG=/data/local/tmp/cgroup2-early.log
exec >>"$LOG" 2>&1
echo "=== $(date) service cgroup2-early ==="

[ -f "$CGROOT/cgroup.controllers" ] || exit 0

enable_controllers() {
  _dir=$1
  [ -f "$_dir/cgroup.controllers" ] || return 1
  _avail=$(cat "$_dir/cgroup.controllers")
  for _c in memory io cpu cpuset pids; do
    case " $_avail " in
      *" $_c "*) ;;
      *) continue ;;
    esac
    echo "+${_c}" >"$_dir/cgroup.subtree_control" 2>/dev/null || true
  done
}

enable_controllers "$CGROOT"
mkdir -p "$CGROOT/apps" "$CGROOT/system"
enable_controllers "$CGROOT/apps"
enable_controllers "$CGROOT/system"
chown system:system "$CGROOT/apps" "$CGROOT/system" 2>/dev/null || true
chmod 0755 "$CGROOT/apps" "$CGROOT/system" 2>/dev/null || true
echo "=== service done ==="
