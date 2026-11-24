#!/usr/bin/env bash
# scripts/config_a_setup.sh — Config A: the rule set in iptables (netfilter)
#
# The rules come from rules/config_a_N.rules (scripts/rule_generator.py N), the
# same file that scripts/rule_compiler.py translates into B0/B1/B2's rules, so
# A and B always filter with identical rules, in the same order and chains:
#   FW_FORWARD:   1 bastion SSH accept, -j FILTER_DROP, -j ALLOW, then DROP (miss)
#   FILTER_DROP:  2-3   drop rules
#   ALLOW:        4-N   accept rules  (4 = BEST port 80, (4+N)/2 = MIDDLE 5500, N = WORST 9900)
#
# Docker-safe and scoped like B1/B2:
#   - adds ONE rule at the top of FORWARD:  -i $IFACE_IN -j FW_FORWARD
#     so only traffic arriving from apt-kitten on the test VLAN is filtered
#     (B1/B2 are attached to the same interface)
#   - never flushes FORWARD, never changes its policy, never touches
#     INPUT/OUTPUT or Docker's chains
#   - flush removes exactly what load added
#
# Usage: sudo bash scripts/config_a_setup.sh [load [N]|flush|show]     N = 10 (default), 100, 1000
#        IFACE_IN=enp0s25.3155 by default (casual-lamb, from apt-kitten)

set -euo pipefail
ACTION=${1:-load}
N=${2:-10}                                    # rule set size: rules/config_a_N.rules
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
        RULES_FILE=rules/config_a_${N}.rules
        [ -f "$RULES_FILE" ] || { echo "missing $RULES_FILE (python3 scripts/rule_generator.py $N)"; exit 1; }
        flush_ours
        # our three chains + their rules, in one step; --noflush keeps every other
        # chain (Docker's, INPUT, OUTPUT) exactly as it is
        iptables-restore --noflush "$RULES_FILE"

        # hook it in last, so traffic is never filtered by a half-built rule set
        iptables -I FORWARD 1 -i "$IFACE_IN" -j FW_FORWARD

        echo " Config A loaded on $IFACE_IN ($N rules from $RULES_FILE: FW_FORWARD -> FILTER_DROP -> ALLOW, miss DROP)"
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
for c in $CHAINS; do iptables -L "$c" -v -n --line-numbers 2>/dev/null | head -14 || true; done
n=$(iptables -S ALLOW 2>/dev/null | grep -c -- '-A ALLOW' || true)
[ "${n:-0}" -gt 12 ] && echo " ... ALLOW has $n rules (first 12 shown)"
true
