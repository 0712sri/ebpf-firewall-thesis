// SPDX-License-Identifier: GPL-2.0
// src/firewall_b2.bpf.c — Config B2: compressed single program
#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

struct {
    __uint(type,        BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 4);
    __type(key,         __u32);
    __type(value,       __u64);
} fw_stats SEC(".maps");

static __always_inline void count(__u32 pk, __u32 bk, __u32 len) {
    __u64 *v; __u32 k = pk;
    v = bpf_map_lookup_elem(&fw_stats, &k); if (v) __sync_fetch_and_add(v, 1);
    k = bk;
    v = bpf_map_lookup_elem(&fw_stats, &k); if (v) __sync_fetch_and_add(v, (__u64)len);
}

SEC("tc")
int firewall_compressed(struct __sk_buff *skb)
{
    void *data     = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) goto accept;
    if (eth->h_proto != bpf_htons(ETH_P_IP)) goto accept;
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) goto accept;
    __u32 src = bpf_ntohl(ip->saddr);
    __u8  proto = ip->protocol;
    if ((src & 0xFFFFFF00U) == 0xC0A86400U) goto drop;
    if (proto == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
        if ((void *)(tcp + 1) > data_end) goto accept;
        __u16 dport = bpf_ntohs(tcp->dest);
        if (dport == 22 && (src & 0xFF000000U) == 0x0A000000U) goto drop;
        if (dport == 80 || dport == 443) goto accept;
        goto drop;
    }
    if (proto == IPPROTO_UDP) {
        struct udphdr *udp = (void *)ip + (ip->ihl * 4);
        if ((void *)(udp + 1) > data_end) goto accept;
        if (bpf_ntohs(udp->dest) == 53) goto accept;
        goto drop;
    }
    if (proto == IPPROTO_ICMP) goto accept;
drop:
    count(1, 3, skb->len); return TC_ACT_SHOT;
accept:
    count(0, 2, skb->len); return TC_ACT_OK;
}
char _license[] SEC("license") = "GPL";
