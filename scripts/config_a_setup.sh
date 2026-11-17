#!/usr/bin/env bash
# scripts/config_a_setup.sh — Config A: the rule set in iptables (netfilter)
#
# Same 10 rules, same order, same chains as B1/B2 (src/fw_rules.h):
#   FW_FORWARD:   1 bastion SSH accept, -j FILTER_DROP, -j ALLOW, then DROP (miss)
#   FILTER_DROP:  2-3   drop rules
#   ALLOW:        4-10  accept rules   (4 = BEST port 80, 7 = MIDDLE 5500, 10 = WORST 9900)
#
# Docker-safe and scoped like B1/B2:
#   - adds ONE rule at the top of FORWARD:  -i $IFACE_IN -j FW_FORWARD
#     so only traffic arriving from apt-kitten on the test VLAN is filtered
#     (B1/B2 are attached to the same interface)
#   - never flushes FORWARD, never changes its policy, never touches
#     INPUT/OUTPUT or Docker's chains
#   - flush removes exactly what load added
#
# Usage: sudo bash scripts/config_a_setup.sh [load|flush|show]
#        IFACE_IN=enp0s25.3155 by default (casual-lamb, from apt-kitten)

set -euo pipefail
ACTION=${1:-load}
IFACE_IN=${IFACE_IN:-enp0s25.3155}
CHAINS="FW_FORWARD FILTER_DROP ALLOW"

flush_ours() {
    # remove our jump(s) from FORWARD, however many are there
    while iptables -D FORWARD -i "$IFACE_IN" -j FW_FORWARD 2>/dev/null; do :; done
    for c in $CHAINS; do iptables -F "$c" 2>/dev/null || true; done   # empty first (they reference each other)
    for c in $CHAINS; do iptables -X "$c" 2>/dev/null || true; done
}

case "$ACTION" in
    load)
        flush_ours
        for c in $CHAINS; do iptables -N "$c"; done

        # FW_FORWARD (stands for FORWARD: same rules, same order as B1/B2)
        iptables -A FW_FORWARD -s 10.8.50.180 -p tcp --dport 22 -j ACCEPT       # 1 bastion SSH
        iptables -A FW_FORWARD -j FILTER_DROP
        iptables -A FW_FORWARD -j ALLOW
        iptables -A FW_FORWARD -j DROP                                           #   miss -> DROP

        # FILTER_DROP
        iptables -A FILTER_DROP -s 192.168.100.0/24 -j DROP                      # 2
        iptables -A FILTER_DROP -s 10.0.0.0/8 -p tcp --dport 22 -j DROP          # 3

        # ALLOW
        iptables -A ALLOW -p udp --dport 80 -j ACCEPT                            # 4  BEST
        iptables -A ALLOW -p tcp -m multiport --ports 80,443,5201 -j ACCEPT      # 5
        iptables -A ALLOW -p udp -m multiport --ports 53,5001 -j ACCEPT          # 6
        iptables -A ALLOW -p udp --dport 5500 -j ACCEPT                          # 7  MIDDLE
        iptables -A ALLOW -p icmp -j ACCEPT                                      # 8
        iptables -A ALLOW -p udp --dport 5201 -j ACCEPT                          # 9
        iptables -A ALLOW -p udp --dport 9900 -j ACCEPT                          # 10 WORST

        # hook it in last, so traffic is never filtered by a half-built rule set
        iptables -I FORWARD 1 -i "$IFACE_IN" -j FW_FORWARD

        echo " Config A loaded on $IFACE_IN (10 rules: FW_FORWARD -> FILTER_DROP -> ALLOW, miss DROP)"
        ;;
    flush)
        flush_ours
        echo " Config A removed (FORWARD and Docker rules untouched)"
        ;;
    show)
        ;;
    *)
        echo "Usage: $0 [load|flush|show]"
        exit 1
        ;;
esac

iptables -S FORWARD | head -3
for c in $CHAINS; do iptables -L "$c" -v -n --line-numbers 2>/dev/null || true; done
