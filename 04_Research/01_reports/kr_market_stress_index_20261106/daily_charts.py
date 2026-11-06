#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""일보용 차트 7종 — A4 세로 본문 폭(약 188mm = 7.4in)에 1:1 로 들어가도록 그린다(글자 9pt 안팎 · 테두리 밖 잘림 없음).
① 게이지(점수 0~100 눈금 + 단계 띠 + 과거 위기 정점 기준점) ② 축별 기여 막대 + 백분위 칩 ③ 최근 65거래일 축 백분위 히트맵 ④ 레이더(오늘 · 20일 전 · 2008 정점) + 점수 분포
⑤ 34지표 롤리팝 ⑥ 최근 18개월 기여 누적 + KOSPI200 ⑦ 전 기간 + LT 위기 음영 + V-KOSPI.
점수 = 10·√(CISS 원값)(make_daily_report.derive_level — d["level"] · d["cl_<축>"] · lt["level"] · lt["contrib_level"] · meta["levels"] · meta["ref_marks"]). 백분위(심각도)는 원값과 같다.
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


TARGET_W_PX = int(round(W * DPI))     # 본문 폭 188mm 에 1:1 로 놓이는 픽셀 폭


def _save(fig, path):
    """저장 뒤 폭을 본문 폭으로 맞춘다 — bbox tight 는 제목 · 라벨이 그림 밖으로 나가면 PNG 가 넓어지고, PDF 가 width:100% 로 줄여
    글자가 차트마다 다른 크기로 보인다(도훈 11-06 "18개월 차트 작아졌어" — 긴 제목이 8.06in 으로 밀어 0.92 배 축소). 좁으면 흰 여백으로 채우고,
    넓으면 경고한다(제목을 두 줄로 줄이는 것이 수리 — 잘라내지 않는다)."""
    fig.savefig(path, dpi=DPI, bbox_inches="tight", pad_inches=0.12, facecolor="white")
    plt.close(fig)
    from PIL import Image
    im = Image.open(path)
    w, h = im.size
    if w < TARGET_W_PX:
        canvas = Image.new("RGB", (TARGET_W_PX, h), "white")
        canvas.paste(im.convert("RGB"), ((TARGET_W_PX - w) // 2, 0))
        canvas.save(path, dpi=(DPI, DPI))
    elif w > TARGET_W_PX + 12:
        print(f"[charts] ★{os.path.basename(path)} 폭 {w / DPI:.2f}in > {W}in — 제목·라벨이 그림 밖으로 넘쳐 PDF 에서 {TARGET_W_PX / w:.2f}배로 줄어든다", flush=True)
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


def _merge_close(items, tol):
    """x 가 tol 안쪽인 표식은 한 라벨로 — items = [(x, text, color, size, bold)] (x 순 정렬 뒤)."""
    out = []
    for it in sorted(items, key=lambda t: t[0]):
        if out and abs(out[-1][0] - it[0]) < tol:
            x0, t0, c0, s0, b0 = out[-1]
            out[-1] = ((x0 + it[0]) / 2, f"{t0.rsplit(' ', 1)[0]} · {it[1]}", c0, max(s0, it[3]), b0 or it[4])
        else:
            out.append(it)
    return out


def _place_labels(ax, items, y0, dy, max_rows=3):
    """가까운 라벨은 다음 단으로 내려(올려) 겹치지 않게 — items 순서가 우선순위(첫 항목이 첫 단을 먼저 차지). dy<0 = 아래로."""
    occupied = [[] for _ in range(max_rows)]
    for x, text, col, size, bold in items:
        w = 1.45 * len(text) * size / 7.6            # 라벨 폭(눈금 단위 어림 — 7.6pt 글자 ≈ 1.45)
        if x >= 86:
            lo, hi, ha, xt = x + 1.5 - w, x + 1.5, "right", x + 1.5
        elif x <= 14:
            lo, hi, ha, xt = x - 1.5, x - 1.5 + w, "left", x - 1.5
        else:
            lo, hi, ha, xt = x - w / 2, x + w / 2, "center", x
        row = next((k for k in range(max_rows) if all(hi + 1 < a or lo - 1 > b for a, b in occupied[k])), max_rows - 1)
        occupied[row].append((lo, hi))
        ax.text(xt, y0 + dy * row, text, ha=ha, va="top" if dy < 0 else "bottom", fontsize=size, color=col, fontweight="bold" if bold else "normal")


# ── ① 게이지 ──────────────────────────────────────────────────────────────────
def chart_gauge(meta, lt, ns, d, eps, path, days=250):
    """위 = 점수 눈금 0~100(단계 띠 · 오늘 ▼ · 전일 · 20일 전 · 60일 전 위 · 과거 위기 정점 · 평상시 아래) · 아래 = 최근 1년 점수의 길(단계 띠 · 위기 기준선 · 급락 구간 음영)."""
    lv = meta["levels"]
    warn, risk = lv["warn"], lv["risk"]
    today = lt["level"]
    top_pct = max(1, round(100 - 100 * lt["score_pct"]))
    fig = plt.figure(figsize=(W, 4.45), dpi=DPI)
    ax = fig.add_axes([0.05, 0.60, 0.90, 0.30])     # 오른쪽 0.05 = '100 / 모든 분야 최악' 눈금 글자 자리(그림 밖으로 나가면 PDF 에서 축소)
    for lo, hi, name in ((0, warn, "정상"), (warn, risk, "주의"), (risk, 100, "위험")):
        ax.barh(0, hi - lo, left=lo, height=0.5, color=TIER_FILL[name], edgecolor=TIER_EDGE[name], lw=0.8)
        if hi - lo > 6:
            ax.text((lo + hi) / 2, 0, name, ha="center", va="center", fontsize=9, color=TIER_EDGE[name], fontweight="bold")
    # 위쪽 = 오늘 ▼ 과 최근 표식(전일 · 20거래일 전 · 60거래일 전) — 오늘 라벨이 첫 단을 먼저 차지
    ax.plot([today], [0.40], marker="v", ms=11, color="#111111", zorder=6, clip_on=False)
    marks = [(today, f"오늘 {today:.0f}", "#111111", 10.5, True)]
    recent = []
    if len(d) > 1 and d["level"].iloc[-2] == d["level"].iloc[-2]:
        recent.append((float(d["level"].iloc[-2]), "전일", "#333333", "o", 5))
    if lt["level_20td_ago"] == lt["level_20td_ago"]:
        recent.append((lt["level_20td_ago"], "20거래일 전", "#555555", "^", 7))
    if lt["level_60td_ago"] == lt["level_60td_ago"]:
        recent.append((lt["level_60td_ago"], "60거래일 전", "#888888", "s", 6))
    for x, lab, col, mk, ms in recent:
        ax.plot([x], [0.40], marker=mk, ms=ms, color=col, zorder=5, clip_on=False)
    marks += _merge_close([(x, f"{lab} {x:.0f}", col, 7.6, False) for x, lab, col, _, _ in recent], 1.0)
    _place_labels(ax, marks, 0.62, 0.36)
    # 아래쪽 = 눈금의 기준점(평상시 · 과거 위기 정점) — 띠 위에 세로 눈금, 라벨은 아래 단
    refs = meta["ref_marks"]
    for r in refs:
        ax.plot([r["level"], r["level"]], [-0.25, -0.50], color="#444444" if r["kind"] == "crisis" else "#2e7d32", lw=1.0, zorder=4)
    ref_items = _merge_close([(r["level"], f"{r['short']} {r['level']:.0f}", "#333333" if r["kind"] == "crisis" else "#2e7d32", 7.6, False) for r in refs], 1.5)
    _place_labels(ax, ref_items, -0.56, -0.34)
    ax.set_xlim(-1, 101)
    ax.set_ylim(-1.62, 1.55)
    ax.set_yticks([])
    ax.set_xticks(range(0, 101, 10))
    ax.set_xticklabels(["0\n역대 가장 평온"] + [str(x) for x in range(10, 100, 10)] + ["100\n모든 분야 최악\n· 한 방향"])
    ax.tick_params(axis="x", labelsize=7.3, length=2, pad=1)
    for sp in ("top", "right", "left"):
        ax.spines[sp].set_visible(False)
    ax.set_title(T(f"오늘의 스트레스 점수 {today:.0f} / 100 — 2006년 이후 거래일 중 나쁜 순 상위 {top_pct}%\n주의 {warn:.0f}점 이상 · 위험 {risk:.0f}점 이상 · 높을수록 나쁨"),
                 fontsize=9.5, loc="left", pad=16)
    # ── 아래: 최근 1년 점수의 길 ──
    ax2 = fig.add_axes([0.08, 0.07, 0.87, 0.40])
    dz = d.tail(days)
    y = dz["level"]
    for lo, hi, name in ((0, warn, "정상"), (warn, risk, "주의"), (risk, 100, "위험")):
        ax2.axhspan(lo, hi, color=TIER_FILL[name], alpha=0.55, lw=0, zorder=0)
    shade(ax2, eps, dz.index[0], dz.index[-1])
    for r in _merge_close([(r["level"], r["short"], "#555555", 7.0, False) for r in refs if r["kind"] == "crisis"], 1.5):
        ax2.axhline(r[0], color="#777777", lw=0.7, ls=":", zorder=1)
        ax2.text(dz.index[0], r[0] + 1.0, f"{r[1]} {r[0]:.0f}", fontsize=6.8, color="#555555", va="bottom", ha="left", zorder=4)
    ax2.plot(dz.index, y, color="#1f4e79", lw=1.3, zorder=3)
    ax2.fill_between(dz.index, 0, y, color="#1f4e79", alpha=0.08, zorder=2)
    ax2.plot([dz.index[-1]], [today], marker="o", ms=6, color="#c62828", zorder=5)
    ax2.annotate(f"{today:.0f}", (dz.index[-1], today), xytext=(6, 0), textcoords="offset points", va="center", fontsize=8.5, color="#c62828", fontweight="bold")
    ax2.set_ylim(0, 100)
    ax2.set_yticks([0, 20, 40, 60, 80, 100])
    ax2.set_ylabel("스트레스 점수(높을수록 나쁨)", fontsize=8)
    ax2.xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    ax2.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    ax2.tick_params(labelsize=7.5)
    ax2.grid(alpha=0.25)
    for sp in ("top", "right"):
        ax2.spines[sp].set_visible(False)
    ax2.set_title(T(f"최근 {days}거래일의 점수 — 어떤 길을 밟아 지금에 왔나(점선 = 과거 위기의 정점 · 회색 = 코스피200 이 고점 대비 20% 넘게 빠진 구간)"), fontsize=8.8, loc="left")
    return _save(fig, path)


# ── ② 축별 기여 + 백분위 칩 ───────────────────────────────────────────────────
def chart_contrib(meta, lt, path):
    axes, ko = meta["axes"], meta["axis_ko"]
    col = {a: PALETTE[i % len(PALETTE)] for i, a in enumerate(axes)}
    order = sorted(axes, key=lambda a: -lt["contrib_level"][a])
    now = np.array([lt["contrib_level"][a] for a in order])
    prev = np.array([lt["contrib_level_20td_ago"][a] for a in order])
    n = len(order)
    fig = plt.figure(figsize=(W, 4.4), dpi=DPI)      # 4.4in = 게이지 쪽 남는 자리(약 140mm)에 들어가는 높이
    ax = fig.add_axes([0.21, 0.12, 0.56, 0.74])      # 위 0.14 = 두 줄 제목 자리
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
    ax.set_xlabel(T(f"분야별 기여도(점) — 진한 막대 = 오늘(합 {lt['level']:.0f}) · 연한 막대 = 20거래일 전(합 {lt['level_20td_ago']:.0f})"), fontsize=8.5)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    # 오른쪽 칩 — 축 백분위
    ax2 = fig.add_axes([0.80, 0.12, 0.18, 0.74], sharey=ax)
    ax2.axis("off")
    ax2.set_xlim(0, 1)
    ax2.text(0.5, -0.75, "심각도", ha="center", va="center", fontsize=8.5, fontweight="bold")
    for i, a in enumerate(order):
        p = lt["axis_pct"][a]
        c = pct_color(p)
        ax2.add_patch(Rectangle((0.08, y[i] - 0.33), 0.84, 0.66, facecolor=c, edgecolor="none", alpha=0.9))
        ax2.text(0.5, y[i], f"{100 * p:.0f}", ha="center", va="center", fontsize=9, color="white", fontweight="bold")
    fig.suptitle(T(f"어느 분야에서 온 스트레스인가 — 점수 {lt['level']:.0f}의 분야별 기여도(진한 막대 = 오늘 · 연한 막대 = 20거래일 전)\n"
                   "오른쪽 칩 = 그 분야의 심각도(높을수록 나쁨 · 빨강 90 이상 · 주황 80 이상 · 노랑 60 이상 · 초록 그 아래)"),
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
    ax.set_yticklabels(["종합(역대 순위)"] + [ko[a] for a in axes], fontsize=8.5)
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
    ax.set_title(T("12개 분야의 심각도 — 바깥일수록 나쁨\n(모양이 위기의 종류를 보여 줍니다)"), fontsize=9.5, pad=12)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.14), ncol=1, frameon=False, fontsize=7.8)
    # 역사 분포(점수 눈금) + 과거 위기 정점
    ax2 = fig.add_axes([0.58, 0.16, 0.40, 0.70])
    s = d["level"].dropna()
    bins = np.arange(0, float(np.ceil(s.max() / 2.5) * 2.5) + 2.5, 2.5)
    ax2.hist(s, bins=bins, color="#9fb3c8", edgecolor="white", lw=0.4)
    ax2.set_yscale("log")
    ax2.set_xlim(0, 100)
    ax2.axvline(lt["level"], color="#c62828", lw=2)
    ax2.text(lt["level"] - 1.2, ax2.get_ylim()[1] * 0.55, f"오늘 {lt['level']:.0f}\n상위 {max(1, round(100 - 100 * lt['score_pct']))}%", color="#c62828", fontsize=8.5, va="top", ha="right")
    for q, lab in ((0.8, "80%"), (0.9, "90%"), (0.95, "95%")):
        x = float(s.quantile(q))
        ax2.axvline(x, color="#777777", lw=0.7, ls=":")
        ax2.text(x, ax2.get_ylim()[0] * 1.4, lab, fontsize=7, color="#555555", ha="center")
    ymax = ax2.get_ylim()[1]
    for r in _merge_close([(r["level"], r["short"], "#555555", 6.8, False) for r in meta["ref_marks"] if r["kind"] == "crisis"], 1.5):
        ax2.axvline(r[0], color="#c0504d", lw=0.7, ls="--")
        ax2.text(r[0] - 1.0, ymax * 0.9, T(f"{r[1]} {r[0]:.0f}"), fontsize=6.6, color="#8b2f2c", ha="right", va="top", rotation=90)
    ax2.set_xlabel("스트레스 점수(0~100 · 높을수록 나쁨)", fontsize=8.5)
    ax2.set_ylabel("거래일 수(로그 눈금)", fontsize=8.5)
    ax2.set_title(T(f"점수의 분포({s.index[0].year}년 이후 {len(s):,} 거래일) — 오늘은 어디쯤인가"), fontsize=9.5)
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
    fig.subplots_adjust(left=0.40, right=0.985, top=0.935, bottom=0.065)   # 긴 지표 이름이 그림 안에 들어오게(밖으로 나가면 PNG 폭이 늘어 PDF 에서 축소)
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
    ax.set_xlabel(T("심각도(0~100 · 높을수록 나쁨) — ● 오늘 · ○ 20거래일 전"), fontsize=8.5)
    ax.grid(axis="x", alpha=0.25)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.set_title(T("34개 세부 지표의 심각도 — 무엇이 나쁜가\n분야별 묶음 · 나쁜 순 · 점선 80 나쁨 / 90 매우 나쁨"), fontsize=9.5, loc="left")
    return _save(fig, path)


# ── ⑥ 최근 18개월 ────────────────────────────────────────────────────────────
def chart_recent(meta, d, eps, bm, path, months=18):
    axes, ko = meta["axes"], meta["axis_ko"]
    col = {a: PALETTE[i % len(PALETTE)] for i, a in enumerate(axes)}
    last = d.index[-1]
    z0 = last - pd.DateOffset(months=months)
    dz = d[d.index >= z0]
    C = dz[[f"cl_{a}" for a in axes]].clip(lower=0)
    fig, ax = plt.subplots(2, 1, figsize=(W, 4.7), dpi=DPI, sharex=True, gridspec_kw={"height_ratios": [2.3, 1.1], "hspace": 0.08})
    fig.subplots_adjust(left=0.085, right=0.955, top=0.895, bottom=0.07)   # 두 줄 제목 자리 + 좌우 여백(맨 오른쪽 날짜 눈금 글자까지)을 그림 안에
    shade(ax[0], eps, z0, last)
    ax[0].stackplot(C.index, [C[f"cl_{a}"] for a in axes], labels=[ko[a] for a in axes], colors=[col[a] for a in axes], alpha=0.9, lw=0)
    ax[0].plot(dz.index, dz["level"], color="black", lw=0.9, label="점수")
    top = max(70.0, float(dz["level"].max()) * 1.18)
    ax[0].set_ylim(0, top)
    for r in _merge_close([(r["level"], r["short"], "#555555", 7.0, False) for r in meta["ref_marks"] if r["kind"] == "crisis"], 1.5):
        if r[0] < top - 2:
            ax[0].axhline(r[0], color="#777777", lw=0.7, ls=":", zorder=1)
            ax[0].text(last, r[0] + 0.8, T(f"{r[1]} 정점 {r[0]:.0f}"), fontsize=6.8, color="#555555", ha="right", va="bottom")
    ax[0].legend(loc="upper left", ncol=4, frameon=False, fontsize=7.3)
    ax[0].set_ylabel("스트레스 점수")
    ax[0].set_title(T(f"최근 {months}개월 — 스트레스 점수(검은 선)와 분야별 기여도(쌓은 색 띠)\n회색 = 코스피200 이 고점 대비 20% 넘게 빠진 구간 · 점선 = -20% 도달일"), fontsize=9.5, loc="left")
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
    fig.subplots_adjust(left=0.075, right=0.985, top=0.9, bottom=0.075)
    shade(ax[0], eps, lo, hi)
    ax[0].plot(d.index, d["level"], color="#1f4e79", lw=1.0, label="스트레스 점수")
    p80 = d["level"].expanding(min_periods=250).quantile(0.80)
    ax[0].plot(d.index, p80, color="#555555", lw=0.7, ls="--", label="그때까지의 과거 80% 선")
    ax[0].plot([hi], [d["level"].iloc[-1]], marker="o", color="#c62828", ms=6, zorder=5)
    ax[0].annotate(f"오늘 {d['level'].iloc[-1]:.0f}", (hi, d["level"].iloc[-1]), xytext=(-6, 10), textcoords="offset points", ha="right", fontsize=8.5, color="#c62828")
    prev_t = None
    for r in sorted([r for r in meta["ref_marks"] if r["kind"] == "crisis"], key=lambda r: r["date"]):      # 위기 정점 라벨 — 가까운 시기는 좌우로 나눠 겹침 회피
        t = pd.Timestamp(r["date"])
        right = prev_t is not None and abs((t - prev_t).days) < 3 * 365
        ax[0].annotate(T(f"{r['short']} {r['level']:.0f}"), (t, r["level"]), xytext=(6 if right else -6, 4), textcoords="offset points",
                       ha="left" if right else "right", fontsize=7.2, color="#333333")
        prev_t = t
    ax[0].set_ylim(0, 100)
    ax[0].legend(loc="upper center", frameon=False, ncol=2)
    ax[0].set_ylabel("점수")
    ax[0].set_title(T(f"{lo.date()} ~ {hi.date()} 스트레스 점수 — 회색 = 코스피200 이 고점 대비 20% 넘게 빠진 구간(고점→저점)"), fontsize=9.5, loc="left")
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
    out = {}
    out["gauge"] = chart_gauge(meta, lt, ns, d, eps, f"{folder}/d1_gauge.png")
    out["contrib"] = chart_contrib(meta, lt, f"{folder}/d2_axis_contrib.png")
    out["heatmap"] = chart_heatmap(meta, d, f"{folder}/d3_heatmap_65d.png")
    out["radar"] = chart_radar_hist(meta, d, lt, f"{folder}/d4_radar_hist.png")
    out["indicators"] = chart_indicators(meta, st, f"{folder}/d5_indicators.png")
    out["recent"] = chart_recent(meta, d, eps, bm, f"{folder}/d6_recent_18m.png")
    out["history"] = chart_history(meta, d, eps, f"{folder}/d7_history.png")
    return out
