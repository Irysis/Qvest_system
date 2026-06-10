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

결측 팩터 정직화 (2026-06-10 P1 — 침묵 NaN 금지):
  - SELECTED_FACTORS 중 일간 DB에 없는 컬럼(전 파일 부재) + 최신월 파일 탈락(trailing gap)
    발견 시 명시 [WARN] 출력 + manifest(stage_artifacts/WT_DPL_GPU_SWEEP/dpl_feature_manifest.json)에
    missing_factors / trailing_gap_factors 기록.
  - 실측 (2026-06-10): INV01_Foreign_NetBuy_20d / INV03_Inst_NetBuy_20d 등 INV* 12컬럼이
    fdb_daily 202603까지 존재(318col) → 202604/202605 빌드에서 탈락(306col) = trailing gap.
    월간 factor_db에는 INV01/INV03 존재 (202605 포함).
  - 월간 DB 브릿지 옵션: DPL_USE_MONTHLY_BRIDGE=1 시 월간 factor_db(long)에서 읽어
    일간으로 backward-asof forward-fill, NaN 행만 채움 (기본 OFF — DPL 재실행 시 명시 결정).

실행: cd <root> && source /home/quant/.venvs/qvest_ml/bin/activate
      python 02_Infrastructure/ml_pipeline/dpl_feature_builder.py
한글경로 회피: __file__ 기준 상대경로.
"""
import os
import re
import sys
import json
import gc
import numpy as np
import pandas as pd

# Windows-native 콘솔(cp949)에서 한글/유니코드 print 깨짐 방지 (2026-06-10 P1)
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
DAILY_DIR = os.path.join(PROJECT_ROOT, ".cache", "factor_db_daily")
MONTHLY_DIR = os.path.join(PROJECT_ROOT, ".cache", "factor_db")  # 월간 long DB (브릿지 소스)
REGISTRY = os.path.join(PROJECT_ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
RAWDATA = os.path.join(PROJECT_ROOT, ".cache", "rawdata.parquet")
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
os.makedirs(OUT_DIR, exist_ok=True)
MANIFEST_PATH = os.path.join(OUT_DIR, "dpl_feature_manifest.json")

# ── 월간 DB 브릿지 (기본 OFF — DPL 재실행 시 결정, 2026-06-10 P1) ────────────
# 일간 DB에 없는 SELECTED 팩터(INV01/INV03 등)를 월간 factor_db(long:
# Date/Ticker/Factor_Name/Raw_Value/Z_Score)에서 읽어 일간 (Ticker,Date)로
# backward-asof forward-fill. PIT: 월말 관측치를 그 일자 및 이후 일자에만 적용.
# 기본 OFF인 이유: 월간 step-function ffill은 단기창(slope/vol) 롤링 통계가
# 계단 아티팩트가 되므로 사용 여부는 DPL 재실행 시 명시적으로 결정.
USE_MONTHLY_BRIDGE = os.environ.get("DPL_USE_MONTHLY_BRIDGE", "0") == "1"
BRIDGE_TOLERANCE_DAYS = 35  # 월말 관측 이후 최대 carry-forward (다음 월말 + 여유)

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
    # encoding 명시 (Windows-native cp949 기본값 → UTF-8 registry decode 오류 방지, 2026-06-10)
    reg = json.load(open(REGISTRY, encoding="utf-8"))
    return {k: v.get("category", "?") for k, v in reg.items()}


def _write_manifest(manifest):
    """피처 가용성 manifest 기록 (침묵 NaN 금지 — 2026-06-10 P1)."""
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    print(f"[feat] availability manifest -> {MANIFEST_PATH}")


def _bridge_monthly_to_daily(daily, missing):
    """월간 factor_db(long)에서 결측 팩터를 읽어 일간으로 backward-asof ffill.

    PIT: 월말 관측치(Date=관측일)를 그 일자 및 이후 일자에만 적용(direction="backward",
    tolerance=BRIDGE_TOLERANCE_DAYS) — lookahead 없음.
    값: Raw_Value 우선, 전결측이면 Z_Score 폴백 (팩터 단위 결정).
    대상 2유형: 컬럼 전체 부재(전기간 채움) / trailing gap(기존 일간값 보존, NaN 행만 채움).
    반환: (daily, bridged, failed). 호출은 USE_MONTHLY_BRIDGE=1일 때만.
    """
    lo = (daily["Date"].min().to_period("M") - 1).strftime("%Y%m")
    hi = daily["Date"].max().strftime("%Y%m")
    if not os.path.isdir(MONTHLY_DIR):
        print(f"[feat][bridge][WARN] 월간 DB 디렉토리 없음: {MONTHLY_DIR} — bridge skip")
        return daily, [], list(missing)
    mfiles = sorted(f for f in os.listdir(MONTHLY_DIR)
                    if re.match(r"factor_db_\d{6}\.parquet$", f) and lo <= f[10:16] <= hi)
    rows = []
    for fb in mfiles:
        fp = os.path.join(MONTHLY_DIR, fb)
        try:
            df = pd.read_parquet(
                fp, columns=["Date", "Ticker", "Factor_Name", "Raw_Value", "Z_Score"],
                filters=[("Factor_Name", "in", list(missing))])
            if len(df):
                rows.append(df)
        except Exception as e:
            print(f"[feat][bridge][warn] skip {fb}: {e}")
    if not rows:
        print(f"[feat][bridge][WARN] 월간 DB({len(mfiles)} files)에서 {missing} 미발견 — bridge 실패")
        return daily, [], list(missing)
    mlong = pd.concat(rows, ignore_index=True)
    mlong["Date"] = pd.to_datetime(mlong["Date"])
    base = daily[["Date", "Ticker"]].copy()
    base["__row"] = np.arange(len(base))
    base = base.sort_values("Date", kind="mergesort")  # merge_asof: on-key 전역 정렬 필수
    bridged, failed = [], []
    for f in missing:
        mf = mlong[mlong["Factor_Name"] == f]
        if mf.empty:
            print(f"[feat][bridge][WARN] {f}: 월간 DB에도 없음 — NaN 유지")
            failed.append(f)
            continue
        use_raw = bool(mf["Raw_Value"].notna().any())
        mfv = pd.DataFrame({
            "Date": mf["Date"].values,
            "Ticker": mf["Ticker"].values,
            "__val": (mf["Raw_Value"] if use_raw else mf["Z_Score"]).values,
        }).dropna(subset=["__val"]).sort_values("Date", kind="mergesort")
        if mfv.empty:
            failed.append(f)
            continue
        merged = pd.merge_asof(base, mfv, on="Date", by="Ticker", direction="backward",
                               tolerance=pd.Timedelta(days=BRIDGE_TOLERANCE_DAYS))
        out = np.full(len(daily), np.nan)
        out[merged["__row"].values] = merged["__val"].values
        if f in daily.columns:
            # trailing gap: 기존 일간 native 값 보존, NaN 행만 월간값으로 채움
            cur = daily[f].to_numpy(dtype=float, copy=True)  # 위치 기준
            fill_mask = ~np.isfinite(cur) & np.isfinite(out)
            cur[fill_mask] = out[fill_mask]
            daily[f] = cur
            n_fill = int(fill_mask.sum())
            mode = "trailing-gap(NaN행만)"
        else:
            daily[f] = out  # ndarray 대입 = 위치 기준 (daily 현재 행순서와 정합)
            n_fill = int(np.isfinite(out).sum())
            mode = "full-column"
        print(f"[feat][bridge] {f}: monthly→daily ffill {n_fill:,}/{len(out):,} rows "
              f"({n_fill / max(len(out), 1):.1%}, {mode}, value={'Raw_Value' if use_raw else 'Z_Score'})")
        bridged.append(f)
    return daily, bridged, failed


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
    presence = {f: 0 for f in use_factors}  # 파일별 컬럼 존재 카운트 (침묵 NaN 금지)
    last_present_ym = {}                    # 팩터별 마지막 존재 파일 ym (trailing gap 감지)
    latest_ym = None
    n_files_read = 0
    for fp in files:
        try:
            import pyarrow.parquet as pq
            avail = set(pq.ParquetFile(fp).schema.names)
            ym_tag = os.path.basename(fp)[10:16]
            for f in use_factors:
                if f in avail:
                    presence[f] += 1
                    last_present_ym[f] = ym_tag
            rd = [c for c in cols_needed if c in avail]
            df = pd.read_parquet(fp, columns=rd)
            frames.append(df)
            latest_ym = ym_tag
            n_files_read += 1
        except Exception as e:
            print(f"[feat][warn] skip {os.path.basename(fp)}: {e}")
    daily = pd.concat(frames, ignore_index=True)
    del frames
    gc.collect()
    daily["Date"] = pd.to_datetime(daily["Date"])
    daily = daily.sort_values(["Ticker", "Date"])

    # ── 결측 팩터 정직화 (2026-06-10 P1 — 명시 WARN + manifest, 침묵 NaN 금지) ──
    # 두 결측 유형 (실측 2026-06-10):
    #   (a) missing  : 전 파일 부재 (presence==0)
    #   (b) trailing : 과거엔 있었으나 최신월 파일에서 탈락 — 일간 DB 202604/202605가
    #       318→306 컬럼으로 빌드되며 INV* 12컬럼 drop. 패널 꼬리(최신 의사결정 구간)가
    #       침묵 NaN→중립 0이 되는 가장 위험한 유형.
    missing = sorted(f for f in use_factors if presence[f] == 0)
    trailing_gap = {f: {"last_present_file_ym": last_present_ym[f], "latest_file_ym": latest_ym}
                    for f in sorted(use_factors)
                    if presence[f] > 0 and last_present_ym.get(f, "") < (latest_ym or "")}
    partial = {f: f"{presence[f]}/{n_files_read}" for f in sorted(use_factors)
               if 0 < presence[f] < n_files_read}
    if missing:
        print(f"[feat][WARN] selected factor {len(missing)}건이 일간 Factor DB({n_files_read} files)에 전혀 없음: {missing}")
    for f, info in trailing_gap.items():
        print(f"[feat][WARN] {f}: 일간 DB 최신월 파일에서 탈락 (마지막 존재={info['last_present_file_ym']}, "
              f"최신 파일={info['latest_file_ym']}) — 패널 꼬리가 NaN")
    if missing or trailing_gap:
        print(f"[feat][WARN] → 결측 구간은 NaN→월말 z단계 0(중립) 처리됨. "
              f"월간 DB 브릿지: DPL_USE_MONTHLY_BRIDGE=1 (현재 {'ON' if USE_MONTHLY_BRIDGE else 'OFF'})")
    bridge_targets = missing + sorted(trailing_gap)
    bridged, bridge_failed = [], []
    if USE_MONTHLY_BRIDGE and bridge_targets:
        daily, bridged, bridge_failed = _bridge_monthly_to_daily(daily, bridge_targets)
    # 브릿지 후에도 없는 컬럼만 NaN 보강 (구 침묵 보강 대체)
    for f in use_factors:
        if f not in daily.columns:
            daily[f] = np.nan
    manifest = {
        "built_at": pd.Timestamp.now().isoformat(timespec="seconds"),
        "n_daily_files": n_files_read,
        "n_selected_factors": len(use_factors),
        "missing_factors": missing,
        "trailing_gap_factors": trailing_gap,
        "partial_presence_files": partial,
        "use_monthly_bridge": USE_MONTHLY_BRIDGE,
        "bridge_targets": bridge_targets,
        "bridged_factors": bridged,
        "bridge_failed_factors": bridge_failed,
        "unresolved_after_bridge": sorted(f for f in bridge_targets if f not in bridged),
        "note": ("missing_factors = 일간 DB 전 파일 부재 / trailing_gap_factors = 최신월 파일 탈락 "
                 "(둘 다 침묵 NaN 금지로 명시 기록 — 결측 구간은 월말 단면 z 단계에서 0(중립)으로 들어감). "
                 "bridged_factors는 월간 관측의 step-function ffill(NaN 구간만 채움) — slope/vol 통계 해석 주의. "
                 "partial_presence_files는 팩터 역사 시작 시점 차이일 수도 있음(전 기간 실행 시 정상 가능)."),
    }
    _write_manifest(manifest)
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
    return snap[["ym", "Ticker"] + feat_cols], feat_cols, manifest


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
    snap, feat_cols, availability = build_features()
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
        "daily_factor_availability": availability,  # missing_factors/bridge 기록 (P1 2026-06-10)
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
    with open(os.path.join(OUT_DIR, "feature_panel_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f"[feat] panel -> {out_panel}  rows={len(panel):,}  feats={len(feat_cols)}  "
          f"months={panel['ym'].nunique()}")
    print(f"[feat] meta -> {os.path.join(OUT_DIR, 'feature_panel_meta.json')}")


if __name__ == "__main__":
    main()
