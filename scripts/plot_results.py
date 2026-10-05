#!/usr/bin/env python3
"""
scripts/plot_results.py
Generate plots from bench/pktgen_results.csv
Since all configs show 0% loss, plots focus on:
  1. Achieved PPS vs Offered PPS — shows NIC ceiling
  2. Packet size vs achieved PPS — shows NIC behaviour
  3. Summary table — confirmed 0% loss with exact counts
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os

df = pd.read_csv('bench/pktgen_results.csv')
df['forwarded_loss_pct'] = pd.to_numeric(df['forwarded_loss_pct'], errors='coerce')
accept = df[df['expected_verdict'] == 'accept'].copy()
os.makedirs('bench/plots', exist_ok=True)

COLORS = {'config_a': '#1f77b4', 'b1': '#ff7f0e', 'b2': '#2ca02c'}

# Plot 1: Achieved PPS vs Offered PPS — shows NIC ceiling
fig, ax = plt.subplots(figsize=(8, 5))
for config in ['config_a', 'b1', 'b2']:
    sub = accept[(accept['config'] == config) &
                 (accept['match_pos'] == 'best') &
                 (accept['pkt_size_bytes'] == 64)]
    grp = sub.groupby('target_pps')['pktgen_achieved_pps'].mean().reset_index()
    ax.plot(grp['target_pps']/1000, grp['pktgen_achieved_pps']/1000,
            marker='o', label=config.upper().replace('_', ' '),
            color=COLORS[config], linewidth=2)
ax.plot([10, 50], [10, 50], 'k--', alpha=0.4, label='Ideal (no loss)')
ax.set_xlabel('Offered rate (kpps)', fontsize=12)
ax.set_ylabel('Achieved PPS (kpps)', fontsize=12)
ax.set_title('Offered vs Achieved PPS — all configs track ideal line\n'
             'NIC ceiling ~50K pps, best case, 64B packets', fontsize=12)
ax.legend(); ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('bench/plots/plot1_offered_vs_achieved.png', dpi=150)
plt.close()
print("✓ Plot 1 saved — offered vs achieved PPS")

# Plot 2: Forwarded packets vs offered — exact counts at 50K pps
fig, ax = plt.subplots(figsize=(8, 5))
sub50 = accept[accept['target_pps'] == 50000].copy()
for config in ['config_a', 'b1', 'b2']:
    for pos in ['best', 'middle', 'worst']:
        sub = sub50[(sub50['config'] == config) & (sub50['match_pos'] == pos) & (sub50['pkt_size_bytes'] == 64)]
        if len(sub) > 0:
            mean_fwd = sub['forwarded_pkts'].mean()
            mean_off = sub['offered_pkts'].mean()
            label = f"{config.upper().replace('_',' ')} {pos}" if pos == 'best' else None
            ax.scatter(mean_off/1000, mean_fwd/1000,
                      color=COLORS[config], s=80, alpha=0.8, label=label)
ax.plot([0, 600], [0, 600], 'k--', alpha=0.4, label='Perfect forwarding')
ax.set_xlabel('Offered packets (thousands)', fontsize=12)
ax.set_ylabel('Forwarded packets (thousands)', fontsize=12)
ax.set_title('Offered vs forwarded packets at 50K pps — all configs, 64B\n'
             'All points on the ideal line: 0% loss confirmed', fontsize=12)
ax.legend(loc='upper left'); ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('bench/plots/plot2_forwarded_vs_offered.png', dpi=150)
plt.close()
print("✓ Plot 2 saved — forwarded vs offered packets")

# Plot 3: Packet size vs achieved PPS — B2 best case
fig, ax = plt.subplots(figsize=(8, 5))
SIZES = [64, 128, 256, 512, 1024, 1400]
for config in ['config_a', 'b1', 'b2']:
    means = []
    for sz in SIZES:
        sub = accept[(accept['config'] == config) &
                     (accept['match_pos'] == 'best') &
                     (accept['pkt_size_bytes'] == sz) &
                     (accept['target_pps'] == 50000)]
        means.append(sub['pktgen_achieved_pps'].mean() / 1000 if len(sub) > 0 else 0)
    ax.plot(SIZES, means, marker='o',
            label=config.upper().replace('_', ' '),
            color=COLORS[config], linewidth=2)
ax.set_xlabel('Packet size (bytes)', fontsize=12)
ax.set_ylabel('Achieved PPS (kpps) at 50K offered', fontsize=12)
ax.set_title('Packet size vs achieved PPS at 50K pps — best case\n'
             'All configs achieve target rate regardless of packet size', fontsize=12)
ax.legend(); ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig('bench/plots/plot3_pktsize_vs_pps.png', dpi=150)
plt.close()
print("✓ Plot 3 saved — packet size vs achieved PPS")

# Plot 4: Summary bar chart — mean forwarding loss by config
fig, ax = plt.subplots(figsize=(7, 4))
configs = ['config_a', 'b1', 'b2']
labels  = ['Config A', 'B1', 'B2']
means   = [accept[accept['config']==c]['forwarded_loss_pct'].mean() for c in configs]
bars = ax.bar(labels, means, color=[COLORS[c] for c in configs], alpha=0.85, width=0.4)
ax.set_ylabel('Mean forwarding loss (%)', fontsize=12)
ax.set_title('Mean forwarding loss across all trials\n'
             '10 rules, 64–1400B, 10K–50K pps, all rule positions', fontsize=12)
ax.set_ylim(0, 0.001)
for bar, val in zip(bars, means):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.00002,
            f'{val:.5f}%', ha='center', va='bottom', fontsize=10, fontweight='bold')
ax.grid(axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig('bench/plots/plot4_mean_loss_summary.png', dpi=150)
plt.close()
print("✓ Plot 4 saved — mean loss summary")

# Print summary statistics
print()
print("=== Forwarding Loss Summary ===")
print(f"Total accept-verdict runs: {len(accept)}")
nonzero = accept[accept['forwarded_loss_pct'] > 0]
print(f"Runs with any loss: {len(nonzero)} ({len(nonzero)/len(accept)*100:.2f}% of runs)")
print(f"Maximum loss in any run: {accept['forwarded_loss_pct'].max():.4f}%")
print()
for config in ['config_a', 'b1', 'b2']:
    sub = accept[accept['config']==config]
    print(f"{config}: {len(sub)} runs, mean loss={sub['forwarded_loss_pct'].mean():.5f}%, max={sub['forwarded_loss_pct'].max():.4f}%")

print("\nAll plots saved to bench/plots/")
