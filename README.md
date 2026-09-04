# eBPF Firewall Chain Compression

Master's thesis — Blekinge Institute of Technology (BTH)

**Title:** eBPF-Based Firewall Chain Compression: Performance Analysis and Rule Translation on Commodity Linux Hardware  
**Author:** Srinika Rachaprolu  
**Supervisor:** Patrik Arlos  
**Repo:** github.com/0712sri/ebpf-firewall-thesis (public)

---

## Research Questions

- **RQ1:** What is the measurable difference in throughput, per-packet latency, and CPU utilisation between netfilter (Config A) and TC eBPF (Config B1) for stateless packet filtering across varying rule set sizes?
- **RQ2:** Does compressing multiple iptables chains into a single TC eBPF program (B2) reduce per-packet processing cost compared to equivalent eBPF with chain boundaries preserved (B1), and what are the measurable benefits and drawbacks?
- **RQ3:** Can stateless iptables rules be automatically translated to TC eBPF BPF C code, and what is the translation coverage?

---

## Configurations

| Config | Mechanism | Programs | Instructions | Tail-calls/pkt |
|--------|-----------|----------|-------------|----------------|
| A  | iptables stateless FORWARD chain | kernel built-in | N/A | N/A |
| B1 | TC eBPF — 3 programs + tail-calls | 3 | 265 total | 2 |
| B2 | TC eBPF — single compressed program | 1 | 126 | 0 |

**RQ1 comparison:** A vs B1  
**RQ2 comparison:** B1 vs B2  
**Compression benefit (B1→B2):** 52.5% fewer instructions, 0 vs 2 tail-calls

---

## Network TopologySSH: bastion at 194.47.155.207 → VMs via ProxyJump

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
```

---

## Benchmark Methodology### Traffic generator
Linux kernel pktgen — exact packet count per trial (target_pps × 10s), controlled dst port, src IP = 192.168.1.2.

### Ingress/egress measurement
TC eBPF counter on ens20 egress counts only benchmark packets (by UDP dst port).  
**Loss % = (offered − forwarded) / offered**  
DROP tests recorded as correct firewall behaviour, not packet loss.

### Rule position testing
Generated via `scripts/rule_generator.py`:
- port 80 = rule 1 (best case)
- port 5500 = rule N/2 (middle case)
- port 9900 = rule N (worst case)
- port 9999 = miss → default DROP

### Experiment matrix

| Experiment | Comparison | Metrics | RQ |
|-----------|------------|---------|-----|
| 1 — Rule position | B2, N=10, best/middle/worst/miss | PPS, loss% | RQ2 setup |
| 2 — Compression | B1 vs B2, N=10/100 | PPS, loss%, CPU cycles | RQ2 |
| 3 — eBPF vs netfilter | A vs B1, N=10/100 | PPS, latency, CPU% | RQ1 |

---

## Run

```bash
# Load N rules — Config A
python3 scripts/rule_generator.py 10 config_a --apply

# Attach B2
sudo bash scripts/tc_attach.sh attach ens19 obj/firewall_b2.bpf.o tc

# Setup egress counter
sudo tc filter del dev ens20 egress 2>/dev/null || true
sudo tc qdisc add dev ens20 clsact 2>/dev/null || true
sudo tc filter add dev ens20 egress bpf obj obj/pkt_counter_port.bpf.o sec tc direct-action
sudo bash scripts/set_counter_port.sh 80

# Run benchmark (on xdp-sender)
sudo bash scripts/bench_pktgen.sh b2 10 best accept

# Read forwarded count (on xdp-firewall)
sudo bash scripts/read_fwd_counter.sh
```

---

## Key Results (preliminary)

| Metric | bare | Config A | B1 | B2 |
|--------|------|----------|-----|-----|
| Throughput mean (Gbits/sec) | 2.32 | 2.37 | 2.29 | 2.32 |
| CPU %sys | 8.30% | 22.49% | 22.94% | 21.62% |
| Latency P50 (ms) | 1.60 | 1.61 | 1.62 | 1.62 |
| Instructions | — | N/A | 265 | 126 |
| Tail-calls/packet | 0 | N/A | 2 | 0 |---

## Key References

- Turull, D., Sjödin, P., Olsson, R. (2016). Pktgen: Measuring performance on high speed networks. *Computer Communications*, 82, 39–48.
- Miano et al. (2019). bpf-iptables (SIGCOMM CCR Best Paper 2020)
- Høiland-Jørgensen et al. (2018). The eXpress Data Path
- RFC 2544 — Benchmarking methodology for network interconnect devices
