// SPDX-License-Identifier: GPL-2.0
// src/firewall_b1.bpf.c — Config B1: chain structure preserved with tail calls
//
// One BPF program per iptables chain (same chains as config A):
//   chain_input   = FORWARD      rule 1, then -j FILTER_DROP
//   chain_forward = FILTER_DROP  rules 2-3, then (return to FORWARD) -j ALLOW
//   chain_custom  = ALLOW        rules 4-10, then FORWARD policy DROP
// Program names are unchanged so obj/b1_loader still wires them:
//   chain_jump_table[1] = chain_forward, [2] = chain_custom
//
// FILTER_DROP only drops, and FORWARD has nothing between its two jumps, so
// "return from FILTER_DROP, then -j ALLOW" is one tail call straight to ALLOW.
//
// Rules: src/fw_rules.h. Parser + counters: src/fw_common.h (shared with B2).
// The packet is parsed once in chain_input and passed on in skb->cb[].
// If a tail call fails (jump table empty, e.g. b1_loader not running) the
// packet is DROPPED and counted in fw_stats[2] — the firewall fails closed.

#include "fw_common.h"
#include "fw_rules.h"

struct {
    __uint(type,        BPF_MAP_TYPE_PROG_ARRAY);
    __uint(max_entries, 8);
    __type(key,         __u32);
    __type(value,       __u32);
} chain_jump_table SEC(".maps");

#define JUMP(idx) do {                                    \
        bpf_tail_call(skb, &chain_jump_table, (idx));     \
        return verdict(K_TCFAIL, TC_ACT_SHOT);            \
    } while (0)

SEC("tc")
int chain_input(struct __sk_buff *skb)          // FORWARD
{
    struct pkt p;
    int rc = parse_pkt(skb, &p);
    if (rc == PARSE_PASS) return TC_ACT_OK;
    if (rc == PARSE_DROP) DROP();
    if (LOCAL_DST(p))     return TC_ACT_OK;   // for the firewall itself: INPUT, not FORWARD

    RULES_FORWARD(p)

    store_pkt(skb, &p);
    JUMP(1);                                    // -j FILTER_DROP
}

SEC("tc")
int chain_forward(struct __sk_buff *skb)        // FILTER_DROP
{
    struct pkt p;
    load_pkt(skb, &p);

    RULES_FILTER_DROP(p)

    JUMP(2);                                    // back in FORWARD: -j ALLOW
}

SEC("tc")
int chain_custom(struct __sk_buff *skb)         // ALLOW
{
    struct pkt p;
    load_pkt(skb, &p);

    RULES_ALLOW(p)

    DROP();                                     // FORWARD policy DROP (miss)
}

char _license[] SEC("license") = "GPL";
