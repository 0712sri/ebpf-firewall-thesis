// SPDX-License-Identifier: GPL-2.0
// src/firewall_b2.bpf.c — Config B2: chains compressed into ONE program
//
// Exactly the same rules, in the same order, as B1 and config A
// (src/fw_rules.h), but FORWARD -> FILTER_DROP -> ALLOW are evaluated in a
// single program: no tail calls, no skb->cb[] hand-over.
// Parser + counters: src/fw_common.h (shared with B1).

#include "fw_common.h"
#include "fw_rules.h"

SEC("tc")
int firewall_compressed(struct __sk_buff *skb)
{
    struct pkt p;
    int rc = parse_pkt(skb, &p);
    if (rc == PARSE_PASS) return TC_ACT_OK;
    if (rc == PARSE_DROP) DROP();
    if (LOCAL_DST(p))     return TC_ACT_OK;   // for the firewall itself: INPUT, not FORWARD

    RULES_FORWARD(p)          // FORWARD
    RULES_FILTER_DROP(p)      // FILTER_DROP (inlined)
    RULES_ALLOW(p)            // ALLOW       (inlined)

    DROP();                   // FORWARD policy DROP (miss)
}

char _license[] SEC("license") = "GPL";
