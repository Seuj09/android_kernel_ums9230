# Magisk: cgroup2 early apps/system (ums9230 A17)

## Why

Kernel `ba98de94` (and later) can put memory/io/cpu/cpuset on unified cgroup2, but A17
still needs `/sys/fs/cgroup/system` and `/sys/fs/cgroup/apps` with controllers
delegated via `cgroup.subtree_control` so `createProcessGroup` can create `uid_*`.
A13 SoT used root-level `uid_*`; A17 expects `system/uid_*`.

## Install (Jeus)

1. Copy `cgroup2-early-ums9230-v1.0.0.zip` to the phone.
2. Magisk app → Modules → Install from storage → pick the zip → Reboot.
3. Keep kernel Image from `ba98de94` (or newer cgroup_no_v1) flashed.

## Verify after reboot (adb shell)

```sh
ls -ld /sys/fs/cgroup /sys/fs/cgroup/apps /sys/fs/cgroup/system
cat /sys/fs/cgroup/cgroup.controllers
cat /sys/fs/cgroup/cgroup.subtree_control
cat /sys/fs/cgroup/system/cgroup.subtree_control
# expect memory/io/cpu/cpuset/pids present where kernel allows

getprop sys.boot_completed
logcat -d | grep -E 'createProcessGroup|libprocessgroup' | tail -30
# createProcessGroup ENOENT should be gone

cat /data/local/tmp/cgroup2-early.log
```

## Optional later

If GSI `cgroups.json` disagrees with this layout, a Magisk overlay of
`/system/etc/cgroups.json` (or product) may be cleaner than mkdir — try this
module first.

## Uninstall

Magisk → Modules → remove → reboot.
