/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_MINMAX_H
#define _LINUX_MINMAX_H

/*
 * Backport shim for the ums9230 5.4 tree.
 *
 * Mainline split the min/max/clamp helpers into <linux/minmax.h> in v5.1,
 * but this vendor tree predates that split and keeps them in
 * <linux/kernel.h>.  SukiSU-Ultra includes <linux/minmax.h> directly, so
 * provide the header here and forward to kernel.h.
 */
#include <linux/kernel.h>

#endif /* _LINUX_MINMAX_H */
