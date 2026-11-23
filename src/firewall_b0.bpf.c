// SPDX-License-Identifier: GPL-2.0
// src/firewall_b0.bpf.c — Config B0: empty baseline (Patrik: "subtract an
// empty-program baseline")
//
// Same entry, same parser and same counter as B1/B2, but NO rules: every
// IPv4 packet is accepted. Measured the same way as B1/B2, so
//   cost of the rule evaluation = ns/packet(B1 or B2) - ns/packet(B0)
// B0 also absorbs the overhead that kernel.bpf_stats_enabled itself adds.

#include "fw_common.h"
#include "fw_rules.h"   // LOCAL_DST only — no rules are used

SEC("tc")
int firewall_empty(struct __sk_buff *skb)
{
    struct pkt p;
    int rc = parse_pkt(skb, &p);
    if (rc == PARSE_PASS) return TC_ACT_OK;
    if (rc == PARSE_DROP) DROP();
    if (LOCAL_DST(p))     return TC_ACT_OK;

    ACCEPT();                 // no rules
}

char _license[] SEC("license") = "GPL";

