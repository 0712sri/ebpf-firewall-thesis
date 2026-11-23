// SPDX-License-Identifier: GPL-2.0
// src/fw_rules.h — THE rule set (v1, 10 rules). Used by B1 and B2.
// Must stay identical to scripts/config_a_setup.sh (config A).
// Scope: traffic arriving on casual-lamb's test VLAN from apt-kitten
// (enp0s25.3155). A filters exactly that (-i enp0s25.3155), B attaches there.
//
// Rule count = rules with a verdict (ACCEPT/DROP). The two jumps in FORWARD
// are chain structure, not rules.
//
//  #   chain        rule                                        verdict  bench
//  1   FORWARD      tcp src 10.8.50.180 dport 22 (bastion SSH)  ACCEPT
//  -   FORWARD      -j FILTER_DROP
//  -   FORWARD      -j ALLOW
//  2   FILTER_DROP  src 192.168.100.0/24                        DROP
//  3   FILTER_DROP  tcp dport 22 from 10.0.0.0/8                DROP
//  4   ALLOW        udp dport 80                                ACCEPT   BEST   (port 80)
//  5   ALLOW        tcp ports 80,443,5201 (either direction)    ACCEPT
//  6   ALLOW        udp ports 53,5001     (either direction)    ACCEPT
//  7   ALLOW        udp dport 5500                              ACCEPT   MIDDLE (port 5500)
//  8   ALLOW        icmp                                        ACCEPT
//  9   ALLOW        udp dport 5201                              ACCEPT
// 10   ALLOW        udp dport 9900                              ACCEPT   WORST  (port 9900)
//  -   policy       FORWARD DROP                                DROP     MISS   (port 9999)
//
// NOTE: test traffic must use a fixed UDP source port (40000), otherwise a
// random source port of 53/5001 would match rule 6 and skew best/middle/worst/miss.

#ifndef FW_RULES_H
#define FW_RULES_H

#define BASTION_IP 0x0A0832B4U   // 10.8.50.180

// Packets addressed to the firewall itself go to INPUT, never through FORWARD,
// so config A does not filter them. B1/B2 sit on TC ingress and must let them
// pass unfiltered too: casual-lamb's own test addresses, broadcast, multicast.
#define LOCAL_DST(p) ((p).dst == 0x0A2305CCU /* 10.35.5.204 */ ||           \
                      (p).dst == 0x0A2304C9U /* 10.35.4.201 */ ||           \
                      (p).dst == 0x0A2305FFU /* 10.35.5.255 */ ||           \
                      (p).dst == 0xFFFFFFFFU /* 255.255.255.255 */ ||       \
                      ((p).dst & 0xF0000000U) == 0xE0000000U /* 224/4 */)

// FORWARD, before the jumps
#define RULES_FORWARD(p)                                                      \
    /* 1 */ if (IS_TCP(p) && (p).src == BASTION_IP && DPORT(p, 22)) ACCEPT();

// chain FILTER_DROP
#define RULES_FILTER_DROP(p)                                                  \
    /* 2 */ if (SRC_NET(p, 0xC0A86400U, 0xFFFFFF00U)) DROP();                 \
    /* 3 */ if (IS_TCP(p) && DPORT(p, 22) &&                                  \
                SRC_NET(p, 0x0A000000U, 0xFF000000U)) DROP();

// chain ALLOW
#define RULES_ALLOW(p)                                                        \
    /* 4  BEST   */ if (IS_UDP(p) && DPORT(p, 80)) ACCEPT();                  \
    /* 5         */ if (IS_TCP(p) && (ANYPORT(p, 80) || ANYPORT(p, 443) ||    \
                                      ANYPORT(p, 5201))) ACCEPT();            \
    /* 6         */ if (IS_UDP(p) && (ANYPORT(p, 53) || ANYPORT(p, 5001)))    \
                        ACCEPT();                                             \
    /* 7  MIDDLE */ if (IS_UDP(p) && DPORT(p, 5500)) ACCEPT();                \
    /* 8         */ if (IS_ICMP(p)) ACCEPT();                                 \
    /* 9         */ if (IS_UDP(p) && DPORT(p, 5201)) ACCEPT();                \
    /* 10 WORST  */ if (IS_UDP(p) && DPORT(p, 9900)) ACCEPT();

#endif // FW_RULES_H

