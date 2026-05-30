#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_baselines.py — DPL 비교군(EW top-N / MVO 2-stage) 월별 net return 산출.

DPL sweep과 동일 OOS 윈도우·universe·비용규약(15bps)으로 EW(top-20) + MVO(top-25 long-only QP).
score = 90개 rolling feature의 단순 평균(피처 종합 신호) — DPL이 학습하는 것과 동일 입력에서
단순 EW/MVO가 어디까지 가는지 baseline.

산출: stage_artifacts/WT_DPL_GPU_SWEEP/baselines_net_returns.parquet
      (method ∈ {EW_top20, MVO_2stage}, date, ret_net, BM_Ret, traded)
"""
import os
import numpy as np
import pandas as pd
import cvxpy as cp

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
PANEL = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
BENCH = os.path.join(OUT_DIR, "benchmark_monthly.parquet")
DPL_BEST = os.path.join(OUT_DIR, "dpl_best_net_returns.parquet")

LOCKBOX = pd.Timestamp("2023-12-22")
CAP = 0.20
ACTIVE_MAX = 25
TOP_N_EW = 20
COST_BPS_ONEWAY = 15.0
HIST_COV = 36
ANNUALIZE = 12.0


def cov_sqrt_shrunk(R_hist, shrink=0.3):
    S = np.cov(R_hist, rowvar=False)
    if S.ndim == 0:
        S = np.array([[float(S)]])
    d = np.diag(np.diag(S))
    S = (1 - shrink) * S + shrink * d
    S += np.eye(S.shape[0]) * 1e-6
    return S


def net_return_series(wdf, rets, bm):
    wj = wdf.merge(rets, on=["ym", "Ticker"], how="left")
    wj["Ret_1m"] = wj["Ret_1m"].fillna(0.0)
    wj["_wr"] = wj["w"] * wj["Ret_1m"]
    gross = wj.groupby("ym")["_wr"].sum().rename("port_gross")
    traded = {}
    prev = {}
    for m in sorted(wdf["ym"].unique()):
        cur = dict(zip(wdf[wdf["ym"] == m]["Ticker"], wdf[wdf["ym"] == m]["w"]))
        keys = set(cur) | set(prev)
        traded[m] = sum(abs(cur.get(k, 0.0) - prev.get(k, 0.0)) for k in keys)
        prev = cur
    out = gross.reset_index()
    out["traded"] = out["ym"].map(traded)
    out["cost"] = out["traded"] * COST_BPS_ONEWAY / 1e4
    out["ret_net"] = out["port_gross"] - out["cost"]
    out = out.merge(bm, on="ym", how="left")
    return out


def main():
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()

    # OOS months = DPL best의 실제 OOS 구간과 정렬
    dpl = pd.read_parquet(DPL_BEST)
    dpl["ym"] = pd.to_datetime(dpl["date"]).dt.to_period("M").astype(str)
    oos_months = sorted(dpl["ym"].unique())
    pan_oos = panel[panel["ym"].isin(oos_months)].copy()
    pan_oos["score"] = pan_oos[feat_cols].mean(axis=1)
    rwide = panel.pivot_table(index="ym", columns="Ticker", values="Ret_1m")

    # EW top-20
    ew_rows = []
    for m, g in pan_oos.groupby("ym"):
        top = g.nlargest(TOP_N_EW, "score")
        wv = 1.0 / len(top)
        for t in top["Ticker"]:
            ew_rows.append((m, t, wv))
    ew_w = pd.DataFrame(ew_rows, columns=["ym", "Ticker", "w"])

    # MVO 2-stage (top-25 long-only QP, μ=score, Σ=shrunk hist cov)
    mvo_rows = []
    for m, g in pan_oos.groupby("ym"):
        g2 = g.nlargest(ACTIVE_MAX, "score")
        tk = g2["Ticker"].values
        mu = g2["score"].values
        n = len(tk)
        if n < 5:
            continue
        hist = rwide.loc[rwide.index < m, tk].tail(HIST_COV).dropna(axis=1, how="all").fillna(0.0)
        Sig = cov_sqrt_shrunk(hist.values) if (hist.shape[1] == n and hist.shape[0] >= 6) else np.eye(n) * 0.05
        wv = cp.Variable(n)
        prob = cp.Problem(cp.Maximize(mu @ wv - 5.0 * cp.quad_form(wv, cp.psd_wrap(Sig))),
                          [wv >= 0, cp.sum(wv) == 1, wv <= CAP])
        try:
            prob.solve(solver=cp.CLARABEL)
        except Exception:
            continue
        if wv.value is None:
            continue
        for t, v in zip(tk, wv.value):
            if v > 1e-5:
                mvo_rows.append((m, t, float(v)))
    mvo_w = pd.DataFrame(mvo_rows, columns=["ym", "Ticker", "w"])

    rows = []
    for name, wdf in [("EW_top20", ew_w), ("MVO_2stage", mvo_w)]:
        s = net_return_series(wdf, rets, bm)
        s["date"] = pd.PeriodIndex(s["ym"], freq="M").to_timestamp("M")
        active = (s["ret_net"] - s["BM_Ret_1m"])
        sr = float(active.mean() / active.std() * np.sqrt(ANNUALIZE))
        print(f"[base] {name}: months={len(s)} active_SR={sr:.3f} TO={s['traded'].mean()*12:.2f}")
        for _, r in s.iterrows():
            rows.append({"method": name, "date": r["date"], "ret_net": r["ret_net"],
                         "BM_Ret": r["BM_Ret_1m"], "traded": r["traded"]})
    out = pd.DataFrame(rows)
    out_path = os.path.join(OUT_DIR, "baselines_net_returns.parquet")
    out.to_parquet(out_path, index=False)
    print(f"[base] -> {out_path}")


if __name__ == "__main__":
    main()
