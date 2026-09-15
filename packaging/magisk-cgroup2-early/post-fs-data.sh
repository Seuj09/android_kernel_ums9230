#!/system/bin/sh
# Magisk post-fs-data — earliest reliable user hook for cgroup2 layout.
# A17 GSI expects /sys/fs/cgroup/{apps,system} with controllers delegated
# so libprocessgroup can create system/uid_* (createProcessGroup).

CGROOT=/sys/fs/cgroup
LOGDIR=/data/local/tmp
LOG=$LOGDIR/cgroup2-early.log

mkdir -p "$LOGDIR"
exec >>"$LOG" 2>&1
echo "=== $(date) post-fs-data cgroup2-early ==="

mkdir -p "$CGROOT"

# Mount cgroup2 only if controllers file missing (do not remount over vendor layout).
if [ ! -f "$CGROOT/cgroup.controllers" ]; then
  mount -t cgroup2 -o rw,nosuid,nodev,noexec,relatime cgroup2 "$CGROOT" 2>/dev/null \
    || mount -t cgroup2 none "$CGROOT" 2>/dev/null \
    || true
fi

# Brief wait for init/kernel to publish controllers after ba98de94-style boot.
i=0
while [ ! -f "$CGROOT/cgroup.controllers" ] && [ "$i" -lt 100 ]; do
  usleep 100000 2>/dev/null || sleep 0.1
  i=$((i + 1))
done

if [ ! -f "$CGROOT/cgroup.controllers" ]; then
  echo "FAIL: $CGROOT/cgroup.controllers missing — abort (kernel cmdline/cgroup2 not ready)"
  exit 0
fi

echo "root controllers: $(tr '\n' ' ' < "$CGROOT/cgroup.controllers")"

enable_controllers() {
  _dir=$1
  [ -f "$_dir/cgroup.controllers" ] || return 1
  _avail=$(cat "$_dir/cgroup.controllers")
  for _c in memory io cpu cpuset pids; do
    case " $_avail " in
      *" $_c "*) ;;
      *) continue ;;
    esac
    # Enable one-by-one; ignore already-enabled / busy errors.
    echo "+${_c}" >"$_dir/cgroup.subtree_control" 2>/dev/null || true
  done
  echo "subtree_control $_dir: $(cat "$_dir/cgroup.subtree_control" 2>/dev/null)"
  return 0
}

enable_controllers "$CGROOT"

mkdir -p "$CGROOT/apps" "$CGROOT/system"

enable_controllers "$CGROOT/apps"
enable_controllers "$CGROOT/system"

# AOSP SetupCgroups / processgroup: dirs are world-traversable; system_server
# creates uid_* as privileged. system:system ownership matches common GSI norms
# without blocking root zygote.
chown system:system "$CGROOT/apps" "$CGROOT/system" 2>/dev/null || true
chmod 0755 "$CGROOT/apps" "$CGROOT/system" 2>/dev/null || true

ls -ld "$CGROOT" "$CGROOT/apps" "$CGROOT/system"
echo "=== post-fs-data done ==="
