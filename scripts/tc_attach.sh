#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-status}; IFACE=${2:-ens3}; OBJ=${3:-""}; SEC=${4:-tc}
case "$ACTION" in
  attach)
    [[ ! -f "$OBJ" ]] && { echo "ERROR: $OBJ not found — run make first"; exit 1; }
    tc qdisc add dev "$IFACE" clsact 2>/dev/null || true
    tc filter del dev "$IFACE" ingress 2>/dev/null || true
    tc filter add dev "$IFACE" ingress bpf obj "$OBJ" sec "$SEC" direct-action
    echo "✓ Attached $OBJ → $IFACE ingress"
    tc filter show dev "$IFACE" ingress ;;
  detach)
    tc filter del dev "$IFACE" ingress 2>/dev/null || true
    tc qdisc del dev "$IFACE" clsact 2>/dev/null || true
    echo "✓ Detached from $IFACE" ;;
  status)
    echo "=== TC filters on $IFACE ==="
    tc filter show dev "$IFACE" ingress 2>/dev/null || echo "(none)" ;;
  *) echo "Usage: $0 [attach|detach|status] <iface> [obj] [sec]"; exit 1 ;;
esac
