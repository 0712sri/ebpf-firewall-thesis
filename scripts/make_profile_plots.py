#!/usr/bin/env python3
"""
scripts/make_profile_plots.py
Generate thesis figures from bench/profile_results.csv
Produces:
  Figure 1 — B1 vs B2 cycles/packet by rule position (95% CI)
  Figure 2 — Percentage change B2 vs B1 by position (paired CI)
  Figure 3 — chain_input alone vs tail-call chain (validation)
  Table    — statistical summary with paired t-test and Holm correction
"""

import csv
import statistics
import math
import os
from collections import defaultdict

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from scipy import stats

os.makedirs('bench/plots', exist_ok=True)

# ── Load and validate data ─────────────────────────────────────────────────
rows = []
with open('bench/profile_results.csv', newline='') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

# Assert workload is constant
pkt_sizes = {int(row['pkt_size_bytes']) for row in rows}
rates     = {int(row['target_pps']) for row in rows}
n_rules   = {int(row['rule_count']) for row in rows}
assert pkt_sizes == {64},    f"Unexpected packet sizes: {pkt_sizes}"
assert rates     == {30000}, f"Unexpected rates: {rates}"
assert n_rules   == {10},    f"Unexpected rule counts: {n_rules}"
print("✓ Workload validated: 64B, 30Kpps, 10 rules")

# Build data by (config, position, rep) — explicitly paired by rep number
positions  = ['best', 'middle', 'worst', 'miss']
pos_labels = ['Best\n(rule 1)', 'Middle\n(rule 5)', 'Worst\n(rule 10)', 'Miss\n(DROP)']


def get_by_rep(config, pos):
    d = {}
    for row in rows:
        if row['config'] == config and row['match_pos'] == pos:
            rep = int(row['rep'])
            if rep in d:
                raise ValueError(f"Duplicate repetition {rep} for {config}/{pos}")
            d[rep] = float(row['cycles_per_packet'])
    return d


B1_rep = {p: get_by_rep('b1', p) for p in positions}
B2_rep = {p: get_by_rep('b2', p) for p in positions}


def paired_lists(p):
    reps = sorted(set(B1_rep[p]) & set(B2_rep[p]))
    if len(reps) != 5:
        raise ValueError(f"Expected 5 paired repetitions for {p}, found {len(reps)}: {reps}")
    return [B1_rep[p][r] for r in reps], [B2_rep[p][r] for r in reps]


def ci95(data):
    n = len(data)
    if n < 2:
        raise ValueError("At least two observations are required for a 95% CI")
    m = statistics.mean(data)
    se = statistics.stdev(data) / math.sqrt(n)
    t = stats.t.ppf(0.975, df=n - 1)
    return m, se * t


B1_COLOR = '#1f77b4'
B2_COLOR = '#2ca02c'

# ── Figure 1: B1 vs B2 cycles/packet by position ──────────────────────────
fig, ax = plt.subplots(figsize=(9, 6))
x = np.arange(len(positions))
width = 0.35

b1_means, b1_cis = [], []
b2_means, b2_cis = [], []
for p in positions:
    b1, b2 = paired_lists(p)
    m1, ci1 = ci95(b1)
    m2, ci2 = ci95(b2)
    b1_means.append(m1)
    b1_cis.append(ci1)
    b2_means.append(m2)
    b2_cis.append(ci2)

bars1 = ax.bar(
    x - width / 2, b1_means, width,
    label='B1 (3 programs + tail-calls)',
    color=B1_COLOR, alpha=0.85,
    yerr=b1_cis, capsize=5,
    error_kw={'elinewidth': 1.5, 'ecolor': 'black'}
)
bars2 = ax.bar(
    x + width / 2, b2_means, width,
    label='B2 (single compressed program)',
    color=B2_COLOR, alpha=0.85,
    yerr=b2_cis, capsize=5,
    error_kw={'elinewidth': 1.5, 'ecolor': 'black'}
)

ax.set_xlabel('Rule match position', fontsize=12)
ax.set_ylabel('Cycles per packet', fontsize=12)
ax.set_title(
    'B1 vs B2 — CPU cycles per packet by rule position\n'
    '10 rules, 64B packets, 30K pps, n=5 repetitions, error bars = 95% CI',
    fontsize=12
)
ax.set_xticks(x)
ax.set_xticklabels(pos_labels, fontsize=11)
ax.legend(fontsize=10)
ax.set_ylim(1900, 2600)
ax.grid(axis='y', alpha=0.3)
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f'{v:,.0f}'))

for bar in bars1:
    ax.text(
        bar.get_x() + bar.get_width() / 2, bar.get_height() + 35,
        f'{bar.get_height():,.0f}', ha='center', va='bottom',
        fontsize=9, color=B1_COLOR, fontweight='bold'
    )
for bar in bars2:
    ax.text(
        bar.get_x() + bar.get_width() / 2, bar.get_height() + 35,
        f'{bar.get_height():,.0f}', ha='center', va='bottom',
        fontsize=9, color=B2_COLOR, fontweight='bold'
    )

plt.tight_layout()
plt.savefig('bench/plots/fig1_cycles_per_packet.png', dpi=150, bbox_inches='tight')
plt.close()
print("✓ Figure 1 saved")

# ── Figure 2: Percentage change B2 vs B1 (paired CI) ─────────────────────
fig, ax = plt.subplots(figsize=(8, 5))

pct_changes, pct_cis = [], []
for p in positions:
    b1, b2 = paired_lists(p)
    b1_mean = statistics.mean(b1)
    diffs   = [b - a for a, b in zip(b1, b2)]
    d_mean  = statistics.mean(diffs)
    d_se    = statistics.stdev(diffs) / math.sqrt(len(diffs))
    t_crit  = stats.t.ppf(0.975, df=len(diffs) - 1)
    pct     = d_mean / b1_mean * 100
    pct_ci  = (t_crit * d_se) / b1_mean * 100
    pct_changes.append(pct)
    pct_cis.append(pct_ci)

colors_v = [B2_COLOR if v < 0 else '#d62728' for v in pct_changes]
bars = ax.bar(
    pos_labels, pct_changes, color=colors_v, alpha=0.85,
    yerr=pct_cis, capsize=5,
    error_kw={'elinewidth': 1.5, 'ecolor': 'black'}
)
ax.axhline(0, color='black', linewidth=1.2, linestyle='--')
ax.set_xlabel('Rule match position', fontsize=12)
ax.set_ylabel('Change in B2 cycles/packet relative to B1 (%)', fontsize=12)
ax.set_title(
    'Effect of chain compression on cycles/packet by rule position\n'
    'negative = B2 uses fewer cycles, positive = B2 uses more cycles',
    fontsize=12
)
ax.grid(axis='y', alpha=0.3)

for bar, val in zip(bars, pct_changes):
    offset = 0.2 if val >= 0 else -0.4
    ax.text(
        bar.get_x() + bar.get_width() / 2,
        bar.get_height() + offset,
        f'{val:+.2f}%', ha='center', va='bottom',
        fontsize=10, fontweight='bold'
    )

green_patch = mpatches.Patch(
    color=B2_COLOR, alpha=0.85,
    label='B2 uses fewer cycles (compression benefit)'
)
red_patch = mpatches.Patch(
    color='#d62728', alpha=0.85,
    label='B2 uses more cycles'
)
ax.legend(handles=[green_patch, red_patch], fontsize=10)

plt.tight_layout()
plt.savefig('bench/plots/fig2_pct_change.png', dpi=150, bbox_inches='tight')
plt.close()
print("✓ Figure 2 saved")

# ── Figure 3: Validation — chain_input alone vs full tail-call chain ──────
fig, ax = plt.subplots(figsize=(7, 5))

# Dedicated validation measurements (manual experiment)
alone_cycles = 2195   # dedicated validation: chain_input attached directly, no jump table
chain_cycles = 2340   # dedicated validation: chain_input with jump table wired

categories = ['chain_input alone\n(no tail-calls)', 'chain_input\nwith tail-call chain']
cycle_vals  = [alone_cycles, chain_cycles]
colors_val  = ['#aec7e8', B1_COLOR]

bars = ax.bar(categories, cycle_vals, color=colors_val, alpha=0.85, width=0.4)
ax.set_ylabel('Cycles per packet', fontsize=12)
ax.set_title(
    'Validation: B1 profiling captures complete tail-call chain\n'
    'cycles/packet, 64B packets, 30K pps',
    fontsize=12
)
ax.set_ylim(1900, 2500)
ax.grid(axis='y', alpha=0.3)
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f'{v:,.0f}'))

for bar, val in zip(bars, cycle_vals):
    ax.text(
        bar.get_x() + bar.get_width() / 2, bar.get_height() + 12,
        f'{val:,.0f}', ha='center', va='bottom',
        fontsize=11, fontweight='bold'
    )

diff = chain_cycles - alone_cycles
ax.annotate(
    '', xy=(1, chain_cycles), xytext=(1, alone_cycles),
    arrowprops=dict(arrowstyle='<->', color='red', lw=2)
)
ax.text(
    1.25, (chain_cycles + alone_cycles) / 2,
    f'+{diff:.0f}\ncycles/pkt\n(observed additional\ncost with\ntail-call chain)',
    ha='left', va='center', fontsize=9, color='red'
)

plt.tight_layout()
plt.savefig('bench/plots/fig3_validation.png', dpi=150, bbox_inches='tight')
plt.close()
print("✓ Figure 3 saved")

# ── Statistical table ──────────────────────────────────────────────────────
# First collect all raw p-values, then apply Holm correction across the four
# position-specific paired tests.
p_vals_all = []
raw_results = []

for p in positions:
    b1, b2 = paired_lists(p)
    t_stat, p_val = stats.ttest_rel(b2, b1)
    p_vals_all.append(p_val)
    raw_results.append((p, b1, b2, t_stat, p_val))

# Holm correction
ranks = sorted(range(len(p_vals_all)), key=lambda i: p_vals_all[i])
n = len(p_vals_all)
holm_p = [0.0] * n
for rank, idx in enumerate(ranks):
    holm_p[idx] = min(1.0, p_vals_all[idx] * (n - rank))

# Make adjusted p-values monotone in ascending raw-p order
for i in range(1, n):
    holm_p[ranks[i]] = max(holm_p[ranks[i]], holm_p[ranks[i - 1]])

print()
print("=" * 112)
print(" Statistical Summary — B1 vs B2 cycles/packet (paired t-test, Holm-adjusted p-values)")
print("=" * 112)
print(
    f"{'Pos':<8} {'B1 mean':>9} {'B1 SD':>7} {'B2 mean':>9} {'B2 SD':>7} "
    f"{'Diff':>7} {'Diff%':>7} {'95%CI':>18} {'p-val':>8} {'p-Holm':>8} {'sig':>4}"
)
print("-" * 112)

for idx, (p, b1, b2, t_stat, p_val) in enumerate(raw_results):
    b1_m = statistics.mean(b1)
    b2_m = statistics.mean(b2)
    b1_s = statistics.stdev(b1)
    b2_s = statistics.stdev(b2)
    diffs  = [b - a for a, b in zip(b1, b2)]
    d_mean = statistics.mean(diffs)
    d_se   = statistics.stdev(diffs) / math.sqrt(len(diffs))
    t_crit = stats.t.ppf(0.975, df=len(diffs) - 1)
    ci_lo  = d_mean - t_crit * d_se
    ci_hi  = d_mean + t_crit * d_se
    pct    = d_mean / b1_m * 100
    p_adj  = holm_p[idx]
    sig = '***' if p_adj < 0.001 else '**' if p_adj < 0.01 else '*' if p_adj < 0.05 else 'ns'

    print(
        f"{p:<8} {b1_m:>9.1f} {b1_s:>7.1f} {b2_m:>9.1f} {b2_s:>7.1f} "
        f"{d_mean:>+7.1f} {pct:>+6.2f}% [{ci_lo:>+7.1f},{ci_hi:>+6.1f}] "
        f"{p_val:>8.4f} {p_adj:>8.4f} {sig:>4}"
    )

print()
print("Paired t-test by repetition index; Holm correction across 4 position tests.")
print("* p-Holm<0.05  ** p-Holm<0.01  *** p-Holm<0.001  ns = not significant")

all_b1 = [v for p in positions for v in paired_lists(p)[0]]
all_b2 = [v for p in positions for v in paired_lists(p)[1]]
print(
    f"\nOverall B1: {statistics.mean(all_b1):.1f}  "
    f"B2: {statistics.mean(all_b2):.1f}  "
    f"Diff: {statistics.mean(all_b2) - statistics.mean(all_b1):+.1f} cycles/pkt  "
    f"({(statistics.mean(all_b2) - statistics.mean(all_b1)) / statistics.mean(all_b1) * 100:+.2f}%)"
)
