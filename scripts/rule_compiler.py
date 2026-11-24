#!/usr/bin/env python3
"""
scripts/rule_compiler.py — RQ3 translator: iptables rules -> TC eBPF rules (C).

Usage:  python3 scripts/rule_compiler.py rules/config_a_100.rules  ->  src/rules/fw_rules_100.h
        python3 scripts/rule_compiler.py IN.rules OUT.h

Input : an iptables-save / iptables-restore file (filter table) with the chain
        structure used in this thesis:
          FW_FORWARD : [rules ...] -j FILTER_DROP, -j ALLOW, -j DROP
          FILTER_DROP: terminal rules (ACCEPT / DROP)
          ALLOW      : terminal rules (ACCEPT / DROP)
Output: a C header defining RULES_FORWARD(p), RULES_FILTER_DROP(p) and
        RULES_ALLOW(p), used unchanged by B0/B1/B2 (src/fw_rules.h includes it).
        B1 runs the three macros in three tail-called programs, B2 in one program.

Supported (stateless) matches: -s / -d [!] CIDR, -p tcp|udp|icmp,
  --dport / --sport N or N:M, -m multiport --dports / --sports / --ports LIST,
  -m tcp / -m udp / -m multiport / -m comment.  Targets: ACCEPT, DROP.
Anything else (conntrack, state, limit, REJECT, LOG, -i/-o, ...) is REFUSED
with the line number: the translator never silently changes a rule's meaning.
"""
import ipaddress
import shlex
import sys

PROTO = {"tcp": "IS_TCP(p)", "udp": "IS_UDP(p)", "icmp": "IS_ICMP(p)"}
CHAINS = ("FW_FORWARD", "FILTER_DROP", "ALLOW")


class Refused(Exception):
    pass


def ports(spec):
    """'80' | '1000:2000' | '80,443,6000:6010' -> [(lo, hi), ...]"""
    out = []
    for part in spec.split(","):
        lo, _, hi = part.partition(":")
        lo = int(lo) if lo else 0
        hi = int(hi) if hi else (65535 if _ else lo)
        if not (0 <= lo <= hi <= 65535):
            raise Refused(f"bad port {part}")
        out.append((lo, hi))
    return out


def port_expr(field, rng):
    lo, hi = rng
    if lo == hi:
        if field == "dport":
            return f"DPORT(p, {lo})"
        if field == "any":
            return f"ANYPORT(p, {lo})"
        return f"((p).has_l4 && (p).sport == {lo})"
    if field == "any":
        return f"({port_expr('dport', rng)} || {port_expr('sport', rng)})"
    return f"((p).has_l4 && (p).{field} >= {lo} && (p).{field} <= {hi})"


def ports_cond(field, ranges):
    terms = [port_expr(field, r) for r in ranges]
    return terms[0] if len(terms) == 1 else "(" + " || ".join(terms) + ")"


def addr_cond(field, cidr, neg):
    net = ipaddress.ip_network(cidr, strict=False)
    if net.prefixlen == 32:
        c = f"(p).{field} == 0x{int(net.network_address):08X}U"
    elif net.prefixlen == 0:
        c = "1"
    elif field == "src":
        c = f"SRC_NET(p, 0x{int(net.network_address):08X}U, 0x{int(net.netmask):08X}U)"
    else:
        c = f"(((p).dst & 0x{int(net.netmask):08X}U) == 0x{int(net.network_address):08X}U)"
    return f"!({c})" if neg else c


def translate_rule(args):
    """args after '-A CHAIN' -> (condition, target)"""
    proto = None
    terms_in_order = []        # matches keep the order they are written in (protocol goes first)
    target = None
    neg = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == "!":
            neg = True; i += 1; continue
        val = args[i + 1] if i + 1 < len(args) else None
        if a in ("-p", "--protocol"):
            if neg or val not in PROTO:
                raise Refused(f"protocol {'! ' if neg else ''}{val}")
            proto = val
        elif a in ("-s", "--source"):
            terms_in_order.append(addr_cond("src", val, neg))
        elif a in ("-d", "--destination"):
            terms_in_order.append(addr_cond("dst", val, neg))
        elif a in ("-m", "--match"):
            if val not in ("tcp", "udp", "multiport", "comment"):
                raise Refused(f"-m {val}")
        elif a == "--comment":
            pass
        elif a in ("--dport", "--destination-port", "--dports", "--destination-ports"):
            if neg: raise Refused(f"! {a}")
            terms_in_order.append(ports_cond("dport", ports(val)))
        elif a in ("--sport", "--source-port", "--sports", "--source-ports"):
            if neg: raise Refused(f"! {a}")
            terms_in_order.append(ports_cond("sport", ports(val)))
        elif a == "--ports":
            if neg: raise Refused(f"! {a}")
            terms_in_order.append(ports_cond("any", ports(val)))
        elif a in ("-j", "--jump"):
            target = val
        else:
            raise Refused(f"option {a}")
        neg = False
        i += 2
    if any("port" in t.lower() for t in terms_in_order) and proto not in ("tcp", "udp"):
        raise Refused("port match without -p tcp/udp")
    terms = ([PROTO[proto]] if proto else []) + terms_in_order
    terms = [t for t in terms if t != "1"]
    return (" && ".join(terms) if terms else "1"), target


def compile_file(text):
    chains = {c: [] for c in CHAINS}
    table = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line == "COMMIT":
            continue
        if line.startswith("*"):
            table = line[1:]; continue
        if line.startswith(":"):
            continue
        toks = shlex.split(line)
        if table != "filter" or toks[0] != "-A" or toks[1] not in chains:
            raise SystemExit(f"line {lineno}: not part of the supported structure: {line}")
        try:
            cond, target = translate_rule(toks[2:])
        except Refused as e:
            raise SystemExit(f"line {lineno}: cannot translate exactly ({e}): {line}")
        chains[toks[1]].append((cond, target, lineno, line))

    fwd = chains["FW_FORWARD"]
    tail = [(c, t) for c, t, _, _ in fwd[-3:]]
    if tail != [("1", "FILTER_DROP"), ("1", "ALLOW"), ("1", "DROP")]:
        raise SystemExit("FW_FORWARD must end with: -j FILTER_DROP, -j ALLOW, -j DROP")
    out = {"FW_FORWARD": fwd[:-3], "FILTER_DROP": chains["FILTER_DROP"], "ALLOW": chains["ALLOW"]}
    for name, rules in out.items():
        for cond, target, lineno, line in rules:
            if target not in ("ACCEPT", "DROP"):
                raise SystemExit(f"line {lineno}: only ACCEPT/DROP allowed here: {line}")
    return out


def macro(name, rules, first_no):
    lines = [f"#define {name}(p)" + " " * max(1, 66 - len(name)) + "\\"]
    for k, (cond, target, _, line) in enumerate(rules):
        act = "ACCEPT();" if target == "ACCEPT" else "DROP();"
        stmt = act if cond == "1" else f"if ({cond}) {act}"
        lines.append(f"    /* {first_no + k} */ {stmt}" + " \\")
    lines.append("    /* end */")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = sys.argv[1]
    n_tag = src.rsplit("_", 1)[-1].split(".")[0]
    dst = sys.argv[2] if len(sys.argv) > 2 else f"src/rules/fw_rules_{n_tag}.h"
    with open(src) as f:
        ch = compile_file(f.read())
    n1, n2 = len(ch["FW_FORWARD"]), len(ch["FILTER_DROP"])
    total = n1 + n2 + len(ch["ALLOW"])
    guard = "FW_RULES_GEN_" + "".join(c if c.isalnum() else "_" for c in n_tag).upper()
    text = "\n".join([
        "// SPDX-License-Identifier: GPL-2.0",
        f"// {dst} — GENERATED by scripts/rule_compiler.py from {src}. Do not edit.",
        f"// {total} rules: FW_FORWARD {n1}, FILTER_DROP {n2}, ALLOW {len(ch['ALLOW'])}.",
        f"#ifndef {guard}", f"#define {guard}", "",
        macro("RULES_FORWARD", ch["FW_FORWARD"], 1), "",
        macro("RULES_FILTER_DROP", ch["FILTER_DROP"], 1 + n1), "",
        macro("RULES_ALLOW", ch["ALLOW"], 1 + n1 + n2), "",
        f"#endif // {guard}", ""])
    with open(dst, "w") as f:
        f.write(text)
    print(f"{src} -> {dst}: {total} rules translated")


if __name__ == "__main__":
    main()
