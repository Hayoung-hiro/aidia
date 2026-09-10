"""Conceptual scheduling example; this is not measured AIDIA performance."""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
import numpy as np

plt.rcParams.update({"font.family": "Malgun Gothic", "axes.unicode_minus": False,
                     "font.size": 11})
fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True,
                         gridspec_kw={"height_ratios": [1.2, 1]})
ax = axes[0]
ax.add_patch(Rectangle((8, 400), 2, 400, facecolor="#cee9e4",
                       edgecolor="#258a7a", linewidth=2))
ax.add_patch(Rectangle((10, 500), 2, 350, facecolor="#d8e5f2",
                       edgecolor="#456f9a", linewidth=2))
ax.plot([8.7, 10], [450, 450], color="#258a7a", linewidth=4)
ax.plot([10, 11.3], [450, 450], color="#d37a32", linewidth=4, linestyle="--")
ax.text(8.15, 745, "이전 범위: 400–800 m/z")
ax.text(10.15, 795, "다음 범위: 500–850 m/z")
ax.text(10.15, 412, "450 m/z 피크는 측정 범위에서 이탈", color="#a35b24")
ax.set(ylim=(370, 880), ylabel="m/z",
       title="RT 스케줄은 이어져 있어도, 특정 피크의 측정은 끊길 수 있습니다",)
t = np.linspace(8, 12, 1001)
y = np.exp(-0.5 * ((t - 10) / 0.3) ** 2)
ax = axes[1]
ax.plot(t, y, color="#38434e", linewidth=2)
ax.fill_between(t, y, where=t <= 10, color="#73b7aa", alpha=0.8,
                label="측정 가능한 부분")
ax.fill_between(t, y, where=t >= 10, color="#e1a475", alpha=0.8,
                label="측정하지 못하는 부분")
ax.text(10.45, 0.60, "경계가 apex와 일치하는\n대칭 피크 예시: 약 50% 손실", color="#a35b24")
ax.set(xlim=(8, 12), ylim=(0, 1.12), xlabel="RT (min)", ylabel="상대 피크 강도")
ax.legend(loc="upper left", frameon=False)
for ax in axes:
    ax.axvline(10, color="#965454", linestyle=":", linewidth=1.5)
    ax.spines[["top", "right"]].set_visible(False)
fig.text(0.5, 0.015,
         "개념도 · 실측 결과 아님 · 위 직사각형은 RT 구간별 전체 분석 범위이며 내부 isolation window는 생략",
         ha="center", fontsize=9, color="#62676d")
fig.tight_layout(rect=(0, 0.04, 1, 1))
target = Path(__file__).with_name("2026-09-08-rt-boundary-illustration.png")
fig.savefig(target, dpi=150)
fig.savefig(target.with_suffix(".svg"))
plt.close(fig)
print(target)
