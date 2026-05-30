#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_portfolio.py — Qvest v8.x 부록: Direct Portfolio Learning (DPL) feasibility pilot.

설계 (You-Zhang 2025 "Direct Portfolio Learning" 정합):
  features (alpha_scores 패널) → 작은 MLP → μ̂ (per-name expected score)
  → cvxpylayers differentiable convex QP layer
      max  wᵀμ̂ − λ·wᵀΣw − γ·‖w − w_prev‖₁
      s.t. w ≥ 0 (long-only), Σw = 1, w ≤ 0.20
  → weights → realized **net Sharpe** loss (−Sharpe + turnover penalty) → end-to-end backprop.

제약 (CLAUDE.md Production Constraints):
  long-only / ≤25 active (top-25 universe 사전제약 + cap 0.20) / w∈[0,0.20] / Σw=1
  / 15bps one-way / turnover penalty. PIT C1~C15: walk-forward time split, lockbox 2023-12-22.

자체합성 backtest 금지 (answer-principles / backtest-contract / python-policy):
  본 스크립트는 **월별 weights와 월별 net return series만** 산출하여 parquet으로 export.
  admission-binding portfolio_alpha_t_nw_lag3 등 contract-grade 수치는 R
  build_benchmark_compare()(02_Infrastructure/contracts/) 단일 경로로 산출한다.
  (DPL / EW top-N / 2-stage MVO 3개 모두 동일 R contract 함수 경유 → apples-to-apples.)

실행: cd <project_root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_portfolio.py
한글 경로 회피: 본 파일 위치 기준 상대경로(PROJECT_ROOT) 사용. normalizePath 류 금지.
"""
import os
import sys
import json
import numpy as np
import pandas as pd
import torch
import cvxpy as cp
from cvxpylayers.torch import CvxpyLayer

torch.set_default_dtype(torch.float64)
np.random.seed(7)
torch.manual_seed(7)

# ── 경로 (한글 회피: __file__ 기준 상대) ──────────────────────────────
THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
STAGE = os.path.join(PROJECT_ROOT, "stage_artifacts")
OUT_DIR = os.path.join(STAGE, "WT_DPL_PILOT")
os.makedirs(OUT_DIR, exist_ok=True)

RAWDATA = os.path.join(PROJECT_ROOT, ".cache", "rawdata.parquet")

# alpha_scores 패널 (Date×Ticker×alpha_score) — 피처 소스
FEATURE_SOURCES = {
    "FLOW":      os.path.join(STAGE, "WT_D20260529_001_FLOW", "alpha_scores.parquet"),
    "RESID_MOM": os.path.join(STAGE, "WT_WT_D20260529_002_RESID_MOM", "alpha_scores.parquet"),
    "QVALUE":    os.path.join(STAGE, "WT_WT_D20260529_004_QVALUE", "alpha_scores.parquet"),
    "INTERACT":  os.path.join(STAGE, "WT_WT_D20260529_004_INTERACT_ML", "alpha_scores.parquet"),
}

# ── 제약 상수 ─────────────────────────────────────────────────────────
LOCKBOX = pd.Timestamp("2023-12-22")  # 정규 리서치 lockbox (PIT, alpha-stage)
CAP = 0.20
ACTIVE_MAX = 25
TOP_N_EW = 20
COST_BPS_ONEWAY = 15.0
LIQ_MIN = 2e8
ANNUALIZE = 12.0


# ════════════════════════════════════════════════════════════════════
# 1. 데이터 로드 + 월별 패널 + forward 1M 실현수익 (PIT-aligned)
# ════════════════════════════════════════════════════════════════════
def load_feature_panel():
    """alpha_scores들을 month-end 키로 wide merge → 피처 행렬."""
    frames = {}
    for name, path in FEATURE_SOURCES.items():
        if not os.path.exists(path):
            print(f"[warn] feature source missing, skip: {name} ({path})")
            continue
        df = pd.read_parquet(path)
        col = "alpha_score" if "alpha_score" in df.columns else "alpha"
        df = df[["Date", "Ticker", col]].copy()
        df["Date"] = pd.to_datetime(df["Date"])
        # month-end 정규화 (각 패널의 sig_date 정렬)
        df["ym"] = df["Date"].dt.to_period("M")
        # cross-section z-score (피처 스케일 통일, PIT: 같은 시점 단면만)
        df[name] = df.groupby("ym")[col].transform(
            lambda s: (s - s.mean()) / (s.std(ddof=0) + 1e-9)
        )
        frames[name] = df[["ym", "Ticker", name]]
    if not frames:
        raise RuntimeError("no feature sources available")
    panel = None
    for name, f in frames.items():
        panel = f if panel is None else panel.merge(f, on=["ym", "Ticker"], how="outer")
    feat_cols = [c for c in frames.keys()]
    # 결측 피처 0(중립 z) 대체 — 한 패널에만 있는 종목 허용
    panel[feat_cols] = panel[feat_cols].fillna(0.0)
    return panel, feat_cols


def build_returns_and_liq():
    """rawdata(daily)에서 month-end → forward 1M 실현수익 + t-1 20d ADV(C10)."""
    raw = pd.read_parquet(RAWDATA, columns=["Date", "Ticker", "Close", "Vol", "BM_Ret",
                                            "AdminStock", "TradingHalt"])
    raw["Date"] = pd.to_datetime(raw["Date"])
    raw = raw.sort_values(["Ticker", "Date"])
    raw = raw[raw["Close"].notna() & (raw["Close"] > 0)]

    # 20d ADV (거래대금 = Close*Vol), t-1 lag (C10)
    raw["adv_value"] = raw["Close"] * raw["Vol"]
    raw["adv20"] = raw.groupby("Ticker")["adv_value"].transform(
        lambda s: s.rolling(20, min_periods=10).mean())
    raw["adv20_lag1"] = raw.groupby("Ticker")["adv20"].shift(1)  # t-1 PIT

    raw["ym"] = raw["Date"].dt.to_period("M")
    # month-end 행 (각 종목·월 마지막 거래일)
    me = raw.groupby(["Ticker", "ym"]).tail(1).copy()
    me = me.sort_values(["Ticker", "ym"])

    # forward 1M return = next month-end Close / this month-end Close - 1  (FORWARD, C1/C2)
    # shift(-1) along time per ticker → 명시적 forward (data.table shift convention 정합)
    me["close_next"] = me.groupby("Ticker")["Close"].shift(-1)
    me["Ret_1m"] = me["close_next"] / me["Close"] - 1.0

    # 거래정지/관리종목 당월 제외 (실투 정합)
    bad = (me["AdminStock"].fillna(0) > 0) | (me["TradingHalt"].fillna(0) > 0)
    me.loc[bad, "Ret_1m"] = np.nan

    rets = me[["ym", "Ticker", "Ret_1m"]].dropna(subset=["Ret_1m"])
    liq = me[["ym", "Ticker", "adv20_lag1"]].rename(columns={"adv20_lag1": "adv"})

    # benchmark monthly: compound daily BM_Ret within month
    bm = raw[["Date", "ym", "BM_Ret"]].dropna(subset=["BM_Ret"]).drop_duplicates(["Date"])
    bm_m = bm.groupby("ym")["BM_Ret"].apply(lambda s: np.prod(1.0 + s.values) - 1.0)
    bm_m = bm_m.reset_index().rename(columns={"BM_Ret": "BM_Ret_1m"})
    return rets, liq, bm_m


# ════════════════════════════════════════════════════════════════════
# 2. DPL model: MLP(features→μ̂) + differentiable QP layer
# ════════════════════════════════════════════════════════════════════
def make_qp_layer(n, lam=5.0, gam=1.0):
    # lam/gam은 고정 하이퍼파라미터(상수) — parameter×변수항은 non-DPP라 상수로 둔다.
    w = cp.Variable(n)
    mu = cp.Parameter(n)
    wprev = cp.Parameter(n)
    L = cp.Parameter((n, n))         # Σ^{1/2} (DPP-safe quadratic)
    risk = cp.sum_squares(L @ w)
    obj = cp.Maximize(mu @ w - lam * risk - gam * cp.norm1(w - wprev))
    cons = [w >= 0, cp.sum(w) == 1, w <= CAP]
    prob = cp.Problem(obj, cons)
    assert prob.is_dpp(), "QP layer must be DPP for differentiability"
    return CvxpyLayer(prob, parameters=[mu, wprev, L], variables=[w])


class DPLNet(torch.nn.Module):
    """features → μ̂ (작은 MLP). per-name expected-score head."""
    def __init__(self, n_feat, hidden=16):
        super().__init__()
        self.net = torch.nn.Sequential(
            torch.nn.Linear(n_feat, hidden),
            torch.nn.Tanh(),
            torch.nn.Linear(hidden, 1),
        )

    def forward(self, X):           # X: [n_names, n_feat]
        return self.net(X).squeeze(-1)   # μ̂: [n_names]


# ════════════════════════════════════════════════════════════════════
# 3. Walk-forward pilot
# ════════════════════════════════════════════════════════════════════
def cov_sqrt_shrunk(R_hist, shrink=0.3):
    """샘플 공분산 → Ledoit-Wolf 류 shrink-to-diagonal → 대칭제곱근(L)."""
    S = np.cov(R_hist, rowvar=False)
    if S.ndim == 0:
        S = np.array([[float(S)]])
    d = np.diag(np.diag(S))
    S = (1 - shrink) * S + shrink * d
    S += np.eye(S.shape[0]) * 1e-6
    vals, vecs = np.linalg.eigh(S)
    vals = np.clip(vals, 1e-8, None)
    return vecs @ np.diag(np.sqrt(vals)) @ vecs.T


def run_pilot():
    print("[dpl] loading panels ...")
    panel, feat_cols = load_feature_panel()
    rets, liq, bm_m = build_returns_and_liq()
    print(f"[dpl] features={feat_cols}  panel_rows={len(panel)}  ret_rows={len(rets)}")

    # 월별 키 정렬: 피처(ym) ⋈ forward ret(ym) ⋈ liq(ym)
    panel = panel.merge(rets, on=["ym", "Ticker"], how="inner")
    panel = panel.merge(liq, on=["ym", "Ticker"], how="left")
    # 유동성 필터 (t-1 ADV, adv 결측은 통과 — rawdata 초기 종목)
    panel = panel[(panel["adv"].isna()) | (panel["adv"] >= LIQ_MIN)].copy()

    months = sorted(panel["ym"].unique())
    # lockbox: 정규 리서치(alpha-stage) — 학습/판정 month-end ≤ lockbox
    lock_period = LOCKBOX.to_period("M")
    months = [m for m in months if m <= lock_period]
    print(f"[dpl] usable months (≤lockbox {lock_period}): {len(months)}  "
          f"[{months[0]} .. {months[-1]}]")

    # walk-forward 분할: 초기 학습창 이후 매월 1-step OOS 예측, 학습은 expanding(점진).
    MIN_TRAIN = 60           # 최소 60개월 학습 후 OOS 시작
    REFIT_EVERY = 24         # 24개월마다 재학습 (계산 절감)
    TRAIN_WINDOW = 72        # rolling 학습창(월) — full-expanding 대비 QP solve 수 제한
    HIST_COV = 36            # 공분산 추정용 과거 월 수
    LAM, GAM = 5.0, 1.0
    LR, EPOCHS = 8e-3, 25

    qp_cache = {}
    # cvxpylayers diffcp는 CPU tensor만 지원(GPU→numpy 변환 불가). QP는 ≤25차원 소규모라 CPU 충분.
    device = "cpu"

    def month_tensors(m):
        sub = panel[panel["ym"] == m]
        X = torch.tensor(sub[feat_cols].values, dtype=torch.float64, device=device)
        r = torch.tensor(sub["Ret_1m"].values, dtype=torch.float64, device=device)
        tickers = sub["Ticker"].values
        return X, r, tickers

    # 종목별 forward-ret 시계열 (공분산용) — wide pivot
    rwide = panel.pivot_table(index="ym", columns="Ticker", values="Ret_1m")

    def train_model(train_months):
        model = DPLNet(len(feat_cols)).to(device).double()
        opt = torch.optim.Adam(model.parameters(), lr=LR)
        for ep in range(EPOCHS):
            opt.zero_grad()
            port_rets = []
            wprev_map = {}
            for m in train_months:
                X, r, tk = month_tensors(m)
                if len(tk) < 6:
                    continue
                # top-25 universe 사전제약 (≤25 active, 그리고 QP 차원 축소)
                mu_all = model(X)
                k = min(ACTIVE_MAX, len(tk))
                idx = torch.topk(mu_all.detach(), k).indices
                mu = mu_all[idx]
                r_sel = r[idx]
                tk_sel = tk[idx.cpu().numpy()]
                n = k
                if n not in qp_cache:
                    qp_cache[n] = make_qp_layer(n, lam=LAM, gam=GAM)
                layer = qp_cache[n]
                # 공분산 L (과거 HIST_COV 월, top-25 종목, PIT: m 이전만)
                hist = rwide.loc[rwide.index < m, tk_sel].tail(HIST_COV)
                hist = hist.dropna(axis=1, how="all").fillna(0.0)
                if hist.shape[1] != n or hist.shape[0] < 6:
                    Lmat = np.eye(n) * 0.05
                else:
                    Lmat = cov_sqrt_shrunk(hist.values)
                Lt = torch.tensor(Lmat, dtype=torch.float64, device=device)
                wprev = torch.tensor(
                    np.array([wprev_map.get(t, 0.0) for t in tk_sel]),
                    dtype=torch.float64, device=device)
                w, = layer(mu, wprev, Lt)
                traded = (w - wprev).abs().sum()
                cost = traded * COST_BPS_ONEWAY / 1e4
                port_rets.append((w * r_sel).sum() - cost)
                wprev_map = {t: float(v) for t, v in zip(tk_sel, w.detach().cpu().numpy())}
            if len(port_rets) < 12:
                return model
            pr = torch.stack(port_rets)
            sharpe = pr.mean() / (pr.std() + 1e-6) * np.sqrt(ANNUALIZE)
            loss = -sharpe + 0.5 * (pr - pr.mean()).pow(2).mean()  # neg Sharpe + var reg
            loss.backward()
            opt.step()
        return model

    # ── OOS walk-forward 예측 ────────────────────────────────────────
    @torch.no_grad()
    def dpl_weights_for_month(model, m, wprev_map):
        X, r, tk = month_tensors(m)
        if len(tk) < 6:
            return None, None, wprev_map
        mu_all = model(X)
        k = min(ACTIVE_MAX, len(tk))
        idx = torch.topk(mu_all, k).indices
        mu = mu_all[idx]; tk_sel = tk[idx.cpu().numpy()]; n = k
        if n not in qp_cache:
            qp_cache[n] = make_qp_layer(n, lam=LAM, gam=GAM)
        layer = qp_cache[n]
        hist = rwide.loc[rwide.index < m, tk_sel].tail(HIST_COV)
        hist = hist.dropna(axis=1, how="all").fillna(0.0)
        Lmat = cov_sqrt_shrunk(hist.values) if (hist.shape[1] == n and hist.shape[0] >= 6) else np.eye(n)*0.05
        Lt = torch.tensor(Lmat, dtype=torch.float64, device=device)
        wprev = torch.tensor(np.array([wprev_map.get(t, 0.0) for t in tk_sel]),
                             dtype=torch.float64, device=device)
        w, = layer(mu, wprev, Lt)
        wv = w.cpu().numpy()
        new_prev = {t: float(v) for t, v in zip(tk_sel, wv)}
        return tk_sel, wv, new_prev

    oos_dpl = []      # (ym, Ticker, w)
    wprev_map = {}
    model = None
    start_i = MIN_TRAIN
    for i in range(start_i, len(months)):
        m = months[i]
        if (model is None) or ((i - start_i) % REFIT_EVERY == 0):
            tr = months[max(0, i - TRAIN_WINDOW):i]   # rolling window
            print(f"[dpl] refit @ {m} (train {tr[0]}..{tr[-1]}, {len(tr)} months)")
            model = train_model(tr)
        tk_sel, wv, wprev_map = dpl_weights_for_month(model, m, wprev_map)
        if tk_sel is None:
            continue
        for t, v in zip(tk_sel, wv):
            if v > 1e-5:
                oos_dpl.append((m, t, float(v)))
    dpl_w = pd.DataFrame(oos_dpl, columns=["ym", "Ticker", "w"])
    print(f"[dpl] OOS months={dpl_w['ym'].nunique()}  weight_rows={len(dpl_w)}")

    # ── baseline weights (동일 OOS months, 동일 universe panel) ──────
    oos_months = sorted(dpl_w["ym"].unique())
    pan_oos = panel[panel["ym"].isin(oos_months)].copy()

    # EW top-N: 각 월 alpha_score 합산(피처 평균) 상위 N EW
    pan_oos["score_ew"] = pan_oos[feat_cols].mean(axis=1)
    ew_rows = []
    for m, g in pan_oos.groupby("ym"):
        top = g.nlargest(TOP_N_EW, "score_ew")
        wv = 1.0 / len(top)
        for t in top["Ticker"]:
            ew_rows.append((m, t, wv))
    ew_w = pd.DataFrame(ew_rows, columns=["ym", "Ticker", "w"])

    # 2-stage MVO: μ̂=score_ew, Σ=shrunk hist cov, analytic long-only QP (cvxpy, top-25 univ)
    mvo_rows = []
    for m, g in pan_oos.groupby("ym"):
        g2 = g.nlargest(ACTIVE_MAX, "score_ew")
        tk = g2["Ticker"].values
        mu = g2["score_ew"].values
        n = len(tk)
        if n < 5:
            continue
        hist = rwide.loc[rwide.index < m, tk].tail(HIST_COV).dropna(axis=1, how="all").fillna(0.0)
        S = cov_sqrt_shrunk(hist.values) if (hist.shape[1] == n and hist.shape[0] >= 6) else np.eye(n)*0.05
        Sig = S @ S.T
        wv = cp.Variable(n)
        prob = cp.Problem(cp.Maximize(mu @ wv - 5.0 * cp.quad_form(wv, cp.psd_wrap(Sig))),
                          [wv >= 0, cp.sum(wv) == 1, wv <= CAP])
        prob.solve(solver=cp.CLARABEL)
        if wv.value is None:
            continue
        for t, v in zip(tk, wv.value):
            if v > 1e-5:
                mvo_rows.append((m, t, float(v)))
    mvo_w = pd.DataFrame(mvo_rows, columns=["ym", "Ticker", "w"])

    # ── 월별 net return series (3 방법) — cost 규약 canonical_screen_bt 정합 ──
    def net_return_series(wdf):
        wj = wdf.merge(rets, on=["ym", "Ticker"], how="left")
        wj["Ret_1m"] = wj["Ret_1m"].fillna(0.0)
        gross = wj.groupby("ym").apply(lambda x: np.sum(x["w"] * x["Ret_1m"])).rename("port_gross")
        # turnover traded_t = Σ|w_t - w_{t-1}| (ticker union)
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
        return out

    series = {}
    for name, wdf in [("DPL", dpl_w), ("EW_topN", ew_w), ("MVO_2stage", mvo_w)]:
        s = net_return_series(wdf)
        s = s.merge(bm_m, on="ym", how="left")
        s["date"] = s["ym"].dt.to_timestamp("M")
        series[name] = s
        print(f"[{name}] months={len(s)}  mean_net={s['ret_net'].mean():.5f}  "
              f"mean_traded={s['traded'].mean():.4f}  turnover_ann={s['traded'].mean()*12:.2f}")

    # export for R contract (단일 long parquet)
    rows = []
    for name, s in series.items():
        for _, r in s.iterrows():
            rows.append({"method": name, "date": r["date"],
                         "ret_net": r["ret_net"], "BM_Ret": r["BM_Ret_1m"],
                         "traded": r["traded"]})
    out_df = pd.DataFrame(rows)
    out_path = os.path.join(OUT_DIR, "dpl_pilot_net_returns.parquet")
    out_df.to_parquet(out_path, index=False)

    # weights export (감사/재현)
    dpl_w.assign(date=lambda d: d["ym"].dt.to_timestamp("M")).to_parquet(
        os.path.join(OUT_DIR, "dpl_weights.parquet"), index=False)

    meta = {
        "feature_cols": feat_cols,
        "n_oos_months": int(len(oos_months)),
        "oos_range": [str(oos_months[0]), str(oos_months[-1])],
        "lockbox": str(LOCKBOX.date()),
        "constraints": {"long_only": True, "cap": CAP, "active_max": ACTIVE_MAX,
                        "sum_w": 1.0, "cost_bps_oneway": COST_BPS_ONEWAY,
                        "liq_min": LIQ_MIN, "top_n_ew": TOP_N_EW},
        "hyperparams": {"lambda_risk": LAM, "gamma_turnover": GAM, "lr": LR,
                        "epochs": EPOCHS, "min_train": MIN_TRAIN,
                        "refit_every": REFIT_EVERY, "hist_cov": HIST_COV},
        "self_synth_note": "월별 net return series만 산출. portfolio_alpha_t_nw_lag3 등 "
                           "contract-grade 수치는 R build_benchmark_compare() 단일 경로.",
        "out_net_returns": out_path,
    }
    with open(os.path.join(OUT_DIR, "dpl_pilot_meta.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f"[dpl] exported -> {out_path}")
    print(f"[dpl] meta -> {os.path.join(OUT_DIR, 'dpl_pilot_meta.json')}")
    return out_path


if __name__ == "__main__":
    run_pilot()
