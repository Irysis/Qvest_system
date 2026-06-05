#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_gpu_sweep_ens2.py — Qvest v8.x Dev: DPL SCORE-SPACE ensemble + EPISTEMIC down-weighting
(research/feasibility only — no admission/book_state change, no canonical handoff).

배경(직전 ENS run, ENS_FINDINGS.json):
  weight-space 앙상블(per-seed projected weight 평균)은 TE/subperiod 안정화에는 성공했으나
  α-t/IR/DSR 하락(K16 α-t 2.387 < baseline DPL_C 2.906). 진단: seed들이 '어느 종목'에 불일치
  → 최종 weight 평균이 EW-중심으로 끌려 conviction 희석. binding constraint = epistemic
  (name-selection) 모델불확실성, estimation noise 아님.

본 run 가설:
  ① SCORE_AVG — projection '이전'의 per-name 점수 μ̂(network output, full universe)를 seed간
     평균 → 단 1회 projection. weight-space 평균이 파괴한 conviction을 score space에서 보존
     (평균 분자 유지 시도).
  ② EPI_DW(k) — μ̃ = mean_s(μ̂) − k·SE_s(μ̂), SE_s = seed간 μ̂ per-name 표준오차. seed 불일치
     큰 종목(진단된 실패 모드)만 명시적으로 down-weight (research_philosophy ③ uncertainty-aware).
     k ∈ {0.5, 1.0, 1.5}.
  ③ CONSENSUS(optional) — K seeds 중 ⌈K/2⌉ 이상에서 top-quantile(entry_n)에 든 종목만 후보로
     남긴 뒤 평균 μ̂로 projection. 합의신호 강화.

★ convex layer / feature pipeline / hysteresis buffer 재구현 금지 — dpl_gpu_sweep_cbe 의
  train_dpl_cbe / hysteresis_select / weights_from_scores / net_return_series 를 그대로 재사용.
  본 wrapper는 "per-month per-seed μ̂(full universe) 수집 → score-space 결합(평균/μ̃/consensus)
  → 단일 hysteresis_select → 단일 weights_from_scores projection" 만 추가한다.
  (직전 ens wrapper와의 유일한 차이: 평균 대상이 projected weight → pre-projection 점수 μ̂)

DPL_C 고정 config (cbe_C best cell):
  gamma=1.5, lookback=72, depth=3, width=32, l2=1e-3, dropout=0.1, temp=1.0, lam=0.0,
  lr=5e-3, epochs=40, min_train=60, buffer=True, keep_n=32, entry_n=25 (active-alpha Sharpe loss).

K16 seeds: {7,17,23,42,101,202,303,404,505,606,707,808,909,111,222,333}.

평가: 월별 net active return series 산출 → R dpl_ens2_eval_contract.R 단일경로
  (build_benchmark_compare NW lag-3, metric_type=backtested). 자체합성 금지.
  baseline DPL_C(cbe_C_net_returns.parquet) 동일 168m OOS / 동일 KOSPI200.

findings-only: admission/book_state 변경 없음. "X 결합 시도 → Y 측정" 형식. DPL 한계 verdict 금지.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_gpu_sweep_ens2.py [--mode ALL|score_avg|epi_dw|consensus]
      (DPL_SMOKE=1 → seed 2개·5 epochs 빠른 검증)
산출: stage_artifacts/WT_DPL_GPU_SWEEP/ens2_{tag}_net_returns.parquet (+ _is)
      ens2_sweep_results.json
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
import dpl_gpu_sweep as base          # noqa: E402  DPLNet / projection / weights_from_scores / DSR / cache
import dpl_gpu_sweep_cbe as cbe       # noqa: E402  train_dpl_cbe / hysteresis_select / net_return_series

torch.set_default_dtype(torch.float64)

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = base.OUT_DIR
PANEL = base.PANEL
BENCH = base.BENCH

LOCKBOX = base.LOCKBOX
CAP = base.CAP
ACTIVE_MAX = base.ACTIVE_MAX       # entry_n = 25
KEEP_N = cbe.KEEP_N                 # 32 (hysteresis keep rank)
COST_BPS_ONEWAY = base.COST_BPS_ONEWAY
ANNUALIZE = base.ANNUALIZE
DEVICE = base.DEVICE

DPL_C_CFG = {
    "lam": 0.0, "gamma": 1.5, "lookback": 72, "depth": 3, "width": 32,
    "l2": 1e-3, "dropout": 0.1, "temp": 1.0, "lr": 5e-3, "epochs": 40,
    "min_train": 60, "buffer": True,
}

SEEDS_K16 = [7, 17, 23, 42, 101, 202, 303, 404, 505, 606, 707, 808, 909, 111, 222, 333]
K_VALUES = [0.5, 1.0, 1.5]

# DSR honest cumulative: prior 125 = baseline 123 + weight-space ens (ENS_FINDINGS K16=125).
# 본 run은 동일 DPL_C 1-config 의 score-space 결합 변주 — 새 HP 탐색 아님. 보수적으로
# prior 위에 변주당 1 가산 (SCORE_AVG=1, EPI_DW 3개=3, CONSENSUS=1).
CUM_TRIALS_PRIOR = 125


# ════════════════════════════════════════════════════════════════════
def load_all():
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    return panel, bm, feat_cols


# ════════════════════════════════════════════════════════════════════
# Score-space combination → single projection
#   μ̂_s (per seed, full month universe, row-aligned to c["tk"]) 수집 →
#     SCORE_AVG : μ̃ = mean_s(μ̂)
#     EPI_DW(k) : μ̃ = mean_s(μ̂) − k · SE_s(μ̂),  SE = std_s/sqrt(K) (cross-seed dispersion)
#     CONSENSUS : ⌈K/2⌉+ seed가 top-entry_n 에 든 종목만 후보 유지(나머지 −∞), 그 위 μ̃=mean
#   → 단일 hysteresis_select(μ̃) → 단일 z-score → 단일 weights_from_scores projection.
# ════════════════════════════════════════════════════════════════════
def combine_scores(mu_stack, mode, k=0.0):
    """mu_stack: [K, N] per-seed pre-projection score (동일 universe·동일 순서).

    반환: mu_tilde [N] (결합 점수). projection 입력.
    """
    mu_bar = mu_stack.mean(axis=0)                                  # [N]
    if mode == "score_avg":
        return mu_bar
    if mode == "epi_dw":
        K = mu_stack.shape[0]
        sd = mu_stack.std(axis=0, ddof=1) if K > 1 else np.zeros_like(mu_bar)
        se = sd / np.sqrt(K)                                        # cross-seed SE of μ̂ per name
        return mu_bar - k * se                                     # down-weight high-disagreement
    if mode == "consensus":
        K = mu_stack.shape[0]
        thresh = int(np.ceil(K / 2.0))
        N = mu_stack.shape[1]
        n_top = min(ACTIVE_MAX, N)
        # per-seed top-n_top membership count
        votes = np.zeros(N, dtype=int)
        for s in range(K):
            top_idx = np.argpartition(-mu_stack[s], n_top - 1)[:n_top]
            votes[top_idx] += 1
        keep = votes >= thresh
        if keep.sum() < ACTIVE_MAX:
            # 합의 종목이 entry_n 미만이면 평균점수 상위로 보충(투표 우선 + 평균 tiebreak)
            order = np.lexsort((mu_bar, votes))[::-1]               # votes desc, then mu_bar desc
            keep = np.zeros(N, dtype=bool)
            keep[order[:ACTIVE_MAX]] = True
        mu_t = mu_bar.copy()
        mu_t[~keep] = -1e30                                         # 비합의 종목 후보 제거
        return mu_t
    raise ValueError(mode)


def project_combined(mu_tilde_np, tk, prev_holdings, cfg):
    """결합 점수 μ̃ → 단일 hysteresis_select → z-score → weights_from_scores (cbe와 동일 primitive).

    반환: dict{ticker: w}, Σw=1, w∈[0,cap], long-only, len<=entry_n.
    """
    if cfg.get("buffer", True) and prev_holdings:
        sel = cbe.hysteresis_select(mu_tilde_np, tk, prev_holdings,
                                    entry_n=ACTIVE_MAX, keep_n=KEEP_N)
    else:
        sel = np.argsort(-mu_tilde_np)[:ACTIVE_MAX]
    mu_sel = torch.tensor(mu_tilde_np[sel], device=DEVICE)
    mu_c = (mu_sel - mu_sel.mean()) / (mu_sel.std() + 1e-6)
    w = base.weights_from_scores(mu_c, cap=CAP, temp=cfg["temp"]).detach().cpu().numpy()
    tk_sel = np.asarray(tk)[sel]
    return dict(zip(tk_sel, [float(x) for x in w]))


# ════════════════════════════════════════════════════════════════════
# Walk-forward (OOS) — per refit window K seeds 학습, 월별 score-space 결합 후 단일 projection.
#   shared prev_holdings (단일 포트폴리오 — weight-space ens의 per-seed buffer와 다름).
# ════════════════════════════════════════════════════════════════════
@torch.no_grad()
def per_seed_mu(models, cache, m):
    """월 m, K seed 각각 full-universe μ̂ [N] 수집 → stack [K,N] (동일 순서 c["tk"])."""
    if m not in cache or cache[m]["n"] < ACTIVE_MAX:
        return None, None
    c = cache[m]
    mus = []
    for model in models:
        mu = model(c["X"]).detach().cpu().numpy()
        mus.append(mu)
    return np.vstack(mus), c["tk"]


def walk_forward_scoreens(cache, n_feat, cfg, months, bm_map, seeds, mode, k=0.0):
    min_train = cfg["min_train"]; train_window = cfg["lookback"]; refit_every = 12
    K = len(seeds)
    models = [None] * K
    prev_holdings = set()                       # single shared portfolio buffer
    rows = []
    start_i = min_train
    for i in range(start_i, len(months)):
        m = months[i]
        if (models[0] is None) or ((i - start_i) % refit_every == 0):
            tr = months[max(0, i - train_window):i]
            for sj, sd in enumerate(seeds):
                torch.manual_seed(sd); np.random.seed(sd)
                models[sj] = cbe.train_dpl_cbe(cache, n_feat, tr, cfg, bm_map)
        mu_stack, tk = per_seed_mu(models, cache, m)
        if mu_stack is None:
            continue
        mu_tilde = combine_scores(mu_stack, mode, k=k)
        wdict = project_combined(mu_tilde, tk, prev_holdings, cfg)
        if not wdict:
            continue
        prev_holdings = set(wdict.keys())
        for t, v in wdict.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


def walk_forward_scoreens_insample(cache, n_feat, cfg, months, bm_map, seeds, mode, k=0.0):
    """in-sample: 전체구간 1회 fit (K seeds) 후 동일구간 평가 (과적합 상한)."""
    K = len(seeds)
    models = []
    for sd in seeds:
        torch.manual_seed(sd); np.random.seed(sd)
        models.append(cbe.train_dpl_cbe(cache, n_feat, months[:], cfg, bm_map))
    prev_holdings = set()
    rows = []
    for m in months:
        mu_stack, tk = per_seed_mu(models, cache, m)
        if mu_stack is None:
            continue
        mu_tilde = combine_scores(mu_stack, mode, k=k)
        wdict = project_combined(mu_tilde, tk, prev_holdings, cfg)
        if not wdict:
            continue
        prev_holdings = set(wdict.keys())
        for t, v in wdict.items():
            if v > 1e-6:
                rows.append((m, t, float(v)))
    return pd.DataFrame(rows, columns=["ym", "Ticker", "w"])


# reuse net_return_series / sharpe_active / export_series from cbe (동일 cost/turnover 회계)
net_return_series = cbe.net_return_series
sharpe_active = cbe.sharpe_active
export_series = cbe.export_series


def subperiods(s):
    s_sorted = s.sort_values("ym").reset_index(drop=True)
    thirds = np.array_split(s_sorted, 3)
    sub = [sharpe_active(t) for t in thirds if len(t) >= 6]
    sr_min = float(np.nanmin(sub)) if sub else np.nan
    return [round(x, 3) for x in sub], sr_min


# ════════════════════════════════════════════════════════════════════
def run_one(tag, mode, k, cache, n_feat, cfg, panel, bm, rets, bm_map, months, seeds):
    print(f"\n{'='*64}\n[ens2] TAG = {tag}  (mode={mode}, k={k})\n{'='*64}")
    wdf = walk_forward_scoreens(cache, n_feat, cfg, months, bm_map, seeds, mode, k=k)
    if wdf.empty:
        print(f"[ens2] {tag}: empty OOS wdf"); return None
    wdf_is = walk_forward_scoreens_insample(cache, n_feat, cfg, months, bm_map, seeds, mode, k=k)

    s = net_return_series(wdf, rets, bm)
    sr = sharpe_active(s)
    to_ann = float(s["traded"].mean() * 12)
    sub, sr_min = subperiods(s)
    n_names = wdf.groupby("ym")["Ticker"].nunique()
    print(f"[ens2] {tag} OOS net_active_SR={sr:.3f} TO={to_ann:.2f} sub={sub} sub_min={sr_min:.3f} "
          f"names(mean={n_names.mean():.1f},max={int(n_names.max())})")

    s_is = net_return_series(wdf_is, rets, bm)
    sr_is = sharpe_active(s_is); to_is = float(s_is["traded"].mean() * 12)

    export_series(s, f"ENS2_{tag}", f"ens2_{tag}_net_returns.parquet")
    export_series(s_is, f"ENS2_{tag}_IS", f"ens2_{tag}_is_net_returns.parquet")

    active = (s["ret_net"] - s["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)) if len(active) > 3 else 0.0
    kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0

    rec = {"tag": tag, "mode": mode, "k": k, "K": len(seeds), "seeds": seeds,
           "config": "DPL_C_fixed_scorespace",
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
                    choices=["ALL", "score_avg", "epi_dw", "consensus"])
    args = ap.parse_args()

    panel, bm, feat_cols = load_all()
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    bm_map = dict(zip(bm["ym"], bm["BM_Ret_1m"]))
    months = sorted(panel["ym"].unique())
    lock = LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]

    smoke = os.environ.get("DPL_SMOKE") == "1"
    seeds = SEEDS_K16[:2] if smoke else SEEDS_K16
    cfg = dict(DPL_C_CFG)
    if smoke:
        cfg["epochs"] = 5

    print(f"[ens2] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}] device={DEVICE}")
    print(f"[ens2] DPL_C fixed cfg: {DPL_C_CFG}  keep_n={KEEP_N} entry_n={ACTIVE_MAX} K={len(seeds)} seeds={seeds}")
    print(f"[ens2] k_values(EPI_DW)={K_VALUES}  mode={args.mode}  smoke={smoke}")
    cache = base.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    # build variant list
    variants = []   # (tag, mode, k)
    if args.mode in ("ALL", "score_avg"):
        variants.append(("SCORE_AVG", "score_avg", 0.0))
    if args.mode in ("ALL", "epi_dw"):
        ks = K_VALUES[:1] if smoke else K_VALUES
        for kv in ks:
            variants.append((f"EPI_DW_k{str(kv).replace('.', '')}", "epi_dw", kv))
    if args.mode in ("ALL", "consensus"):
        variants.append(("CONSENSUS", "consensus", 0.0))

    out = {"device": DEVICE, "lockbox": str(LOCKBOX.date()),
           "scope": "findings-only — admission/book_state 변경 없음. canonical alpha_package handoff 없음. "
                    "weight-space ENS run과 동일 posture. DPL 한계/된다 verdict 없음.",
           "hypothesis": "pre-projection score(μ̂) seed간 평균 + single projection → weight-space 평균이 "
                         "파괴한 conviction 보존. EPI_DW: μ̃=mean−k·SE(μ̂)로 seed 불일치 종목만 down-weight.",
           "dpl_c_cfg": DPL_C_CFG, "keep_n": KEEP_N, "entry_n": ACTIVE_MAX,
           "seeds_K16": SEEDS_K16, "k_values": K_VALUES,
           "score_space_note": "직전 ENS run은 per-seed projected WEIGHT 평균. 본 run은 projection "
                               "이전 per-name μ̂(network output, full month universe, row-aligned c['tk']) "
                               "를 seed간 결합 후 단일 hysteresis_select+weights_from_scores projection.",
           "baseline_dpl_c_contract": {
               "portfolio_alpha_t_nw_lag3": 2.906, "p": 0.0037, "IR": 0.703,
               "net_active_SR": 0.703, "TE": 0.355, "TO_yr": 14.35,
               "DSR_corrected": 0.508, "subperiod_active_SR": [1.482, -0.346, 0.763],
               "subperiod_min": -0.346, "n_trials_cumulative": 123,
               "metric_type": "backtested (cbe_eval_contract.json)"},
           "prior_weightspace_ens_K16": {
               "portfolio_alpha_t_nw_lag3": 2.387, "IR": 0.521, "TE": 0.304,
               "TO_yr": 11.96, "DSR_corrected": 0.242, "subperiod_min": -0.122,
               "note": "weight-space K16 — conviction 희석으로 α-t 하락."},
           "variants": {}}

    cum_trials = CUM_TRIALS_PRIOR
    for (tag, mode, kv) in variants:
        r = run_one(tag, mode, kv, cache, n_feat, cfg, panel, bm, rets, bm_map, months, seeds)
        if r:
            cum_trials += 1
            r["n_trials_cumulative"] = cum_trials
            bs = pd.read_parquet(os.path.join(OUT_DIR, f"ens2_{tag}_net_returns.parquet"))
            active = (bs["ret_net"] - bs["BM_Ret"]).values
            from scipy import stats as st
            skew = float(st.skew(active)); kurt = float(st.kurtosis(active, fisher=False))
            r["DSR_cumulative_python"] = base.deflated_sharpe_ratio(
                r["net_active_sr_python"], len(active), cum_trials, skew, kurt)
            out["variants"][tag] = r

    out["n_trials_cumulative_final"] = cum_trials
    with open(os.path.join(OUT_DIR, "ens2_sweep_results.json"), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, default=float)
    print(f"\n[ens2] results -> {os.path.join(OUT_DIR, 'ens2_sweep_results.json')}")
    print(f"[ens2] cumulative n_trials (prior {CUM_TRIALS_PRIOR} + score-space variants) = {cum_trials}")


if __name__ == "__main__":
    main()
