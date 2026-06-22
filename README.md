# eBPF Firewall Chain Compression

Master's thesis — Blekinge Institute of Technology (BTH)

**Title:** eBPF-Based Firewall Chain Compression: Performance Analysis and Rule Translation on Commodity Linux Hardware

## Configurations

| Config | Mechanism | Structure |
|--------|-----------|-----------|
| A  | iptables/nftables | Netfilter baseline |
| B1 | TC eBPF (cls_bpf) | Equivalent chain structure (tail-calls) |
| B2 | TC eBPF (cls_bpf) | Compressed — single program, no boundaries |

**Compression benefit = (Cost_B1 − Cost_B2) / Cost_B1 × 100%**

## Environment

- Ubuntu 24.04, kernel 6.8.0
- clang-18, bpftool v7.4, libbpf v1.4
- BTH OpenStack: xdp-bastion / xdp-sender / xdp-receiver

## Build

```bash
make        # compiles all BPF objects into obj/
make skels  # generates bpftool skeletons
make clean
```

## Run

```bash
sudo bash scripts/tc_attach.sh attach ens3 obj/pkt_counter.bpf.o tc
sudo bash scripts/read_stats.sh
sudo bash scripts/tc_attach.sh detach ens3
```

## Key Prior Work

- Miano et al. 2019 — bpf-iptables (SIGCOMM CCR Best Paper 2020)
- Høiland-Jørgensen et al. 2018 — XDP paperEOF

