"""21_design_diagnostics_IS.py — 가설 설계용 IS 진단(결과일 ≤ 2022-12-31 만 읽는다 · OOS 비공개).

무엇을 보나(설계 질문):
  ① 분포 층: PIT 모양(과대 · 과소 분산 · 치우침) · ν 경계 쏠림 · μ 의 크기와 σ 와의 관계
  ② 척도 층: 예측 σ vs 실현 |y| (구간별 기울기) · 국면별 점수
  ③ 비교: P3 vs GJR · EWMA · HS500 의 IS 점수
산출: output/design_IS_diag.json · charts/design_IS_*.png
"""
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

TAU_D = pd.Timestamp("2022-12-31")


def is_only(d):
    bm = pd.read_parquet(C.BM_PATH, columns=["Date"])
    dd = pd.to_datetime(bm["Date"]).sort_values().reset_index(drop=True)
    nxt = pd.Series(dd.shift(-1).values, index=dd.values)
    yd = pd.to_datetime(d["Date"].map(nxt))
    return d[(yd <= TAU_D).values].reset_index(drop=True)


def main():
    C.CHARTS.mkdir(parents=True, exist_ok=True)
    p3 = is_only(pd.read_parquet(C.OUT / "sc_P3.parquet"))
    out = {"n_IS": int(len(p3)), "first": str(p3.Date.min().date()), "last": str(p3.Date.max().date())}
    # ① 분포 층
    out["nu_at_lower_bound_frac"] = float((p3.nu < 2.51).mean())
    out["nu_at_upper_bound_frac"] = float((p3.nu > 49.9).mean())
    out["nu_quantiles"] = {str(q): float(p3.nu.quantile(q)) for q in (0.05, 0.25, 0.5, 0.75, 0.95)}
    out["lam_quantiles"] = {str(q): float(p3.lam.quantile(q)) for q in (0.05, 0.25, 0.5, 0.75, 0.95)}
    out["mu_quantiles"] = {str(q): float(p3.mu.quantile(q)) for q in (0.05, 0.25, 0.5, 0.75, 0.95)}
    out["mu_mean"] = float(p3.mu.mean()); out["y_mean"] = float(p3.y.mean())
    out["corr_mu_sigma"] = float(np.corrcoef(p3.mu, p3.sigma)[0, 1])
    out["corr_mu_y"] = float(np.corrcoef(p3.mu, p3.y)[0, 1])
    # 분위회귀 11점 vs Hansen 적합 분위의 차이(적합 잔차)
    qcols = [f"q_{int(round(t*1000)):03d}" for t in C.P_TAUS]
    Qh = C.hansen_ppf(np.array(C.P_TAUS), p3.mu.values, p3.sigma.values, p3.nu.values, p3.lam.values)
    Qr = np.sort(p3[qcols].values, axis=1)
    out["hansen_fit_resid_by_tau"] = {str(t): float(np.mean(Qh[:, i] - Qr[:, i])) for i, t in enumerate(C.P_TAUS)}
    out["qr_empirical_coverage_by_tau"] = {str(t): float(np.mean(p3.y.values <= Qr[:, i])) for i, t in enumerate(C.P_TAUS)}
    # ② 척도 층 — σ 오분위별 실현 표준편차
    p3["sig_q"] = pd.qcut(p3.sigma, 5, labels=False)
    g = p3.groupby("sig_q").agg(sig_pred=("sigma", "mean"), real_sd=("y", "std"), ls=("ls", "mean"),
                                 pit_mean=("pit", "mean"), hit5=("hit_050", "mean"), n=("y", "size"))
    out["by_sigma_quintile"] = g.reset_index().to_dict(orient="records")
    # ③ 비교 점수(IS)
    comp = {}
    for m in ("P3", "GJR", "EWMA", "HS500"):
        f = C.OUT / f"sc_{m}.parquet"
        if not f.exists():
            continue
        d = is_only(pd.read_parquet(f))
        d = d[d.Date.isin(p3.Date)]
        comp[m] = {"n": int(len(d)), "ls": float(d.ls.mean()) if d.ls.notna().any() else None,
                   "crps": float(d.crps.mean()), "twcrps": float(d.twcrps.mean()), "qs_010": float(d.qs_010.mean()),
                   "qs_050": float(d.qs_050.mean()), "fz0_050": float(d.fz0_050.mean()),
                   "hit_050": float(d.hit_050.mean()), "hit_010": float(d.hit_010.mean()),
                   "pit_chi2_p": S.pit_chi2(d.pit.values)["p"], "berk": S.berkowitz_ar1(d.pit.values),
                   "sd_pred": float(d.sd_pred.mean())}
    out["compare_IS"] = comp
    C.write_json(C.OUT / "design_IS_diag.json", out)

    # ── 차트: PIT 히스토그램(IS) 4모형
    fig, axs = plt.subplots(1, 4, figsize=(15, 3.6), sharey=True)
    for ax, m in zip(axs, ("P3", "GJR", "EWMA", "HS500")):
        f = C.OUT / f"sc_{m}.parquet"
        if not f.exists():
            ax.set_visible(False); continue
        d = is_only(pd.read_parquet(f)); d = d[d.Date.isin(p3.Date)]
        ax.hist(d.pit, bins=20, range=(0, 1), color="#4C78A8", edgecolor="white")
        ax.axhline(len(d) / 20, color="#E45756", lw=1.2, ls="--")
        ax.set_title(f"{m} (IS) PIT"); ax.set_xlabel("PIT")
    fig.tight_layout(); fig.savefig(C.CHARTS / "design_IS_pit_hist.png", dpi=120); plt.close(fig)

    # ── 차트: ν · λ · μ 분포(P3, IS)
    fig, axs = plt.subplots(1, 3, figsize=(14, 3.6))
    axs[0].hist(p3.nu, bins=60, color="#72B7B2"); axs[0].set_title("P3 ν (IS)"); axs[0].axvline(2.5, color="k", lw=0.8)
    axs[1].hist(p3.lam, bins=60, color="#F58518"); axs[1].set_title("P3 λ (IS)")
    axs[2].scatter(p3.sigma, p3.mu, s=3, alpha=0.4, color="#54A24B"); axs[2].set_xlabel("σ"); axs[2].set_ylabel("μ")
    axs[2].set_title("P3 μ vs σ (IS)")
    fig.tight_layout(); fig.savefig(C.CHARTS / "design_IS_shape.png", dpi=120); plt.close(fig)
    print(open(C.OUT / "design_IS_diag.json", encoding="utf-8").read()[:6000])


if __name__ == "__main__":
    main()
