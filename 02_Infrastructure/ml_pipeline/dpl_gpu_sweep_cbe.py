#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_gpu_sweep_cbe.py — Qvest v8.x Dev-CBE: DPL 발전방향 탐색 (C + B + E variants).

기존 dpl_gpu_sweep.py(90f, α-t 2.766, TO 15.83, fully-invested) 를 확장:

  C — 손실정렬 + hysteresis buffer (HIGH feasibility 선행):
    (C1) loss의 Sharpe를 net Sharpe → **active-alpha Sharpe**(net − benchmark_monthly) 로 교체.
         게이트(portfolio-α t)와 학습 목적함수 정합. benchmark는 PIT-safe(동월 실현 BM).
    (C2) **hysteresis buffer**: 직전월 보유종목은 keep_n(=32) 랭킹까지 유지, 신규는 entry_n(=25)
         진입. weight 산출에 hard-encode → 월간 reshuffle 억제 → TO 15.83 → ≤11 강제.
         (FLOW EW 히스테리시스 버퍼 패턴 재사용. 학습 loss의 turnover penalty와 별개의 hard mechanism.)

  B — β-overlay 합성 (HIGH 레버):
    dpl_regime_export.py의 month-end regime_score(PIT t-1, 252d trend expanding 분위) 를
    **cash node**로 합성: 최종 노출 = regime_score 를 prior로, risky weight 합 = exposure,
    w_cash = 1 - exposure (cash 수익 0). exposure 는 (a)regime prior 고정 또는 (b)학습형
    (regime_score 를 MLP 입력 scalar 로 추가해 end-to-end) 2모드. 본 sweep은 (a)고정 prior로
    먼저 측정(해석가능·PIT 명확), 학습형은 후속.

  E — 피처 pruning (안정화):
    feature_importance.json permutation importance > 0.05 인 ~31 피처 subset variant.

평가: 월별 net active return series 산출 → R dpl_eval_contract 단일경로(NW lag-3, backtested).
  자체합성 backtest 금지. in-sample(train) 과 OOS(walk-forward) 분리 export.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_gpu_sweep_cbe.py [--variant C|CB|CBE|ALL]
산출: stage_artifacts/WT_DPL_GPU_SWEEP/cbe_{variant}_net_returns.parquet (+ _is for in-sample)
      cbe_sweep_results.json
"""
import os
import sys
import json
import itertools
import argparse
import numpy as np
import pandas as pd
import torch

# 기존 sweep 모듈 재사용 (DPLNet / projection / DSR / load_panel)
THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, THIS_DIR)
import dpl_gpu_sweep as base  # noqa: E402

torch.set_default_dtype(torch.float64)

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = base.OUT_DIR
PANEL = base.PANEL
BENCH = base.BENCH
REGIME = os.path.join(OUT_DIR, "regime_monthly.parquet")
FIMP = os.path.join(OUT_DIR, "feature_importance.json")

LOCKBOX = base.LOCKBOX
CAP = base.CAP
ACTIVE_MAX = base.ACTIVE_MAX           # entry_n = 25 (신규 진입 랭킹)
KEEP_N = int(os.environ.get("DPL_KEEP_N", "32"))   # hysteresis: 직전 보유 유지 랭킹(env override)
COST_BPS_ONEWAY = base.COST_BPS_ONEWAY
ANNUALIZE = base.ANNUALIZE
DEVICE = base.DEVICE

IMP_THRESHOLD = 0.05                   # E: permutation importance cutoff


# ════════════════════════════════════════════════════════════════════
# 데이터 로드 (panel + benchmark + regime + pruned feature list)
# ════════════════════════════════════════════════════════════════════
def load_all(variant):
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]

    # E: prune to importance > threshold
    if "E" in variant:
        imp = json.load(open(FIMP))["permutation_importance"]
        keep = [f for f, v in imp.items() if v > IMP_THRESHOLD and f in feat_cols]
        feat_cols = keep
        print(f"[cbe] E pruning: {len(feat_cols)} features (importance>{IMP_THRESHOLD})")

    # B: month regime score (PIT t-1)
    regime = None
    if "B" in variant:
        regime = pd.read_parquet(REGIME)[["ym", "regime_score"]].copy()
        regime["ym"] = regime["ym"].astype(str)
        regime = dict(zip(regime["ym"], regime["regime_score"]))
        print(f"[cbe] B overlay: regime_score for {len(regime)} months loaded")
    return panel, bm, feat_cols, regime


# ════════════════════════════════════════════════════════════════════
# C2 — Hysteresis buffer weight construction (inference time, hard-encode)
# ════════════════════════════════════════════════════════════════════
def hysteresis_select(mu_all_np, tickers, prev_holdings, entry_n=ACTIVE_MAX, keep_n=KEEP_N):
    """직전월 보유(prev_holdings)는 keep_n 랭킹까지 유지, 신규는 entry_n 진입.

    반환: 선택 ticker index(panel local), 최종 selected 종목수<=entry_n (FLOW buffer 패턴).
    로직:
      rank = argsort desc mu.  held_kept = {t in prev_holdings : rank(t) < keep_n}.
      new_slots = entry_n - len(held_kept).  new = top new_slots from non-held by rank.
      최종 = held_kept ∪ new  (정확히 entry_n 종목 — long-only top-N 정합).
    """
    order = np.argsort(-mu_all_np)               # desc
    rank = np.empty_like(order)
    rank[order] = np.arange(len(order))
    tk = np.asarray(tickers)
    held_mask = np.array([t in prev_holdings for t in tk])
    # 유지: 직전 보유 AND rank < keep_n
    keep_idx = np.where(held_mask & (rank < keep_n))[0]
    # 유지 종목이 entry_n 초과면 rank 상위 entry_n 만
    if len(keep_idx) > entry_n:
        keep_idx = keep_idx[np.argsort(rank[keep_idx])][:entry_n]
    n_new = entry_n - len(keep_idx)
    if n_new > 0:
        cand = np.where(~np.isin(np.arange(len(tk)), keep_idx))[0]
        cand = cand[np.argsort(rank[cand])][:n_new]
        sel = np.concatenate([keep_idx, cand])
    else:
        sel = keep_idx
    return sel


# ════════════════════════════════════════════════════════════════════
# 학습 (C1 active-alpha Sharpe loss) — 배치 GPU
# ════════════════════════════════════════════════════════════════════
def train_dpl_cbe(cache, n_feat, train_months, cfg, bm_map):
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
    # C1: benchmark monthly per train-month (active = net - bm)
    bm_vec = torch.tensor([bm_map.get(m, 0.0) for m in valid], device=DEVICE)  # [B]

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
        W = base.weights_from_scores_batch(MU_c, cap=CAP, temp=temp)        # [B,k]
        gross = (W * R).sum(dim=1)                                         # [B]
        Wdense = torch.zeros(B, N_T, device=DEVICE)
        Wdense.scatter_(1, TID, W)
        Wprev = torch.zeros_like(Wdense)
        Wprev[1:] = Wdense[:-1].detach()
        traded = (Wdense - Wprev).abs().sum(dim=1)
        cost = traded * COST_BPS_ONEWAY / 1e4
        net = gross - cost
        active = net - bm_vec                                             # ★ C1 active alpha
        sharpe = active.mean() / (active.std() + 1e-6) * sqrtA            # ★ active Sharpe
        mean_traded = traded.mean()
        mean_risk = (W * W).sum(dim=1).mean()
        loss = -sharpe + gam * mean_traded + lam * mean_risk
        loss.backward()
        opt.step()
    return model


@torch.no_grad()
def dpl_weights_cbe(model, cache, m, cfg, prev_holdings, regime):
    """C2 buffer + B overlay 적용한 월 m의 weight (inference).

    반환: dict{ticker: w_risky}, exposure(=Σw_risky), bucket(미사용).
    """
    if m not in cache or cache[m]["n"] < ACTIVE_MAX:
        return None, None
    c = cache[m]
    mu_all = model(c["X"])
    mu_np = mu_all.detach().cpu().numpy()
    tk = c["tk"]
    if cfg.get("buffer", True) and prev_holdings:
        sel = hysteresis_select(mu_np, tk, prev_holdings,
                                entry_n=ACTIVE_MAX, keep_n=KEEP_N)
    else:
        sel = np.argsort(-mu_np)[:ACTIVE_MAX]
    mu_sel = torch.tensor(mu_np[sel], device=DEVICE)
    mu_c = (mu_sel - mu_sel.mean()) / (mu_sel.std() + 1e-6)
    w = base.weights_from_scores(mu_c, cap=CAP, temp=cfg["temp"]).detach().cpu().numpy()
    tk_sel = tk[sel]
    # B: regime cash node — risky exposure scaled by regime_score prior
    exposure = 1.0
    if regime is not None:
        exposure = float(regime.get(m, 1.0))   # PIT t-1 regime prior (1=full, 0.25=crisis)
    w_risky = w * exposure                       # w_cash = 1 - exposure (cash ret 0)
    return dict(zip(tk_sel, w_risky)), exposure


def walk_forward_cbe(cache, n_feat, cfg, months, bm_map, regime, split="oos"):
    """다중분할 walk-forward. split='oos' → OOS 1-step. split='is' → train구간 fit-period 평가.

    C2 buffer: prev_holdings 상태 유지하며 순차 진행(turnover 실측).
    """
    min_train = cfg["min_train"]; train_window = cfg["lookback"]; refit_every = 12
    rows = []; model = None; start_i = min_train; prev_holdings = set()
    for i in range(start_i, len(months)):
        m = months[i]
        if (model is None) or ((i - start_i) % refit_every == 0):
            tr = months[max(0, i - train_window):i]
            model = train_dpl_cbe(cache, n_feat, tr, cfg, bm_map)
        wdict, exposure = dpl_weights_cbe(model, cache, m, cfg, prev_holdings, regime)
        if wdict is None:
            continue
        prev_holdings = set(wdict.keys())
        for t, v in wdict.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


def walk_forward_insample(cache, n_feat, cfg, months, bm_map, regime):
    """in-sample: 전체 train구간(<=lockbox)으로 1회 fit 후 동일구간 평가(과적합 상한 진단).

    OOS 와 분리 보고 — SECTOR_REL cherry-pick 교훈(in-sample 낙관 명시).
    """
    tr = months[:]                                  # 전체 사용 가능 구간
    model = train_dpl_cbe(cache, n_feat, tr, cfg, bm_map)
    rows = []; prev_holdings = set()
    for m in months:
        wdict, _ = dpl_weights_cbe(model, cache, m, cfg, prev_holdings, regime)
        if wdict is None:
            continue
        prev_holdings = set(wdict.keys())
        for t, v in wdict.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


# ════════════════════════════════════════════════════════════════════
# net active return series (cash node aware: gross over risky only, w_cash ret=0)
# ════════════════════════════════════════════════════════════════════
def net_return_series(wdf, rets, bm):
    wj = wdf.merge(rets, on=["ym", "Ticker"], how="left")
    wj["Ret_1m"] = wj["Ret_1m"].fillna(0.0)
    wj["_wr"] = wj["w"] * wj["Ret_1m"]
    gross = wj.groupby("ym")["_wr"].sum().rename("port_gross")   # cash(1-Σw) ret 0 → 자동 반영
    traded = {}; prev = {}
    for m in sorted(wdf["ym"].unique()):
        cur = dict(zip(wdf[wdf["ym"] == m]["Ticker"], wdf[wdf["ym"] == m]["w"]))
        keys = set(cur) | set(prev)
        # cash 이동(Σw 변화)도 turnover에 포함: |Σcur - Σprev| 는 risky 변동 합으로 이미 cover
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
def run_variant(variant, focused_grid=True):
    print(f"\n{'='*64}\n[cbe] VARIANT = {variant}\n{'='*64}")
    panel, bm, feat_cols, regime = load_all(variant)
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    bm_map = dict(zip(bm["ym"], bm["BM_Ret_1m"]))
    months = sorted(panel["ym"].unique())
    lock = LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    print(f"[cbe] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}] device={DEVICE}")
    cache = base.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    # focused grid around incumbent best (cell 37: gamma1.5/temp1.0/lookback72/depth3/width32)
    # + buffer 항상 ON(C2), gamma 변주로 TO 추가 압박, temp 변주로 집중도.
    if focused_grid:
        grid = {
            "lam": [0.0], "gamma": [0.5, 1.5], "lookback": [72],
            "depth": [3], "width": [32], "l2": [1e-3], "dropout": [0.1],
            "temp": [1.0, 1.5], "lr": [5e-3], "epochs": [40], "min_train": [60],
            "buffer": [True],
        }
    else:
        grid = {
            "lam": [0.0], "gamma": [1.5], "lookback": [72], "depth": [3],
            "width": [32], "l2": [1e-3], "dropout": [0.1], "temp": [1.0],
            "lr": [5e-3], "epochs": [40], "min_train": [60], "buffer": [True],
        }
    if os.environ.get("DPL_SMOKE") == "1":
        grid = {k: [v[0]] for k, v in grid.items()}
        grid["epochs"] = [5]
        print("[cbe] SMOKE — 1 cell 5 epochs")
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    n_trials = len(combos)
    print(f"[cbe] grid cells (this variant) = {n_trials}")

    results = []; best = None; best_oos = None
    for ci, vals in enumerate(combos):
        cfg = dict(zip(keys, vals))
        torch.manual_seed(7); np.random.seed(7)
        wdf = walk_forward_cbe(cache, n_feat, cfg, months, bm_map, regime, split="oos")
        if wdf.empty:
            continue
        s = net_return_series(wdf, rets, bm)
        sr = sharpe_active(s)
        to_ann = float(s["traded"].mean() * 12)
        s_sorted = s.sort_values("ym").reset_index(drop=True)
        thirds = np.array_split(s_sorted, 3)
        sub = [sharpe_active(t) for t in thirds if len(t) >= 6]
        sr_min = float(np.nanmin(sub)) if sub else np.nan
        rec = {"cell": ci, **{k: cfg[k] for k in cfg}, "net_active_sr": sr,
               "turnover_ann": to_ann, "n_oos_months": int(s["ym"].nunique()),
               "sr_min_subperiod": sr_min, "sub_period_srs": [round(x, 3) for x in sub]}
        results.append(rec)
        print(f"[cbe] {variant} cell {ci+1}/{n_trials} OOS_SR={sr:.3f} TO={to_ann:.2f} "
              f"sub_min={sr_min:.3f} cfg(g={cfg['gamma']},temp={cfg['temp']})")
        if (best is None) or (np.nan_to_num(sr, nan=-9) > np.nan_to_num(best["net_active_sr"], nan=-9)):
            best = rec; best_oos = s.copy(); best_cfg = cfg

    if best is None:
        print(f"[cbe] {variant}: no valid cell"); return None

    # in-sample for best cfg (분리 보고)
    torch.manual_seed(7); np.random.seed(7)
    wdf_is = walk_forward_insample(cache, n_feat, best_cfg, months, bm_map, regime)
    s_is = net_return_series(wdf_is, rets, bm)
    sr_is = sharpe_active(s_is); to_is = float(s_is["traded"].mean() * 12)
    best["insample_active_sr"] = sr_is
    best["insample_turnover_ann"] = to_is

    # export OOS + IS series for R contract eval
    export_series(best_oos, f"CBE_{variant}", f"cbe_{variant}_net_returns.parquet")
    export_series(s_is, f"CBE_{variant}_IS", f"cbe_{variant}_is_net_returns.parquet")

    # DSR (honest: this variant n_trials; cumulative tracked in aggregate by caller)
    active = (best_oos["ret_net"] - best_oos["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)) if len(active) > 3 else 0.0
    kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0
    best["DSR_thisvariant"] = base.deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, skew, kurt)
    best["active_skew"] = skew; best["active_kurt"] = kurt
    print(f"[cbe] {variant} BEST cell={best['cell']} OOS_SR={best['net_active_sr']:.3f} "
          f"TO={best['turnover_ann']:.2f} IS_SR={sr_is:.3f} IS_TO={to_is:.2f} "
          f"DSR(thisvar n={n_trials})={best['DSR_thisvariant']:.3f}")
    return {"variant": variant, "n_trials_thisvariant": n_trials,
            "n_feature_cols": len(feat_cols), "best": best,
            "all_cells": sorted(results, key=lambda r: -np.nan_to_num(r["net_active_sr"], nan=-9))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="ALL", choices=["C", "CB", "CBE", "ALL"])
    ap.add_argument("--single", action="store_true", help="1 cell only (fast)")
    args = ap.parse_args()
    variants = ["C", "CB", "CBE"] if args.variant == "ALL" else [args.variant]
    out = {"device": DEVICE, "lockbox": str(LOCKBOX.date()),
           "keep_n": KEEP_N, "entry_n": ACTIVE_MAX, "imp_threshold": IMP_THRESHOLD,
           "variants": {}}
    cum_trials = 96  # 기존 GPU sweep 96-trial 누적 (DSR honest cumulative)
    for v in variants:
        r = run_variant(v, focused_grid=not args.single)
        if r:
            cum_trials += r["n_trials_thisvariant"]
            r["best"]["n_trials_cumulative"] = cum_trials
            # cumulative DSR (전체 탐색 trial 누적)
            bs = pd.read_parquet(os.path.join(OUT_DIR, f"cbe_{v}_net_returns.parquet"))
            active = (bs["ret_net"] - bs["BM_Ret"]).values
            from scipy import stats as st
            skew = float(st.skew(active)); kurt = float(st.kurtosis(active, fisher=False))
            r["best"]["DSR_cumulative"] = base.deflated_sharpe_ratio(
                r["best"]["net_active_sr"], len(active), cum_trials, skew, kurt)
            out["variants"][v] = r
    out["n_trials_cumulative_final"] = cum_trials
    with open(os.path.join(OUT_DIR, "cbe_sweep_results.json"), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, default=float)
    print(f"\n[cbe] results -> {os.path.join(OUT_DIR, 'cbe_sweep_results.json')}")
    print(f"[cbe] cumulative n_trials (96 base + CBE) = {cum_trials}")


if __name__ == "__main__":
    main()
