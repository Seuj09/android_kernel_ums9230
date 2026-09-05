/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_PGTABLE_H
#define _LINUX_PGTABLE_H

/*
 * Backport shim for the ums9230 5.4 tree.
 *
 * <linux/pgtable.h> was introduced in v5.9 as the generic page-table
 * header.  SukiSU-Ultra includes it, but references no pgtable symbols
 * from it, so mapping it onto the 5.4-era <asm/pgtable.h> is sufficient.
 */
#include <asm/pgtable.h>

#endif /* _LINUX_PGTABLE_H */
