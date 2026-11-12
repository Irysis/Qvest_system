"""32_challenger_recal.py — 기준 모형 예측 분포의 베타 변환 재보정(온라인 · PIT 안전).

  F̃_t(y) = G_t(F_t(y)),  G_t = Beta(a_t, b_t) CDF
  (a_t, b_t) = 예측일 t 이전에 결과가 실현된 기준 모형 PIT(예측일 s ≤ t−1)로 최대우도 추정
  창 = 직전 W 개(--window · 0 이면 확장 창) · W 개 미만이면 G = 항등(재보정 없음)
근거: 베타 변환 선형 풀(BLP)의 단일 모형 경우 — Gneiting & Ranjan (2013) Electron. J. Statist. 7:1747, doi:10.1214/13-EJS823
최소 표본 250 = 바젤 역검정 창(BCBS 1996 'Supervisory framework for the use of backtesting').
밀도: f̃(y) = g(F(y))·f(y) → LS = log g(PIT) + LS_base.  분위: F^-1(G^-1(u)).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import optimize as sp_opt
from scipy import stats as sp_stats

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

MIN_N = 250


def beta_mle(u):
    u = np.clip(np.asarray(u, float), 1e-6, 1 - 1e-6)
    def nll(th):
        a, b = np.exp(th)
        return -float(np.sum(sp_stats.beta.logpdf(u, a, b)))
    res = sp_opt.minimize(nll, np.zeros(2), method="L-BFGS-B", bounds=[(-3, 3), (-3, 3)])
    a, b = np.exp(res.x)
    return float(a), float(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=str, default="P3")
    ap.add_argument("--name", type=str, required=True)
    ap.add_argument("--window", type=int, default=0)
    ap.add_argument("--until", type=str, default="2099-12-31")
    args = ap.parse_args()
    sc = pd.read_parquet(C.OUT / f"sc_{args.base}.parquet")
    sc["Date"] = pd.to_datetime(sc["Date"])
    sc = sc[sc["Date"] <= pd.Timestamp(args.until)].sort_values("Date").reset_index(drop=True)
    pit = sc["pit"].values
    N = len(sc)
    A = np.ones(N); B = np.ones(N)
    last = None
    for i in range(N):
        lo = 0 if args.window == 0 else max(0, i - args.window)
        past = pit[lo:i]  # 예측일 s ≤ t−1 의 PIT — 결과일 s+1 ≤ t 라 t 에 이미 실현
        if len(past) < MIN_N:
            continue
        if last is None or i % 5 == 0:  # 5거래일마다 재추정(주간) — 하루 1개 표본 증가는 추정치를 거의 안 바꾼다
            last = beta_mle(past)
        A[i], B[i] = last
    mu, sg, nu, lm, y = (sc[c].values.astype(float) for c in ("mu", "sigma", "nu", "lam", "y"))
    # 재보정 분위 = F^-1(G^-1(u))
    Ginv = np.vstack([sp_stats.beta.ppf(C.U_GRID, A[i], B[i]) for i in range(N)])
    Ginv = np.clip(Ginv, 1e-9, 1 - 1e-9)
    Q = C.hansen_ppf(Ginv, mu, sg, nu, lm)
    lsb = C.hansen_logpdf(y, mu, sg, nu, lm)
    pb = np.clip(C.hansen_cdf(y, mu, sg, nu, lm), 1e-12, 1 - 1e-12)
    ls = lsb + sp_stats.beta.logpdf(pb, A, B)
    d = S.score_quantile_grid(sc["Date"].values, y, Q, logpdf=ls, extra={"beta_a": A, "beta_b": B})
    # 사건 확률 · PIT 는 정확식으로 덮어쓴다(격자 보간 대신)
    d["pit"] = sp_stats.beta.cdf(pb, A, B)
    for c in S.EVENT_THRESHOLDS:
        pc = C.hansen_cdf(np.full(N, c), mu, sg, nu, lm)
        d[f"p_le_{int(-c)}"] = sp_stats.beta.cdf(np.clip(pc, 1e-12, 1 - 1e-12), A, B)
    for a in S.LEVELS_VAR:
        ga = np.clip(sp_stats.beta.ppf(a, A, B), 1e-9, 1 - 1e-9)  # (N,)
        d[f"var_{int(a*1000):03d}"] = C.hansen_ppf(ga[:, None], mu, sg, nu, lm)[:, 0]  # 행마다 자기 분위 수준
    # ES 5% = (1/0.05)∫_0^0.05 F^-1(G^-1(u)) du
    uu = (np.arange(1, 401) - 0.5) / 400 * 0.05
    Gi = np.vstack([np.clip(sp_stats.beta.ppf(uu, A[i], B[i]), 1e-9, 1 - 1e-9) for i in range(N)])
    d["es_050"] = C.hansen_ppf(Gi, mu, sg, nu, lm).mean(axis=1)
    d = S._finish(d)
    d.to_parquet(C.OUT / f"sc_{args.name}.parquet")
    C.write_json(C.OUT / f"sc_{args.name}.meta.json", {"name": args.name, "base": args.base, "window": args.window,
                 "min_n": MIN_N, "until": args.until, "beta_a_last": float(A[-1]), "beta_b_last": float(B[-1]),
                 "active_frac": float(np.mean((A != 1) | (B != 1))), "data_vintage": C.data_vintage()})
    print(f"[{args.name}] n={N} active={np.mean((A != 1) | (B != 1)):.2f} last a={A[-1]:.3f} b={B[-1]:.3f}")


if __name__ == "__main__":
    main()
