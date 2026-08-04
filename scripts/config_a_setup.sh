#!/usr/bin/env bash
# Config A — stateless iptables FORWARD rules on xdp-firewall
# Bidirectional rules — no conntrack — matches B1/B2 scope

set -euo pipefail
ACTION=${1:-load}

case "$ACTION" in
    load)
        iptables -F FORWARD
        iptables -P FORWARD DROP

        # TCP port 80 — both directions (stateless)
        iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
        iptables -A FORWARD -p tcp --sport 80 -j ACCEPT

        # TCP port 443 — both directions
        iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
        iptables -A FORWARD -p tcp --sport 443 -j ACCEPT

        # TCP port 5201 (iperf3) — both directions
        iptables -A FORWARD -p tcp --dport 5201 -j ACCEPT
        iptables -A FORWARD -p tcp --sport 5201 -j ACCEPT

        # ICMP both directions
        iptables -A FORWARD -p icmp -j ACCEPT

        # UDP port 53 (DNS) — both directions
        iptables -A FORWARD -p udp --dport 53 -j ACCEPT
        iptables -A FORWARD -p udp --sport 53 -j ACCEPT

        # UDP port 5001 (pktgen test traffic) — both directions
        iptables -A FORWARD -p udp --dport 5001 -j ACCEPT
        iptables -A FORWARD -p udp --sport 5001 -j ACCEPT

        echo "✓ Config A (stateless) loaded on xdp-firewall FORWARD chain"
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
