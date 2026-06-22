// SPDX-License-Identifier: GPL-2.0
// src/pkt_counter.bpf.c — Stage 1 smoke test
#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <bpf/bpf_helpers.h>

struct {
    __uint(type,        BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 2);
    __type(key,         __u32);
    __type(value,       __u64);
} pkt_stats SEC(".maps");

SEC("tc")
int pkt_counter(struct __sk_buff *skb)
{
    __u32 key; __u64 *val;
    key = 0; val = bpf_map_lookup_elem(&pkt_stats, &key);
    if (val) __sync_fetch_and_add(val, 1);
    key = 1; val = bpf_map_lookup_elem(&pkt_stats, &key);
    if (val) __sync_fetch_and_add(val, (__u64)skb->len);
    return TC_ACT_OK;
}
char _license[] SEC("license") = "GPL";
