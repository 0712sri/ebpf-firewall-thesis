#!/usr/bin/env bash
# scripts/pktgen_sender.sh
# Follows: Turull et al. 2016 — Pktgen: Measuring performance on high speed networks
# Sends exact packet count at controlled rate, multiple packet sizes
#
# Usage:
#   sudo bash scripts/pktgen_sender.sh <pps> <pkt_size> <num_packets>
#   sudo bash scripts/pktgen_sender.sh 10000 64 100000

set -euo pipefail

PPS=${1:-10000}
PKT_SIZE=${2:-64}
NUM_PKTS=${3:-100000}
DST_PORT=${4:-5001}
IFACE=eth1
DST_IP=192.168.2.2
DST_MAC=bc:24:11:8e:2c:cb  # xdp-firewall ens19 next hop
THREAD=kpktgend_0

DELAY=$(python3 -c "print(int(1000000000 / $PPS))")

echo "[pktgen] PPS=$PPS  PktSize=${PKT_SIZE}B  NumPkts=$NUM_PKTS  Delay=${DELAY}ns"
echo "[pktgen] Start: $(date +%s%N) ns"

sudo modprobe pktgen 2>/dev/null || true

sudo bash -c "
echo 'rem_device_all'        > /proc/net/pktgen/$THREAD
echo 'add_device $IFACE'     > /proc/net/pktgen/$THREAD
echo 'count $NUM_PKTS'       > /proc/net/pktgen/$IFACE
echo 'delay $DELAY'          > /proc/net/pktgen/$IFACE
echo 'pkt_size $PKT_SIZE'    > /proc/net/pktgen/$IFACE
echo 'dst $DST_IP'           > /proc/net/pktgen/$IFACE
echo 'dst_mac $DST_MAC'      > /proc/net/pktgen/$IFACE
echo 'src 192.168.1.2'       > /proc/net/pktgen/$IFACE
echo 'udp_dst_min $DST_PORT' > /proc/net/pktgen/$IFACE
echo 'udp_dst_max $DST_PORT' > /proc/net/pktgen/$IFACE
echo 'udp_src_min 1024'      > /proc/net/pktgen/$IFACE
echo 'udp_src_max 65535'     > /proc/net/pktgen/$IFACE
echo 'start'                 > /proc/net/pktgen/pgctrl
"

sudo bash -c "echo 'start' > /proc/net/pktgen/pgctrl"

echo "[pktgen] End: $(date +%s%N) ns"
echo ""
echo "=== pktgen results ==="
sudo cat /proc/net/pktgen/$IFACE | grep -E "Result|pps|pkts-sofar|errors|stopped"
