#!/usr/bin/env bash
# scripts/pktgen_sender.sh
# Runs on xdp-RECEIVER — sends traffic toward xdp-sender's eth1 firewall.
#
# Usage:
#   sudo bash scripts/pktgen_sender.sh <pkt_size> <duration_sec>
#   sudo bash scripts/pktgen_sender.sh 64 30

set -euo pipefail

PKT_SIZE=${1:-64}
DURATION=${2:-30}
IFACE=eth1
DST_IP=10.35.5.250
DST_MAC=bc:24:11:0b:16:81
THREAD=kpktgend_0

echo "[pktgen] Sending ${PKT_SIZE}B packets → $DST_IP for ${DURATION}s"

sudo modprobe pktgen

sudo bash -c "
echo 'rem_device_all'     > /proc/net/pktgen/$THREAD
echo 'add_device $IFACE'  > /proc/net/pktgen/$THREAD
echo 'count 0'            > /proc/net/pktgen/$IFACE
echo 'delay 0'            > /proc/net/pktgen/$IFACE
echo 'pkt_size $PKT_SIZE' > /proc/net/pktgen/$IFACE
echo 'dst $DST_IP'        > /proc/net/pktgen/$IFACE
echo 'dst_mac $DST_MAC'   > /proc/net/pktgen/$IFACE
"

sudo bash -c "echo 'start' > /proc/net/pktgen/pgctrl" &
sleep "$DURATION"
sudo bash -c "echo 'stop' > /proc/net/pktgen/pgctrl"

echo ""
sudo cat /proc/net/pktgen/$IFACE | grep -E "Result|pps|pkts-sofar"
