#!/usr/bin/env bash
# scripts/config_a_setup.sh
# Config A — iptables baseline ruleset
# Same logical rules as B1/B2 but using netfilter.
#
# Usage:
#   sudo bash scripts/config_a_setup.sh load    # apply rules
#   sudo bash scripts/config_a_setup.sh flush   # remove all rules

set -euo pipefail

ACTION=${1:-load}
IFACE=eth1

case "$ACTION" in
    load)
        # Flush existing rules first
        iptables -F
        iptables -X

        # Default policy — DROP everything not explicitly allowed
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT

        # Rule 0 — SAFETY: always accept SSH from bastion (10.8.50.180)
        iptables -A INPUT -i eth0 -p tcp --dport 22 -s 10.8.50.180 -j ACCEPT

        # Rule 0b — accept established connections (needed for SSH to stay up)
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        # Rule 1 — DROP src 192.168.100.0/24
        iptables -A INPUT -i $IFACE -s 192.168.100.0/24 -j DROP

        # Rule 2 — DROP tcp:22 from 10.0.0.0/8
        iptables -A INPUT -i $IFACE -p tcp --dport 22 -s 10.0.0.0/8 -j DROP

        # Rule 3 — ACCEPT tcp:80
        iptables -A INPUT -i $IFACE -p tcp --dport 80 -j ACCEPT

        # Rule 4 — ACCEPT tcp:443
        iptables -A INPUT -i $IFACE -p tcp --dport 443 -j ACCEPT

        # Rule 5 — ACCEPT udp:53
        iptables -A INPUT -i $IFACE -p udp --dport 53 -j ACCEPT

        # Rule 6 — ACCEPT ICMP
        iptables -A INPUT -i $IFACE -p icmp -j ACCEPT

        # Rule 7 — DROP default (already set by policy)

        echo "✓ Config A loaded on $IFACE"
        echo ""
        iptables -L INPUT -v -n --line-numbers
        ;;

    flush)
        iptables -F
        iptables -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        echo "✓ iptables flushed — all traffic allowed"
        ;;

    *)
        echo "Usage: $0 [load|flush]"
        exit 1
        ;;
esac
