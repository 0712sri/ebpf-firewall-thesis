#!/usr/bin/env bash
# scripts/pktgen_sender.sh
# Follows: Turull et al. 2016 pktgen methodology
#
# Usage: sudo bash scripts/pktgen_sender.sh <pps> <pkt_size> <num_packets> <dst_port>

set -euo pipefail

PPS=${1:-10000}
PKT_SIZE=${2:-64}
NUM_PKTS=${3:-100000}
DST_PORT=${4:-5001}
IFACE=eth1
DST_IP=192.168.2.2
DST_MAC=bc:24:11:8e:2c:cb
THREAD=kpktgend_0
DELAY=$(python3 -c "print(int(1000000000 / $PPS))")

echo "[pktgen] PPS=$PPS  PktSize=${PKT_SIZE}B  NumPkts=$NUM_PKTS  DstPort=$DST_PORT  Delay=${DELAY}ns"
echo "[pktgen] Start: $(date +%s%N) ns"

sudo modprobe pktgen 2>/dev/null || true

# Write each parameter separately — avoids quoting issues
echo rem_device_all          | sudo tee /proc/net/pktgen/$THREAD > /dev/null
echo "add_device $IFACE"     | sudo tee /proc/net/pktgen/$THREAD > /dev/null
echo "count $NUM_PKTS"       | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "delay $DELAY"          | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "pkt_size $PKT_SIZE"    | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "dst $DST_IP"           | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "dst_mac $DST_MAC"      | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "src_min 192.168.1.2"   | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "src_max 192.168.1.2"   | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "udp_dst_min $DST_PORT" | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "udp_dst_max $DST_PORT" | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "udp_src_min 1024"      | sudo tee /proc/net/pktgen/$IFACE > /dev/null
echo "udp_src_max 65535"     | sudo tee /proc/net/pktgen/$IFACE > /dev/null

echo start | sudo tee /proc/net/pktgen/pgctrl > /dev/null

echo "[pktgen] End: $(date +%s%N) ns"
echo ""
echo "=== pktgen results ==="
sudo cat /proc/net/pktgen/$IFACE | grep -E "Result|pps|pkts-sofar|errors|stopped"