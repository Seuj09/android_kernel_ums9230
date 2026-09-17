# Helix-Tweaked — Performance profile

Branch: `tweaks`  
LOCALVERSION: `-Helix-Tweaked` (kept; see `unisoc_defconfig`)

This document describes boot-safe performance defaults applied for Helix-Tweaked.
Thermal emergency limits remain enabled.

## What changed

### 1. CPUFreq default governor → `performance`

In `arch/arm64/configs/unisoc_defconfig`:

- `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y`
- `# CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL is not set` (was default)

**All governors stay enabled** (userspace can switch anytime):

- performance, powersave, userspace, ondemand, conservative, interactive, schedutil

No other in-tree CPUFreq governors were missing for this tree (5.4 Unisoc).

### 2. CPU idle: TEO enabled (MENU kept)

- `CONFIG_CPU_IDLE_GOV_TEO=y`
- `CONFIG_CPU_IDLE_GOV_MENU=y` (unchanged)

TEO can improve idle selection latency on interactive workloads; MENU remains available.

### 3. Sprd CPUFreq boot boost: 60s → 600s (10 minutes)

Unisoc auto-disables cpufreq boost a short time after boot. For the performance
profile this window was extended substantially (thermal cooling paths untouched):

| File | Macro | Was | Now |
|------|-------|-----|-----|
| `drivers/cpufreq/sprd-cpufreq-common.h` | `SPRD_CPUFREQ_DRV_BOOST_DURATOIN` | 60 × HZ | **600 × HZ** |
| `drivers/cpufreq/sprd-cpufreq-v2-driver.c` | `SPRD_CPUFREQ_BOOST_DURATION` | 60 × HZ | **600 × HZ** |

Boost still auto-disables after the window (or earlier if policy max is lowered).
`CONFIG_SPRD_THERMAL_MAX_FREQ_LIMIT=y` is **not** disabled.

### 4. DEVFREQ

Defconfig already had:

- `CONFIG_DEVFREQ_GOV_PERFORMANCE=y` (+ powersave, userspace, passive, simple_ondemand)
- `CONFIG_DEVFREQ_GOV_SPRD_VOTE=m`

**DDR default governor left as `sprd-governor`** in
`drivers/devfreq/sprd/sprd_ddr_dvfs_core.c` — switching this string to
`performance` is **not** considered boot-safe on Unisoc vote/DVFS paths.
Userspace may still switch DEVFREQ governors where the driver allows.

### 5. Explicitly left alone (safety / disk / prior policy)

- `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3` — left unset (O2 / default PERFORMANCE)
- `CONFIG_SPRD_THERMAL_MAX_FREQ_LIMIT` — remains **y**
- HybridSwap / MGLRU (`CONFIG_LRU_GEN_ENABLED`) — remain default-off
- No bpf / maple_tree / per-VMA / SukiSU / master merges

## GPU / APSYS (DT / userspace — not changed in kernel defaults)

These use Unisoc-specific governor names wired in drivers; they are **not**
switched to generic `performance` here (boot / display / multimedia safety):

| Path | Governor name |
|------|----------------|
| GSP | `gsp_governor` |
| VSP | `vsp_governor` |
| DPU | `dpu_governor` |
| VDSP | `vdsp_governor` |
| DDR DVFS | `sprd-governor` (vote) |

GPU clocks / opp are typically DT + userspace (HAL / powerHAL). Document only;
no DT edits in this change set.

## Verify on device (sysfs)

After boot, as root / adb shell:

```sh
# Kernel identity
uname -a   # expect ...-Helix-Tweaked...

# CPUFreq default / current governor (per policy)
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
# expect: performance (until userspace overrides)

# Available governors
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors

# Current freqs (should sit high with performance)
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq

# DEVFREQ devices (names vary by platform)
ls /sys/class/devfreq/
# optional: cat /sys/class/devfreq/*/governor

# Thermal still present
ls /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head
```

dmesg around boot may show boost disable after ~600s:

```text
Disables boost it is 600 seconds after boot up
```

## Heat / battery caveat

**Default `performance` keeps CPUs at high OPP.** Expect:

- Higher surface temperature under sustained load
- Faster battery drain
- Thermal framework (`SPRD_THERMAL_MAX_FREQ_LIMIT`) may still cap freq when hot

If the device feels too warm, switch governors (e.g. `schedutil` or `interactive`)
via sysfs or your ROM’s power profile — all governors remain built-in.

## Packing note

Flashable zip for CI Image: `Helix-Tweaked_Beta.zip` (AnyKernel3, Image-only
`split_boot` + `flash_boot`), published on release tag `tweaks-f8b3e47`.
