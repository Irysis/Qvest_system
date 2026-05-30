#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_regime_export.py — Qvest v8.x Dev-CBE Track B: month-end regime score export (PIT t-1).

목적 (β-overlay 합성용):
  DPL에 cash node (w_cash = 1 - Σw_risky) 를 추가해 regime-conditional 시장노출을 end-to-end
  학습하려면, 학습/평가 매월말에 "그 시점에 알 수 있던" regime score 1개가 필요하다.

설계 (self-contained, 05_Production 비의존):
  - benchmark 일간 수익(rawdata BM_Ret) → 누적 BM_Close index.
  - 252d AR-style trend score = 252거래일 누적수익(= BM[t]/BM[t-252]-1) 의 cross-time z-like 신호.
    추가로 60d 단기 trend, 252d 실현변동성도 동반 export(진단/대안용).
  - ★ PIT: 각 월 ym의 regime score = "직전 월말(ym-1) EOM"에 관측된 252d trend (t-1 lag).
    즉 의사결정 시점 t(ym 리밸 시점)에서는 ym-1 월말까지의 정보만 사용 → lookahead 없음.
  - q70/q90 분위 임계는 expanding(누적) 분위로 산출(C1 — full-sample 분위 금지):
    각 월의 임계 = 그 월 이전(<=ym-1)까지 관측된 trend 의 expanding q70/q90.
    이로써 "현재가 강세/약세 국면인가"를 미래정보 없이 판정.

출력: stage_artifacts/WT_DPL_GPU_SWEEP/regime_monthly.parquet
  columns: ym(str, 리밸 시점) , trend_252, trend_60, rvol_252, q70_exp, q90_exp,
           regime_score(0~1, 시장노출 prior), regime_bucket(BULL/NORMAL/CAUTION/CRISIS)
  + bm_close_eom.parquet (Date, BM_Close) — bear_date_audit / validate_label_direction 검증용.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_regime_export.py
"""
import os
import numpy as np
import pandas as pd

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
RAWDATA = os.path.join(PROJECT_ROOT, ".cache", "rawdata.parquet")
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")

START_YEAR = 2003          # warmup for 252d trend prior to 2005 panel start
LB_LONG = 252
LB_SHORT = 60


def build_bm_close():
    raw = pd.read_parquet(RAWDATA, columns=["Date", "BM_Ret"])
    raw["Date"] = pd.to_datetime(raw["Date"])
    raw = raw.dropna(subset=["BM_Ret"]).drop_duplicates("Date").sort_values("Date")
    raw = raw[raw["Date"] >= pd.Timestamp(f"{START_YEAR}-01-01")]
    # cumulative index from daily returns (level for ratio-based trend/audit)
    raw["BM_Close"] = 100.0 * np.cumprod(1.0 + raw["BM_Ret"].values)
    return raw[["Date", "BM_Close", "BM_Ret"]].reset_index(drop=True)


def build_regime(bm):
    """252d / 60d backward trend + 252d realized vol at each trading day (backward-only)."""
    c = bm["BM_Close"].values
    n = len(c)
    trend252 = np.full(n, np.nan)
    trend60 = np.full(n, np.nan)
    rvol252 = np.full(n, np.nan)
    r = bm["BM_Ret"].values
    for i in range(n):
        if i >= LB_LONG:
            trend252[i] = c[i] / c[i - LB_LONG] - 1.0          # BACKWARD (past 252d)
            rvol252[i] = np.std(r[i - LB_LONG + 1:i + 1]) * np.sqrt(252.0)
        if i >= LB_SHORT:
            trend60[i] = c[i] / c[i - LB_SHORT] - 1.0
    bm = bm.copy()
    bm["trend_252"] = trend252
    bm["trend_60"] = trend60
    bm["rvol_252"] = rvol252
    bm["ym"] = bm["Date"].dt.to_period("M")
    return bm


def month_end_snapshot(bm):
    """각 월말(EOM)의 trend/rvol — 그 월말 시점까지의 backward 정보."""
    eom = bm.groupby("ym").tail(1).copy()
    eom = eom.sort_values("ym").reset_index(drop=True)
    # expanding q70/q90 of trend_252 using ONLY months strictly before current month-end
    # (C1: 미래정보 금지 — shift(1)로 현재월 자신도 제외).
    t = eom["trend_252"]
    eom["q70_exp"] = t.expanding(min_periods=24).quantile(0.30).shift(1)   # q30 of trend = q70 caution threshold (low trend = bad)
    eom["q90_exp"] = t.expanding(min_periods=24).quantile(0.10).shift(1)   # q10 of trend = crisis threshold
    eom["q_bull_exp"] = t.expanding(min_periods=24).quantile(0.70).shift(1)
    return eom


def regime_score_and_bucket(eom):
    """regime_score in [0,1] = market-exposure prior (1=full bull, 0=defensive).

    매핑(PIT-safe, expanding 분위 기준):
      trend_252 >= q_bull (top 30%)        → BULL    score 1.00
      q70(=q30 trend) <= trend < q_bull    → NORMAL  score 0.85
      q90(=q10 trend) <= trend < q70       → CAUTION score 0.55
      trend < q90 (bottom 10%)             → CRISIS  score 0.25
    (cash node target prior; DPL이 이 prior 주변에서 노출을 학습하도록 입력 feature로 제공.)
    """
    def classify(row):
        t = row["trend_252"]
        if not np.isfinite(t) or not np.isfinite(row["q70_exp"]):
            return ("NORMAL", 0.85)
        if t >= row["q_bull_exp"]:
            return ("BULL", 1.00)
        if t >= row["q70_exp"]:
            return ("NORMAL", 0.85)
        if t >= row["q90_exp"]:
            return ("CAUTION", 0.55)
        return ("CRISIS", 0.25)
    bs = eom.apply(classify, axis=1)
    eom["regime_bucket"] = [b[0] for b in bs]
    eom["regime_score"] = [b[1] for b in bs]
    return eom


def main():
    bm = build_bm_close()
    print(f"[regime] BM daily rows={len(bm)} range=[{bm['Date'].min().date()}..{bm['Date'].max().date()}]")
    bm = build_regime(bm)
    eom = month_end_snapshot(bm)
    eom = regime_score_and_bucket(eom)

    # ★ PIT t-1: 리밸 시점 ym 에 사용할 regime = 직전 월말(ym-1) EOM snapshot.
    #   shift(1) on the month-ordered EOM table → regime_used_at[ym] = regime_observed_at[ym-1].
    out = eom[["ym", "trend_252", "trend_60", "rvol_252",
               "q70_exp", "q90_exp", "regime_bucket", "regime_score"]].copy()
    for col in ["trend_252", "trend_60", "rvol_252", "regime_bucket", "regime_score"]:
        out[col + "_t1"] = out[col].shift(1)          # value observed at PREVIOUS month-end
    # 사용 컬럼: *_t1 가 의사결정 시점 정보. ym 은 리밸(적용) 시점.
    out_use = out[["ym", "regime_score_t1", "regime_bucket_t1",
                   "trend_252_t1", "rvol_252_t1"]].copy()
    out_use.columns = ["ym", "regime_score", "regime_bucket", "trend_252", "rvol_252"]
    out_use["ym"] = out_use["ym"].astype(str)
    out_use = out_use.dropna(subset=["regime_score"])

    out_path = os.path.join(OUT_DIR, "regime_monthly.parquet")
    out_use.to_parquet(out_path, index=False)

    # bear_date_audit / validate_label_direction 검증용 daily BM_Close
    bm[["Date", "BM_Close"]].to_parquet(
        os.path.join(OUT_DIR, "bm_close_eom.parquet"), index=False)

    dist = out_use["regime_bucket"].value_counts().to_dict()
    print(f"[regime] month-end regime exported: {len(out_use)} months "
          f"[{out_use['ym'].min()}..{out_use['ym'].max()}]")
    print(f"[regime] bucket distribution (t-1 applied): {dist}")
    print(f"[regime] regime_score mean={out_use['regime_score'].mean():.3f} "
          f"min={out_use['regime_score'].min():.2f} max={out_use['regime_score'].max():.2f}")
    print(f"[regime] -> {out_path}")
    # quick PIT sanity: 2020-03 (COVID) should inherit a low score (CRISIS/CAUTION) from 2020-02 EOM trend
    for ym in ["2020-02", "2020-03", "2020-04", "2008-10", "2008-11"]:
        row = out_use[out_use["ym"] == ym]
        if len(row):
            print(f"  PIT check {ym}: score={row['regime_score'].iloc[0]:.2f} "
                  f"bucket={row['regime_bucket'].iloc[0]} (uses {ym} 직전월말 trend)")


if __name__ == "__main__":
    main()
