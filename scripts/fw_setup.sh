#!/usr/bin/env bash
# scripts/fw_setup.sh — switch the firewall config on casual-lamb
#
# Usage: sudo bash scripts/fw_setup.sh <a|b0|b1|b2|off|status>
#   a       iptables (config_a_setup.sh), scoped to the test VLAN
#   b0      eBPF empty baseline   (obj/firewall_b0.bpf.o)
#   b1      eBPF tail calls       (obj/b1_loader, runs in the background)
#   b2      eBPF compressed       (obj/firewall_b2.bpf.o)
#   off     remove everything this script ever adds
#   status  show what is active
#
# Every config also gets the egress counter on the outgoing VLAN (packets
# actually forwarded to smooth-gecko). Only the two test VLAN interfaces are
# touched — never the control NIC, Docker's rules, INPUT/OUTPUT, IPs or routes.
# Run from the repo root: ~/srinika/ebpf-firewall-thesis

set -euo pipefail
cd "$(dirname "$0")/.."

IFACE_IN=enp0s25.3155     # from apt-kitten   (B attaches here, A filters -i here)
IFACE_OUT=enp0s25.3154    # to smooth-gecko   (egress counter)
CFG=${1:-status}

off() {
    IFACE_IN=$IFACE_IN bash scripts/config_a_setup.sh flush >/dev/null
    # stop B1 and WAIT until it is gone: on exit it removes the ingress hook,
    # which would otherwise delete the next config's hook
    pkill b1_loader 2>/dev/null || true
    for _ in $(seq 1 20); do pgrep -x b1_loader >/dev/null || break; sleep 0.25; done
    pkill -9 -x b1_loader 2>/dev/null || true
    tc qdisc del dev "$IFACE_IN"  clsact 2>/dev/null || true    # B0/B1/B2 hook
    tc qdisc del dev "$IFACE_OUT" clsact 2>/dev/null || true    # egress counter
    sysctl -qw kernel.bpf_stats_enabled=0
}

counter_on() {
    tc qdisc add dev "$IFACE_OUT" clsact
    tc filter add dev "$IFACE_OUT" egress bpf da obj obj/pkt_counter_port.bpf.o sec tc
}

status() {
    echo "== $(hostname): config =="
    echo "iptables jump : $(iptables -S FORWARD | grep -c FW_FORWARD || true)"
    echo "b1_loader     : $(pgrep b1_loader >/dev/null && echo running || echo stopped)"
    echo "ingress $IFACE_IN : $(tc filter show dev "$IFACE_IN" ingress 2>/dev/null | grep -oP 'name \K\S+' || echo none)"
    echo "egress $IFACE_OUT : $(tc filter show dev "$IFACE_OUT" egress 2>/dev/null | grep -oP 'name \K\S+' || echo none)"
    echo "bpf_stats     : $(sysctl -n kernel.bpf_stats_enabled)"
}

case "$CFG" in
    off)
        off
        ;;
    a)
        off
        IFACE_IN=$IFACE_IN bash scripts/config_a_setup.sh load >/dev/null
        counter_on
        ;;
    b0|b2)
        off
        bash scripts/tc_attach.sh attach "$IFACE_IN" "obj/firewall_${CFG}.bpf.o" tc >/dev/null
        counter_on
        sysctl -qw kernel.bpf_stats_enabled=1
        ;;
    b1)
        off
        setsid nohup stdbuf -oL ./obj/b1_loader "$IFACE_IN" < /dev/null > /tmp/b1_loader.log 2>&1 &
        for _ in $(seq 1 20); do       # wait until chain_input is attached (max 5 s)
            tc filter show dev "$IFACE_IN" ingress 2>/dev/null | grep -q chain_input && break
            sleep 0.25
        done
        tc filter show dev "$IFACE_IN" ingress | grep -q chain_input \
            || { echo "B1 did not attach:"; cat /tmp/b1_loader.log; off; exit 1; }
        counter_on
        sysctl -qw kernel.bpf_stats_enabled=1
        ;;
    status)
        ;;
    *)
        echo "Usage: $0 <a|b0|b1|b2|off|status>"; exit 1
        ;;
esac
status
