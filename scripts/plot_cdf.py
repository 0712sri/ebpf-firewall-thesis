#!/usr/bin/env python3
"""
scripts/plot_cdf.py — Generate CDF plots from latency data
Usage: python3 scripts/plot_cdf.py
Output: bench/latency_cdf.png
"""

import numpy as np
import matplotlib.pyplot as plt

configs = {
    'bare':     ('bench/latency_bare.txt',     'gray',   '--'),
    'Config A': ('bench/latency_config_a.txt', 'blue',   '-.'),
    'B2':       ('bench/latency_b2.txt',        'green',  '-'),
    'B1':       ('bench/latency_b1.txt',        'red',    ':'),
}

plt.figure(figsize=(10, 6))

for label, (filepath, color, linestyle) in configs.items():
    data = np.loadtxt(filepath)
    sorted_data = np.sort(data)
    cdf = np.arange(1, len(sorted_data) + 1) / len(sorted_data)
    plt.plot(sorted_data, cdf, label=label, color=color,
             linestyle=linestyle, linewidth=2)
    p50 = np.percentile(data, 50)
    p95 = np.percentile(data, 95)
    p99 = np.percentile(data, 99)
    print(f"{label}: P50={p50:.3f}ms  P95={p95:.3f}ms  P99={p99:.3f}ms  "
          f"mean={np.mean(data):.3f}ms  std={np.std(data):.3f}ms")

plt.xlabel('RTT (ms)', fontsize=13)
plt.ylabel('CDF', fontsize=13)
plt.title('Latency CDF — bare vs Config A vs B1 vs B2', fontsize=14)
plt.legend(fontsize=12)
plt.grid(True, alpha=0.3)
plt.xlim(0, 10)
plt.axvline(x=np.percentile(np.loadtxt('bench/latency_b2.txt'), 95),
            color='green', alpha=0.3, linestyle='--', linewidth=1)
plt.tight_layout()
plt.savefig('bench/latency_cdf.png', dpi=150)
print("\n✓ Saved: bench/latency_cdf.png")
