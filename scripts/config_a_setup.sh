#!/usr/bin/env bash
# scripts/config_a_setup.sh
# Config A — iptables FORWARD rules on xdp-firewall
# Traffic flows: xdp-sender (192.168.1.2) → xdp-firewall → xdp-receiver (192.168.2.2)
# Rules filter FORWARDED traffic — not INPUT to the firewall itself

set -euo pipefail
ACTION=${1:-load}

case "$ACTION" in
    load)
        iptables -F FORWARD
        iptables -P FORWARD DROP

        # Allow established/related return traffic (conntrack)
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        # Allow HTTP to receiver
        iptables -A FORWARD -p tcp -d 192.168.2.2 --dport 80 -j ACCEPT

        # Allow HTTPS to receiver
        iptables -A FORWARD -p tcp -d 192.168.2.2 --dport 443 -j ACCEPT

        # Allow iperf3 to receiver
        iptables -A FORWARD -p tcp -d 192.168.2.2 --dport 5201 -j ACCEPT

        # Allow ICMP (ping) through
        iptables -A FORWARD -p icmp -j ACCEPT

        # Default DROP (already set by policy)
        echo "✓ Config A loaded on xdp-firewall FORWARD chain"
        iptables -L FORWARD -v -n --line-numbers
        ;;
    flush)
        iptables -F FORWARD
        iptables -P FORWARD ACCEPT
        echo "✓ iptables FORWARD flushed — all traffic allowed"
        ;;
    *)
        echo "Usage: $0 [load|flush]"
        exit 1
        ;;
esac
