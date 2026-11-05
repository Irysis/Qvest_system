#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""KR-CISS 차트 · ① 지수 시계열 + LT 위기 음영 ② 최근 축별 기여 막대 ③ 축 기여 누적 면적 ④ 사건 연구(고점 정렬) ⑤ 최근 1년 확대.
입력 = build_kr_stress_index.py 의 output/. 글꼴 = 현대하모니 M(차트 규약 qvest-telegram SKILL §0.7)."""
from __future__ import annotations

import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib import font_manager  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
OUT, CH = HERE + "/output", HERE + "/charts"
os.makedirs(CH, exist_ok=True)

AXES = ["equity", "credit", "fx", "flow", "breadth", "funding", "global"]
AXIS_KO = {"equity": "주식 변동성·낙폭", "credit": "신용·금리", "fx": "환율", "flow": "외국인 수급",
           "breadth": "시장 폭·동조화", "funding": "단기 자금", "global": "글로벌 전이"}
# 구분 색(채도 다른 7색 · 색약 구분 가능)
COL = {"equity": "#1f4e79", "credit": "#c0504d", "fx": "#e69f00", "flow": "#009e73", "breadth": "#7b4ea3",
       "funding": "#56b4e9", "global": "#8c8c8c"}


def set_font():
    for d in [os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "Windows", "Fonts"),
              os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts")]:
        p = os.path.join(d, "현대하모니+M.ttf")
        if os.path.exists(p):
            font_manager.fontManager.addfont(p)
            name = font_manager.FontProperties(fname=p).get_name()
            plt.rcParams["font.family"] = name
            plt.rcParams["axes.unicode_minus"] = False
            return name
    plt.rcParams["font.family"] = "Malgun Gothic"
    plt.rcParams["axes.unicode_minus"] = False
    return "Malgun Gothic(폴백)"


def shade(ax, eps, lo, hi):
    """LT 위기 구간 = 고점 → 바닥(behavior_card 의 위기 창). -20% 확정일은 점선."""
    for _, e in eps.iterrows():
        a, c, b = pd.Timestamp(e["peak"]), pd.Timestamp(e["confirm"]), pd.Timestamp(e["trough"])
        if b < lo or a > hi:
            continue
        ax.axvspan(max(a, lo), min(b, hi), color="#cfcfcf", alpha=0.6, lw=0, zorder=0)
        if lo <= c <= hi:
            ax.axvline(c, color="#999999", lw=0.6, ls=":", zorder=0)
    ax.set_xlim(lo, hi)


def main():
    fam = set_font()
    d = pd.read_parquet(OUT + "/kr_stress_daily.parquet")
    d.index = pd.to_datetime(d.index)
    eps = pd.read_csv(OUT + "/crisis_episodes_lt2020_kospi200.csv", parse_dates=["peak", "confirm", "trough", "recover"])
    meta = json.load(open(OUT + "/run_meta.json", encoding="utf-8"))
    last = d.index[-1]
    lo, hi = d.index[0], last
    C = d[[f"c_{a}" for a in AXES]].clip(lower=0)  # 음의 상관 기여는 0 으로 접어 면적만 그린다(합계선은 원값)

    # ① 전 기간 · 지수 + 위기 음영 + V-KOSPI 비교
    fig, ax = plt.subplots(2, 1, figsize=(14, 8.5), sharex=True, gridspec_kw={"height_ratios": [3, 1.4]})
    shade(ax[0], eps, lo, hi)
    ax[0].plot(d.index, d["score"], color="#1f4e79", lw=1.1, label="KR 스트레스 지수(0~100 · CISS 식 집계)")
    ax[0].plot(d.index, d["score_linear"], color="#c0504d", lw=0.7, alpha=0.7, label="축 단순 평균 ×100(상관 미반영)")
    p80 = d["score"].expanding(min_periods=250).quantile(0.80)
    ax[0].plot(d.index, p80, color="#555555", lw=0.6, ls="--", label="재귀 80백분위")
    ax[0].set_ylim(0, 100)
    ax[0].set_ylabel("지수")
    ax[0].legend(loc="upper left", fontsize=9, frameon=False)
    ax[0].set_title(f"국내 자본시장 스트레스 지수 시제품 · {lo.date()}~{last.date()} · 회색 = KOSPI200 Lunde-Timmermann 20/20 위기(고점→바닥 · 점선 = -20% 확정일)", fontsize=12)
    ax[0].text(0.995, 0.97, f"최근 {last.date()}: {d['score'].iloc[-1]:.1f} (재귀 백분위 {100 * d['score_pct'].iloc[-1]:.0f})",
               transform=ax[0].transAxes, ha="right", va="top", fontsize=10,
               bbox=dict(boxstyle="round", fc="white", ec="#999999"))
    shade(ax[1], eps, lo, hi)
    ax[1].plot(d.index, d["vkospi"], color="#444444", lw=0.8, label="V-KOSPI200(비교 · 지수 입력 아님)")
    ax[1].set_ylabel("V-KOSPI")
    ax[1].legend(loc="upper left", fontsize=9, frameon=False)
    ax[1].xaxis.set_major_locator(mdates.YearLocator(2))
    ax[1].xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
    for a in ax:
        a.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(CH + "/01_index_timeseries_crises.png", dpi=150)
    plt.close(fig)

    # ② 최근 축별 기여 막대 · 최신 vs 20거래일 전
    lt = meta["latest"]
    fig, ax = plt.subplots(figsize=(10, 5))
    y = np.arange(len(AXES))
    now = [lt["contrib"][a] for a in AXES]
    prev = [lt["contrib_20td_ago"][a] for a in AXES]
    ax.barh(y + 0.2, now, height=0.38, color=[COL[a] for a in AXES], label=f"{lt['date']} (합계 {lt['score']:.1f})")
    ax.barh(y - 0.2, prev, height=0.38, color=[COL[a] for a in AXES], alpha=0.35, label=f"{lt['date_20td_ago']} (합계 {lt['score_20td_ago']:.1f})")
    for i, a in enumerate(AXES):
        ax.text(max(now[i], prev[i], 0) + 0.3, i + 0.2, f"{now[i]:.1f}  (하위지수 {lt['subindex'][a]:.2f} · 축 백분위 {100 * lt['axis_pct'][a]:.0f})",
                va="center", fontsize=9)
    ax.set_yticks(y)
    ax.set_yticklabels([AXIS_KO[a] for a in AXES])
    ax.invert_yaxis()
    ax.set_xlabel("지수 기여(점) = w·s_i × Σ_j ρ_ij w·s_j × 100 · 합이 지수")
    ax.set_title(f"축별 기여 분해 · 지수 {lt['score']:.1f} · 축 평균 상관 {lt['avg_axis_corr']:.2f} · 비교 V-KOSPI {lt['vkospi']:.1f}", fontsize=12)
    ax.legend(loc="lower right", fontsize=9, frameon=False)
    ax.grid(axis="x", alpha=0.25)
    ax.set_xlim(left=min(0, min(now + prev)) - 1)
    fig.tight_layout()
    fig.savefig(CH + "/02_axis_contribution_latest.png", dpi=150)
    plt.close(fig)

    # ③ 축 기여 누적 면적(월말 표본 · 가독성) + 위기 음영
    m = C.resample("W-FRI").last().dropna(how="all")
    fig, ax = plt.subplots(figsize=(14, 6))
    shade(ax, eps, lo, hi)
    ax.stackplot(m.index, [m[f"c_{a}"] for a in AXES], labels=[AXIS_KO[a] for a in AXES], colors=[COL[a] for a in AXES], alpha=0.9, lw=0)
    ax.plot(d.index, d["score"], color="black", lw=0.6, label="지수(원값)")
    ax.set_ylim(0, 100)
    ax.set_title("축별 기여의 시간 변화(주간 표본 · 음의 상관 기여는 0 으로 접음) · 위기마다 켜지는 축이 다르다", fontsize=12)
    ax.legend(loc="upper left", fontsize=8, ncol=4, frameon=False)
    ax.xaxis.set_major_locator(mdates.YearLocator(2))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
    ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(CH + "/03_axis_contribution_stacked.png", dpi=150)
    plt.close(fig)

    # ④ 사건 연구 · 고점 · -20% 확정일 기준 평균 경로
    ev = pd.read_csv(OUT + "/event_study_paths.csv")
    fig, ax = plt.subplots(1, 2, figsize=(14, 5), sharey=True)
    for k, anchor in enumerate(["peak", "confirm"]):
        e = ev[ev["anchor"] == anchor]
        piv = e.pivot_table(index="offset_td", columns="peak", values="score")
        for c in piv.columns:
            ax[k].plot(piv.index, piv[c], lw=0.7, alpha=0.5)
        ax[k].plot(piv.index, piv.median(axis=1), color="black", lw=2, label=f"중앙값(n={piv.shape[1]})")
        ax[k].axvline(0, color="red", lw=0.8, ls="--")
        ax[k].set_title("KOSPI200 고점일 = 0" if anchor == "peak" else "-20% 첫 통과(위기 확정)일 = 0")
        ax[k].set_xlabel("거래일 오프셋")
        ax[k].grid(alpha=0.25)
        ax[k].legend(fontsize=9, frameon=False)
    ax[0].set_ylabel("지수")
    fig.suptitle("사건 연구 · 위기 고점 · 확정일 전후의 지수 경로(얇은 선 = 위기별 · 굵은 선 = 중앙값)", fontsize=12)
    fig.tight_layout()
    fig.savefig(CH + "/04_event_study.png", dpi=150)
    plt.close(fig)

    # ⑤ 최근 18개월 확대 · 지수 · 기여 · KOSPI200
    z0 = last - pd.DateOffset(months=18)
    dz = d[d.index >= z0]
    mz = C[C.index >= z0]
    fig, ax = plt.subplots(2, 1, figsize=(14, 8), sharex=True, gridspec_kw={"height_ratios": [2.2, 1.2]})
    shade(ax[0], eps, z0, hi)
    ax[0].stackplot(mz.index, [mz[f"c_{a}"] for a in AXES], labels=[AXIS_KO[a] for a in AXES], colors=[COL[a] for a in AXES], alpha=0.9, lw=0)
    ax[0].plot(dz.index, dz["score"], color="black", lw=0.8, label="지수")
    ax[0].set_ylim(0, max(100, dz["score"].max() * 1.05))
    ax[0].legend(loc="upper left", fontsize=8, ncol=4, frameon=False)
    ax[0].set_title(f"최근 18개월 · 지수와 축별 기여 · 마지막 {last.date()} = {d['score'].iloc[-1]:.1f}", fontsize=12)
    ax[0].grid(alpha=0.25)
    bm = pd.read_parquet(HERE + "/../../../.cache/benchmark.parquet")
    bm["Date"] = pd.to_datetime(bm["Date"])
    bm = bm.set_index("Date")["BM_Close"]
    bz = bm[bm.index >= z0]
    shade(ax[1], eps, z0, hi)
    ax[1].plot(bz.index, bz, color="#1f4e79", lw=1.0, label="KOSPI200")
    ax[1].set_ylabel("KOSPI200")
    ax[1].legend(loc="upper left", fontsize=9, frameon=False)
    ax[1].grid(alpha=0.25)
    ax[1].xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    ax[1].xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    fig.tight_layout()
    fig.savefig(CH + "/05_recent_18m_zoom.png", dpi=150)
    plt.close(fig)
    print("[charts] font =", fam, "| 5 charts →", CH)


if __name__ == "__main__":
    main()
