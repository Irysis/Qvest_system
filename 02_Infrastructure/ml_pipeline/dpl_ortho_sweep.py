#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_ortho_sweep.py — Qvest v8.x: DPL GPU sweep on 102f panel (90f baseline + 4 직교 알파 factor).

measurement-graduation §5 검증: 직교 슬리브 사냥서 standalone OOS 붕괴한 알파(value BM / earnings-rev
breadth / reversal)를 DPL 피처로 추가 → DPL net Sharpe 직접최적화가 비선형 결합으로 baseline(90f
DPL_C OOS α-t 2.906)·incumbent(STR_1715 α-t 5.344) 대비 개선하는지 측정.

apples-to-apples: 기존 dpl_gpu_sweep.py 의 함수(DPLNet/projection/cache/walk_forward/net_return/
DSR) 전부 재사용. 패널/출력만 WT_DPL_ORTHO. 동일 lockbox(2023-12-22)·동일 walk-forward refit/12m·
동일 benchmark·동일 KOSPI200∪KOSDAQ150·동일 15bps·top25/cap0.20/Σw=1.

두 trains:
  (A) 96-cell GPU 그리드 (net-Sharpe loss) — baseline 동일 그리드 재탐색 → 직교 피처가 HP 서치
      하에서 천장을 올리는지. honest n_trials = 96.
  (B) DPL_C config (active-alpha Sharpe loss, cell37 HP) — 기존 OOS 최고(2.906) 직접 동조건 비교.

산출: ortho_best_net_returns.parquet / ortho_dplC_net_returns.parquet (+ _is) → R eval contract.
자체합성 backtest 금지: 월별 net return series만 export → portfolio_alpha_t_nw_lag3 는 R 단일경로.

실행: cd <root> && G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe \
        02_Infrastructure/ml_pipeline/dpl_ortho_sweep.py [--mode grid|dplC|ALL]
      DPL_SMOKE=1 → 축소(빠른 검증).
"""
import os
import sys
import json
import itertools
import argparse
import numpy as np
import pandas as pd
import torch
import torch.nn as nn

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, THIS_DIR)
import dpl_gpu_sweep as base  # noqa: E402  (DPLNet/projection/cache/DSR/net_return/sharpe 재사용)

torch.set_default_dtype(torch.float64)

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_ORTHO")
os.makedirs(OUT_DIR, exist_ok=True)
PANEL = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
BENCH = os.path.join(OUT_DIR, "benchmark_monthly.parquet")

LOCKBOX = base.LOCKBOX
CAP = base.CAP
ACTIVE_MAX = base.ACTIVE_MAX
COST_BPS_ONEWAY = base.COST_BPS_ONEWAY
ANNUALIZE = base.ANNUALIZE
DEVICE = base.DEVICE

# DSR 누적 trial honest 카운트: 기존 90f 누적(108 = 96 GPU sweep + 12 CBE) + ENS/LEX/ENS2 trains.
# 직교 변형은 별도 feature-set 가설이나 같은 DPL 패밀리 다중검정 → 보수적으로 prior 누적에 더한다.
CUM_TRIALS_PRIOR = 140  # 90f 패밀리 누적 추정(96 sweep +12 CBE +4 ENS +~12 LEX +~4 ENS2 +reserve)


def load_panel():
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    return panel, bm, feat_cols


# ════════════════════════════════════════════════════════════════════
# train (active-alpha 옵션 추가 버전 — base.train_dpl 은 net-Sharpe loss)
# ════════════════════════════════════════════════════════════════════
def train_dpl(cache, n_feat, train_months, cfg, bm_map=None, active_alpha=False):
    """base.train_dpl 과 동일하되 active_alpha=True 면 loss Sharpe 분자를 (net − bm) 로.

    DPL_C(기존 OOS 최고)의 핵심이 active-alpha Sharpe loss라 직접 비교 위해 재구현(나머지 동일).
    """
    model = base.DPLNet(n_feat, depth=cfg["depth"], width=cfg["width"],
                        dropout=cfg["dropout"]).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=cfg["lr"], weight_decay=cfg["l2"])
    gam = cfg["gamma"]; lam = cfg["lam"]; temp = cfg["temp"]
    sqrtA = float(np.sqrt(ANNUALIZE))
    N_T = cache["__global__"]["n_tickers"]
    valid = [m for m in train_months if m in cache and cache[m]["n"] >= ACTIVE_MAX]
    if len(valid) < 12:
        return model
    B = len(valid); k = ACTIVE_MAX
    Xb = torch.cat([cache[m]["X"] for m in valid], 0)
    starts = []; cur = 0
    for m in valid:
        starts.append((cur, cur + cache[m]["n"])); cur += cache[m]["n"]
    r_blocks = [cache[m]["r"] for m in valid]
    tid_blocks = [cache[m]["tid"] for m in valid]
    bm_vec = None
    if active_alpha:
        bm_vec = torch.tensor([(bm_map or {}).get(m, 0.0) for m in valid], device=DEVICE)

    for ep in range(cfg["epochs"]):
        opt.zero_grad()
        mu_full = model(Xb)
        MU = torch.empty(B, k, device=DEVICE)
        R = torch.empty(B, k, device=DEVICE)
        TID = torch.empty(B, k, dtype=torch.long, device=DEVICE)
        for b, (s, e) in enumerate(starts):
            mu_all = mu_full[s:e]
            idx = torch.topk(mu_all, k).indices
            MU[b] = mu_all[idx]; R[b] = r_blocks[b][idx]; TID[b] = tid_blocks[b][idx]
        MU_c = (MU - MU.mean(dim=1, keepdim=True)) / (MU.std(dim=1, keepdim=True) + 1e-6)
        W = base.weights_from_scores_batch(MU_c, cap=CAP, temp=temp)
        gross = (W * R).sum(dim=1)
        Wdense = torch.zeros(B, N_T, device=DEVICE)
        Wdense.scatter_(1, TID, W)
        Wprev = torch.zeros_like(Wdense)
        Wprev[1:] = Wdense[:-1].detach()
        traded = (Wdense - Wprev).abs().sum(dim=1)
        cost = traded * COST_BPS_ONEWAY / 1e4
        net = gross - cost
        target = (net - bm_vec) if active_alpha else net
        sharpe = target.mean() / (target.std() + 1e-6) * sqrtA
        mean_traded = traded.mean()
        mean_risk = (W * W).sum(dim=1).mean()
        loss = -sharpe + gam * mean_traded + lam * mean_risk
        loss.backward()
        opt.step()
    return model


def walk_forward(cache, n_feat, cfg, months, bm_map=None, active_alpha=False):
    min_train = cfg["min_train"]; train_window = cfg["lookback"]; refit_every = 12
    oos = []; model = None; start_i = min_train
    for i in range(start_i, len(months)):
        m = months[i]
        if (model is None) or ((i - start_i) % refit_every == 0):
            tr = months[max(0, i - train_window):i]
            model = train_dpl(cache, n_feat, tr, cfg, bm_map, active_alpha)
        tk_sel, wv = base.dpl_weights(model, cache, m, cfg["temp"])
        if tk_sel is None:
            continue
        for t, v in zip(tk_sel, wv):
            if v > 1e-5:
                oos.append((m, t, float(v)))
    return pd.DataFrame(oos, columns=["ym", "Ticker", "w"])


def walk_forward_insample(cache, n_feat, cfg, months, bm_map=None, active_alpha=False):
    model = train_dpl(cache, n_feat, months[:], cfg, bm_map, active_alpha)
    rows = []
    for m in months:
        tk_sel, wv = base.dpl_weights(model, cache, m, cfg["temp"])
        if tk_sel is None:
            continue
        for t, v in zip(tk_sel, wv):
            if v > 1e-5:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


def export_series(s, tag, out_name):
    e = s[["ym", "ret_net", "BM_Ret_1m", "traded"]].copy()
    e["date"] = pd.PeriodIndex(e["ym"], freq="M").to_timestamp("M")
    e["method"] = tag
    e.rename(columns={"BM_Ret_1m": "BM_Ret"}, inplace=True)
    e[["method", "date", "ret_net", "BM_Ret", "traded"]].to_parquet(
        os.path.join(OUT_DIR, out_name), index=False)


def subperiod_min(s):
    s2 = s.sort_values("ym").reset_index(drop=True)
    thirds = np.array_split(s2, 3)
    sub = [base.sharpe_of(t) for t in thirds if len(t) >= 6]
    return (float(np.nanmin(sub)) if sub else np.nan, [round(x, 3) for x in sub])


def run_grid(cache, n_feat, panel, bm, feat_cols, rets, months):
    """96-cell net-Sharpe GPU grid (baseline 동일 그리드, 직교 패널)."""
    print(f"\n{'='*64}\n[ortho] (A) 96-cell GPU grid (net-Sharpe loss)\n{'='*64}")
    grid = {
        "lam": [0.0, 0.3], "gamma": [0.1, 0.5, 1.5], "lookback": [72, 120],
        "depth": [2, 3], "width": [32, 64], "l2": [1e-3], "dropout": [0.1],
        "temp": [0.5, 1.0], "lr": [5e-3], "epochs": [40], "min_train": [60],
    }
    if os.environ.get("DPL_SMOKE") == "1":
        grid = {k: [v[0]] for k, v in grid.items()}; grid["epochs"] = [5]
        print("[ortho] SMOKE — 1 cell 5 epochs")
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    n_trials = len(combos)
    print(f"[ortho] grid cells (n_trials) = {n_trials}")
    results = []; best = None; best_wdf = None
    for ci, vals in enumerate(combos):
        cfg = dict(zip(keys, vals))
        torch.manual_seed(7); np.random.seed(7)
        wdf = walk_forward(cache, n_feat, cfg, months, active_alpha=False)
        if wdf.empty:
            continue
        s = base.net_return_series(wdf, rets, bm)
        sr = base.sharpe_of(s); to_ann = float(s["traded"].mean() * 12)
        sr_min, subs = subperiod_min(s)
        rec = {"cell": ci, **cfg, "net_active_sr": sr, "turnover_ann": to_ann,
               "n_oos_months": int(s["ym"].nunique()),
               "sr_min_subperiod": sr_min, "sub_period_srs": subs}
        results.append(rec)
        if (best is None) or (np.nan_to_num(sr, nan=-9) > np.nan_to_num(best["net_active_sr"], nan=-9)):
            best = rec; best_wdf = wdf.copy(); best_s = s.copy()
        print(f"[ortho] grid {ci+1}/{n_trials} SR={sr:.3f} TO={to_ann:.2f} sub_min={sr_min:.3f} cfg={cfg}")
    export_series(best_s, "ORTHO_grid_best", "ortho_best_net_returns.parquet")
    best_wdf.assign(date=lambda d: pd.PeriodIndex(d["ym"], freq="M").to_timestamp("M")).to_parquet(
        os.path.join(OUT_DIR, "ortho_best_weights.parquet"), index=False)
    active = (best_s["ret_net"] - best_s["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)); kurt = float(st.kurtosis(active, fisher=False))
    best["DSR_thisgrid"] = base.deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, skew, kurt)
    best["DSR_cumulative"] = base.deflated_sharpe_ratio(
        best["net_active_sr"], len(active), CUM_TRIALS_PRIOR + n_trials, skew, kurt)
    return {"n_trials_thisgrid": n_trials, "best": best,
            "all_cells": sorted(results, key=lambda r: -np.nan_to_num(r["net_active_sr"], nan=-9))[:15]}


def run_dplC(cache, n_feat, panel, bm, feat_cols, rets, months, bm_map):
    """DPL_C: active-alpha Sharpe loss + cell37 HP (기존 OOS 최고 2.906 직접 비교)."""
    print(f"\n{'='*64}\n[ortho] (B) DPL_C (active-alpha loss, cell37 HP)\n{'='*64}")
    cfg = {"lam": 0.0, "gamma": 1.5, "lookback": 72, "depth": 3, "width": 32,
           "l2": 1e-3, "dropout": 0.1, "temp": 1.0, "lr": 5e-3, "epochs": 40, "min_train": 60}
    if os.environ.get("DPL_SMOKE") == "1":
        cfg["epochs"] = 5
    torch.manual_seed(7); np.random.seed(7)
    wdf = walk_forward(cache, n_feat, cfg, months, bm_map, active_alpha=True)
    s = base.net_return_series(wdf, rets, bm)
    sr = base.sharpe_of(s); to_ann = float(s["traded"].mean() * 12)
    sr_min, subs = subperiod_min(s)
    export_series(s, "ORTHO_DPL_C", "ortho_dplC_net_returns.parquet")
    # in-sample (분리 보고)
    torch.manual_seed(7); np.random.seed(7)
    wdf_is = walk_forward_insample(cache, n_feat, cfg, months, bm_map, active_alpha=True)
    s_is = base.net_return_series(wdf_is, rets, bm)
    sr_is = base.sharpe_of(s_is); to_is = float(s_is["traded"].mean() * 12)
    export_series(s_is, "ORTHO_DPL_C_IS", "ortho_dplC_is_net_returns.parquet")
    active = (s["ret_net"] - s["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)); kurt = float(st.kurtosis(active, fisher=False))
    dsr_cum = base.deflated_sharpe_ratio(sr, len(active), CUM_TRIALS_PRIOR + 1, skew, kurt)
    print(f"[ortho] DPL_C OOS SR={sr:.3f} TO={to_ann:.2f} sub_min={sr_min:.3f} | IS SR={sr_is:.3f} TO={to_is:.2f}")
    return {"cfg": cfg, "oos_net_active_sr": sr, "oos_turnover_ann": to_ann,
            "oos_subperiod_min": sr_min, "oos_subperiod_srs": subs,
            "insample_active_sr": sr_is, "insample_turnover_ann": to_is,
            "DSR_cumulative": dsr_cum, "n_trials_cumulative": CUM_TRIALS_PRIOR + 1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="ALL", choices=["grid", "dplC", "ALL"])
    args = ap.parse_args()
    smoke = os.environ.get("DPL_SMOKE") == "1"
    print(f"[ortho] device={DEVICE}  DPL_SMOKE={os.environ.get('DPL_SMOKE')!r} -> smoke={smoke} "
          f"({'1 cell/5ep' if smoke else 'FULL 96-cell/40ep'})")
    panel, bm, feat_cols = load_panel()
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    bm_map = dict(zip(bm["ym"], bm["BM_Ret_1m"]))
    months = sorted(panel["ym"].unique())
    lock = LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    print(f"[ortho] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}]")
    cache = base.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    out = {"variant": "ortho 102f (90f + V01_BM + C13_Revision_Breadth_3m + M12_LR_Reversal + L35_Reversal_Intensity)",
           "device": DEVICE, "n_feature_cols": len(feat_cols), "lockbox": str(LOCKBOX.date()),
           "oos_window": f"{months[base.__dict__.get('MIN_TRAIN', 60) if False else 60]}..{months[-1]}",
           "cum_trials_prior_90f_family": CUM_TRIALS_PRIOR}
    if args.mode in ("grid", "ALL"):
        out["grid"] = run_grid(cache, n_feat, panel, bm, feat_cols, rets, months)
    if args.mode in ("dplC", "ALL"):
        out["dplC"] = run_dplC(cache, n_feat, panel, bm, feat_cols, rets, months, bm_map)

    with open(os.path.join(OUT_DIR, "ortho_sweep_results.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, default=float)
    print(f"\n[ortho] results -> {os.path.join(OUT_DIR, 'ortho_sweep_results.json')}")


if __name__ == "__main__":
    main()
