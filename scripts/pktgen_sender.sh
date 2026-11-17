#!/usr/bin/env bash
# scripts/pktgen_sender.sh — traffic source, runs on apt-kitten (testbed)
# Sends UDP 10.35.5.203:40000 -> 10.35.4.4:<dst_port> through casual-lamb.
# pktgen uses the physical test NIC and adds the VLAN tag itself
# (pktgen on a VLAN interface is unreliable).
#
# Usage: sudo bash scripts/pktgen_sender.sh <pps> <pkt_size> <num_packets> <dst_port>
set -euo pipefail

PPS=${1:-10000}
PKT_SIZE=${2:-64}
NUM_PKTS=${3:-100000}
DST_PORT=${4:-80}

IFACE=eno2                   # apt-kitten test NIC (100 Mbit)
VLAN=3155                    # apt-kitten <-> casual-lamb test VLAN
SRC_IP=10.35.5.203           # apt-kitten
DST_IP=10.35.4.4             # smooth-gecko (forwarded by casual-lamb)
DST_MAC=00:22:4d:a8:54:9b    # casual-lamb enp0s25 = next hop
SRC_PORT=40000               # fixed: must not match rule 6 (53/5001)
THREAD=kpktgend_0
DELAY=$((1000000000 / PPS))
PG=/proc/net/pktgen

modprobe pktgen
pg() { echo "$2" > "$PG/$1"; }

pg "$THREAD" rem_device_all
pg "$THREAD" "add_device $IFACE"
pg "$IFACE" "count $NUM_PKTS"
pg "$IFACE" "delay $DELAY"
pg "$IFACE" "pkt_size $PKT_SIZE"
pg "$IFACE" "vlan_id $VLAN"
pg "$IFACE" "dst $DST_IP"
pg "$IFACE" "dst_mac $DST_MAC"
pg "$IFACE" "src_min $SRC_IP"
pg "$IFACE" "src_max $SRC_IP"
pg "$IFACE" "udp_src_min $SRC_PORT"
pg "$IFACE" "udp_src_max $SRC_PORT"
pg "$IFACE" "udp_dst_min $DST_PORT"
pg "$IFACE" "udp_dst_max $DST_PORT"

echo "[pktgen] $NUM_PKTS pkts, ${PKT_SIZE}B, $PPS pps -> $DST_IP:$DST_PORT (vlan $VLAN)"
pg pgctrl start
grep -E "Result|pkts-sofar|errors" "$PG/$IFACE"