#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_feature_builder.py — Qvest v8.x: 일간 Factor DB → 팩터특성별 커스텀 롤링피처 → 월간 패널 + label.

도훈 설계 (핵심):
  - .cache/factor_db_daily/ (309 daily factor, wide). 카테고리별 배치 로드(22GB 전체 로드 금지).
  - factor_registry.json category 기준 팩터특성별 롤링 윈도우:
      momentum  → 252/21d   value/quality/accrual/growth → 252/63d
      liquidity/investor_flow → 60/20d   volatility(risk/defense) → 120/60d
      consensus → 63/21d   crowding → 120/60d   technical → 21/5d   regime → 120/60d
  - 팩터당 롤링 통계 3종: level z-score(현재값 단면표준화) + slope(추세 OLS) + rolling vol(안정성).
  - 월말 snapshot(rebal date 정렬).

★ PIT 절대규율 (Cycle 50 lookahead 사건 재발 방지):
  - 모든 롤링피처 backward only (t-1 이전 데이터로 t 시점 피처). forward는 label(미래 1M 수익)만.
  - data.table::shift 부호규칙의 pandas 등가: rolling은 과거창, label은 .shift(-1) 명시 forward.
  - 산출 후 R validate_label_direction() + bear_date_audit.R 통과 의무(run_all.R에서 호출).

피처폭발 대응: 카테고리당 대표 팩터만 선별(전체 316 → 커스텀 subset). 정규화는 sweep 단계.

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_feature_builder.py
한글경로 회피: __file__ 기준 상대경로.
"""
import os
import re
import json
import gc
import numpy as np
import pandas as pd

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
DAILY_DIR = os.path.join(PROJECT_ROOT, ".cache", "factor_db_daily")
REGISTRY = os.path.join(PROJECT_ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
RAWDATA = os.path.join(PROJECT_ROOT, ".cache", "rawdata.parquet")
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
os.makedirs(OUT_DIR, exist_ok=True)

LOCKBOX = pd.Timestamp("2023-12-22")
LIQ_MIN = 2e8
# 메모리 bound (RAM≤4GB/proc 규율): daily 전체 1990~ 로드 금지. min_train 60m + lookback 120m + cov 36m
# 여유 위해 2005부터 (lockbox 2023-12까지 ~19년 = 충분). KOSPI200/KQ150 체제 정합.
START_YEAR = 2005

# ── 카테고리별 롤링 윈도우 (거래일 기준) ─────────────────────────────────
# (long_window, short_window) — 팩터 특성에 맞춘 커스텀 lookback.
CATEGORY_WINDOWS = {
    "momentum":      (252, 21),
    "value":         (252, 63),
    "quality":       (252, 63),
    "accrual":       (252, 63),
    "growth":        (252, 63),
    "liquidity":     (60, 20),
    "investor_flow": (60, 20),
    "risk":          (120, 60),
    "defense":       (120, 60),
    "consensus":     (63, 21),
    "crowding":      (120, 60),
    "technical":     (21, 5),
    "regime":        (120, 60),
    "size":          (252, 63),
}

# ── 카테고리별 대표 팩터 선별 (피처폭발 방지: 전체 316 → 커스텀 subset) ──
# 각 카테고리 핵심 팩터만. KR 실증 정합(momentum/quality/value/flow 중심) + 다양성.
SELECTED_FACTORS = {
    "momentum":      ["M01_Mom_12_1", "M02_Mom_6_1", "M03_Mom_3_1", "M05_Trended_Mom", "M11_ST_Reversal"],
    "value":         ["V02_EP", "V03_CFP", "V10_FCF_Yield", "V12_Composite_Value", "V14_EBIT_EV"],
    "quality":       ["Q01_GPA", "Q02_ROE", "Q03_ROA"],
    "accrual":       ["AC01_Total_Accruals_CF", "AC10_Pct_Accruals"],
    "growth":        ["GR01_Revenue_Growth"],
    "liquidity":     ["L01_Amihud", "L02_Turnover"],
    "investor_flow": ["INV01_Foreign_NetBuy_20d", "INV03_Inst_NetBuy_20d"],
    "risk":          ["R03_CVaR_95"],
    "defense":       ["D01_IdioVol", "D02_Beta", "D03_RealVol"],
    "consensus":     ["C01_SUE", "C02_EPS_Chg_1m"],
    "crowding":      ["CR09_Money_Flow_Ratio"],
    "technical":     ["T01_RSI14"],
    "regime":        ["RE_MRS"],
    "size":          ["S01_Size"],
}


def _load_registry_categories():
    reg = json.load(open(REGISTRY))
    return {k: v.get("category", "?") for k, v in reg.items()}


def _month_files():
    files = sorted(f for f in os.listdir(DAILY_DIR) if re.match(r"fdb_daily_\d{6}\.parquet", f))
    files = [f for f in files if int(f[10:14]) >= START_YEAR]
    return [os.path.join(DAILY_DIR, f) for f in files]


def _rolling_slope_vec(series_by_ticker, window, min_periods):
    """Vectorized rolling OLS slope per ticker group.

    For fixed window with index t=0..w-1 (within-window), slope = cov(y, t) / var(t).
    var(t) constant → slope = (mean(y*t) - mean(y)*mean(t)) / var(t).
    rolling.mean으로 벡터화(per-window .apply 회피 — 100x+ 빠름). backward-only window.
    """
    w = window
    t = np.arange(w, dtype=float)
    t_mean = t.mean()
    t_var = ((t - t_mean) ** 2).mean()  # population var of index
    # within each ticker: rolling mean of y and of y*weighted-index is non-trivial because
    # the index resets each window. Use the equivalent: slope = sum((t-tbar)(y-ybar)) / sum((t-tbar)^2)
    # = [sum(t*y) - w*tbar*ybar] / [w*t_var]. rolling sums of y and of (positional) require
    # multiplying y by its position within window — approximate via correlation of y with a ramp.
    # Exact vectorization: use rolling apply only on the linear-weighted term via convolution-free
    # trick: weight_k = (t_k - tbar). Then numerator_t = sum_k weight_k * y_{t-w+1+k}.
    weights = (t - t_mean)  # length w, fixed
    denom = (weights ** 2).sum()

    def per_ticker(y):
        yv = y.values.astype(float)
        out = np.full(len(yv), np.nan)
        if len(yv) < min_periods:
            return pd.Series(out, index=y.index)
        # sliding window dot product with fixed weights
        from numpy.lib.stride_tricks import sliding_window_view
        if len(yv) >= w:
            sw = sliding_window_view(yv, w)  # (len-w+1, w)
            # NaN-robust: mask
            valid = (~np.isnan(sw)).sum(axis=1) >= min_periods
            swf = np.nan_to_num(sw, nan=0.0)
            num = swf @ weights
            slope = np.where(valid & (denom > 0), num / denom, np.nan)
            out[w - 1:] = slope
        return pd.Series(out, index=y.index)

    return series_by_ticker.transform(per_ticker)


def build_features():
    """일간 Factor DB → 팩터특성별 롤링피처 → 월말 snapshot 패널.

    PIT: 각 월말(rebal) 시점에서 그 월말까지의 일간 데이터로만 롤링 통계 산출(backward).
    label(forward 1M return)은 별도(build_labels)에서 .shift(-1) 명시.
    """
    cats = _load_registry_categories()
    files = _month_files()
    # 사용 팩터 flat list
    use_factors = sorted({f for lst in SELECTED_FACTORS.values() for f in lst})
    cols_needed = ["Date", "Ticker"] + use_factors
    print(f"[feat] selected factors: {len(use_factors)} across {len(SELECTED_FACTORS)} categories")

    # ── 일간 데이터 누적 로드 (카테고리 배치가 아닌 컬럼 subset만 → RAM 효율) ──
    # 월별 parquet은 wide. 필요 컬럼만 읽음(rbindlist once). RAM≤4GB.
    frames = []
    for fp in files:
        try:
            import pyarrow.parquet as pq
            avail = set(pq.ParquetFile(fp).schema.names)
            rd = [c for c in cols_needed if c in avail]
            df = pd.read_parquet(fp, columns=rd)
            frames.append(df)
        except Exception as e:
            print(f"[feat][warn] skip {os.path.basename(fp)}: {e}")
    daily = pd.concat(frames, ignore_index=True)
    del frames
    gc.collect()
    daily["Date"] = pd.to_datetime(daily["Date"])
    daily = daily.sort_values(["Ticker", "Date"])
    # 결측 팩터 컬럼 보강
    for f in use_factors:
        if f not in daily.columns:
            daily[f] = np.nan
    print(f"[feat] daily rows={len(daily):,}  range=[{daily['Date'].min().date()}..{daily['Date'].max().date()}]")

    daily["ym"] = daily["Date"].dt.to_period("M")

    # ── 팩터별 롤링 통계 (그룹: Ticker, 시계열은 backward window) ──────────
    g = daily.groupby("Ticker", sort=False)
    feat_frames = []
    for cat, flist in SELECTED_FACTORS.items():
        lw, sw = CATEGORY_WINDOWS[cat]
        for f in flist:
            if f not in daily.columns:
                continue
            s = daily[f]
            # level: 원값(이후 월말 단면 z-score). slope: 단기창 OLS 추세. vol: 장기창 표준편차.
            lvl = s  # 현재값 (월말 snapshot에서 단면 z)
            slope = _rolling_slope_vec(g[f], window=sw, min_periods=max(3, sw // 2))
            vol = g[f].transform(
                lambda x: x.rolling(lw, min_periods=max(10, lw // 4)).std())
            feat_frames.append(pd.DataFrame({
                f"{f}__lvl": lvl,
                f"{f}__slp": slope,
                f"{f}__vol": vol,
            }, index=daily.index))
    feats = pd.concat([daily[["Date", "Ticker", "ym"]]] + feat_frames, axis=1)
    del feat_frames, daily
    gc.collect()

    # ── 월말 snapshot: 각 Ticker·월의 마지막 거래일 행 (그 시점까지 backward 누적) ──
    snap = feats.groupby(["Ticker", "ym"]).tail(1).copy()
    del feats
    gc.collect()

    # ── 월말 단면 z-score (level/slope/vol 각각) — 같은 시점 단면만(PIT 안전) ──
    feat_cols = [c for c in snap.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    for c in feat_cols:
        snap[c] = snap.groupby("ym")[c].transform(
            lambda v: (v - v.mean()) / (v.std(ddof=0) + 1e-9))
    snap[feat_cols] = snap[feat_cols].fillna(0.0)  # 중립 z
    print(f"[feat] monthly snapshot rows={len(snap):,}  feature_cols={len(feat_cols)}")
    return snap[["ym", "Ticker"] + feat_cols], feat_cols


def build_labels_and_universe():
    """rawdata → forward 1M label + t-1 ADV(C10) + KOSPI200∪KOSDAQ150 universe + benchmark.

    ★ forward label: month-end Close → next month-end Close (명시적 .shift(-1) per ticker).
      backward 금지 (Cycle 50 재발방지). 산출 후 R validate_label_direction PASS 의무.
    """
    raw = pd.read_parquet(RAWDATA, columns=["Date", "Ticker", "Close", "Vol", "BM_Ret",
                                            "K200", "KQ150", "AdminStock", "TradingHalt"])
    raw["Date"] = pd.to_datetime(raw["Date"])
    raw = raw[raw["Date"] >= pd.Timestamp(f"{START_YEAR - 1}-01-01")]  # -1y warmup for ADV/cov
    raw = raw.sort_values(["Ticker", "Date"])
    raw = raw[raw["Close"].notna() & (raw["Close"] > 0)]

    # 20d ADV (거래대금), t-1 lag (C10)
    raw["adv_value"] = raw["Close"] * raw["Vol"]
    raw["adv20"] = raw.groupby("Ticker")["adv_value"].transform(
        lambda s: s.rolling(20, min_periods=10).mean())
    raw["adv20_lag1"] = raw.groupby("Ticker")["adv20"].shift(1)

    raw["ym"] = raw["Date"].dt.to_period("M")
    me = raw.groupby(["Ticker", "ym"]).tail(1).copy()
    me = me.sort_values(["Ticker", "ym"])

    # forward 1M return (FORWARD — 명시 shift(-1) per ticker timeline)
    me["close_next"] = me.groupby("Ticker")["Close"].shift(-1)
    me["Ret_1m"] = me["close_next"] / me["Close"] - 1.0

    # 거래정지/관리종목 당월 제외
    bad = (me["AdminStock"].fillna(0) > 0) | (me["TradingHalt"].fillna(0) > 0)
    me.loc[bad, "Ret_1m"] = np.nan

    # universe membership: K200 OR KQ150 (월말 시점 flag, PIT: 당월 membership는 알 수 있음)
    me["in_univ"] = (me["K200"].fillna(0) > 0) | (me["KQ150"].fillna(0) > 0)

    labels = me[["ym", "Ticker", "Ret_1m", "adv20_lag1", "in_univ"]].rename(
        columns={"adv20_lag1": "adv"})
    labels = labels.dropna(subset=["Ret_1m"])
    labels = labels[labels["in_univ"]].copy()

    # benchmark monthly (compound daily BM_Ret)
    bm = raw[["Date", "ym", "BM_Ret"]].dropna(subset=["BM_Ret"]).drop_duplicates(["Date"])
    bm_m = bm.groupby("ym")["BM_Ret"].apply(lambda s: float(np.prod(1.0 + s.values) - 1.0))
    bm_m = bm_m.reset_index().rename(columns={"BM_Ret": "BM_Ret_1m"})
    return labels, bm_m


def main():
    print("[feat] building rolling features from daily Factor DB ...")
    snap, feat_cols = build_features()
    print("[feat] building forward labels + universe ...")
    labels, bm_m = build_labels_and_universe()

    # merge: 피처(ym,Ticker) ⋈ label/univ/adv ⋈ — PIT: 피처는 t까지 backward, label은 forward
    panel = snap.merge(labels, on=["ym", "Ticker"], how="inner")
    # 유동성 필터 (t-1 ADV, 결측 통과)
    panel = panel[(panel["adv"].isna()) | (panel["adv"] >= LIQ_MIN)].copy()

    out_panel = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
    panel["date"] = panel["ym"].dt.to_timestamp("M")
    panel.to_parquet(out_panel, index=False)
    bm_path = os.path.join(OUT_DIR, "benchmark_monthly.parquet")
    bm_m["date"] = bm_m["ym"].dt.to_timestamp("M")
    bm_m.to_parquet(bm_path, index=False)

    meta = {
        "n_feature_cols": len(feat_cols),
        "feature_cols": feat_cols,
        "n_selected_factors": sum(len(v) for v in SELECTED_FACTORS.values()),
        "selected_factors": SELECTED_FACTORS,
        "category_windows": CATEGORY_WINDOWS,
        "stats_per_factor": ["lvl(level z)", "slp(short-window OLS slope)", "vol(long-window std)"],
        "panel_rows": int(len(panel)),
        "n_months": int(panel["ym"].nunique()),
        "month_range": [str(panel["ym"].min()), str(panel["ym"].max())],
        "lockbox": str(LOCKBOX.date()),
        "liq_min": LIQ_MIN,
        "universe": "KOSPI200 ∪ KOSDAQ150 (K200|KQ150 flag, month-end)",
        "pit_note": "rolling features backward-only; label=forward 1M (shift(-1)); "
                    "R validate_label_direction + bear_date_audit PASS 의무.",
        "out_panel": out_panel,
        "out_benchmark": bm_path,
    }
    with open(os.path.join(OUT_DIR, "feature_panel_meta.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f"[feat] panel -> {out_panel}  rows={len(panel):,}  feats={len(feat_cols)}  "
          f"months={panel['ym'].nunique()}")
    print(f"[feat] meta -> {os.path.join(OUT_DIR, 'feature_panel_meta.json')}")


if __name__ == "__main__":
    main()
