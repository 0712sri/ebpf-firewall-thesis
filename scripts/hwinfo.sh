#!/usr/bin/env bash
# scripts/hwinfo.sh — record the hardware/software setup of THIS machine (read-only).
# run.sh runs it on casual-lamb and apt-kitten and stores the output as
# hwinfo_<host>.txt in every results folder (reproducibility: CPU, NIC, driver,
# kernel, IRQ affinity, offloads, TC configuration).
#
# Usage: bash scripts/hwinfo.sh [test interface]     (default: the VLAN parent NIC)

IF=${1:-}
if [ -z "$IF" ]; then
    case "$(hostname)" in
        casual-lamb) IF=enp0s25 ;;
        apt-kitten|smooth-gecko) IF=eno2 ;;
        *) IF=$(ip -o route show default | awk '{print $5; exit}') ;;
    esac
fi
sec() { echo; echo "=== $* ==="; }
run() { echo "\$ $*"; "$@" 2>&1 || true; }

echo "hwinfo $(hostname)  $(date -Is)  test NIC: $IF"
sec OS / kernel;      grep PRETTY /etc/os-release; uname -a
sec CPU;              lscpu | grep -E 'Model name|Socket|Core|Thread|^CPU\(s\)|MHz|NUMA node\(|L1d|L2|L3'
sec CPU frequency;    for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do [ -d "$c" ] && echo "$(basename "$(dirname "$c")") governor=$(cat "$c/scaling_governor" 2>/dev/null) cur_kHz=$(cat "$c/scaling_cur_freq" 2>/dev/null)"; done
sec Memory;           grep MemTotal /proc/meminfo
sec "NIC $IF";        run ip -d link show "$IF"
if command -v ethtool >/dev/null; then
    run sudo ethtool "$IF"
    run sudo ethtool -i "$IF"
    sec "Offloads $IF"; sudo ethtool -k "$IF" 2>&1 | grep -E 'segmentation|receive-offload|checksumming|rx-vlan|tx-vlan|scatter' || true
    sec "Ring / channels $IF"; run sudo ethtool -g "$IF"; run sudo ethtool -l "$IF"
else
    echo "(ethtool not installed: sudo apt install ethtool)"
    echo "driver: $(basename "$(readlink -f /sys/class/net/$IF/device/driver)" 2>/dev/null)"
    echo "speed: $(cat /sys/class/net/$IF/speed 2>/dev/null) Mbit/s"
fi
sec PCI NIC;          lspci 2>/dev/null | grep -iE 'ethernet|network' || echo "(lspci not available)"
sec "VLAN interfaces"; ip -br link show type vlan
sec "IRQs of $IF and their CPU affinity"
grep -E "$IF|$(basename "$(readlink -f /sys/class/net/$IF/device)" 2>/dev/null)" /proc/interrupts | while read -r line; do
    irq=${line%%:*}; irq=${irq// /}
    echo "IRQ $irq -> CPUs $(cat /proc/irq/$irq/smp_affinity_list 2>/dev/null)   ($(echo "$line" | awk '{print $NF}'))"
done
echo "irqbalance: $(systemctl is-active irqbalance 2>/dev/null)"
echo "RPS: $(for q in /sys/class/net/$IF/queues/rx-*/rps_cpus; do [ -f "$q" ] && printf '%s=%s ' "$(basename "$(dirname "$q")")" "$(cat "$q")"; done)"
sec "TC qdiscs";      run sudo tc qdisc show
sec Tools;            iptables -V 2>&1; (bpftool version 2>/dev/null || /usr/sbin/bpftool version 2>&1) | head -2; clang --version 2>/dev/null | head -1
sec Sysctl;           sysctl net.ipv4.ip_forward kernel.bpf_stats_enabled net.core.bpf_jit_enable 2>&1
sec Docker;           echo "docker: $(systemctl is-active docker 2>/dev/null), running containers: $(sudo docker ps -q 2>/dev/null | wc -l)"
