"""11_reference_models.py — 업계 표준 비교 모형 3종(1일 분포 예측 · 워크포워드).

  GJR      GJR-GARCH(1,1) + Hansen 비대칭 t 혁신 · MLE · 12년 이동 창 · 21거래일마다 재추정 · 매일 필터
           (Glosten, Jagannathan & Runkle 1993 · Hansen 1994)
  EWMA     RiskMetrics 지수가중 분산 λ = 0.94(J.P. Morgan 1996) + 표준화 잔차에 Hansen t MLE(12년 · 21거래일마다)
  HS500    역사적 시뮬레이션 — 직전 500거래일 수익률의 경험분포(바젤 내부모형 관행 · 밀도 없음 → LS 미산출)
PIT: 예측일 t 의 분산 필터는 r_t(=t 종가)까지 · 모수는 직전 재추정일까지의 창으로만 추정.
표적 y_{t+1} = 100·log(P_{t+1}/P_t) — P3 재현(10)과 같은 날짜 · 같은 표적.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import optimize as sp_opt
from scipy.signal import lfilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

LOOKBACK_YEARS = 12
REFIT_EVERY = 21
EWMA_LAMBDA = 0.94
HS_WINDOW = 500


def load_returns():
    bm = pd.read_parquet(C.BM_PATH)
    bm["Date"] = pd.to_datetime(bm["Date"])
    bm = bm.sort_values("Date").reset_index(drop=True)
    bm["r"] = np.log(bm["BM_Close"]).diff() * 100.0
    bm = bm[bm["Date"] >= "2001-01-03"].dropna(subset=["r"]).reset_index(drop=True)
    return bm[["Date", "r"]]


# ─── GJR-GARCH(1,1)-Hansen ───────────────────────────────────────────────────────────────
def gjr_filter(e, omega, alpha, gamma, beta, h0):
    e2 = e * e
    neg = (e < 0).astype(float)
    x = omega + (alpha + gamma * neg[:-1]) * e2[:-1]
    h = np.empty_like(e)
    h[0] = h0
    h[1:] = lfilter([1.0], [1.0, -beta], x, zi=[beta * h0])[0]
    return h  # h[t] = 조건부 분산 of e[t] given ≤ t−1


def gjr_nll(theta, r):
    mu, omega, alpha, gamma, beta, nu, lam = theta
    if omega <= 0 or alpha < 0 or gamma < 0 or beta < 0 or alpha + 0.5 * gamma + beta >= 0.9995:
        return 1e10
    e = r - mu
    h = gjr_filter(e, omega, alpha, gamma, beta, float(np.var(e)))
    if not np.all(np.isfinite(h)) or np.any(h <= 0):
        return 1e10
    ll = C.hansen_logpdf(r, mu, np.sqrt(h), nu, lam)
    v = -float(np.sum(ll))
    return v if np.isfinite(v) else 1e10


def gjr_fit(r, x0=None):
    if x0 is None:
        x0 = np.array([0.05, 0.02, 0.02, 0.10, 0.88, 8.0, -0.05])
    bnds = [(-1, 1), (1e-5, 5), (0, 0.5), (0, 0.6), (0.3, 0.9995), (2.2, 60), (-0.8, 0.8)]
    res = sp_opt.minimize(gjr_nll, x0, args=(r,), method="L-BFGS-B", bounds=bnds,
                          options={"maxiter": 500})
    return res.x, res


# ─── EWMA-Hansen ──────────────────────────────────────────────────────────────────────
def ewma_var(r, lam=EWMA_LAMBDA, init_n=60):
    h = np.empty_like(r)
    h[0] = np.var(r[:init_n])
    x = (1 - lam) * r[:-1] ** 2
    h[1:] = lfilter([1.0], [1.0, -lam], x, zi=[lam * h[0]])[0]
    return h  # h[t] = 분산 of r[t] given ≤ t−1


def hansen_mle(z):
    def nll(th):
        nu, lam = th
        v = -float(np.sum(C.hansen_logpdf(z, 0.0, 1.0, nu, lam)))
        return v if np.isfinite(v) else 1e10
    res = sp_opt.minimize(nll, np.array([8.0, -0.05]), method="L-BFGS-B", bounds=[(2.2, 60), (-0.8, 0.8)])
    return res.x


def main():
    t0 = time.time()
    rr = load_returns()
    p3 = pd.read_parquet(C.OUT / "fc_P3_replica.parquet")[["Date", "y"]] if (C.OUT / "fc_P3_replica.parquet").exists() else None
    D = rr["Date"].values
    r = rr["r"].values
    idx_of = {pd.Timestamp(d): i for i, d in enumerate(D)}
    if p3 is not None:
        f_dates = [pd.Timestamp(d) for d in p3["Date"]]
    else:
        f_dates = [pd.Timestamp(d) for d in D if pd.Timestamp(d) >= pd.Timestamp("2013-01-24")][:-1]
    f_idx = np.array([idx_of[d] for d in f_dates])
    y = r[f_idx + 1]

    # ── GJR
    rows = []
    theta_prev = None
    for k0 in range(0, len(f_idx), REFIT_EVERY):
        blk = f_idx[k0:k0 + REFIT_EVERY]
        t_fit = blk[0]
        start_date = pd.Timestamp(D[t_fit]) - pd.DateOffset(years=LOOKBACK_YEARS)
        s0 = int(np.searchsorted(D, np.datetime64(start_date)))
        win = r[s0:t_fit + 1]
        th, res = gjr_fit(win, theta_prev)
        theta_prev = th
        mu, om, al, ga, be, nu, lm = th
        # 필터: 창 시작부터 블록 끝 + 1(예측 분산 h_{t+1})
        seg = r[s0:blk[-1] + 2] if blk[-1] + 1 < len(r) else r[s0:]
        e = seg - mu
        h = gjr_filter(e, om, al, ga, be, float(np.var(win - mu)))
        for t in blk:
            j = t + 1 - s0  # h[j] = 분산 of r[t+1] given ≤ t
            rows.append({"Date": pd.Timestamp(D[t]), "y": r[t + 1], "mu": mu, "sigma": float(np.sqrt(h[j])),
                         "nu": nu, "lam": lm, "persist": al + 0.5 * ga + be, "refit_date": pd.Timestamp(D[t_fit]),
                         "conv": bool(res.success)})
    gjr = pd.DataFrame(rows)
    gjr_s = S.score_hansen(gjr)
    gjr_s.to_parquet(C.OUT / "sc_GJR.parquet")
    print(f"[ref] GJR done n={len(gjr_s)} conv={gjr['conv'].mean():.3f} {time.time()-t0:.0f}s", flush=True)

    # ── EWMA
    h_all = ewma_var(r)
    rows = []
    for k0 in range(0, len(f_idx), REFIT_EVERY):
        blk = f_idx[k0:k0 + REFIT_EVERY]
        t_fit = blk[0]
        start_date = pd.Timestamp(D[t_fit]) - pd.DateOffset(years=LOOKBACK_YEARS)
        s0 = max(int(np.searchsorted(D, np.datetime64(start_date))), 60)
        z = r[s0:t_fit + 1] / np.sqrt(h_all[s0:t_fit + 1])
        nu, lm = hansen_mle(z)
        for t in blk:
            rows.append({"Date": pd.Timestamp(D[t]), "y": r[t + 1], "mu": 0.0,
                         "sigma": float(np.sqrt(h_all[t + 1])), "nu": nu, "lam": lm})
    ew = pd.DataFrame(rows)
    S.score_hansen(ew).to_parquet(C.OUT / "sc_EWMA.parquet")
    print(f"[ref] EWMA done {time.time()-t0:.0f}s", flush=True)

    # ── HS500
    Q = np.empty((len(f_idx), len(C.U_GRID)))
    for i, t in enumerate(f_idx):
        Q[i] = np.quantile(r[t - HS_WINDOW + 1:t + 1], C.U_GRID)
    hs = S.score_quantile_grid(f_dates, y, Q)
    hs.to_parquet(C.OUT / "sc_HS500.parquet")
    print(f"[ref] HS500 done {time.time()-t0:.0f}s", flush=True)
    C.write_json(C.OUT / "sc_reference.meta.json", {
        "script": "11_reference_models.py", "n": int(len(f_idx)), "lookback_years": LOOKBACK_YEARS,
        "refit_every": REFIT_EVERY, "ewma_lambda": EWMA_LAMBDA, "hs_window": HS_WINDOW,
        "data_vintage": C.data_vintage(), "elapsed_s": round(time.time() - t0, 1)})


if __name__ == "__main__":
    main()
