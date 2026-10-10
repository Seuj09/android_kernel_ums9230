/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _NET_BPF_SK_LOOKUP_H
#define _NET_BPF_SK_LOOKUP_H

#include <linux/bpf.h>
#include <linux/errno.h>
#include <linux/err.h>
#include <linux/filter.h>
#include <linux/in.h>
#include <linux/static_key.h>
#include <net/net_namespace.h>

/* Runners for BPF_SK_LOOKUP programs to invoke on socket lookup.
 *
 * Allowed return values for a BPF SK_LOOKUP program are SK_PASS and
 * SK_DROP. Their meaning is as follows:
 *
 *  SK_PASS && ctx.selected_sk != NULL: use selected_sk as lookup result
 *  SK_PASS && ctx.selected_sk == NULL: continue to htable-based socket lookup
 *  SK_DROP                           : terminate lookup with -ECONNREFUSED
 *
 * This macro aggregates return values and selected sockets from
 * multiple BPF programs according to following rules in order:
 *
 *  1. If any program returned SK_PASS and a non-NULL ctx.selected_sk,
 *     macro result is SK_PASS and last ctx.selected_sk is used.
 *  2. If any program returned SK_DROP return value,
 *     macro result is SK_DROP.
 *  3. Otherwise result is SK_PASS and ctx.selected_sk is NULL.
 *
 * Caller must ensure that the prog array is non-NULL, and that the
 * array as well as the programs it contains remain valid.
 */
#define BPF_PROG_SK_LOOKUP_RUN_ARRAY(array, ctx, func)			\
	({								\
		struct bpf_sk_lookup_kern *_ctx = &(ctx);		\
		struct bpf_prog_array_item *_item;			\
		struct sock *_selected_sk = NULL;			\
		bool _no_reuseport = false;				\
		struct bpf_prog *_prog;					\
		bool _all_pass = true;					\
		u32 _ret;						\
									\
		migrate_disable();					\
		_item = &(array)->items[0];				\
		while ((_prog = READ_ONCE(_item->prog))) {		\
			/* restore most recent selection */		\
			_ctx->selected_sk = _selected_sk;		\
			_ctx->no_reuseport = _no_reuseport;		\
									\
			_ret = func(_prog, _ctx);			\
			if (_ret == SK_PASS && _ctx->selected_sk) {	\
				/* remember last non-NULL socket */	\
				_selected_sk = _ctx->selected_sk;	\
				_no_reuseport = _ctx->no_reuseport;	\
			} else if (_ret == SK_DROP && _all_pass) {	\
				_all_pass = false;			\
			}						\
			_item++;					\
		}							\
		_ctx->selected_sk = _selected_sk;			\
		_ctx->no_reuseport = _no_reuseport;			\
		migrate_enable();					\
		_all_pass || _selected_sk ? SK_PASS : SK_DROP;		\
	 })

static inline bool bpf_sk_lookup_run_v4(struct net *net, int protocol,
					 const __be32 saddr, const __be16 sport,
					 const __be32 daddr, const u16 dport,
					 struct sock **psk)
{
	struct bpf_prog_array *run_array;
	struct sock *selected_sk = NULL;
	bool no_reuseport = false;

	rcu_read_lock();
	run_array = rcu_dereference(net->bpf.run_array[NETNS_BPF_SK_LOOKUP]);
	if (run_array) {
		struct bpf_sk_lookup_kern ctx = {
			.family		= AF_INET,
			.protocol	= protocol,
			.v4.saddr	= saddr,
			.v4.daddr	= daddr,
			.sport		= sport,
			.dport		= dport,
		};
		u32 act;

		act = BPF_PROG_SK_LOOKUP_RUN_ARRAY(run_array, ctx, BPF_PROG_RUN);
		if (act == SK_PASS) {
			selected_sk = ctx.selected_sk;
			no_reuseport = ctx.no_reuseport;
		} else {
			selected_sk = ERR_PTR(-ECONNREFUSED);
		}
	}
	rcu_read_unlock();
	*psk = selected_sk;
	return no_reuseport;
}

#if IS_ENABLED(CONFIG_IPV6)
static inline bool bpf_sk_lookup_run_v6(struct net *net, int protocol,
					 const struct in6_addr *saddr,
					 const __be16 sport,
					 const struct in6_addr *daddr,
					 const u16 dport,
					 struct sock **psk)
{
	struct bpf_prog_array *run_array;
	struct sock *selected_sk = NULL;
	bool no_reuseport = false;

	rcu_read_lock();
	run_array = rcu_dereference(net->bpf.run_array[NETNS_BPF_SK_LOOKUP]);
	if (run_array) {
		struct bpf_sk_lookup_kern ctx = {
			.family		= AF_INET6,
			.protocol	= protocol,
			.v6.saddr	= saddr,
			.v6.daddr	= daddr,
			.sport		= sport,
			.dport		= dport,
		};
		u32 act;

		act = BPF_PROG_SK_LOOKUP_RUN_ARRAY(run_array, ctx, BPF_PROG_RUN);
		if (act == SK_PASS) {
			selected_sk = ctx.selected_sk;
			no_reuseport = ctx.no_reuseport;
		} else {
			selected_sk = ERR_PTR(-ECONNREFUSED);
		}
	}
	rcu_read_unlock();
	*psk = selected_sk;
	return no_reuseport;
}
#endif /* IS_ENABLED(CONFIG_IPV6) */

#endif /* _NET_BPF_SK_LOOKUP_H */
