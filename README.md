# eBPF Firewall Chain Compression

Master's thesis — Blekinge Institute of Technology (BTH)

**Title:** eBPF-Based Firewall Chain Compression: Performance Analysis and Rule Translation on Commodity Linux Hardware  
**Author:** Srinika Rachaprolu  
**Supervisor:** Patrik Arlos  
**Repo:** github.com/0712sri/ebpf-firewall-thesis

---

## Research Questions

- **RQ1:** Does TC eBPF outperform netfilter (iptables) for stateless packet filtering?
- **RQ2:** Does compressing eBPF chains (B1→B2) reduce per-packet cost?
- **RQ3:** Can stateless iptables rules be automatically translated to TC eBPF?

---

## Configurations

| Config | Mechanism | Structure | Instructions | Tail-calls |
|--------|-----------|-----------|-------------|------------|
| A  | iptables stateless | Netfilter FORWARD chain, bidirectional rules | N/A | N/A |
| B1 | TC eBPF (cls_bpf) | 3 programs connected by tail-calls | 265 total | 2 per packet |
| B2 | TC eBPF (cls_bpf) | Single compressed program, goto statements | 126 | 0 |

**Compression benefit (B1→B2): 52.5% fewer instructions**

---

## Network TopologySSH access: bastion at 194.47.155.207 → VMs via ProxyJump

---

## Environment

- Ubuntu 24.04, kernel 6.8.0
- clang-18, bpftool v7.4, libbpf v1.4, iproute2 tc
- BTH Proxmox: xdp-bastion / xdp-sender / xdp-firewall / xdp-receiver

---

## Build

```bash
# On xdp-firewall
make clean && make
# Produces: obj/firewall_b1.bpf.o  obj/firewall_b2.bpf.o
#           obj/firewall_generated.bpf.o  obj/b1_loader
```

---

## Run

```bash
# Config A — iptables stateless bidirectional
sudo bash scripts/config_a_setup.sh load
sudo bash scripts/config_a_setup.sh flush

# Config B2 — attach/detach
sudo bash scripts/tc_attach.sh attach ens19 obj/firewall_b2.bpf.o tc
sudo bash scripts/tc_attach.sh detach ens19

# Config B1 — load/unload
sudo ./obj/b1_loader ens19 &
kill %1

# Read BPF stats
sudo bash scripts/read_stats.sh fw_stats

# Benchmark — run from xdp-sender
iperf3 -c 192.168.2.2 -t 30
ping -c 1000 -i 0.05 192.168.2.2

# Saturation test — run from xdp-sender
sudo bash scripts/pktgen_sender.sh 50000 10 64

# RQ3 — auto-translate iptables rules to BPF C
sudo iptables-save | python3 scripts/rule_compiler.py
```

---

## Key Results

| Metric | bare | Config A | B1 | B2 |
|--------|------|----------|-----|-----|
| Throughput (Gbits/sec) | 2.32 | 2.37 | 2.29 | 2.32 |
| CPU %sys | 8.30% | 22.49% | 22.94% | 21.62% |
| Latency P50 (ms) | 1.60 | 1.61 | 1.62 | 1.62 |
| Instructions | — | N/A | 265 | 126 |
| Tail-calls/packet | — | N/A | 2 | 0 |

---

## Repository Structure---

## Key Prior Work

- Miano et al. 2019 — bpf-iptables (SIGCOMM CCR Best Paper 2020)
- Høiland-Jørgensen et al. 2018 — XDP paper
