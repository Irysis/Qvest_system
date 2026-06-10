#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_gpu_sweep.py — Qvest v8.x: DPL GPU sweep (analytic differentiable simplex+box projection).

설계:
  rich rolling features → MLP(depth/width sweep) → μ̂(per-name) → top-25 universe 사전제약
  → **analytic capped-simplex projection layer** (long-only / Σw=1 / w∈[0,cap], 완전 GPU·미분가능)
  → realized net Sharpe loss (− Sharpe + turnover penalty, 15bps) → end-to-end backprop.

convex layer 방식 (도훈 택1):
  cvxpylayers diffcp = CPU-only(GPU 배치 QP 불가). qpth 미설치.
  → **analytic simplex+box projection** 채택: QP 솔버 제거, 완전 GPU·고속 배치, 미분가능(a.e.).
    Euclidean projection onto {w: Σw=1, 0≤w≤cap} via sorting (Held-Wolfe / Wang-Carreira-Perpiñán 2013).
    PyTorch autograd가 sort/clamp 통해 자동 미분 → MLP까지 gradient 흐름.

Sweep (★최대 리스크 = 피처폭발 과적합):
  HP grid: lambda(risk) / gamma(turnover) / lookback(train window) / MLP depth·width / L2 / dropout.
  walk-forward 다중분할 + DSR(honest n_trials = grid cell 수). 단일분할 금지.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_gpu_sweep.py
산출: best/모든 cell 월별 net return series parquet (R contract 경유 평가용) + sweep 결과표 json.
자체합성 backtest 금지: 월별 net return series만 export → portfolio_alpha_t_nw_lag3는 R 단일경로.
"""
import os
import json
import itertools
import numpy as np
import pandas as pd
import torch
import torch.nn as nn

torch.set_default_dtype(torch.float64)

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
OUT_DIR = os.environ.get(
    "DPL_OUT_DIR",
    os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP"))
PANEL = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
BENCH = os.path.join(OUT_DIR, "benchmark_monthly.parquet")

LOCKBOX = pd.Timestamp("2023-12-22")
CAP = 0.20
ACTIVE_MAX = 25
COST_BPS_ONEWAY = 15.0
ANNUALIZE = 12.0
HIST_COV = 36  # (참고용 — analytic projection은 Σ 미사용; risk는 vol penalty로 흡수)

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


# ════════════════════════════════════════════════════════════════════
# Analytic differentiable capped-simplex projection (GPU-native)
# ════════════════════════════════════════════════════════════════════
def project_capped_simplex(v, cap=CAP, n_iter=30):
    """Euclidean projection of v onto {w: sum(w)=1, 0<=w<=cap}.

    Bisection on the dual variable tau: w = clamp(v - tau, 0, cap), find tau s.t. sum(w)=1.
    완전 미분가능(clamp + 선형) → autograd가 v(=μ̂)까지 gradient 전파. GPU 배치 OK.
    """
    n = v.numel()
    assert n * cap >= 1.0 - 1e-9, f"infeasible: n*cap={n*cap:.3f} < 1"
    lo = (v.min() - cap).detach()
    hi = (v.max()).detach()
    for _ in range(n_iter):
        tau = (lo + hi) / 2
        w = torch.clamp(v - tau, 0.0, cap)
        s = w.sum()
        # s decreasing in tau → if s>1 raise tau (lo=tau) else hi=tau
        lo = torch.where(s > 1.0, tau, lo)
        hi = torch.where(s > 1.0, hi, tau)
    tau = (lo + hi) / 2
    w = torch.clamp(v - tau, 0.0, cap)
    # renormalize residual (numerical) — 미분가능
    w = w / (w.sum() + 1e-12)
    return w


def weights_from_scores(mu, cap=CAP, temp=0.5):
    """μ̂ → portfolio weights, gradient-friendly.

    문제: capped-simplex projection을 z-score에 직접 적용하면 top-k가 cap에 saturate →
          clamp 평탄구간에서 gradient 소실(n=25,cap=0.2면 5개 cap·20개 0). 학습 불가.
    해법: softmax(μ̂/temp)로 부드러운 사전배분 → 그 위에 projection(cap·Σw=1 강제).
          softmax는 모든 입력에 대해 gradient 비영 → MLP까지 신호 전달. projection은
          cap/long-only/Σw=1을 hard 보장(미분가능 clamp). temp가 집중도 제어.
    """
    p = torch.softmax(mu / temp, dim=0)        # smooth allocation, gradient everywhere
    w = project_capped_simplex(p, cap=cap)      # enforce cap/Σw=1/long-only
    return w


def project_capped_simplex_batch(V, cap=CAP, n_iter=30):
    """배치 [B,k] 각 행을 {sum=1, 0<=w<=cap}로 projection (GPU 벡터화). per-month loop 제거."""
    lo = (V.min(dim=1, keepdim=True).values - cap).detach()
    hi = (V.max(dim=1, keepdim=True).values).detach()
    for _ in range(n_iter):
        tau = (lo + hi) / 2
        W = torch.clamp(V - tau, 0.0, cap)
        s = W.sum(dim=1, keepdim=True)
        ge = (s > 1.0)
        lo = torch.where(ge, tau, lo)
        hi = torch.where(ge, hi, tau)
    W = torch.clamp(V - (lo + hi) / 2, 0.0, cap)
    return W / (W.sum(dim=1, keepdim=True) + 1e-12)


def weights_from_scores_batch(MU, cap=CAP, temp=0.5):
    """배치 [B,k] μ̂ → weights [B,k]. softmax(행) → capped-simplex projection(행)."""
    P = torch.softmax(MU / temp, dim=1)
    return project_capped_simplex_batch(P, cap=cap)


class DPLNet(nn.Module):
    def __init__(self, n_feat, depth=2, width=32, dropout=0.0):
        super().__init__()
        layers = []
        d = n_feat
        for _ in range(depth):
            layers += [nn.Linear(d, width), nn.Tanh()]
            if dropout > 0:
                layers += [nn.Dropout(dropout)]
            d = width
        layers += [nn.Linear(d, 1)]
        self.net = nn.Sequential(*layers)

    def forward(self, X):
        return self.net(X).squeeze(-1)


def load_panel():
    panel = pd.read_parquet(PANEL)
    bm = pd.read_parquet(BENCH)
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat_cols = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    # DPL_FEAT_DROP (CSV of exact feature names) — prune panel cols for ablation
    # (risk RF-R5: drop RESIDMOM__lvl + 4 __slp -> 93f; or base90 ablation).
    # Non-invasive: only filters columns, verified projection/train logic untouched.
    drop_env = os.environ.get("DPL_FEAT_DROP", "").strip()
    if drop_env:
        drop = {c.strip() for c in drop_env.split(",") if c.strip()}
        feat_cols = [c for c in feat_cols if c not in drop]
        print(f"[load_panel] DPL_FEAT_DROP applied: dropped {len(drop)} -> {len(feat_cols)} feats")
    # DPL_FEAT_KEEP_ADDED (CSV of added-feature names to KEEP; all other added dropped to base90)
    keep_env = os.environ.get("DPL_FEAT_KEEP_ADDED", "").strip()
    if keep_env:
        added = ["RESIDMOM__lvl", "RESIDMOM__slp", "PIOTROSKI__lvl", "PIOTROSKI__slp",
                 "MOHANRAM__lvl", "MOHANRAM__slp", "NETISSUE__lvl", "NETISSUE__slp"]
        keep = {c.strip() for c in keep_env.split(",") if c.strip()}
        feat_cols = [c for c in feat_cols if (c not in added) or (c in keep)]
        print(f"[load_panel] DPL_FEAT_KEEP_ADDED={sorted(keep)} -> {len(feat_cols)} feats (base90 + kept)")
    return panel, bm, feat_cols


def build_month_cache(panel, feat_cols):
    """월별 텐서를 1회 사전적재(GPU 상주). 추가로 전체월 stacked X_all(배치 MLP용) + 경계.

    각 월: X(GPU), r(GPU), tid(GPU long, global ticker id), n.
    전역: X_all(모든 (name,month) 행 stack), month_slices(start,end), tid_all.
    배치 MLP: 한 epoch에 forward 1회 → 월별 슬라이스 (per-month Python loop 제거).
    """
    cache = {}
    all_tk = sorted(panel["Ticker"].unique())
    t2id = {t: i for i, t in enumerate(all_tk)}
    gp = panel.groupby("ym", sort=True)
    X_blocks = []; tid_blocks = []; r_blocks = []
    cursor = 0
    for m, sub in gp:
        X = torch.tensor(sub[feat_cols].values, dtype=torch.float64, device=DEVICE)
        r = torch.tensor(sub["Ret_1m"].values, dtype=torch.float64, device=DEVICE)
        tid = torch.tensor([t2id[t] for t in sub["Ticker"].values], dtype=torch.long, device=DEVICE)
        n = X.shape[0]
        cache[m] = {"X": X, "r": r, "tid": tid, "n": n,
                    "tk": sub["Ticker"].values,
                    "slice": (cursor, cursor + n)}
        X_blocks.append(X); r_blocks.append(r); tid_blocks.append(tid)
        cursor += n
    cache["__global__"] = {
        "X_all": torch.cat(X_blocks, 0),
        "r_all": torch.cat(r_blocks, 0),
        "tid_all": torch.cat(tid_blocks, 0),
        "n_tickers": len(all_tk),
        "id2tk": all_tk,
    }
    return cache


def train_dpl(cache, n_feat, train_months, cfg):
    model = DPLNet(n_feat, depth=cfg["depth"], width=cfg["width"],
                   dropout=cfg["dropout"]).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=cfg["lr"], weight_decay=cfg["l2"])
    gam = cfg["gamma"]; lam = cfg["lam"]; temp = cfg["temp"]
    sqrtA = float(np.sqrt(ANNUALIZE))
    N_T = cache["__global__"]["n_tickers"]
    valid = [m for m in train_months if m in cache and cache[m]["n"] >= ACTIVE_MAX]
    if len(valid) < 12:
        return model
    B = len(valid)
    k = ACTIVE_MAX
    # 배치 MLP 입력: 각 월 X를 [n_m, F] → stack. per-month n 다름 → 패딩 불필요, slice로.
    Xb = torch.cat([cache[m]["X"] for m in valid], 0)         # [sumN, F]
    starts = []; cur = 0
    for m in valid:
        starts.append((cur, cur + cache[m]["n"])); cur += cache[m]["n"]
    starts_t = torch.tensor(starts, device=DEVICE)            # [B,2]
    # 월별 r/tid도 [B,k]로 모으기 위해, 매 epoch topk 후 gather (tid는 고정 아님 — μ̂ 의존)
    r_blocks = [cache[m]["r"] for m in valid]
    tid_blocks = [cache[m]["tid"] for m in valid]

    for ep in range(cfg["epochs"]):
        opt.zero_grad()
        mu_full = model(Xb)                                   # ★ 배치 forward 1회
        # per-month topk (k 고정) → [B,k] 행렬로 모음
        MU = torch.empty(B, k, device=DEVICE)
        R = torch.empty(B, k, device=DEVICE)
        TID = torch.empty(B, k, dtype=torch.long, device=DEVICE)
        for b, (s, e) in enumerate(starts):
            mu_all = mu_full[s:e]
            idx = torch.topk(mu_all, k).indices
            MU[b] = mu_all[idx]
            R[b] = r_blocks[b][idx]
            TID[b] = tid_blocks[b][idx]
        # 단면 z-score per row (월별)
        MU_c = (MU - MU.mean(dim=1, keepdim=True)) / (MU.std(dim=1, keepdim=True) + 1e-6)
        W = weights_from_scores_batch(MU_c, cap=CAP, temp=temp)   # [B,k] ★ 배치 projection
        # gross net return per month: sum(W*R)
        gross = (W * R).sum(dim=1)                            # [B]
        # turnover: dense [B,N_T] scatter → shifted diff (PIT: 순차 turnover)
        Wdense = torch.zeros(B, N_T, device=DEVICE)
        Wdense.scatter_(1, TID, W)
        Wprev = torch.zeros_like(Wdense)
        Wprev[1:] = Wdense[:-1].detach()                     # 직전월 (detach: graph 절단)
        traded = (Wdense - Wprev).abs().sum(dim=1)           # [B]
        cost = traded * COST_BPS_ONEWAY / 1e4
        net = gross - cost
        sharpe = net.mean() / (net.std() + 1e-6) * sqrtA
        mean_traded = traded.mean()
        mean_risk = (W * W).sum(dim=1).mean()
        loss = -sharpe + gam * mean_traded + lam * mean_risk
        loss.backward()
        opt.step()
    return model


@torch.no_grad()
def dpl_weights(model, cache, m, temp):
    if m not in cache or cache[m]["n"] < ACTIVE_MAX:
        return None, None
    c = cache[m]
    mu_all = model(c["X"])
    idx = torch.topk(mu_all, ACTIVE_MAX).indices
    mu = mu_all[idx]
    tk_sel = c["tk"][idx.detach().cpu().numpy()]
    mu_c = (mu - mu.mean()) / (mu.std() + 1e-6)
    w = weights_from_scores(mu_c, cap=CAP, temp=temp)
    return tk_sel, w.detach().cpu().numpy()


def walk_forward(cache, n_feat, cfg, months):
    """다중분할 walk-forward: rolling train window, refit, OOS 1-step (cache 사용)."""
    min_train = cfg["min_train"]
    train_window = cfg["lookback"]
    refit_every = 12
    oos = []
    model = None
    start_i = min_train
    for i in range(start_i, len(months)):
        m = months[i]
        if (model is None) or ((i - start_i) % refit_every == 0):
            tr = months[max(0, i - train_window):i]
            model = train_dpl(cache, n_feat, tr, cfg)
        tk_sel, wv = dpl_weights(model, cache, m, cfg["temp"])
        if tk_sel is None:
            continue
        for t, v in zip(tk_sel, wv):
            if v > 1e-5:
                oos.append((m, t, float(v)))
    return pd.DataFrame(oos, columns=["ym", "Ticker", "w"])


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


def sharpe_of(series):
    active = (series["ret_net"] - series["BM_Ret_1m"]).values
    if len(active) < 6 or active.std() == 0:
        return np.nan
    return float(active.mean() / active.std() * np.sqrt(ANNUALIZE))


def deflated_sharpe_ratio(sr, n_obs, n_trials, skew=0.0, kurt=3.0):
    """Bailey-Lopez de Prado (2014) Deflated Sharpe Ratio.

    n_trials = honest sweep cell 수. 모든 계산은 per-period(월) SR 단위.
    sr_m = 월 SR = 연 SR / sqrt(12). 추정분산 Var(SR_hat) ≈ (1 - skew·sr + (kurt-1)/4·sr²)/(n-1).
    sr0(기대 최댓값, 다중검정 deflation) = sqrt(Var0)·[(1-γ)Φ⁻¹(1-1/N) + γ·Φ⁻¹(1-1/(N·e))],
    Var0 ≈ 1/(n-1) (null SR=0). DSR = Φ[(sr_m - sr0)·sqrt(n-1) / sqrt(Var(SR_hat))].
    """
    from scipy.stats import norm
    if not np.isfinite(sr) or n_obs < 12:
        return np.nan
    emc = 0.5772156649
    sr_m = sr / np.sqrt(ANNUALIZE)   # 연 → 월 per-period SR
    var0 = 1.0 / (n_obs - 1)         # null SR estimate variance (per-period)
    if n_trials < 2:
        sr0 = 0.0
    else:
        z1 = norm.ppf(1 - 1.0 / n_trials)
        z2 = norm.ppf(1 - 1.0 / (n_trials * np.e))
        sr0 = np.sqrt(var0) * ((1 - emc) * z1 + emc * z2)
    den = np.sqrt(1 - skew * sr_m + (kurt - 1) / 4.0 * sr_m ** 2)
    if den <= 0:
        return np.nan
    num = (sr_m - sr0) * np.sqrt(n_obs - 1)
    return float(norm.cdf(num / den))


def main():
    print(f"[sweep] device={DEVICE}")
    panel, bm, feat_cols = load_panel()
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    months = sorted(panel["ym"].unique())
    lock = LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    print(f"[sweep] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}]")
    print("[sweep] building per-month GPU tensor cache ...")
    cache = build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    # ── HP grid (sweep cells = honest n_trials for DSR) ──────────────
    grid = {
        "lam":      [0.0, 0.3],          # risk aversion (concentration/Herfindahl penalty)
        "gamma":    [0.1, 0.5, 1.5],     # turnover penalty (mean_traded에 직접 작용, TO≤11 압박)
        "lookback": [72, 120],           # train window (months)
        "depth":    [2, 3],              # MLP depth
        "width":    [32, 64],            # MLP width
        "l2":       [1e-3],              # L2 reg (강한 정규화 — 피처폭발 과적합 대응)
        "dropout":  [0.1],               # dropout
        "temp":     [0.5, 1.0],          # softmax 집중도 (높을수록 EW화 → 회전↓)
        "lr":       [5e-3],
        "epochs":   [40],
        "min_train": [60],
    }
    # DPL_GRID env override (JSON): partial axis override, defaults retained for unset keys.
    # e.g. DPL_GRID='{"gamma":[2,4,7],"temp":[0.7,1.5]}' → extend TO penalty upward (TO≤11 압박).
    grid_override = os.environ.get("DPL_GRID")
    if grid_override:
        ov = json.loads(grid_override)
        for k, v in ov.items():
            if k not in grid:
                raise KeyError(f"DPL_GRID unknown axis '{k}' (valid: {list(grid.keys())})")
            grid[k] = v if isinstance(v, list) else [v]
        print(f"[sweep] DPL_GRID override applied: {list(ov.keys())}")
    if os.environ.get("DPL_SMOKE") == "1":
        grid = {k: [v[0]] for k, v in grid.items()}
        grid["epochs"] = [5]
        print("[sweep] SMOKE mode — 1 cell, 5 epochs")
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    n_trials = len(combos)
    print(f"[sweep] grid cells (n_trials) = {n_trials}")

    results = []
    all_series = []
    best = None
    # ── completion-guarantee checkpoint: append each cell's record as soon as it
    #    finishes so a mid-sweep crash never loses completed work (death-loss fix).
    ckpt_path = os.path.join(OUT_DIR, "sweep_progress.jsonl")
    with open(ckpt_path, "w", encoding="utf-8") as _f:
        _f.write(json.dumps({"_meta": "DPL sweep progress checkpoint",
                             "n_trials": n_trials, "n_feature_cols": len(feat_cols),
                             "device": DEVICE, "grid": grid}, ensure_ascii=False) + "\n")
    print(f"[sweep] checkpoint -> {ckpt_path}", flush=True)
    for ci, vals in enumerate(combos):
        cfg = dict(zip(keys, vals))
        torch.manual_seed(7)
        np.random.seed(7)
        print(f"[sweep] cell {ci+1}/{n_trials} START cfg={cfg}", flush=True)
        wdf = walk_forward(cache, n_feat, cfg, months)
        # free per-cell GPU scratch (refit Xb cats) before next cell — OOM guard
        if DEVICE == "cuda":
            torch.cuda.empty_cache()
        if wdf.empty:
            print(f"[sweep] cell {ci+1}/{n_trials} EMPTY (skipped)", flush=True)
            with open(ckpt_path, "a", encoding="utf-8") as _f:
                _f.write(json.dumps({"cell": ci, **cfg, "status": "EMPTY"},
                                    ensure_ascii=False, default=float) + "\n")
            continue
        s = net_return_series(wdf, rets, bm)
        sr = sharpe_of(s)
        to_ann = float(s["traded"].mean() * 12)
        # walk-forward 다중분할 안정성: OOS를 3 sub-period로 쪼개 SR 안정성
        s_sorted = s.sort_values("ym").reset_index(drop=True)
        thirds = np.array_split(s_sorted, 3)
        sub_srs = [sharpe_of(t) for t in thirds if len(t) >= 6]
        sr_min_sub = float(np.nanmin(sub_srs)) if sub_srs else np.nan
        rec = {"cell": ci, **cfg, "net_active_sr": sr, "turnover_ann": to_ann,
               "n_oos_months": int(s["ym"].nunique()),
               "sr_min_subperiod": sr_min_sub,
               "sub_period_srs": [round(x, 3) for x in sub_srs]}
        results.append(rec)
        # tag series
        s2 = s.copy(); s2["method"] = f"DPL_cell{ci}"; all_series.append(s2)
        if (best is None) or (np.nan_to_num(sr, nan=-9) > np.nan_to_num(best["net_active_sr"], nan=-9)):
            best = rec
            best_wdf = wdf.copy()
        print(f"[sweep] cell {ci+1}/{n_trials} DONE SR={sr:.3f} TO={to_ann:.2f} "
              f"sub_min={sr_min_sub:.3f} cfg={cfg}", flush=True)
        # checkpoint append (death-loss fix — completed cell persisted immediately)
        with open(ckpt_path, "a", encoding="utf-8") as _f:
            _f.write(json.dumps({**rec, "status": "DONE"},
                                ensure_ascii=False, default=float) + "\n")

    if best is None:
        print("[sweep] NO valid cells produced output — aborting export. "
              f"See checkpoint {ckpt_path}", flush=True)
        return
    # DSR for best (honest n_trials)
    best_series = [s for s in all_series if s["method"].iloc[0] == f"DPL_cell{best['cell']}"][0]
    active = (best_series["ret_net"] - best_series["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)) if len(active) > 3 else 0.0
    kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0
    dsr = deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, skew, kurt)
    best["DSR"] = dsr
    best["active_skew"] = skew
    best["active_kurt"] = kurt
    print(f"[sweep] BEST cell={best['cell']} SR={best['net_active_sr']:.3f} "
          f"DSR={dsr:.3f} (n_trials={n_trials})")

    # ── export best DPL series for R contract + all results table ────
    best_export = best_series[["ym", "ret_net", "BM_Ret_1m", "traded"]].copy()
    best_export["date"] = pd.PeriodIndex(best_export["ym"], freq="M").to_timestamp("M")
    best_export["method"] = "DPL_best"
    best_export.rename(columns={"BM_Ret_1m": "BM_Ret"}, inplace=True)
    out_series = os.path.join(OUT_DIR, "dpl_best_net_returns.parquet")
    best_export[["method", "date", "ret_net", "BM_Ret", "traded"]].to_parquet(out_series, index=False)
    best_wdf.assign(date=lambda d: pd.PeriodIndex(d["ym"], freq="M").to_timestamp("M")).to_parquet(
        os.path.join(OUT_DIR, "dpl_best_weights.parquet"), index=False)

    sweep_out = {
        "n_trials": n_trials,
        "n_feature_cols": len(feat_cols),
        "device": DEVICE,
        "convex_layer": "analytic capped-simplex Euclidean projection (GPU-native, autograd-diff)",
        "lockbox": str(LOCKBOX.date()),
        "best": best,
        "all_cells": sorted(results, key=lambda r: -np.nan_to_num(r["net_active_sr"], nan=-9)),
        "out_best_net_returns": out_series,
        "self_synth_note": "월별 net return series만 산출. portfolio_alpha_t_nw_lag3 등 contract-grade는 "
                           "R canonical/build_benchmark_compare 단일경로.",
    }
    with open(os.path.join(OUT_DIR, "sweep_results.json"), "w") as f:
        json.dump(sweep_out, f, indent=2, ensure_ascii=False, default=float)
    print(f"[sweep] results -> {os.path.join(OUT_DIR, 'sweep_results.json')}")
    print(f"[sweep] best series -> {out_series}")


if __name__ == "__main__":
    main()
