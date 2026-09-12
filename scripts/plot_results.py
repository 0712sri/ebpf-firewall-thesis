#!/usr/bin/env python3
"""
scripts/plot_results.py
Generate plots from bench/pktgen_results.csv
Produces:
  1. Offered PPS vs Loss% — by config and match position
  2. Packet size vs Loss% — by config
  3. Rule position effect — B1 vs B2
  4. Config A vs B1 vs B2 comparison
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import os

# Load data
df = pd.read_csv('bench/pktgen_results.csv')

# Convert loss to numeric
df['forwarded_loss_pct'] = pd.to_numeric(df['forwarded_loss_pct'], errors='coerce')

# Filter only ACCEPT tests for loss analysis
accept = df[df['expected_verdict'] == 'accept'].copy()
drop   = df[df['expected_verdict'] == 'drop'].copy()

os.makedirs('bench/plots', exist_ok=True)

COLORS = {
    'config_a': '#1f77b4',
    'b1':       '#ff7f0e',
    'b2':       '#2ca02c',
}
MARKERS = {
    'best':   'o',
    'middle': 's',
    'worst':  '^',
}
SIZES = [64, 128, 256, 512, 1024, 1400]

# ── Plot 1: Offered PPS vs Loss% per config (best case, 64B) ─────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for config in ['config_a', 'b1', 'b2']:
    sub = accept[(accept['config'] == config) &
                 (accept['match_pos'] == 'best') &
                 (accept['pkt_size_bytes'] == 64)]
    grp = sub.groupby('target_pps')['forwarded_loss_pct'].mean().reset_index()
    ax.plot(grp['target_pps']/1000, grp['forwarded_loss_pct'],
            marker='o', label=config.upper().replace('_', ' '),
            color=COLORS[config], linewidth=2)

ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Forwarding loss (%)', fontsize=12)
ax.set_title('Offered PPS vs Forwarding Loss — best case, 64B packets', fontsize=13)
ax.legend()
ax.grid(True, alpha=0.3)
ax.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.4f'))
plt.tight_layout()
plt.savefig('bench/plots/plot1_pps_vs_loss_best64.png', dpi=150)
plt.close()
print("✓ Plot 1 saved")

# ── Plot 2: Rule position effect on B2 — 64B ─────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for pos in ['best', 'middle', 'worst']:
    sub = accept[(accept['config'] == 'b2') &
                 (accept['match_pos'] == pos) &
                 (accept['pkt_size_bytes'] == 64)]
    grp = sub.groupby('target_pps')['forwarded_loss_pct'].mean().reset_index()
    ax.plot(grp['target_pps']/1000, grp['forwarded_loss_pct'],
            marker=MARKERS[pos], label=f'{pos} case',
            linewidth=2)

ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Forwarding loss (%)', fontsize=12)
ax.set_title('Rule position effect — B2, 10 rules, 64B packets', fontsize=13)
ax.legend()
ax.grid(True, alpha=0.3)
ax.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.4f'))
plt.tight_layout()
plt.savefig('bench/plots/plot2_rule_position_b2_64.png', dpi=150)
plt.close()
print("✓ Plot 2 saved")

# ── Plot 3: B1 vs B2 rule position comparison — worst case ───────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for config in ['b1', 'b2']:
    for pos in ['best', 'worst']:
        sub = accept[(accept['config'] == config) &
                     (accept['match_pos'] == pos) &
                     (accept['pkt_size_bytes'] == 64)]
        grp = sub.groupby('target_pps')['forwarded_loss_pct'].mean().reset_index()
        ax.plot(grp['target_pps']/1000, grp['forwarded_loss_pct'],
                marker=MARKERS[pos],
                color=COLORS[config],
                linestyle='-' if pos == 'best' else '--',
                label=f'{config.upper()} {pos}',
                linewidth=2)

ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Forwarding loss (%)', fontsize=12)
ax.set_title('B1 vs B2 — best and worst case, 64B packets', fontsize=13)
ax.legend()
ax.grid(True, alpha=0.3)
ax.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.4f'))
plt.tight_layout()
plt.savefig('bench/plots/plot3_b1_vs_b2_position.png', dpi=150)
plt.close()
print("✓ Plot 3 saved")

# ── Plot 4: Packet size effect — B2 best case ─────────────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for pkt_size in SIZES:
    sub = accept[(accept['config'] == 'b2') &
                 (accept['match_pos'] == 'best') &
                 (accept['pkt_size_bytes'] == pkt_size)]
    grp = sub.groupby('target_pps')['forwarded_loss_pct'].mean().reset_index()
    ax.plot(grp['target_pps']/1000, grp['forwarded_loss_pct'],
            marker='o', label=f'{pkt_size}B', linewidth=2)

ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Forwarding loss (%)', fontsize=12)
ax.set_title('Packet size effect — B2, 10 rules, best case', fontsize=13)
ax.legend(title='Packet size')
ax.grid(True, alpha=0.3)
ax.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.4f'))
plt.tight_layout()
plt.savefig('bench/plots/plot4_pkt_size_b2.png', dpi=150)
plt.close()
print("✓ Plot 4 saved")

# ── Plot 5: Config A vs B1 vs B2 — worst case, 64B ───────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for config in ['config_a', 'b1', 'b2']:
    sub = accept[(accept['config'] == config) &
                 (accept['match_pos'] == 'worst') &
                 (accept['pkt_size_bytes'] == 64)]
    grp = sub.groupby('target_pps')['forwarded_loss_pct'].mean().reset_index()
    ax.plot(grp['target_pps']/1000, grp['forwarded_loss_pct'],
            marker='o', label=config.upper().replace('_', ' '),
            color=COLORS[config], linewidth=2)

ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Forwarding loss (%)', fontsize=12)
ax.set_title('Config A vs B1 vs B2 — worst case, 64B packets', fontsize=13)
ax.legend()
ax.grid(True, alpha=0.3)
ax.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.4f'))
plt.tight_layout()
plt.savefig('bench/plots/plot5_all_configs_worst64.png', dpi=150)
plt.close()
print("✓ Plot 5 saved")

# ── Plot 6: Achieved PPS vs Offered PPS — all configs ────────────────────────
fig, ax = plt.subplots(figsize=(8, 5))
for config in ['config_a', 'b1', 'b2']:
    sub = accept[(accept['config'] == config) &
                 (accept['match_pos'] == 'best') &
                 (accept['pkt_size_bytes'] == 64)]
    grp = sub.groupby('target_pps')['pktgen_achieved_pps'].mean().reset_index()
    ax.plot(grp['target_pps']/1000, grp['pktgen_achieved_pps']/1000,
            marker='o', label=config.upper().replace('_', ' '),
            color=COLORS[config], linewidth=2)

ax.plot([10, 50], [10, 50], 'k--', alpha=0.3, label='ideal')
ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Achieved PPS (kpps)', fontsize=12)
ax.set_title('Offered vs Achieved PPS — best case, 64B', fontsize=13)
ax.legend()
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('bench/plots/plot6_offered_vs_achieved.png', dpi=150)
plt.close()
print("✓ Plot 6 saved")

print("\nAll plots saved to bench/plots/")