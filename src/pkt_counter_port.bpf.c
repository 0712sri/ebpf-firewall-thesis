// SPDX-License-Identifier: GPL-2.0
// src/pkt_counter_port.bpf.c
// Counts UDP packets matching specific dst port on ens20
// Used for forwarded packet counting in benchmark
// Target port is set at runtime via target_port_map

#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

// Runtime-configurable target port
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __type(key, __u32);
    __type(value, __u16);
} target_port_map SEC(".maps");

// Per-CPU forwarded packet counter
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 1);
    __type(key, __u32);
    __type(value, __u64);
} fwd_counter SEC(".maps");

SEC("tc")
int count_forwarded(struct __sk_buff *skb)
{
    void *data     = (void *)(long)skb->data;
    void *data_end = (void *)(long)skb->data_end;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return TC_ACT_OK;
    if (eth->h_proto != bpf_htons(ETH_P_IP)) return TC_ACT_OK;

    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) return TC_ACT_OK;
    if (ip->protocol != IPPROTO_UDP) return TC_ACT_OK;

    struct udphdr *udp = (void *)ip + (ip->ihl * 4);
    if ((void *)(udp + 1) > data_end) return TC_ACT_OK;

    // Read target port from map — set by userspace before benchmark
    __u32 key = 0;
    __u16 *tport = bpf_map_lookup_elem(&target_port_map, &key);
    if (!tport || *tport == 0) return TC_ACT_OK;
    if (udp->dest != bpf_htons(*tport)) return TC_ACT_OK;

    // Increment forwarded counter
    __u64 *cnt = bpf_map_lookup_elem(&fwd_counter, &key);
    if (cnt) __sync_fetch_and_add(cnt, 1);

    return TC_ACT_OK;
}

char _license[] SEC("license") = "GPL";