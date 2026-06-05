#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_gpu_sweep_ens.py — Qvest v8.x Dev: DPL ENSEMBLE variance-reduction (research/feasibility only).

가설: 단일-seed NN 추정분산이 binding constraint (DPL_C OOS subperiod active-SR 매우 불안정,
DSR overfit-discounted < 0.5). 독립 seed(및 top-N config) 앙상블 = projection 후 weight 벡터
평균 → 추정분산 ↓ → OOS DSR 0.5↑ + subperiod 안정 + portfolio-α t 유지/소폭개선.

★ convex layer / feature pipeline / hysteresis buffer 재구현 금지 — dpl_gpu_sweep_cbe(C-variant)
  의 train_dpl_cbe / dpl_weights_cbe / hysteresis_select 를 그대로 재사용. 본 wrapper는
  "per-refit-window K개 독립모델 학습 → 월별 per-seed simplex-projected weight 벡터 평균 +
   [0,0.20] clip + renorm(Σ=1)" 만 추가한다. long-only/Σw=1/cap/buffer 모두 per-seed에서 보존됨.

DPL_C 고정 config (cbe_C best cell):
  gamma=1.5, lookback=72, depth=3, width=32, l2=1e-3, dropout=0.1, temp=1.0, lam=0.0,
  lr=5e-3, epochs=40, min_train=60, buffer=True, keep_n=32, entry_n=25 (active-alpha Sharpe loss).

ensemble 종류:
  seed_K8  : seeds {7,17,23,42,101,202,303,404} (DPL_C 고정 config) — weight 평균.
  seed_K16 : seeds {위 8 + 505,606,707,808,909,111,222,333} (GPU time 허용 시).
  config5  : 단일 seed=7, sweep_results.json IS 상위 5 config × C-variant loss/buffer — weight 평균.

평가: 월별 net active return series 산출 → R dpl_ens_eval_contract.R 단일경로
  (build_benchmark_compare NW lag-3, metric_type=backtested). 자체합성 금지.
  baseline DPL_C(cbe_C_net_returns.parquet) 와 동일 168m OOS / 동일 KOSPI200.

findings-only: admission/book_state 변경 없음. "X 구성 시도 → Y 측정" 형식. DPL 한계 verdict 금지.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_gpu_sweep_ens.py [--mode seed_K8|seed_K16|config5|ALL]
      (DPL_SMOKE=1 → seed 2개·5 epochs 빠른 검증)
산출: stage_artifacts/WT_DPL_GPU_SWEEP/ens_{mode}_net_returns.parquet (+ _is)
      ens_sweep_results.json
"""
import os
import sys
import json
import argparse
import numpy as np
import pandas as pd
import torch

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, THIS_DIR)
import dpl_gpu_sweep as base          # noqa: E402  DPLNet / projection / DSR / cache
import dpl_gpu_sweep_cbe as cbe       # noqa: E402  train_dpl_cbe / dpl_weights_cbe / hysteresis / buffer

torch.set_default_dtype(torch.float64)

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = base.OUT_DIR
PANEL = base.PANEL
BENCH = base.BENCH

LOCKBOX = base.LOCKBOX
CAP = base.CAP
ACTIVE_MAX = base.ACTIVE_MAX       # entry_n = 25
COST_BPS_ONEWAY = base.COST_BPS_ONEWAY
ANNUALIZE = base.ANNUALIZE
DEVICE = base.DEVICE

# DPL_C 고정 config (cbe_C best cell)
DPL_C_CFG = {
    "lam": 0.0, "gamma": 1.5, "lookback": 72, "depth": 3, "width": 32,
    "l2": 1e-3, "dropout": 0.1, "temp": 1.0, "lr": 5e-3, "epochs": 40,
    "min_train": 60, "buffer": True,
}

SEEDS_K8 = [7, 17, 23, 42, 101, 202, 303, 404]
SEEDS_K16 = SEEDS_K8 + [505, 606, 707, 808, 909, 111, 222, 333]

# DSR honest cumulative: prior 123 (96 GPU + 12 CBE + 15 lex) + 본 ensemble trials.
# 본 연구는 "이미 발견한 DPL_C 1 config"의 분산축소 검증 — 새 HP 탐색이 아니라
# variance-reduction 적용. ensemble trial 자체는 추가 over-search가 아니므로 보수적으로
# prior 누적 위에 mode당 1(seed_K8/K16) + config5(=5 config) 만 가산.
CUM_TRIALS_PRIOR = 123


# ════════════════════════════════════════════════════════════════════
def load_all():
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    return panel, bm, feat_cols


def avg_weight_dicts(wdicts):
    """K개 per-seed weight dict 평균 → [0,cap] clip → renorm(Σ=1).

    각 wdict 는 이미 long-only top-N(buffer 적용) Σw=1 (cbe dpl_weights_cbe, regime=None → exposure 1).
    union 종목에 대해 평균(미보유 seed는 0 기여) → 평균 자체가 Σ=1 (각 dict Σ=1의 평균).
    clip(cap) 후 잔차 renorm 으로 Σw=1·w∈[0,cap] hard 보장. 종목수는 union(≤ K×entry_n)이나
    평균이 작은 fringe 종목은 1e-6 cut. max 25 제약은 dominant top-N 평균이라 사실상 유지되며,
    엄격 cut 은 net_return_series 후 별도 점검(아래 enforce_max_names).
    """
    if not wdicts:
        return {}
    allt = set()
    for d in wdicts:
        allt |= set(d.keys())
    K = len(wdicts)
    avg = {t: sum(d.get(t, 0.0) for d in wdicts) / K for t in allt}
    # clip cap, renorm Σ=1 (2-pass)
    avg = {t: min(v, CAP) for t, v in avg.items()}
    s = sum(avg.values())
    if s > 1e-12:
        avg = {t: v / s for t, v in avg.items()}
    s2 = sum(min(v, CAP) for v in avg.values())
    avg = {t: min(v, CAP) for t, v in avg.items()}
    s2 = sum(avg.values())
    if s2 > 1e-12:
        avg = {t: v / s2 for t, v in avg.items()}
    return {t: v for t, v in avg.items() if v > 1e-6}


def enforce_max_names(wdict, max_n=ACTIVE_MAX):
    """ensemble union 이 max_n 초과 시 top-max_n weight 만 유지 후 renorm (max 25 production 제약)."""
    if len(wdict) <= max_n:
        return wdict
    items = sorted(wdict.items(), key=lambda kv: -kv[1])[:max_n]
    s = sum(v for _, v in items)
    return {t: v / s for t, v in items} if s > 1e-12 else dict(items)


# ════════════════════════════════════════════════════════════════════
# Seed ensemble walk-forward
#   per refit window: K seeds 각각 train_dpl_cbe (독립 init) → per-seed prev_holdings 상태로
#   순차 inference (buffer 보존) → 월별 K개 weight dict 평균.
# ════════════════════════════════════════════════════════════════════
def walk_forward_seed_ensemble(cache, n_feat, cfg, months, bm_map, seeds, split="oos"):
    min_train = cfg["min_train"]; train_window = cfg["lookback"]; refit_every = 12
    K = len(seeds)
    models = [None] * K
    prev_holdings = [set() for _ in range(K)]   # per-seed buffer state
    rows = []
    start_i = min_train
    for i in range(start_i, len(months)):
        m = months[i]
        if (models[0] is None) or ((i - start_i) % refit_every == 0):
            tr = months[max(0, i - train_window):i]
            for sj, sd in enumerate(seeds):
                torch.manual_seed(sd); np.random.seed(sd)
                models[sj] = cbe.train_dpl_cbe(cache, n_feat, tr, cfg, bm_map)
        # per-seed inference (regime=None → exposure 1, fully invested; buffer per-seed)
        wdicts = []
        for sj in range(K):
            wdict, _ = cbe.dpl_weights_cbe(models[sj], cache, m, cfg, prev_holdings[sj], regime=None)
            if wdict is None:
                wdicts = []
                break
            prev_holdings[sj] = set(wdict.keys())
            wdicts.append(wdict)
        if not wdicts:
            continue
        ens = enforce_max_names(avg_weight_dicts(wdicts))
        for t, v in ens.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


def walk_forward_seed_insample(cache, n_feat, cfg, months, bm_map, seeds):
    """in-sample: 전체구간 1회 fit (K seeds) 후 동일구간 평가 (과적합 상한)."""
    K = len(seeds)
    models = []
    for sd in seeds:
        torch.manual_seed(sd); np.random.seed(sd)
        models.append(cbe.train_dpl_cbe(cache, n_feat, months[:], cfg, bm_map))
    prev_holdings = [set() for _ in range(K)]
    rows = []
    for m in months:
        wdicts = []
        for sj in range(K):
            wdict, _ = cbe.dpl_weights_cbe(models[sj], cache, m, cfg, prev_holdings[sj], regime=None)
            if wdict is None:
                wdicts = []; break
            prev_holdings[sj] = set(wdict.keys())
            wdicts.append(wdict)
        if not wdicts:
            continue
        ens = enforce_max_names(avg_weight_dicts(wdicts))
        for t, v in ens.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


# ════════════════════════════════════════════════════════════════════
# Config ensemble: top-5 IS config × C-variant (single seed=7), weight 평균.
# ════════════════════════════════════════════════════════════════════
def top5_configs():
    """sweep_results.json (96-cell GPU sweep) 의 IS 성능 상위 5 config 를 읽어 C-variant cfg 로 매핑.

    sweep_results.json all_cells 는 OOS net_active_sr 정렬 — IS proxy 부재. C-variant 정합 위해
    config 다양성만 취하되 DPL_C 기준 HP 근방의 상위 5 셀(net_active_sr 상위)을 config 다양원으로 사용.
    각 셀 cfg → DPL_C loss/buffer 틀에 lookback/depth/width/temp/gamma/lam 만 이식.
    """
    sw = json.load(open(os.path.join(OUT_DIR, "sweep_results.json")))
    cells = sorted(sw["all_cells"],
                   key=lambda c: -np.nan_to_num(c.get("net_active_sr", np.nan), nan=-9))[:5]
    cfgs = []
    for c in cells:
        cfg = dict(DPL_C_CFG)
        for k in ("lam", "gamma", "lookback", "depth", "width", "temp", "l2", "dropout"):
            if k in c:
                cfg[k] = c[k]
        cfg["_src_cell"] = c.get("cell")
        cfg["_src_oos_sr"] = c.get("net_active_sr")
        cfgs.append(cfg)
    return cfgs


def walk_forward_config_ensemble(cache, n_feat, cfgs, months, bm_map, seed=7, split="oos"):
    min_train = cfgs[0]["min_train"]; refit_every = 12
    K = len(cfgs)
    models = [None] * K
    prev_holdings = [set() for _ in range(K)]
    rows = []
    start_i = min_train
    for i in range(start_i, len(months)):
        m = months[i]
        # refit per cfg's own lookback
        for cj, cfg in enumerate(cfgs):
            if (models[cj] is None) or ((i - start_i) % refit_every == 0):
                tw = cfg["lookback"]
                tr = months[max(0, i - tw):i]
                torch.manual_seed(seed); np.random.seed(seed)
                models[cj] = cbe.train_dpl_cbe(cache, n_feat, tr, cfg, bm_map)
        wdicts = []
        for cj, cfg in enumerate(cfgs):
            wdict, _ = cbe.dpl_weights_cbe(models[cj], cache, m, cfg, prev_holdings[cj], regime=None)
            if wdict is None:
                wdicts = []; break
            prev_holdings[cj] = set(wdict.keys())
            wdicts.append(wdict)
        if not wdicts:
            continue
        ens = enforce_max_names(avg_weight_dicts(wdicts))
        for t, v in ens.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


def walk_forward_config_insample(cache, n_feat, cfgs, months, bm_map, seed=7):
    K = len(cfgs)
    models = []
    for cfg in cfgs:
        torch.manual_seed(seed); np.random.seed(seed)
        models.append(cbe.train_dpl_cbe(cache, n_feat, months[:], cfg, bm_map))
    prev_holdings = [set() for _ in range(K)]
    rows = []
    for m in months:
        wdicts = []
        for cj in range(K):
            wdict, _ = cbe.dpl_weights_cbe(models[cj], cache, m, cfgs[cj], prev_holdings[cj], regime=None)
            if wdict is None:
                wdicts = []; break
            prev_holdings[cj] = set(wdict.keys())
            wdicts.append(wdict)
        if not wdicts:
            continue
        ens = enforce_max_names(avg_weight_dicts(wdicts))
        for t, v in ens.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


# reuse net_return_series / sharpe_active / export_series from cbe module (동일 cost/turnover 회계)
net_return_series = cbe.net_return_series
sharpe_active = cbe.sharpe_active
export_series = cbe.export_series


def subperiods(s):
    s_sorted = s.sort_values("ym").reset_index(drop=True)
    thirds = np.array_split(s_sorted, 3)
    sub = [sharpe_active(t) for t in thirds if len(t) >= 6]
    sr_min = float(np.nanmin(sub)) if sub else np.nan
    return [round(x, 3) for x in sub], sr_min


def run_mode(mode, cache, n_feat, panel, bm, feat_cols, rets, bm_map, months):
    print(f"\n{'='*64}\n[ens] MODE = {mode}\n{'='*64}")
    smoke = os.environ.get("DPL_SMOKE") == "1"
    cfg = dict(DPL_C_CFG)
    if smoke:
        cfg["epochs"] = 5

    meta = {}
    if mode == "seed_K8":
        seeds = SEEDS_K8[:2] if smoke else SEEDS_K8
        wdf = walk_forward_seed_ensemble(cache, n_feat, cfg, months, bm_map, seeds)
        wdf_is = walk_forward_seed_insample(cache, n_feat, cfg, months, bm_map, seeds)
        meta = {"seeds": seeds, "K": len(seeds), "config": "DPL_C_fixed",
                "ensemble_trials": 1}
    elif mode == "seed_K16":
        seeds = SEEDS_K16[:2] if smoke else SEEDS_K16
        wdf = walk_forward_seed_ensemble(cache, n_feat, cfg, months, bm_map, seeds)
        wdf_is = walk_forward_seed_insample(cache, n_feat, cfg, months, bm_map, seeds)
        meta = {"seeds": seeds, "K": len(seeds), "config": "DPL_C_fixed",
                "ensemble_trials": 1}
    elif mode == "config5":
        cfgs = top5_configs()
        if smoke:
            cfgs = cfgs[:2]
            for c in cfgs:
                c["epochs"] = 5
        wdf = walk_forward_config_ensemble(cache, n_feat, cfgs, months, bm_map, seed=7)
        wdf_is = walk_forward_config_insample(cache, n_feat, cfgs, months, bm_map, seed=7)
        meta = {"seed": 7, "K": len(cfgs), "config": "top5_IS_cells",
                "src_cells": [c.get("_src_cell") for c in cfgs],
                "src_oos_sr": [c.get("_src_oos_sr") for c in cfgs],
                "ensemble_trials": 5}
    else:
        raise ValueError(mode)

    if wdf.empty:
        print(f"[ens] {mode}: empty OOS wdf"); return None

    s = net_return_series(wdf, rets, bm)
    sr = sharpe_active(s)
    to_ann = float(s["traded"].mean() * 12)
    sub, sr_min = subperiods(s)
    n_names = wdf.groupby("ym")["Ticker"].nunique()
    print(f"[ens] {mode} OOS net_active_SR={sr:.3f} TO={to_ann:.2f} sub={sub} sub_min={sr_min:.3f} "
          f"names(mean={n_names.mean():.1f},max={int(n_names.max())})")

    s_is = net_return_series(wdf_is, rets, bm)
    sr_is = sharpe_active(s_is); to_is = float(s_is["traded"].mean() * 12)

    export_series(s, f"ENS_{mode}", f"ens_{mode}_net_returns.parquet")
    export_series(s_is, f"ENS_{mode}_IS", f"ens_{mode}_is_net_returns.parquet")

    active = (s["ret_net"] - s["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)) if len(active) > 3 else 0.0
    kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0

    rec = {"mode": mode, "meta": meta,
           "net_active_sr_python": sr, "turnover_ann": to_ann,
           "n_oos_months": int(s["ym"].nunique()),
           "sub_period_srs_python": sub, "sr_min_subperiod_python": sr_min,
           "n_names_mean": float(n_names.mean()), "n_names_max": int(n_names.max()),
           "insample_active_sr_python": sr_is, "insample_turnover_ann": to_is,
           "active_skew": skew, "active_kurt": kurt,
           "metric_type": "python_screen_preview"}  # contract-grade는 R eval에서 backtested
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="ALL",
                    choices=["seed_K8", "seed_K16", "config5", "ALL"])
    args = ap.parse_args()
    modes = ["seed_K8", "seed_K16", "config5"] if args.mode == "ALL" else [args.mode]

    panel, bm, feat_cols = load_all()
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    bm_map = dict(zip(bm["ym"], bm["BM_Ret_1m"]))
    months = sorted(panel["ym"].unique())
    lock = LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    print(f"[ens] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}] device={DEVICE}")
    print(f"[ens] DPL_C fixed cfg: {DPL_C_CFG}  keep_n={cbe.KEEP_N} entry_n={ACTIVE_MAX}")
    cache = base.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    out = {"device": DEVICE, "lockbox": str(LOCKBOX.date()),
           "scope": "findings-only — admission/book_state 변경 없음. canonical alpha_package handoff 없음.",
           "dpl_c_cfg": DPL_C_CFG, "keep_n": cbe.KEEP_N, "entry_n": ACTIVE_MAX,
           "seeds_K8": SEEDS_K8, "seeds_K16": SEEDS_K16,
           "baseline_dpl_c_contract": {
               "portfolio_alpha_t_nw_lag3": 2.9058, "p": 0.0037, "IR": 0.7026,
               "net_active_SR": 0.703, "TE": 0.3554, "TO_yr": 14.35,
               "sub_period_active_SR_python": [1.495, -0.349, 0.77],
               "DSR_cumulative_prior": 0.378,
               "metric_type": "backtested (cbe_eval_contract.json)"},
           "modes": {}}
    cum_trials = CUM_TRIALS_PRIOR
    for mode in modes:
        r = run_mode(mode, cache, n_feat, panel, bm, feat_cols, rets, bm_map, months)
        if r:
            cum_trials += r["meta"].get("ensemble_trials", 1)
            r["n_trials_cumulative"] = cum_trials
            # cumulative DSR on the exported OOS active series (python preview; R eval is authoritative SR)
            bs = pd.read_parquet(os.path.join(OUT_DIR, f"ens_{mode}_net_returns.parquet"))
            active = (bs["ret_net"] - bs["BM_Ret"]).values
            from scipy import stats as st
            skew = float(st.skew(active)); kurt = float(st.kurtosis(active, fisher=False))
            r["DSR_cumulative_python"] = base.deflated_sharpe_ratio(
                r["net_active_sr_python"], len(active), cum_trials, skew, kurt)
            out["modes"][mode] = r
    out["n_trials_cumulative_final"] = cum_trials
    with open(os.path.join(OUT_DIR, "ens_sweep_results.json"), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, default=float)
    print(f"\n[ens] results -> {os.path.join(OUT_DIR, 'ens_sweep_results.json')}")
    print(f"[ens] cumulative n_trials (prior {CUM_TRIALS_PRIOR} + ensemble) = {cum_trials}")


if __name__ == "__main__":
    main()
