#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""일보용 차트 7종 — A4 세로 본문 폭(약 188mm = 7.4in)에 1:1 로 들어가도록 그린다(글자 9pt 안팎 · 테두리 밖 잘림 없음).
① 게이지(역사 백분위 + 단계 띠) ② 축별 기여 막대 + 백분위 칩 ③ 최근 65거래일 축 백분위 히트맵 ④ 레이더(오늘 · 20일 전 · 2008 정점) + 역사 분포
⑤ 34지표 롤리팝 ⑥ 최근 18개월 기여 누적 + KOSPI200 ⑦ 전 기간 + LT 위기 음영 + V-KOSPI.
글꼴 = 현대하모니 M(차트 규약). 색 = 축 12색 팔레트 · 단계색(정상 초록 · 주의 노랑 · 위험 빨강)."""
from __future__ import annotations

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib import font_manager  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402

W = 7.4          # 본문 폭(in)
DPI = 200
PALETTE = ["#1f4e79", "#c0504d", "#e69f00", "#009e73", "#7b4ea3", "#56b4e9", "#8c8c8c",
           "#d55e00", "#cc79a7", "#117733", "#882255", "#999933"]
SHORT = {"equity": "대형주", "smallcap": "중소형", "breadth": "하락 확산", "liquidity": "유동성", "rates": "국채 금리", "credit": "회사채",
         "funding": "단기자금", "fx": "환율", "financial": "금융주", "flow": "외국인", "global": "해외", "contagion": "시장 간"}
TIER_FILL = {"정상": "#c8e6c9", "주의": "#fff3c4", "위험": "#ffcdd2"}
TIER_EDGE = {"정상": "#2e7d32", "주의": "#f9a825", "위험": "#c62828"}


def set_font():
    for d in [os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "Windows", "Fonts"),
              os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts")]:
        p = os.path.join(d, "현대하모니+M.ttf")
        if os.path.exists(p):
            font_manager.fontManager.addfont(p)
            pb = os.path.join(d, "현대하모니+B.ttf")      # 굵은 글씨(제목 · 칩 숫자)용 — 같은 패밀리면 bold 로 잡힌다
            if os.path.exists(pb):
                font_manager.fontManager.addfont(pb)
            plt.rcParams["font.family"] = font_manager.FontProperties(fname=p).get_name()
            break
    else:
        plt.rcParams["font.family"] = "Malgun Gothic"
    plt.rcParams["axes.unicode_minus"] = False
    plt.rcParams["font.size"] = 9
    plt.rcParams["axes.titlesize"] = 10.5
    plt.rcParams["axes.labelsize"] = 9
    plt.rcParams["xtick.labelsize"] = 8.5
    plt.rcParams["ytick.labelsize"] = 8.5
    plt.rcParams["legend.fontsize"] = 8
    return plt.rcParams["font.family"]


def T(s: str) -> str:
    """현대하모니에 없는 기호(— – −)를 하이픈으로 — 차트 글자는 대체 글꼴 없이 그려지므로 빈 상자로 나온다."""
    return str(s).replace("—", "-").replace("–", "-").replace("−", "-")


def pct_color(p):
    """역사 백분위(0~1) → 단계색(≥.9 빨강 · ≥.8 주황 · ≥.6 노랑 · 그 외 초록)."""
    return "#c62828" if p >= 0.9 else "#ef6c00" if p >= 0.8 else "#f9a825" if p >= 0.6 else "#2e7d32"


def _save(fig, path):
    fig.savefig(path, dpi=DPI, bbox_inches="tight", pad_inches=0.12, facecolor="white")
    plt.close(fig)
    return path


def shade(ax, eps, lo, hi):
    for _, e in eps.iterrows():
        a, c, b = pd.Timestamp(e["peak"]), pd.Timestamp(e["confirm"]), pd.Timestamp(e["trough"])
        if b < lo or a > hi:
            continue
        ax.axvspan(max(a, lo), min(b, hi), color="#d0d0d0", alpha=0.6, lw=0, zorder=0)
        if lo <= c <= hi:
            ax.axvline(c, color="#999999", lw=0.6, ls=":", zorder=0)
    ax.set_xlim(lo, hi)


# ── ① 게이지 ──────────────────────────────────────────────────────────────────
def chart_gauge(lt, ns, d, eps, pct_20d, path, days=250):
    """위 = 심각도 눈금(0 역대 가장 평온 ~ 100 역대 최악 · 단계 띠 · 오늘 · 전일 · 20일 전 · 60일 전 · V-KOSPI) · 아래 = 최근 1년 심각도의 길(단계 띠 · 급락 구간 음영)."""
    warn = 100 * (ns.get("threshold_warn") or 0.8)
    risk = 100 * (ns.get("threshold_risk") or 0.99)
    today = 100 * lt["score_pct"]
    fig = plt.figure(figsize=(W, 4.0), dpi=DPI)
    ax = fig.add_axes([0.05, 0.60, 0.92, 0.30])
    for lo, hi, name in ((0, warn, "정상"), (warn, risk, "주의"), (risk, 100, "위험")):
        ax.barh(0, hi - lo, left=lo, height=0.5, color=TIER_FILL[name], edgecolor=TIER_EDGE[name], lw=0.8)
        if hi - lo > 6:
            ax.text((lo + hi) / 2, 0, name, ha="center", va="center", fontsize=9, color=TIER_EDGE[name], fontweight="bold")
    for x, lab in ((60, "다소 나쁨"), (80, "나쁨"), (90, "매우 나쁨")):     # 세부 단계 경계
        ax.plot([x, x], [-0.25, 0.25], color="#666666", lw=0.6, ls=":")
        ax.text(x, 0.30, lab, ha="center", va="bottom", fontsize=6.6, color="#555555")
    ax.plot([today], [0.42], marker="v", ms=11, color="#111111", zorder=6, clip_on=False)
    ax.text(min(max(today, 6), 94), 0.70, f"오늘 {today:.0f}", ha="center", va="bottom", fontsize=10.5, fontweight="bold")
    # 아래쪽 표식 — 같은 값은 한 라벨로 합치고, 가까운 라벨은 최대 3단으로 내려 겹치지 않게
    marks = []
    if len(d) > 1 and d["score_pct"].iloc[-2] == d["score_pct"].iloc[-2]:
        marks.append((100 * float(d["score_pct"].iloc[-2]), "전일", "#333333", "o", 5))
    if pct_20d == pct_20d:
        marks.append((100 * pct_20d, "20거래일 전", "#555555", "^", 8))
    i60 = max(0, len(d) - 61)
    if d["score_pct"].iloc[i60] == d["score_pct"].iloc[i60]:
        marks.append((100 * float(d["score_pct"].iloc[i60]), "60거래일 전", "#888888", "s", 6))
    marks.append((100 * lt["vkospi_pct"], "V-KOSPI", "#1f4e79", "D", 6))
    marks.sort(key=lambda t: t[0])
    merged = []
    for x, lab, col, mk, ms in marks:
        if merged and abs(merged[-1][0] - x) < 1.0:
            merged[-1] = (merged[-1][0], merged[-1][1] + " · " + lab, merged[-1][2], merged[-1][3], merged[-1][4])
        else:
            merged.append((x, lab, col, mk, ms))
    occupied = [[], [], []]   # 단(level)별로 라벨이 차지한 x 구간 — 글자 폭을 어림해 겹치면 아래 단으로
    for x, lab, col, mk, ms in merged:
        text = f"{lab} {x:.0f}"
        w = 1.45 * len(text)                       # 라벨 폭(눈금 단위 · 7.6pt 어림)
        if x >= 86:
            lo, hi, ha, xt = x + 1.5 - w, x + 1.5, "right", x + 1.5
        elif x <= 14:
            lo, hi, ha, xt = x - 1.5, x - 1.5 + w, "left", x - 1.5
        else:
            lo, hi, ha, xt = x - w / 2, x + w / 2, "center", x
        lvl = next((k for k in range(3) if all(hi + 1 < a or lo - 1 > b for a, b in occupied[k])), 2)
        occupied[lvl].append((lo, hi))
        ax.plot([x], [-0.52], marker=mk, ms=ms, color=col, zorder=5, clip_on=False)
        ax.text(xt, -0.74 - 0.34 * lvl, text, ha=ha, va="top", fontsize=7.6, color=col)
    ax.set_xlim(-1, 101)
    ax.set_ylim(-1.85, 1.05)
    ax.set_yticks([])
    ax.set_xticks(range(0, 101, 10))
    ax.set_xticklabels(["0\n역대 가장 평온"] + [str(x) for x in range(10, 100, 10)] + ["100\n역대 최악"])
    ax.tick_params(axis="x", labelsize=7.3, length=2, pad=1)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.set_title(T(f"오늘의 스트레스 심각도 {today:.0f} — 2006년 이후 전체 거래일 중 나쁜 순으로 상위 {100 - today:.0f}% (높을수록 나쁨 · 주의 {warn:.0f} · 위험 {risk:.0f})"),
                 fontsize=9.5, loc="left", pad=18)
    # ── 아래: 최근 1년 심각도의 길 ──
    ax2 = fig.add_axes([0.08, 0.07, 0.89, 0.40])
    dz = d.tail(days)
    y = 100 * dz["score_pct"]
    for lo, hi, name in ((0, warn, "정상"), (warn, risk, "주의"), (risk, 100, "위험")):
        ax2.axhspan(lo, hi, color=TIER_FILL[name], alpha=0.55, lw=0, zorder=0)
    shade(ax2, eps, dz.index[0], dz.index[-1])
    ax2.plot(dz.index, y, color="#1f4e79", lw=1.3, zorder=3)
    ax2.fill_between(dz.index, 0, y, color="#1f4e79", alpha=0.08, zorder=2)
    ax2.plot([dz.index[-1]], [today], marker="o", ms=6, color="#c62828", zorder=5)
    ax2.annotate(f"{today:.0f}", (dz.index[-1], today), xytext=(6, 0), textcoords="offset points", va="center", fontsize=8.5, color="#c62828", fontweight="bold")
    ax2.set_ylim(0, 100)
    ax2.set_yticks([0, 20, 40, 60, 80, 100])
    ax2.set_ylabel("심각도(높을수록 나쁨)", fontsize=8)
    ax2.xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    ax2.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    ax2.tick_params(labelsize=7.5)
    ax2.grid(alpha=0.25)
    for sp in ("top", "right"):
        ax2.spines[sp].set_visible(False)
    ax2.set_title(T(f"최근 {days}거래일의 심각도 — 어떤 길을 밟아 지금에 왔나(회색 = 코스피200 이 고점 대비 20% 넘게 빠진 구간)"), fontsize=8.8, loc="left")
    return _save(fig, path)


# ── ② 축별 기여 + 백분위 칩 ───────────────────────────────────────────────────
def chart_contrib(meta, lt, path):
    axes, ko = meta["axes"], meta["axis_ko"]
    col = {a: PALETTE[i % len(PALETTE)] for i, a in enumerate(axes)}
    order = sorted(axes, key=lambda a: -lt["contrib"][a])
    now = np.array([lt["contrib"][a] for a in order])
    prev = np.array([lt["contrib_20td_ago"][a] for a in order])
    n = len(order)
    fig = plt.figure(figsize=(W, 4.9), dpi=DPI)
    ax = fig.add_axes([0.21, 0.11, 0.56, 0.80])
    y = np.arange(n)
    ax.barh(y + 0.2, now, height=0.38, color=[col[a] for a in order], zorder=3)
    ax.barh(y - 0.2, prev, height=0.38, color=[col[a] for a in order], alpha=0.33, zorder=3)
    span = max(1.0, float(np.nanmax(np.concatenate([now, prev, [0]]))) - min(0.0, float(np.nanmin(np.concatenate([now, prev, [0]])))))
    for i in range(n):
        ax.text(max(now[i], 0) + span * 0.02, y[i] + 0.2, f"{now[i]:.1f}", va="center", ha="left", fontsize=8.5, zorder=4)
        ax.text(max(prev[i], 0) + span * 0.02, y[i] - 0.2, f"{prev[i]:.1f}", va="center", ha="left", fontsize=7.5, color="#666666", zorder=4)
    lo = min(0.0, float(np.nanmin(np.concatenate([now, prev])))) - span * 0.06
    hi = max(0.0, float(np.nanmax(np.concatenate([now, prev])))) + span * 0.22
    ax.set_xlim(lo, hi)
    ax.set_ylim(-0.7, n - 0.3)
    ax.invert_yaxis()
    ax.set_yticks(y)
    ax.set_yticklabels([ko[a] for a in order], fontsize=9)
    ax.axvline(0, color="#444444", lw=0.8)
    ax.grid(axis="x", alpha=0.25)
    ax.set_xlabel(T("분야별 몫(점) — 진한 막대 = 오늘 · 연한 막대 = 20거래일 전 · 모두 더하면 지수"), fontsize=8.5)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    # 오른쪽 칩 — 축 백분위
    ax2 = fig.add_axes([0.80, 0.11, 0.18, 0.80], sharey=ax)
    ax2.axis("off")
    ax2.set_xlim(0, 1)
    ax2.text(0.5, -0.75, "심각도", ha="center", va="center", fontsize=8.5, fontweight="bold")
    for i, a in enumerate(order):
        p = lt["axis_pct"][a]
        c = pct_color(p)
        ax2.add_patch(Rectangle((0.08, y[i] - 0.33), 0.84, 0.66, facecolor=c, edgecolor="none", alpha=0.9))
        ax2.text(0.5, y[i], f"{100 * p:.0f}", ha="center", va="center", fontsize=9, color="white", fontweight="bold")
    fig.suptitle(T(f"어느 분야에서 온 스트레스인가 — 지수 {lt['score']:.1f}점의 분야별 몫 · 오른쪽 칩 = 심각도(높을수록 나쁨 · 빨강 ≥90 매우 나쁨 · 주황 ≥80 나쁨 · 노랑 ≥60)"),
                 fontsize=9.5, x=0.02, ha="left", y=0.985)
    return _save(fig, path)


# ── ③ 히트맵 ──────────────────────────────────────────────────────────────────
def chart_heatmap(meta, d, path, n=65):
    axes, ko = meta["axes"], meta["axis_ko"]
    rows = ["score_pct"] + [f"pct_{a}" for a in axes]
    sub = d[rows].tail(n) * 100
    fig, ax = plt.subplots(figsize=(W, 4.4), dpi=DPI)
    im = ax.imshow(sub.T.values, aspect="auto", cmap="RdYlGn_r", vmin=0, vmax=100, interpolation="nearest")
    ax.set_yticks(range(len(rows)))
    ax.set_yticklabels(["종합 지수"] + [ko[a] for a in axes], fontsize=8.5)
    ax.get_yticklabels()[0].set_fontweight("bold")
    dates = sub.index
    ticks = [i for i in range(1, len(dates)) if dates[i].month != dates[i - 1].month]
    if not ticks or ticks[0] > 6:
        ticks = [0] + ticks
    ax.set_xticks(ticks)
    ax.set_xticklabels([dates[i].strftime("%Y-%m") for i in ticks], fontsize=8)
    ax.axhline(0.5, color="black", lw=0.8)
    for j, r in enumerate(rows):
        v = sub[r].iloc[-1]
        if v == v:
            ax.text(len(dates) - 1, j, f"{v:.0f}", ha="center", va="center", fontsize=6.8, color="black" if 25 < v < 75 else "white", fontweight="bold")
    cb = fig.colorbar(im, ax=ax, fraction=0.035, pad=0.02)
    cb.set_label("심각도(0~100 · 높을수록 나쁨)", fontsize=8.5, rotation=270, labelpad=14)
    cb.ax.tick_params(labelsize=8)
    ax.set_title(T(f"최근 {n}거래일 — 분야별로 언제 나빠졌나(빨강 = 심각 · 초록 = 평온 · 맨 오른쪽 숫자 = 오늘 심각도)"), fontsize=9.5, loc="left")
    return _save(fig, path)


# ── ④ 레이더 + 역사 분포 ──────────────────────────────────────────────────────
def chart_radar_hist(meta, d, lt, path):
    axes = meta["axes"]
    n = len(axes)
    ang = np.linspace(0, 2 * np.pi, n, endpoint=False).tolist()
    ang_c = ang + ang[:1]
    fig = plt.figure(figsize=(W, 3.9), dpi=DPI)
    ax = fig.add_axes([0.06, 0.21, 0.40, 0.64], projection="polar")
    today = [100 * lt["axis_pct"][a] for a in axes]
    t20 = pd.Timestamp(lt["date_20td_ago"])
    prev = [100 * float(d.loc[t20, f"pct_{a}"]) if t20 in d.index else np.nan for a in axes]
    tmax = pd.Timestamp(lt["max_score_date"])
    ref = [100 * float(d.loc[tmax, f"pct_{a}"]) if tmax in d.index else np.nan for a in axes]
    for vals, lab, sty in ((ref, f"{tmax.date()} 정점", dict(color="#c62828", lw=1.0, ls=":", alpha=0.9)),
                           (prev, f"20거래일 전({t20.date()})", dict(color="#777777", lw=1.2, ls="--")),
                           (today, "오늘", dict(color="#1f4e79", lw=2.0))):
        v = vals + vals[:1]
        ax.plot(ang_c, v, label=lab, **sty)
        if lab == "오늘":
            ax.fill(ang_c, v, color="#1f4e79", alpha=0.15)
    ax.set_xticks(ang)
    ax.set_xticklabels([SHORT[a] for a in axes], fontsize=8.5)
    ax.set_ylim(0, 100)
    ax.set_yticks([50, 80, 90])
    ax.set_yticklabels(["50", "80", "90"], fontsize=7, color="#555555")
    ax.set_rlabel_position(15)
    ax.grid(alpha=0.35)
    ax.set_title(T("12개 분야의 심각도 — 바깥일수록 나쁨 · 모양이 위기의 종류를 보여 줍니다"), fontsize=9.5, pad=14)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=1, frameon=False, fontsize=7.8)
    # 역사 분포
    ax2 = fig.add_axes([0.58, 0.16, 0.40, 0.70])
    s = d["score"].dropna()
    bins = np.arange(0, float(np.ceil(s.max() / 2.5) * 2.5) + 2.5, 2.5)
    ax2.hist(s, bins=bins, color="#9fb3c8", edgecolor="white", lw=0.4)
    ax2.set_yscale("log")
    ax2.axvline(lt["score"], color="#c62828", lw=2)
    ax2.text(lt["score"] + 0.8, ax2.get_ylim()[1] * 0.55, f"오늘 {lt['score']:.1f}\n백분위 {100 * lt['score_pct']:.0f}", color="#c62828", fontsize=8.5, va="top")
    for q, lab in ((0.8, "80%"), (0.9, "90%"), (0.95, "95%")):
        x = float(s.quantile(q))
        ax2.axvline(x, color="#777777", lw=0.7, ls=":")
        ax2.text(x, ax2.get_ylim()[0] * 1.4, lab, fontsize=7, color="#555555", ha="center")
    ax2.set_xlabel("스트레스 지수(0~100 · 높을수록 나쁨)", fontsize=8.5)
    ax2.set_ylabel("거래일 수(로그 눈금)", fontsize=8.5)
    ax2.set_title(f"지수의 분포({s.index[0].year}년 이후 {len(s):,} 거래일) — 오늘은 어디쯤인가", fontsize=9.5)
    ax2.grid(alpha=0.25)
    for sp in ("top", "right"):
        ax2.spines[sp].set_visible(False)
    return _save(fig, path)


# ── ⑤ 34지표 롤리팝 ──────────────────────────────────────────────────────────
def chart_indicators(meta, st, path):
    axes, ko = meta["axes"], meta["axis_ko"]
    col = {a: PALETTE[i % len(PALETTE)] for i, a in enumerate(axes)}
    rows = []
    for a in axes:
        g = st[st.axis == a].sort_values("ecdf_pct", ascending=False)
        rows.extend(g.to_dict("records"))
    n = len(rows)
    fig, ax = plt.subplots(figsize=(W, 6.0), dpi=DPI)
    y = np.arange(n)
    for i, r in enumerate(rows):
        c = col[r["axis"]]
        p, p20 = 100 * r["ecdf_pct"], 100 * r["ecdf_pct_20td_ago"]
        ax.hlines(y[i], 0, p, color=c, lw=1.6, alpha=0.9)
        ax.plot([p], [y[i]], marker="o", ms=6.5, color=c, zorder=4)
        if p20 == p20:
            ax.plot([p20], [y[i]], marker="o", ms=5, mfc="white", mec=c, mew=1.1, zorder=3)
        # 숫자는 눈금 밖 고정 열(x=103)에 — 점 · 20일 전 ○ 와 절대 겹치지 않는다(도훈 11-06 "끝 점이랑 숫자 겹침")
        ax.text(103, y[i], f"{p:.0f}", va="center", ha="left", fontsize=7.8, color="#222222", fontweight="bold")
        if p20 == p20:
            ax.text(109.5, y[i], f"{p20:.0f}", va="center", ha="left", fontsize=7.0, color="#888888")
    bounds = np.cumsum([int((st.axis == a).sum()) for a in axes])
    for b in bounds[:-1]:
        ax.axhline(b - 0.5, color="#dddddd", lw=0.7)
    ax.axvline(80, color="#ef6c00", lw=0.8, ls="--")
    ax.axvline(90, color="#c62828", lw=0.8, ls="--")
    ax.axvline(100.5, color="#bbbbbb", lw=0.6)
    ax.text(80, -1.1, "80", color="#ef6c00", fontsize=7.5, ha="center")
    ax.text(90, -1.1, "90", color="#c62828", fontsize=7.5, ha="center")
    ax.text(103, -1.1, "오늘", fontsize=7.2, ha="left", color="#222222")
    ax.text(109.5, -1.1, "20일 전", fontsize=7.0, ha="left", color="#888888")
    ax.set_yticks(y)
    ax.set_yticklabels([T(f"[{SHORT[r['axis']]}] {r['name']}") for r in rows], fontsize=7.8)
    ax.set_ylim(n - 0.4, -1.8)
    ax.set_xlim(0, 118)
    ax.set_xticks(range(0, 101, 20))
    ax.tick_params(axis="x", labelsize=8)
    ax.set_xlabel(T("심각도(0~100 · 높을수록 나쁨) — ● 오늘 · ○ 20거래일 전 · 점선 80 나쁨 / 90 매우 나쁨"), fontsize=8.5)
    ax.grid(axis="x", alpha=0.25)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.set_title(T("34개 세부 지표의 심각도 — 무엇이 나쁜가(분야별 묶음 · 분야 안은 나쁜 순)"), fontsize=9.5, loc="left")
    return _save(fig, path)


# ── ⑥ 최근 18개월 ────────────────────────────────────────────────────────────
def chart_recent(meta, d, eps, bm, path, months=18):
    axes, ko = meta["axes"], meta["axis_ko"]
    col = {a: PALETTE[i % len(PALETTE)] for i, a in enumerate(axes)}
    last = d.index[-1]
    z0 = last - pd.DateOffset(months=months)
    dz = d[d.index >= z0]
    C = dz[[f"c_{a}" for a in axes]].clip(lower=0)
    fig, ax = plt.subplots(2, 1, figsize=(W, 4.7), dpi=DPI, sharex=True, gridspec_kw={"height_ratios": [2.3, 1.1], "hspace": 0.08})
    shade(ax[0], eps, z0, last)
    ax[0].stackplot(C.index, [C[f"c_{a}"] for a in axes], labels=[ko[a] for a in axes], colors=[col[a] for a in axes], alpha=0.9, lw=0)
    ax[0].plot(dz.index, dz["score"], color="black", lw=0.9, label="지수")
    ax[0].set_ylim(0, max(10.0, float(dz["score"].max()) * 1.12))
    ax[0].legend(loc="upper left", ncol=4, frameon=False, fontsize=7.3)
    ax[0].set_ylabel("지수(분야별 몫을 쌓음)")
    ax[0].set_title(T(f"최근 {months}개월 — 지수와 분야별 몫(회색 = 코스피200 이 고점 대비 20% 넘게 빠진 구간 · 점선 = -20% 도달일)"), fontsize=9.5, loc="left")
    ax[0].grid(alpha=0.25)
    bz = bm[bm.index >= z0]
    shade(ax[1], eps, z0, last)
    ax[1].plot(bz.index, bz, color="#1f4e79", lw=1.0)
    ax[1].set_ylabel("KOSPI200")
    ax[1].grid(alpha=0.25)
    ax[1].xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    ax[1].xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    for a in ax:
        for s in ("top", "right"):
            a.spines[s].set_visible(False)
    return _save(fig, path)


# ── ⑦ 전 기간 ────────────────────────────────────────────────────────────────
def chart_history(meta, d, eps, path):
    lo, hi = d.index[0], d.index[-1]
    fig, ax = plt.subplots(2, 1, figsize=(W, 4.3), dpi=DPI, sharex=True, gridspec_kw={"height_ratios": [2.6, 1.1], "hspace": 0.08})
    shade(ax[0], eps, lo, hi)
    ax[0].plot(d.index, d["score"], color="#1f4e79", lw=1.0, label="스트레스 지수")
    p80 = d["score"].expanding(min_periods=250).quantile(0.80)
    ax[0].plot(d.index, p80, color="#555555", lw=0.7, ls="--", label="그때까지의 과거 80% 선")
    ax[0].plot([hi], [d["score"].iloc[-1]], marker="o", color="#c62828", ms=6, zorder=5)
    ax[0].annotate(f"오늘 {d['score'].iloc[-1]:.1f}", (hi, d["score"].iloc[-1]), xytext=(-6, 10), textcoords="offset points", ha="right", fontsize=8.5, color="#c62828")
    ax[0].set_ylim(0, float(d["score"].max()) * 1.1)
    ax[0].legend(loc="upper left", frameon=False)
    ax[0].set_ylabel("지수")
    ax[0].set_title(T(f"{lo.date()} ~ {hi.date()} — 회색 = 코스피200 이 고점 대비 20% 넘게 빠진 구간(고점→저점)"), fontsize=9.5, loc="left")
    ax[0].grid(alpha=0.25)
    shade(ax[1], eps, lo, hi)
    ax[1].plot(d.index, d["vkospi"], color="#444444", lw=0.8, label="V-KOSPI200(비교)")
    ax[1].set_ylabel("V-KOSPI")
    ax[1].legend(loc="upper left", frameon=False)
    ax[1].grid(alpha=0.25)
    ax[1].xaxis.set_major_locator(mdates.YearLocator(2))
    ax[1].xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
    for a in ax:
        for s in ("top", "right"):
            a.spines[s].set_visible(False)
    return _save(fig, path)


def make_all(meta, d, st, eps, bm, folder, ns):
    set_font()
    lt = meta["latest"]
    t20 = pd.Timestamp(lt["date_20td_ago"])
    pct_20d = float(d.loc[t20, "score_pct"]) if t20 in d.index else float("nan")
    out = {}
    out["gauge"] = chart_gauge(lt, ns, d, eps, pct_20d, f"{folder}/d1_gauge.png")
    out["contrib"] = chart_contrib(meta, lt, f"{folder}/d2_axis_contrib.png")
    out["heatmap"] = chart_heatmap(meta, d, f"{folder}/d3_heatmap_65d.png")
    out["radar"] = chart_radar_hist(meta, d, lt, f"{folder}/d4_radar_hist.png")
    out["indicators"] = chart_indicators(meta, st, f"{folder}/d5_indicators.png")
    out["recent"] = chart_recent(meta, d, eps, bm, f"{folder}/d6_recent_18m.png")
    out["history"] = chart_history(meta, d, eps, f"{folder}/d7_history.png")
    return out
