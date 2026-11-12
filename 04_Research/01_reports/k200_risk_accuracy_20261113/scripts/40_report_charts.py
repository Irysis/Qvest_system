"""40_report_charts.py — 보고 차트 5장(현대하모니 M · 폭 1600px 안팎).

  fig1_pit_coverage.png   PIT 히스토그램(기준 vs 최우수 · IS/OOS) + 왼꼬리 보정 곡선(명목 vs 실현 · 이항 95% 띠)
  fig2_score_gain.png     도전 vs P3 점수 개선(ΔLS · ΔCRPS% · ΔtwCRPS% · ΔFZ0% · HAC 95% 구간 · IS/OOS) + 누적 ΔLS 시계열
  fig3_oos_var.png        OOS 일별 수익 vs VaR 1% · 5%(P3 · 최우수) · 위반 표시
  fig4_crisis_zoom.png    LT 위기 구간 확대 — 예측 표준편차 vs 실현 |수익|
  fig5_events.png         다음날 ≤ −3% · ≤ −5% 사건 확률의 보정 곡선(분위 구간) + ROC(OOS)
--segments IS 면 OOS 를 그리지 않는다(설계 단계 미리보기).
"""
from __future__ import annotations

import argparse
import math
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from matplotlib import font_manager
import numpy as np
import pandas as pd
from scipy import stats as sp_stats

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

TAU_D = pd.Timestamp("2022-12-31")
COL = {"P3": "#E45756", "GJR": "#9D755D", "EWMA": "#BAB0AC", "HS500": "#B279A2"}
PAL = ["#4C78A8", "#54A24B", "#F58518", "#72B7B2", "#EECA3B"]


def set_font():
    for d in [os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "Windows", "Fonts"),
              os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts")]:
        p = os.path.join(d, "현대하모니+M.ttf")
        if os.path.exists(p):
            font_manager.fontManager.addfont(p)
            pb = os.path.join(d, "현대하모니+B.ttf")
            if os.path.exists(pb):
                font_manager.fontManager.addfont(pb)
            plt.rcParams["font.family"] = font_manager.FontProperties(fname=p).get_name()
            break
    else:
        plt.rcParams["font.family"] = "Malgun Gothic"
    plt.rcParams.update({"axes.unicode_minus": False, "font.size": 9, "axes.titlesize": 10.5, "axes.labelsize": 9,
                         "xtick.labelsize": 8.5, "ytick.labelsize": 8.5, "legend.fontsize": 8,
                         "axes.spines.top": False, "axes.spines.right": False})


def T(s):
    return str(s).replace("—", "-").replace("–", "-").replace("−", "-")


def load(name, nxt):
    d = pd.read_parquet(C.OUT / f"sc_{name}.parquet"); d["Date"] = pd.to_datetime(d["Date"])
    d["y_date"] = pd.to_datetime(d["Date"].map(nxt))
    d["seg"] = np.where(d["y_date"] <= TAU_D, "IS", "OOS")
    return d.sort_values("Date").reset_index(drop=True)


def hac_ci(diff, lag=None):
    diff = np.asarray(diff, float); diff = diff[np.isfinite(diff)]
    n = len(diff)
    if lag is None:
        lag = int(math.floor(4 * (n / 100) ** (2 / 9)))
    se = math.sqrt(S.nw_lrv(diff, lag) / n)
    return diff.mean(), 1.96 * se


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="P3")
    ap.add_argument("--challengers", required=True)
    ap.add_argument("--labels", default="")
    ap.add_argument("--best", default="")
    ap.add_argument("--segments", default="IS,OOS")
    ap.add_argument("--outdir", default=str(C.CHARTS))
    args = ap.parse_args()
    set_font()
    segs = [s for s in args.segments.split(",") if s]
    ch = [c for c in args.challengers.split(",") if c]
    labels = dict(zip(ch, args.labels.split(","))) if args.labels else {c: c for c in ch}
    labels[args.base] = "P3(운영)"
    best = args.best or ch[0]
    out = Path(args.outdir); out.mkdir(parents=True, exist_ok=True)
    bm = pd.read_parquet(C.BM_PATH); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date").reset_index(drop=True)
    nxt = pd.Series(bm["Date"].shift(-1).values, index=bm["Date"].values)
    D = {m: load(m, nxt) for m in [args.base] + ch}
    common = set.intersection(*[set(v["Date"]) for v in D.values()])
    for m in D:
        D[m] = D[m][D[m]["Date"].isin(common) & D[m]["seg"].isin(segs)].reset_index(drop=True)
    cr = S.lt_crises(bm["Date"], bm["BM_Ret"].fillna(0.0).values)
    lo, hi = D[args.base]["Date"].min(), D[args.base]["Date"].max()
    cr = cr[(cr["trough"] >= lo) & (cr["peak"] <= hi)].reset_index(drop=True)
    colors = {args.base: COL["P3"]}
    for i, c in enumerate(ch):
        colors[c] = PAL[i % len(PAL)]

    # ── fig1 PIT + 꼬리 보정
    fig = plt.figure(figsize=(16, 7.6))
    gs = fig.add_gridspec(2, 4, height_ratios=[1, 1.05], hspace=0.42, wspace=0.28)
    k = 0
    for m in (args.base, best):
        for sg in segs:
            ax = fig.add_subplot(gs[0, k]); k += 1
            d = D[m][D[m]["seg"] == sg]
            n = len(d); e = n / 20
            lo_b, hi_b = sp_stats.binom.ppf([0.025, 0.975], n, 1 / 20)
            ax.bar(np.arange(20) / 20 + 0.025, np.histogram(d["pit"], bins=20, range=(0, 1))[0], width=0.045,
                   color=colors[m], alpha=0.85)
            ax.axhline(e, color="k", lw=0.8); ax.axhspan(lo_b, hi_b, color="k", alpha=0.08)
            chi = S.pit_chi2(d["pit"].values)["p"]; bk = S.berkowitz_ar1(d["pit"].values)["p"]
            ax.set_title(T(f"{labels[m]} · {sg} PIT (n={n})\nχ² p={chi:.3f} · Berkowitz p={bk:.3f}"))
            ax.set_xlabel("PIT")
    lv = np.array([0.005, 0.01, 0.025, 0.05, 0.10, 0.25])
    for j, sg in enumerate(segs):
        ax = fig.add_subplot(gs[1, 2 * j:2 * j + 2])
        n = len(D[args.base][D[args.base]["seg"] == sg])
        band = np.array([sp_stats.binom.ppf([0.025, 0.975], n, a) / n for a in lv])
        ax.fill_between(lv * 100, band[:, 0] * 100, band[:, 1] * 100, color="k", alpha=0.08, label="이항 95% 띠")
        ax.plot(lv * 100, lv * 100, color="k", lw=0.8, ls="--")
        for m in [args.base] + ch:
            d = D[m][D[m]["seg"] == sg]
            emp = [np.mean(d["pit"].values <= a) * 100 for a in lv]
            ax.plot(lv * 100, emp, marker="o", ms=4, color=colors[m], label=labels[m], lw=1.6 if m in (args.base, best) else 1.0)
        ax.set_xscale("log"); ax.set_yscale("log")
        ax.set_xticks(lv * 100); ax.set_xticklabels([f"{a*100:g}" for a in lv])
        ax.set_yticks(lv * 100); ax.set_yticklabels([f"{a*100:g}" for a in lv])
        ax.set_xlabel("명목 왼꼬리 확률 (%)"); ax.set_ylabel("실현 빈도 (%)")
        ax.set_title(T(f"{sg} 왼꼬리 보정 — 대각선 위 = 위험 과소평가"))
        ax.legend(loc="upper left", ncol=2)
    fig.suptitle(T("① 예측 분포 보정 — PIT 균등성 · 왼꼬리 분위 적중"), fontsize=12, x=0.01, ha="left")
    fig.savefig(out / "fig1_pit_coverage.png", dpi=110, bbox_inches="tight"); plt.close(fig)

    # ── fig2 점수 개선 + 누적 ΔLS
    fig = plt.figure(figsize=(16, 7.6))
    gs = fig.add_gridspec(2, 4, height_ratios=[1, 1.1], hspace=0.45, wspace=0.32)
    b = D[args.base]
    mets = [("ls", "ΔLS (nats/일 · +가 개선)", 1, False), ("crps", "ΔCRPS (% · −가 개선)", -1, True),
            ("twcrps", "Δ왼꼬리 CRPS (% · −가 개선)", -1, True), ("fz0_050", "ΔFZ0 5% (% · −가 개선)", -1, True)]
    for j, (c, lab, sign, pct) in enumerate(mets):
        ax = fig.add_subplot(gs[0, j])
        w = 0.8 / max(len(segs), 1)
        for si, sg in enumerate(segs):
            bs = b[b["seg"] == sg]
            vals, errs = [], []
            for m in ch:
                d = D[m][D[m]["seg"] == sg]
                diff = d[c].values - bs[c].values
                mu_, ci = hac_ci(diff)
                if pct:
                    den = abs(bs[c].mean()); mu_, ci = mu_ / den * 100, ci / den * 100
                vals.append(mu_); errs.append(ci)
            x = np.arange(len(ch)) + (si - (len(segs) - 1) / 2) * w
            ax.bar(x, vals, width=w * 0.9, yerr=errs, capsize=3, color=[colors[m] for m in ch],
                   alpha=0.55 if sg == "IS" else 0.95, edgecolor="k", lw=0.4, label=sg)
        ax.axhline(0, color="k", lw=0.8)
        ax.set_xticks(np.arange(len(ch))); ax.set_xticklabels([labels[m] for m in ch], rotation=20, ha="right")
        ax.set_title(T(lab))
        if j == 0:
            ax.legend(title="옅음 = IS · 진함 = OOS" if len(segs) > 1 else None)
    ax = fig.add_subplot(gs[1, :])
    for m in ch:
        d = D[m]
        cum = np.cumsum(d["ls"].values - b["ls"].values)
        ax.plot(d["Date"], cum, color=colors[m], lw=1.6, label=labels[m])
    for _, r in cr.iterrows():
        ax.axvspan(r.peak, r.trough, color="#E45756", alpha=0.08)
    if "OOS" in segs:
        ax.axvline(TAU_D, color="k", ls="--", lw=0.9); ax.text(TAU_D, ax.get_ylim()[1], " IS | OOS", va="top", fontsize=8.5)
    ax.axhline(0, color="k", lw=0.6)
    ax.set_title(T("누적 로그 점수 차이 Σ(LS 도전 − LS P3) — 오를수록 도전 모형이 그날 실현을 더 잘 예측 · 붉은 음영 = LT 20/20 위기"))
    ax.legend(loc="upper left"); ax.xaxis.set_major_locator(mdates.YearLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
    fig.suptitle(T("② 점수 개선 — 도전 모형 vs P3 (HAC 95% 구간)"), fontsize=12, x=0.01, ha="left")
    fig.savefig(out / "fig2_score_gain.png", dpi=110, bbox_inches="tight"); plt.close(fig)

    # ── fig3 OOS(또는 마지막 구간) VaR 시계열
    sg = "OOS" if "OOS" in segs else segs[-1]
    fig, axs = plt.subplots(2, 1, figsize=(16, 7.8), sharex=True, gridspec_kw={"hspace": 0.18})
    for ax, (m, lab) in zip(axs, ((args.base, labels[args.base]), (best, labels[best]))):
        d = D[m][D[m]["seg"] == sg]
        ax.bar(d["Date"], d["y"], width=1.0, color="#9E9E9E", alpha=0.7, label="실현 수익(다음날 %)")
        ax.plot(d["Date"], d["var_050"], color=colors[m], lw=1.0, label="VaR 5%")
        ax.plot(d["Date"], d["var_010"], color=colors[m], lw=1.0, ls="--", label="VaR 1%")
        h1 = d[d["hit_010"] == 1]; h5 = d[(d["hit_050"] == 1) & (d["hit_010"] == 0)]
        ax.scatter(h5["Date"], h5["y"], s=14, color="#F58518", zorder=3, label=f"5% 위반 {len(h5) + len(h1)}회")
        ax.scatter(h1["Date"], h1["y"], s=22, color="#B71C1C", marker="v", zorder=4, label=f"1% 위반 {len(h1)}회")
        ax.set_title(T(f"{lab} — {sg} 일별 수익 vs VaR · 5% 위반률 {d['hit_050'].mean():.1%} · 1% 위반률 {d['hit_010'].mean():.1%}"))
        ax.legend(loc="lower left", ncol=5); ax.set_ylabel("%")
    axs[-1].xaxis.set_major_locator(mdates.MonthLocator(bymonth=(1, 4, 7, 10)))
    axs[-1].xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    fig.suptitle(T(f"③ 예측 vs 실현 — {sg} VaR 와 위반"), fontsize=12, x=0.01, ha="left")
    fig.savefig(out / "fig3_oos_var.png", dpi=110, bbox_inches="tight"); plt.close(fig)

    # ── fig4 위기 구간 확대
    crs = cr.copy()
    if len(crs) > 6:
        crs = crs.tail(6)
    nC = len(crs)
    if nC:
        ncol = 3; nrow = int(math.ceil(nC / ncol))
        fig, axs = plt.subplots(nrow, ncol, figsize=(16, 3.8 * nrow), squeeze=False)
        for ax, (_, r) in zip(axs.ravel(), crs.iterrows()):
            a0 = r.peak - pd.Timedelta(days=45); a1 = r.trough + pd.Timedelta(days=30)
            for m in (args.base, best):
                d = D[m][(D[m]["Date"] >= a0) & (D[m]["Date"] <= a1)]
                ax.plot(d["Date"], d["sd_pred"], color=colors[m], lw=1.6, label=f"{labels[m]} 예측 표준편차")
            d = D[args.base][(D[args.base]["Date"] >= a0) & (D[args.base]["Date"] <= a1)]
            ax.scatter(d["Date"], d["y"].abs(), s=8, color="#616161", alpha=0.7, label="실현 |수익|")
            rms = np.sqrt((d["y"] ** 2).rolling(5, min_periods=3).mean())
            ax.plot(d["Date"], rms, color="#212121", lw=0.9, ls=":", label="실현 5일 RMS")
            ax.axvspan(r.peak, r.trough, color="#E45756", alpha=0.08)
            ax.set_title(T(f"고점 {r.peak.date()} → 바닥 {r.trough.date()} · 깊이 {r.depth:.0%}" + (" · 진행" if r.ongoing else "")))
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%y-%m"))
        for ax in axs.ravel()[nC:]:
            ax.set_visible(False)
        axs[0, 0].legend(loc="upper left")
        fig.suptitle(T("④ 위기 구간 확대 — 예측 표준편차(%) vs 실현 · 붉은 음영 = 고점→바닥"), fontsize=12, x=0.01, ha="left")
        fig.tight_layout(); fig.savefig(out / "fig4_crisis_zoom.png", dpi=110, bbox_inches="tight"); plt.close(fig)

    # ── fig5 사건 보정 + ROC
    fig, axs = plt.subplots(1, 4, figsize=(16, 4.4))
    for j, thr in enumerate((-3, -5)):
        ax = axs[2 * j]; ax2 = axs[2 * j + 1]
        for m in (args.base, best):
            d = D[m][D[m]["seg"] == sg]
            p = d[f"p_le_{-thr}"].values; e = (d["y"].values <= thr).astype(int)
            qb = np.unique(np.quantile(p, np.linspace(0, 1, 11)))
            idx = np.clip(np.digitize(p, qb[1:-1]), 0, len(qb) - 2)
            xs = [p[idx == k].mean() * 100 for k in range(len(qb) - 1) if (idx == k).any()]
            ys = [e[idx == k].mean() * 100 for k in range(len(qb) - 1) if (idx == k).any()]
            ax.plot(xs, ys, marker="o", color=colors[m], label=f"{labels[m]} (Brier {np.mean((p - e) ** 2):.4f})")
            o = np.argsort(-p); tp = np.cumsum(e[o]) / max(e.sum(), 1); fp = np.cumsum(1 - e[o]) / max((1 - e).sum(), 1)
            ax2.plot(fp, tp, color=colors[m], label=f"{labels[m]} AUC {S.auc(p, e):.3f}")
        mx = max(ax.get_xlim()[1], ax.get_ylim()[1])
        ax.plot([0, mx], [0, mx], "k--", lw=0.8)
        ax.set_xlabel("예측 확률 (%)"); ax.set_ylabel("실현 빈도 (%)")
        ax.set_title(T(f"{sg} 다음날 ≤ {thr}% — 보정(10분위)")); ax.legend(loc="upper left")
        ax2.plot([0, 1], [0, 1], "k--", lw=0.8); ax2.set_xlabel("거짓 경보율"); ax2.set_ylabel("적중률")
        ax2.set_title(T(f"{sg} 다음날 ≤ {thr}% — ROC (사건 {int((D[args.base][D[args.base]['seg']==sg]['y'] <= thr).sum())}회)"))
        ax2.legend(loc="lower right")
    fig.suptitle(T("⑤ 하락 사건 예측 — 확률 보정과 판별력"), fontsize=12, x=0.01, ha="left")
    fig.tight_layout(); fig.savefig(out / "fig5_events.png", dpi=110, bbox_inches="tight"); plt.close(fig)
    print("[charts] saved to", out)


if __name__ == "__main__":
    main()
