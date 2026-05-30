#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_gpu_sweep_lex.py — Qvest v8.x Dev: DPL learned-exposure + |Δw| smoothing penalty.

Dev-CBE 진단 두 결함 직접 공략 (research/feasibility only — admission/book 변경 금지):

  결함1 (B fixed regime cash node가 α-t를 2.91→2.19 끌어내림):
    → LEARNED EXPOSURE. regime_score(PIT t-1, dpl_regime_export.py 산출)를 exposure-head 입력으로
      넣어 g_t = sigmoid(head(regime_feat)) ∈ (0,1) 를 end-to-end 학습. 최종 노출 = g_t·Σw_risky,
      w_cash = 1 - g_t (cash ret 0). fixed prior(B) 아님 — 모델이 "언제 노출 줄일지" 학습.
      regime_feat = [regime_score, regime_score^2, rvol_252(있으면)] (월별 scalar, cross-section 공통).
      exposure head는 per-name MLP(μ̂)와 분리된 작은 head(별도 파라미터, 동시 학습).

  결함2 (TO 근본원인 = weight-churn(보유종목 비중 재배분), name-churn 아님 → buffer 무효):
    → |Δw| SMOOTHING PENALTY. 손실에 +γ_dw·E[Σ|w_t − w_{t-1}|] 추가(dense weight L1, train-time).
      추가로 INFERENCE WEIGHT INERTIA(ρ): w_t = renorm((1-ρ)·w_target + ρ·w_{t-1,held}) 로
      보유종목 비중을 직전월에 anchor → weight-churn 직접 제어(hard, projection 후 재투영).
      γ_dw grid + ρ grid 로 TO≤11 지점 탐색.

  C 유지: active-alpha Sharpe loss(net − benchmark_monthly). 게이트(portfolio-α t)와 정합.

설계 매트릭스 (둘다 토글 가능 → ablation):
   base   = C only (active-alpha loss, fully-invested, no inertia) ............ 재현 baseline
   +lex   = C + learned exposure head .......................................... 결함1 공략
   +dw    = C + |Δw| penalty(γ_dw) + inference inertia(ρ) ...................... 결함2 공략
   +both  = C + learned exposure + |Δw| penalty ............................... 둘다

평가: 월별 net active return series 산출 → R dpl_lex_eval_contract.R 단일경로
  (build_benchmark_compare NW lag-3, metric_type=backtested). 자체합성 금지.
  in-sample(전체구간 fit·eval, 과적합 상한) 과 OOS(walk-forward 1-step) 분리 export.
  DSR honest(누적 trial). TO≤11 AND α-t>2.906 동시충족 셀 탐색.

findings-only: "이 구성에서 X(N=k)". DPL 한계/된다 단정 금지.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_gpu_sweep_lex.py [--mode base|lex|dw|both|ALL]
      (DPL_SMOKE=1 환경변수 → 1 cell 5 epochs 빠른 검증)
산출: stage_artifacts/WT_DPL_GPU_SWEEP/lex_{mode}_net_returns.parquet (+ _is)
      lex_sweep_results.json
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
import dpl_gpu_sweep as base  # noqa: E402  (DPLNet / projection / DSR / cache 재사용)

torch.set_default_dtype(torch.float64)

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = base.OUT_DIR
PANEL = base.PANEL
BENCH = base.BENCH
REGIME = os.path.join(OUT_DIR, "regime_monthly.parquet")

LOCKBOX = base.LOCKBOX
CAP = base.CAP
ACTIVE_MAX = base.ACTIVE_MAX           # top-25 universe
COST_BPS_ONEWAY = base.COST_BPS_ONEWAY
ANNUALIZE = base.ANNUALIZE
DEVICE = base.DEVICE

# baseline cumulative trial 누적 (DSR honest): 96 (기존 GPU sweep) + 12 (CBE focused 3 variant × 4) = 108
CUM_TRIALS_PRIOR = 108


# ════════════════════════════════════════════════════════════════════
# 데이터 로드 (panel + benchmark + regime month-scalar features)
# ════════════════════════════════════════════════════════════════════
def load_all():
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]

    reg = pd.read_parquet(REGIME)
    reg["ym"] = reg["ym"].astype(str)
    # month-scalar regime features (PIT t-1; dpl_regime_export 이미 t-1 shift 적용)
    rvol = reg["rvol_252"] if "rvol_252" in reg.columns else pd.Series(np.nan, index=reg.index)
    # standardize rvol with expanding mean/std would need care; use simple fill+clip for a robust scalar
    rvol_z = (rvol - rvol.mean()) / (rvol.std() + 1e-9)
    reg_feat = {}
    for _, r in reg.iterrows():
        s = float(r["regime_score"]) if np.isfinite(r["regime_score"]) else 0.85
        rv = float(rvol_z.loc[r.name]) if np.isfinite(rvol_z.loc[r.name]) else 0.0
        reg_feat[r["ym"]] = np.array([s, s * s, rv], dtype=np.float64)
    reg_score = dict(zip(reg["ym"], reg["regime_score"]))
    return panel, bm, feat_cols, reg_feat, reg_score


# ════════════════════════════════════════════════════════════════════
# Networks: per-name μ̂ MLP (재사용 base.DPLNet) + 분리된 exposure head
# ════════════════════════════════════════════════════════════════════
class ExposureHead(nn.Module):
    """월별 regime-scalar feature → g ∈ (0,1) 시장노출 학습. (cross-section 공통, per-month scalar)"""
    def __init__(self, n_in=3, hidden=8):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(n_in, hidden), nn.Tanh(),
            nn.Linear(hidden, 1),
        )
        # bias 초기화: 초기 노출 ~1.0 근처(full-invested)에서 출발 → 학습으로 줄이도록.
        with torch.no_grad():
            self.net[-1].bias.fill_(3.0)   # sigmoid(3)≈0.953

    def forward(self, rfeat):
        return torch.sigmoid(self.net(rfeat)).squeeze(-1)


# ════════════════════════════════════════════════════════════════════
# 학습 (C1 active-alpha Sharpe + |Δw| penalty + learned exposure)
# ════════════════════════════════════════════════════════════════════
def train_dpl_lex(cache, n_feat, train_months, cfg, bm_map, reg_feat):
    use_lex = cfg["use_lex"]
    gam_dw = cfg["gamma_dw"]
    model = base.DPLNet(n_feat, depth=cfg["depth"], width=cfg["width"],
                        dropout=cfg["dropout"]).to(DEVICE)
    params = list(model.parameters())
    exp_head = None
    if use_lex:
        exp_head = ExposureHead(n_in=3, hidden=8).to(DEVICE)
        params += list(exp_head.parameters())
    opt = torch.optim.Adam(params, lr=cfg["lr"], weight_decay=cfg["l2"])
    gam = cfg["gamma"]; lam = cfg["lam"]; temp = cfg["temp"]
    sqrtA = float(np.sqrt(ANNUALIZE))
    N_T = cache["__global__"]["n_tickers"]
    valid = [m for m in train_months if m in cache and cache[m]["n"] >= ACTIVE_MAX]
    if len(valid) < 12:
        return model, exp_head
    B = len(valid); k = ACTIVE_MAX
    Xb = torch.cat([cache[m]["X"] for m in valid], 0)
    starts = []; cur = 0
    for m in valid:
        starts.append((cur, cur + cache[m]["n"])); cur += cache[m]["n"]
    r_blocks = [cache[m]["r"] for m in valid]
    tid_blocks = [cache[m]["tid"] for m in valid]
    bm_vec = torch.tensor([bm_map.get(m, 0.0) for m in valid], device=DEVICE)        # [B]
    # month regime feature matrix [B,3] (PIT t-1)
    Rf = torch.tensor(np.stack([reg_feat.get(m, np.array([0.85, 0.7225, 0.0]))
                                for m in valid]), device=DEVICE)                     # [B,3]

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
        W = base.weights_from_scores_batch(MU_c, cap=CAP, temp=temp)        # [B,k] risky weights (Σ=1 per row)
        # learned exposure g [B] → final risky exposure
        if use_lex:
            g = exp_head(Rf)                                                # [B] in (0,1)
        else:
            g = torch.ones(B, device=DEVICE)
        Weff = W * g.unsqueeze(1)                                           # [B,k] effective (Σ=g)
        gross = (Weff * R).sum(dim=1)                                       # [B] cash(1-g) ret 0
        # dense weights for turnover (effective, includes cash move via Σ change)
        Wdense = torch.zeros(B, N_T, device=DEVICE)
        Wdense.scatter_(1, TID, Weff)
        Wprev = torch.zeros_like(Wdense)
        Wprev[1:] = Wdense[:-1].detach()
        dW = (Wdense - Wprev).abs().sum(dim=1)                              # [B] = |Δw| L1 (weight-churn)
        cost = dW * COST_BPS_ONEWAY / 1e4
        net = gross - cost
        active = net - bm_vec                                              # ★ C1 active alpha
        sharpe = active.mean() / (active.std() + 1e-6) * sqrtA
        mean_traded = dW.mean()
        mean_risk = (Weff * Weff).sum(dim=1).mean()
        # loss: -active_sharpe + gamma·traded + gamma_dw·|Δw| + lam·risk
        loss = -sharpe + gam * mean_traded + gam_dw * mean_traded + lam * mean_risk
        loss.backward()
        opt.step()
    return model, exp_head


@torch.no_grad()
def dpl_weights_lex(model, exp_head, cache, m, cfg, prev_w, reg_feat):
    """월 m weight (inference). learned exposure + inference weight-inertia(ρ).

    prev_w: dict{ticker: w_effective_prev}. 반환: dict{ticker: w_effective}, g.
    inertia: w_target(top-25 risky·g) 와 직전월 보유 weight 를 ρ blend 후 top-25 재선택·재투영.
    """
    if m not in cache or cache[m]["n"] < ACTIVE_MAX:
        return None, None
    c = cache[m]
    mu_all = model(c["X"])
    mu_np = mu_all.detach().cpu().numpy()
    tk = c["tk"]
    idx = np.argsort(-mu_np)[:ACTIVE_MAX]
    mu_sel = torch.tensor(mu_np[idx], device=DEVICE)
    mu_c = (mu_sel - mu_sel.mean()) / (mu_sel.std() + 1e-6)
    w = base.weights_from_scores(mu_c, cap=CAP, temp=cfg["temp"]).detach().cpu().numpy()  # Σ=1
    tk_sel = tk[idx]
    # learned exposure g
    if cfg["use_lex"] and exp_head is not None:
        rf = torch.tensor(reg_feat.get(m, np.array([0.85, 0.7225, 0.0])), device=DEVICE).unsqueeze(0)
        g = float(exp_head(rf).item())
    else:
        g = 1.0
    w_eff = {t: float(wi) * g for t, wi in zip(tk_sel, w)}

    # inference weight-inertia(ρ): blend held weights toward previous; renorm to Σ=g.
    rho = cfg.get("rho", 0.0)
    if rho > 0 and prev_w:
        blended = {}
        for t, wi in w_eff.items():
            pv = prev_w.get(t, 0.0)
            blended[t] = (1.0 - rho) * wi + rho * pv
        # held names not re-selected this month are dropped (long-only top-N 정합 유지);
        # renormalize to target exposure g, keep cap [0,0.20].
        ssum = sum(blended.values())
        if ssum > 1e-12:
            scale = g / ssum
            blended = {t: min(v * scale, CAP * g) for t, v in blended.items()}
            # cap 적용 후 잔차 renorm (간단 2-pass; Σ=g 보장)
            ssum2 = sum(blended.values())
            if ssum2 > 1e-12:
                blended = {t: v * (g / ssum2) for t, v in blended.items()}
        w_eff = blended
    return {t: v for t, v in w_eff.items() if v > 1e-6}, g


def walk_forward_lex(cache, n_feat, cfg, months, bm_map, reg_feat):
    min_train = cfg["min_train"]; train_window = cfg["lookback"]; refit_every = 12
    rows = []; gs = []; model = None; exp_head = None
    start_i = min_train; prev_w = {}
    for i in range(start_i, len(months)):
        m = months[i]
        if (model is None) or ((i - start_i) % refit_every == 0):
            tr = months[max(0, i - train_window):i]
            model, exp_head = train_dpl_lex(cache, n_feat, tr, cfg, bm_map, reg_feat)
        wdict, g = dpl_weights_lex(model, exp_head, cache, m, cfg, prev_w, reg_feat)
        if wdict is None:
            continue
        prev_w = wdict
        gs.append((m, g))
        for t, v in wdict.items():
            rows.append((m, t, float(v)))
    wdf = pd.DataFrame(rows, columns=["ym", "Ticker", "w"])
    gdf = pd.DataFrame(gs, columns=["ym", "g"])
    return wdf, gdf


def walk_forward_insample(cache, n_feat, cfg, months, bm_map, reg_feat):
    tr = months[:]
    model, exp_head = train_dpl_lex(cache, n_feat, tr, cfg, bm_map, reg_feat)
    rows = []; prev_w = {}
    for m in months:
        wdict, _ = dpl_weights_lex(model, exp_head, cache, m, cfg, prev_w, reg_feat)
        if wdict is None:
            continue
        prev_w = wdict
        for t, v in wdict.items():
            rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


# ════════════════════════════════════════════════════════════════════
# net active return series (cash node aware: gross over risky·g only, w_cash ret=0)
# ════════════════════════════════════════════════════════════════════
def net_return_series(wdf, rets, bm):
    wj = wdf.merge(rets, on=["ym", "Ticker"], how="left")
    wj["Ret_1m"] = wj["Ret_1m"].fillna(0.0)
    wj["_wr"] = wj["w"] * wj["Ret_1m"]
    gross = wj.groupby("ym")["_wr"].sum().rename("port_gross")
    traded = {}; prev = {}
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


def sharpe_active(series):
    a = (series["ret_net"] - series["BM_Ret_1m"]).values
    if len(a) < 6 or a.std() == 0:
        return np.nan
    return float(a.mean() / a.std() * np.sqrt(ANNUALIZE))


def export_series(s, tag, out_name):
    e = s[["ym", "ret_net", "BM_Ret_1m", "traded"]].copy()
    e["date"] = pd.PeriodIndex(e["ym"], freq="M").to_timestamp("M")
    e["method"] = tag
    e.rename(columns={"BM_Ret_1m": "BM_Ret"}, inplace=True)
    e[["method", "date", "ret_net", "BM_Ret", "traded"]].to_parquet(
        os.path.join(OUT_DIR, out_name), index=False)


# ════════════════════════════════════════════════════════════════════
def mode_grid(mode, focused=True):
    """mode → (use_lex, gamma_dw grid, rho grid).

    base : C only. lex: +learned exposure. dw: +|Δw| penalty+inertia. both: 둘다.
    incumbent best cfg(cell37): gamma1.5 / temp1.0 / lookback72 / depth3 / width32.
    """
    g = {"lam": [0.0], "gamma": [1.5], "lookback": [72], "depth": [3], "width": [32],
         "l2": [1e-3], "dropout": [0.1], "temp": [1.0], "lr": [5e-3], "epochs": [40],
         "min_train": [60]}
    if mode == "base":
        g.update({"use_lex": [False], "gamma_dw": [0.0], "rho": [0.0]})
    elif mode == "lex":
        g.update({"use_lex": [True], "gamma_dw": [0.0], "rho": [0.0]})
    elif mode == "dw":
        g.update({"use_lex": [False], "gamma_dw": [0.0, 1.5, 3.0], "rho": [0.0, 0.3, 0.5]})
    elif mode == "both":
        g.update({"use_lex": [True], "gamma_dw": [1.5, 3.0], "rho": [0.3, 0.5]})
    return g


def run_mode(mode, cache, n_feat, panel, bm, feat_cols, reg_feat, rets, bm_map, months):
    print(f"\n{'='*64}\n[lex] MODE = {mode}\n{'='*64}")
    grid = mode_grid(mode)
    if os.environ.get("DPL_SMOKE") == "1":
        grid = {k: [v[0]] for k, v in grid.items()}
        grid["epochs"] = [5]
        print("[lex] SMOKE — 1 cell 5 epochs")
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    n_trials = len(combos)
    print(f"[lex] {mode} grid cells = {n_trials}")

    results = []; best = None; best_oos = None; best_cfg = None; best_gdf = None
    for ci, vals in enumerate(combos):
        cfg = dict(zip(keys, vals))
        torch.manual_seed(7); np.random.seed(7)
        wdf, gdf = walk_forward_lex(cache, n_feat, cfg, months, bm_map, reg_feat)
        if wdf.empty:
            continue
        s = net_return_series(wdf, rets, bm)
        sr = sharpe_active(s)
        to_ann = float(s["traded"].mean() * 12)
        s_sorted = s.sort_values("ym").reset_index(drop=True)
        thirds = np.array_split(s_sorted, 3)
        sub = [sharpe_active(t) for t in thirds if len(t) >= 6]
        sr_min = float(np.nanmin(sub)) if sub else np.nan
        g_mean = float(gdf["g"].mean()) if len(gdf) else 1.0
        g_min = float(gdf["g"].min()) if len(gdf) else 1.0
        rec = {"cell": ci, "mode": mode,
               "gamma_dw": cfg["gamma_dw"], "rho": cfg["rho"], "use_lex": cfg["use_lex"],
               "gamma": cfg["gamma"], "temp": cfg["temp"],
               "net_active_sr": sr, "turnover_ann": to_ann,
               "n_oos_months": int(s["ym"].nunique()),
               "sr_min_subperiod": sr_min, "sub_period_srs": [round(x, 3) for x in sub],
               "g_mean": g_mean, "g_min": g_min}
        results.append(rec)
        print(f"[lex] {mode} cell {ci+1}/{n_trials} OOS_SR={sr:.3f} TO={to_ann:.2f} "
              f"sub_min={sr_min:.3f} g(mean={g_mean:.3f},min={g_min:.3f}) "
              f"cfg(dw={cfg['gamma_dw']},rho={cfg['rho']},lex={cfg['use_lex']})")
        # 선택 기준: TO≤11 우선, 그 안에서 SR 최대. (TO≤11 없으면 SR 최대 fallback)
        def key(r):
            feas = 1 if (np.isfinite(r["turnover_ann"]) and r["turnover_ann"] <= 11.0) else 0
            return (feas, np.nan_to_num(r["net_active_sr"], nan=-9))
        if (best is None) or (key(rec) > key(best)):
            best = rec; best_oos = s.copy(); best_cfg = cfg; best_gdf = gdf.copy()

    if best is None:
        print(f"[lex] {mode}: no valid cell"); return None

    # in-sample for best cfg (분리 보고)
    torch.manual_seed(7); np.random.seed(7)
    wdf_is = walk_forward_insample(cache, n_feat, best_cfg, months, bm_map, reg_feat)
    s_is = net_return_series(wdf_is, rets, bm)
    sr_is = sharpe_active(s_is); to_is = float(s_is["traded"].mean() * 12)
    best["insample_active_sr"] = sr_is
    best["insample_turnover_ann"] = to_is

    export_series(best_oos, f"LEX_{mode}", f"lex_{mode}_net_returns.parquet")
    export_series(s_is, f"LEX_{mode}_IS", f"lex_{mode}_is_net_returns.parquet")
    if best_gdf is not None and len(best_gdf):
        best_gdf.to_parquet(os.path.join(OUT_DIR, f"lex_{mode}_exposure.parquet"), index=False)

    active = (best_oos["ret_net"] - best_oos["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)) if len(active) > 3 else 0.0
    kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0
    best["DSR_thisvariant"] = base.deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, skew, kurt)
    best["active_skew"] = skew; best["active_kurt"] = kurt
    print(f"[lex] {mode} BEST cell={best['cell']} OOS_SR={best['net_active_sr']:.3f} "
          f"TO={best['turnover_ann']:.2f} IS_SR={sr_is:.3f} IS_TO={to_is:.2f} "
          f"g_mean={best['g_mean']:.3f}")
    return {"mode": mode, "n_trials_thismode": n_trials, "n_feature_cols": len(feat_cols),
            "best": best,
            "all_cells": sorted(results, key=lambda r: -np.nan_to_num(r["net_active_sr"], nan=-9))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="ALL", choices=["base", "lex", "dw", "both", "ALL"])
    args = ap.parse_args()
    modes = ["base", "lex", "dw", "both"] if args.mode == "ALL" else [args.mode]

    panel, bm, feat_cols, reg_feat, reg_score = load_all()
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    bm_map = dict(zip(bm["ym"], bm["BM_Ret_1m"]))
    months = sorted(panel["ym"].unique())
    lock = LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    print(f"[lex] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}] device={DEVICE}")
    cache = base.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    out = {"device": DEVICE, "lockbox": str(LOCKBOX.date()), "modes": {}}
    cum_trials = CUM_TRIALS_PRIOR
    for mode in modes:
        r = run_mode(mode, cache, n_feat, panel, bm, feat_cols, reg_feat, rets, bm_map, months)
        if r:
            cum_trials += r["n_trials_thismode"]
            r["best"]["n_trials_cumulative"] = cum_trials
            bs = pd.read_parquet(os.path.join(OUT_DIR, f"lex_{mode}_net_returns.parquet"))
            active = (bs["ret_net"] - bs["BM_Ret"]).values
            from scipy import stats as st
            skew = float(st.skew(active)); kurt = float(st.kurtosis(active, fisher=False))
            r["best"]["DSR_cumulative"] = base.deflated_sharpe_ratio(
                r["best"]["net_active_sr"], len(active), cum_trials, skew, kurt)
            out["modes"][mode] = r
    out["n_trials_cumulative_final"] = cum_trials
    with open(os.path.join(OUT_DIR, "lex_sweep_results.json"), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, default=float)
    print(f"\n[lex] results -> {os.path.join(OUT_DIR, 'lex_sweep_results.json')}")
    print(f"[lex] cumulative n_trials (prior {CUM_TRIALS_PRIOR} + this) = {cum_trials}")


if __name__ == "__main__":
    main()
