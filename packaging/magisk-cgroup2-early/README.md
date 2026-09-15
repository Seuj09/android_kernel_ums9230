# cgroup2 early apps/system (ums9230 A17) — ReSukiSU / TWRP

Jeus runs **ReSukiSU**, not Magisk Manager. Use the **TWRP** zip.

## Download

- TWRP/ReSukiSU zip (primary):
  https://raw.githubusercontent.com/Seuj09/android_kernel_ums9230/bpf/packaging/magisk-cgroup2-early/cgroup2-early-ums9230-twrp-v1.0.0.zip
- Or from tree: `packaging/magisk-cgroup2-early/cgroup2-early-ums9230-twrp-v1.0.0.zip` on branch `bpf`
- Legacy Magisk `update-binary` zip (`cgroup2-early-ums9230-v1.0.0.zip`) is wrong for ReSukiSU — ignore unless on Magisk.

## Install (Jeus)

1. Kernel `ba98de94`+ still required (cgroup_no_v1 includes memory).
2. Flash `cgroup2-early-ums9230-twrp-v1.0.0.zip` in TWRP (or any recovery that runs META-INF update-binary).
3. Installer copies `module.prop` / `post-fs-data.sh` / `service.sh` to  
   `/data/adb/modules/cgroup2_early_ums9230/` (KernelSU/ReSukiSU module dir).
4. Reboot A17.

Manual alternate (adb root / recovery shell):

```sh
MOD=/data/adb/modules/cgroup2_early_ums9230
mkdir -p "$MOD"
# copy the three files from the zip, then:
chmod 755 "$MOD/post-fs-data.sh" "$MOD/service.sh"
chmod 644 "$MOD/module.prop"
rm -f "$MOD/disable" "$MOD/remove"
reboot
```

## Verify

```sh
ls -ld /sys/fs/cgroup/apps /sys/fs/cgroup/system
cat /sys/fs/cgroup/cgroup.subtree_control
cat /sys/fs/cgroup/system/cgroup.subtree_control
ls /data/adb/modules/cgroup2_early_ums9230/
getprop sys.boot_completed
logcat -d | grep -E 'createProcessGroup|ActivateControllers' | tail -30
cat /data/local/tmp/cgroup2-early.log
```

If `ActivateControllers` hits EBUSY after mkdir, next step is an early `cgroups.json` overlay (not this zip).
