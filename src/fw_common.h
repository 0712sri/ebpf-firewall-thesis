// SPDX-License-Identifier: GPL-2.0
// src/fw_common.h — shared by firewall_b1.bpf.c and firewall_b2.bpf.c
//
// Everything that is NOT the chain structure lives here, so B1 and B2
// differ only in tail calls vs. one program (RQ2: compression is the only
// variable):
//   - one header parser (parse_pkt), run exactly once per packet
//   - one counter update per packet (fw_stats, same map in both)
//   - the rule set itself comes from fw_rules.h (also shared)

#ifndef FW_COMMON_H
#define FW_COMMON_H

#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

// fw_stats keys: 0 = accepted, 1 = dropped, 2 = tail call failed (B1 only, should stay 0)
#define K_ACCEPT  0
#define K_DROP    1
#define K_TCFAIL  2

struct {
    __uint(type,        BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 3);
    __type(key,         __u32);
    __type(value,       __u64);
} fw_stats SEC(".maps");

// one lookup + one add per packet, identical in B1 and B2
// (per-CPU map, TC runs with preemption off -> plain add is safe)
static __always_inline int verdict(__u32 key, int action)
{
    __u64 *v = bpf_map_lookup_elem(&fw_stats, &key);
    if (v)
        *v += 1;
    return action;
}

#define ACCEPT() return verdict(K_ACCEPT, TC_ACT_OK)
#define DROP()   return verdict(K_DROP,   TC_ACT_SHOT)

// parsed packet, host byte order
struct pkt {
    __u32 src;
    __u32 dst;
    __u16 sport;
    __u16 dport;
    __u8  proto;
    __u8  has_l4;   // 1 = sport/dport valid (TCP/UDP, not a non-first fragment)
};

#define PARSE_OK   0
#define PARSE_PASS 1   // not IPv4 (ARP etc.): let it through, iptables FORWARD never sees it
#define PARSE_DROP 2   // broken IPv4 / truncated TCP-UDP header: drop, like iptables does

static __always_inline int parse_pkt(struct __sk_buff *skb, struct pkt *p)
{
    void *data     = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end)          return PARSE_PASS;
    if (eth->h_proto != bpf_htons(ETH_P_IP))   return PARSE_PASS;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end)           return PARSE_DROP;
    if (ip->ihl < 5)                           return PARSE_DROP;
    void *l4 = (void *)ip + ip->ihl * 4;
    if (l4 > data_end)                         return PARSE_DROP;

    p->src    = bpf_ntohl(ip->saddr);
    p->dst    = bpf_ntohl(ip->daddr);
    p->proto  = ip->protocol;
    p->sport  = 0;
    p->dport  = 0;
    p->has_l4 = 0;

    // non-first fragment: no TCP/UDP header -> port rules can't match (same as iptables)
    if (ip->frag_off & bpf_htons(0x1FFF))
        return PARSE_OK;

    if (p->proto == IPPROTO_TCP) {
        struct tcphdr *tcp = l4;
        if ((void *)(tcp + 1) > data_end)      return PARSE_DROP;
        p->sport  = bpf_ntohs(tcp->source);
        p->dport  = bpf_ntohs(tcp->dest);
        p->has_l4 = 1;
    } else if (p->proto == IPPROTO_UDP) {
        struct udphdr *udp = l4;
        if ((void *)(udp + 1) > data_end)      return PARSE_DROP;
        p->sport  = bpf_ntohs(udp->source);
        p->dport  = bpf_ntohs(udp->dest);
        p->has_l4 = 1;
    }
    return PARSE_OK;
}

// B1 only: tail-called programs have no access to the caller's stack, so the
// parsed packet travels in skb->cb[] (5 x 32 bit scratch, kept across tail calls)
static __always_inline void store_pkt(struct __sk_buff *skb, const struct pkt *p)
{
    skb->cb[0] = p->src;
    skb->cb[1] = p->dst;
    skb->cb[2] = ((__u32)p->sport << 16) | p->dport;
    skb->cb[3] = p->proto | ((__u32)p->has_l4 << 8);
}

static __always_inline void load_pkt(struct __sk_buff *skb, struct pkt *p)
{
    __u32 ports = skb->cb[2], w = skb->cb[3];
    p->src    = skb->cb[0];
    p->dst    = skb->cb[1];
    p->sport  = ports >> 16;
    p->dport  = ports & 0xFFFF;
    p->proto  = w & 0xFF;
    p->has_l4 = (w >> 8) & 0xFF;
}

// rule helpers (used by fw_rules.h)
#define IS_TCP(p)        ((p).proto == IPPROTO_TCP)
#define IS_UDP(p)        ((p).proto == IPPROTO_UDP)
#define IS_ICMP(p)       ((p).proto == IPPROTO_ICMP)
#define DPORT(p, x)      ((p).has_l4 && (p).dport == (x))
#define ANYPORT(p, x)    ((p).has_l4 && ((p).dport == (x) || (p).sport == (x)))   // -m multiport --ports
#define SRC_NET(p, net, mask) (((p).src & (mask)) == (net))

#endif // FW_COMMON_H
