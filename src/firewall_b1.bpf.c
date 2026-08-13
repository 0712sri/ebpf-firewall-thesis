// SPDX-License-Identifier: GPL-2.0
// src/firewall_b1.bpf.c — Config B1: tail-call chain structure
// SAFETY: Rule 0 always ACCEPTs SSH from bastion (10.8.50.180)

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

struct {
    __uint(type,        BPF_MAP_TYPE_PROG_ARRAY);
    __uint(max_entries, 8);
    __type(key,         __u32);
    __type(value,       __u32);
} chain_jump_table SEC(".maps");

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

static __always_inline struct iphdr *parse_ip(struct __sk_buff *skb) {
    void *data = (void *)(long)skb->data, *data_end = (void *)(long)skb->data_end;
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return NULL;
    if (eth->h_proto != bpf_htons(ETH_P_IP)) return NULL;
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return NULL;
    return ip;
}

SEC("tc") int chain_input(struct __sk_buff *skb) {
    struct iphdr *ip = parse_ip(skb); if (!ip) goto accept;
    __u32 src = bpf_ntohl(ip->saddr);
    void *data_end = (void *)(long)skb->data_end;

    // Rule 0 — SAFETY: always ACCEPT SSH from bastion
    if (src == BASTION_IP && ip->protocol == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
        if ((void *)(tcp + 1) <= data_end && bpf_ntohs(tcp->dest) == 22)
            goto accept;
    }

    // Rule 1 — DROP src 192.168.100.0/24
    if ((src & 0xFFFFFF00U) == 0xC0A86400U) { count(1,3,skb->len); return TC_ACT_SHOT; }

    // Rule 2 — DROP tcp:22 from 10.0.0.0/8
    if (ip->protocol == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
        if ((void *)(tcp+1) <= data_end && bpf_ntohs(tcp->dest)==22 &&
            (src & 0xFF000000U) == 0x0A000000U)
            { count(1,3,skb->len); return TC_ACT_SHOT; }
    }

    bpf_tail_call(skb, &chain_jump_table, 1);
accept:
    count(0,2,skb->len); return TC_ACT_OK;
}

SEC("tc") int chain_forward(struct __sk_buff *skb) {
    struct iphdr *ip = parse_ip(skb); if (!ip) goto accept;
    void *data_end = (void *)(long)skb->data_end;

    // Rule 3,4,5 — ACCEPT tcp:80, tcp:443, tcp:5201 both directions
    if (ip->protocol == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
        if ((void *)(tcp+1) <= data_end) {
            __u16 d = bpf_ntohs(tcp->dest);
            __u16 s = bpf_ntohs(tcp->source);
            if (d==80||d==443||d==5201||s==80||s==443||s==5201)
                { count(0,2,skb->len); return TC_ACT_OK; }
        }
    }

    // Rule 6 — ACCEPT udp:53 and udp:5001
    if (ip->protocol == IPPROTO_UDP) {
        struct udphdr *udp = (void *)ip + (ip->ihl * 4);
        if ((void *)(udp+1) <= data_end && (bpf_ntohs(udp->dest)==53 || bpf_ntohs(udp->dest)==5001))
            { count(0,2,skb->len); return TC_ACT_OK; }
    }

    // Rule 7 — ACCEPT ICMP
    if (ip->protocol == IPPROTO_ICMP) { count(0,2,skb->len); return TC_ACT_OK; }

    bpf_tail_call(skb, &chain_jump_table, 2);
accept:
    count(0,2,skb->len); return TC_ACT_OK;
}

SEC("tc") int chain_custom(struct __sk_buff *skb) {
    count(1,3,skb->len); return TC_ACT_SHOT;
}

char _license[] SEC("license") = "GPL";