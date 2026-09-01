#!/usr/bin/env python3
"""
scripts/rule_generator.py
Generates firewall rules for benchmark experiments.
Creates N rules where:
  Rule 1   = port 80   (best case match)
  Rule N/2 = port 5500 (middle case match)
  Rule N   = port 9900 (worst case match)
  Miss     = port 9999 (no rule → default DROP)

Usage:
  python3 scripts/rule_generator.py <N> <config> [--apply]
  config: config_a | b2
  --apply: actually load the rules (requires sudo)
"""

import sys
import subprocess

def generate_ports(n):
    ports = []
    ports.append(80)          # rule 1 — best case
    base = 10000
    for i in range(1, n - 1):
        if i == n // 2 - 1:
            ports.append(5500) # middle case
        else:
            ports.append(base)
            base += 1
    ports.append(9900)        # rule N — worst case
    return ports

def print_port_map(n, ports):
    print(f"\n=== Port map for N={n} ===")
    print(f"  BEST   : port 80   → rule 1")
    print(f"  MIDDLE : port 5500 → rule {n//2}")
    print(f"  WORST  : port 9900 → rule {n}")
    print(f"  MISS   : port 9999 → default DROP")

def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    n = int(sys.argv[1])
    config = sys.argv[2]
    apply_rules = "--apply" in sys.argv

    if n < 3:
        print("ERROR: N must be >= 3")
        sys.exit(1)

    ports = generate_ports(n)
    print_port_map(n, ports)

    if config == "config_a":
        print(f"\n=== iptables commands ({n} rules) ===")
        cmds = ["iptables -F FORWARD", "iptables -P FORWARD DROP"]
        for port in ports:
            cmds.append(f"iptables -A FORWARD -p udp --dport {port} -j ACCEPT")
        for c in cmds:
            print(f"  {c}")
        if apply_rules:
            for c in cmds:
                subprocess.run(["sudo"] + c.split(), check=True)
            print("✓ Applied")

    elif config == "b2":
        print(f"\n=== BPF rules ({n} rules) ===")
        lines = [f"    // {n} auto-generated rules"]
        for i, port in enumerate(ports):
            note = ""
            if i == 0: note = "  // BEST"
            elif i == n//2 - 1: note = "  // MIDDLE"
            elif i == n-1: note = "  // WORST"
            lines.append(f"    if (proto == IPPROTO_UDP && dport == {port}) goto accept;{note}")
        lines.append("    goto drop;  // MISS — default DROP")
        print("\n".join(lines))

    # Save port map
    import os
    os.makedirs("bench", exist_ok=True)
    with open(f"bench/portmap_{n}.txt", "w") as f:
        f.write(f"BEST_PORT=80\nMIDDLE_PORT=5500\nWORST_PORT=9900\nMISS_PORT=9999\nRULE_COUNT={n}\n")
    print(f"\n✓ Port map saved to bench/portmap_{n}.txt")

if __name__ == "__main__":
    main()