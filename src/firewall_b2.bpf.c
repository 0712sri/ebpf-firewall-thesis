// SPDX-License-Identifier: GPL-2.0
// src/firewall_b2.bpf.c — Config B2: compressed single program (optimised)
// SAFETY: Rule 0 always ACCEPTs SSH from bastion (10.8.50.180)
// Optimisations vs original:
//   - Port extracted once (not per-rule)
//   - Simplified stats: 2 slots only (accept/drop)
//   - Single L4 parse path

#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

#define BASTION_IP 0x0A0832B4U  // 10.8.50.180

// Simplified stats: 0=accepted, 1=dropped
struct {
    __uint(type,        BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 2);
    __type(key,         __u32);
    __type(value,       __u64);
} fw_stats SEC(".maps");

static __always_inline void count(__u32 dropped) {
    __u64 *v = bpf_map_lookup_elem(&fw_stats, &dropped);
    if (v) __sync_fetch_and_add(v, 1);
}

SEC("tc")
int firewall_compressed(struct __sk_buff *skb)
{
    void *data     = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;

    // L2 parse
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return TC_ACT_OK;
    if (eth->h_proto != bpf_htons(ETH_P_IP)) return TC_ACT_OK;

    // L3 parse
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return TC_ACT_OK;

    __u32 src   = bpf_ntohl(ip->saddr);
    __u8  proto = ip->protocol;
    __u16 dport = 0;

    // L4 parse — extract dest port once for TCP or UDP
    if (proto == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
        if ((void *)(tcp + 1) > data_end) return TC_ACT_OK;
        dport = bpf_ntohs(tcp->dest);
    } else if (proto == IPPROTO_UDP) {
        struct udphdr *udp = (void *)ip + (ip->ihl * 4);
        if ((void *)(udp + 1) > data_end) return TC_ACT_OK;
        dport = bpf_ntohs(udp->dest);
    }

    // Rule 0 — SAFETY: always ACCEPT SSH from bastion
    if (src == BASTION_IP && proto == IPPROTO_TCP && dport == 22) {
        count(0); return TC_ACT_OK;
    }

    // Rule 1 — DROP src 192.168.100.0/24
    if ((src & 0xFFFFFF00U) == 0xC0A86400U) {
        count(1); return TC_ACT_SHOT;
    }

    // Rule 2 — DROP tcp:22 from 10.0.0.0/8
    if (proto == IPPROTO_TCP && dport == 22 &&
        (src & 0xFF000000U) == 0x0A000000U) {
        count(1); return TC_ACT_SHOT;
    }

    // Rule 3 — ACCEPT tcp:80, tcp:443, tcp:5201 both directions
    if (proto == IPPROTO_TCP) {
    struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
    if ((void *)(tcp + 1) > data_end) return TC_ACT_OK;
    __u16 sport = bpf_ntohs(tcp->source);
    if (dport == 80 || dport == 443 || dport == 5201 ||
        sport == 80 || sport == 443 || sport == 5201) {
        count(0); return TC_ACT_OK;
    }
    count(1); return TC_ACT_SHOT;
    }

    // Rule 4 — ACCEPT udp:53 (DNS)
    if (proto == IPPROTO_UDP && (dport == 53 || dport == 5001 ||
    dport == 80 || dport == 5500 || dport == 9900)) {   
        count(0); return TC_ACT_OK;
    }
    // Rule 5 — ACCEPT ICMP
    if (proto == IPPROTO_ICMP) {
        count(0); return TC_ACT_OK;
    }

    // Rule 6 — DROP default
    count(1); return TC_ACT_SHOT;
}

char _license[] SEC("license") = "GPL";