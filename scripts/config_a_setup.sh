#!/usr/bin/env bash
# Config A — stateless iptables FORWARD rules on xdp-firewall
# Single direction (ens19 ingress equivalent) — matches B1/B2 scope
# Only filters traffic FROM sender TO receiver — same as TC ingress on ens19

set -euo pipefail
ACTION=${1:-load}

case "$ACTION" in
    load)
        iptables -F FORWARD
        iptables -P FORWARD DROP

        # TCP port 80 — destination only (matches B1/B2 scope)
        iptables -A FORWARD -p tcp --dport 80 -j ACCEPT

        # TCP port 443
        iptables -A FORWARD -p tcp --dport 443 -j ACCEPT

        # TCP port 5201 (iperf3)
        iptables -A FORWARD -p tcp --dport 5201 -j ACCEPT

        # ICMP
        iptables -A FORWARD -p icmp -j ACCEPT

        # UDP port 53 (DNS)
        iptables -A FORWARD -p udp --dport 53 -j ACCEPT

        # UDP port 5001 (pktgen)
        iptables -A FORWARD -p udp --dport 5001 -j ACCEPT

        echo "✓ Config A (stateless, single-direction) loaded on xdp-firewall FORWARD chain"
        iptables -L FORWARD -v -n --line-numbers
        ;;
    flush)
        iptables -F FORWARD
        iptables -P FORWARD ACCEPT
        echo "✓ iptables FORWARD flushed"
        ;;
    *)
        echo "Usage: $0 [load|flush]"
        exit 1
        ;;
esac
