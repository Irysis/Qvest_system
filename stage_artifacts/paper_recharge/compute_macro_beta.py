"""
compute_macro_beta.py — rolling OLS beta 계산 (numpy vectorized)
arXiv 2608.12283 pure-beta trigger 구현

입력:
  - rawdata.parquet  (Date, Ticker, Ret, ...)
  - fred_macro.parquet (Date, Series, Value)

출력:
  - .cache/macro_beta_scores.parquet (Date, Ticker, Score)

PIT 준수:
  - beta_ij[t] = rolling 60 trading days (t 포함, 과거만)
  - delta20_j[t] = macro_j[t-1] - macro_j[t-21]  (t-1 이전)
  - 매크로 변화량: t-1 lag 적용
"""

import sys
import os
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

PROJ = os.environ.get("CLAUDE_PROJECT_DIR",
       os.environ.get("QM_ROOT",
       "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

BETA_WINDOW = 60
MACRO_WINDOW = 20
TARGET_SERIES = ["Term_Spread", "VIX", "KRW_USD"]
START_DATE = "2005-01-01"

print("[macro_beta_py] Loading FRED data...")
fred_long = pd.read_parquet(os.path.join(PROJ, ".cache", "fred_macro.parquet"))
fred_sub = fred_long[fred_long["Series"].isin(TARGET_SERIES) &
                     (fred_long["Frequency"] == "d")][["Date", "Series", "Value"]]
fred_wide = fred_sub.pivot(index="Date", columns="Series", values="Value")
fred_wide = fred_wide.sort_index()
# LOCF
fred_wide = fred_wide.ffill()

# PIT lag: 당일 FRED 미확정 → t-1 값 사용
# delta20 = macro[t-1] - macro[t-21]
fred_m1  = fred_wide.shift(1)   # t-1
fred_m21 = fred_wide.shift(21)  # t-21
delta20 = fred_m1 - fred_m21    # Δm_j_20d (PIT-safe)

print(f"[macro_beta_py] FRED wide shape: {fred_wide.shape}, date: {fred_wide.index[0]} ~ {fred_wide.index[-1]}")

print("[macro_beta_py] Loading RAWDATA...")
rawdata_path = os.path.join(PROJ, ".cache", "RAWDATA.parquet")
raw = pd.read_parquet(rawdata_path,
                      columns=["Date", "Ticker", "Ret", "Size"])
raw["Date"] = pd.to_datetime(raw["Date"])
raw = raw[raw["Date"] >= "2004-01-01"].copy()
# 유동성 필터: 20일 rolling 평균 거래대금 >= 2e8 (Size = 거래대금)
LIQ_THRESHOLD = 2e8
raw = raw.sort_values(["Ticker", "Date"])
raw["AvgSize20"] = raw.groupby("Ticker")["Size"].transform(
    lambda x: x.rolling(20, min_periods=1).mean()
)
raw["LiqPass"] = raw["AvgSize20"] >= LIQ_THRESHOLD

print(f"[macro_beta_py] RAWDATA rows: {len(raw)}, tickers: {raw['Ticker'].nunique()}")

# ---- 일별 FRED 변화량과 Ret 날짜 alignment ---------------------------------
# FRED 날짜 기준으로 Ret 데이터를 align
fred_dm = pd.DataFrame({
    s: np.diff(fred_wide[s].values, prepend=np.nan)
    for s in TARGET_SERIES
}, index=fred_wide.index)
fred_dm.index = pd.to_datetime(fred_dm.index)

# raw에 FRED 변화량 join
raw["Date"] = pd.to_datetime(raw["Date"])
fred_dm_reset = fred_dm.reset_index().rename(columns={"index": "Date"})
fred_dm_reset["Date"] = pd.to_datetime(fred_dm_reset["Date"])
raw = raw.merge(fred_dm_reset, on="Date", how="inner")
raw = raw.dropna(subset=TARGET_SERIES)
raw = raw.sort_values(["Ticker", "Date"]).reset_index(drop=True)

print(f"[macro_beta_py] Aligned panel: {len(raw)} rows, {raw['Ticker'].nunique()} tickers")

# ---- rolling OLS beta 계산 (numpy vectorized per ticker) ------------------
print("[macro_beta_py] Computing rolling betas...")

def rolling_ols_betas(ret_arr, macro_arr, window):
    """
    ret_arr: shape (T,)
    macro_arr: shape (T, J) — J macro factors
    window: int
    returns: shape (T, J) — rolling OLS betas (single-factor betas, not multivariate)
    """
    T = len(ret_arr)
    J = macro_arr.shape[1]
    betas = np.full((T, J), np.nan)

    for t in range(window - 1, T):
        idx = slice(t - window + 1, t + 1)
        r = ret_arr[idx]
        m = macro_arr[idx, :]
        valid = ~np.isnan(r) & ~np.any(np.isnan(m), axis=1)
        if valid.sum() < 15:
            continue
        r_v = r[valid]
        m_v = m[valid, :]
        # 단순 개별 beta: beta_j = cov(r, m_j) / var(m_j)
        # (다중회귀 대신 개별 기여분 방식 — 계산 속도 우선)
        for j in range(J):
            vj = np.var(m_v[:, j], ddof=1)
            if vj < 1e-12:
                continue
            betas[t, j] = np.cov(r_v, m_v[:, j])[0, 1] / vj
    return betas

all_scores = []

tickers = raw["Ticker"].unique()
n_tickers = len(tickers)
report_every = max(1, n_tickers // 10)

for i, tk in enumerate(tickers):
    tk_data = raw[raw["Ticker"] == tk].reset_index(drop=True)
    ret_arr = tk_data["Ret"].values
    macro_arr = tk_data[TARGET_SERIES].values
    dates = tk_data["Date"].values
    liq_pass = tk_data["LiqPass"].values

    betas = rolling_ols_betas(ret_arr, macro_arr, BETA_WINDOW)

    tk_scores = pd.DataFrame({
        "Date": dates,
        "Ticker": tk,
        **{f"beta_{s}": betas[:, j] for j, s in enumerate(TARGET_SERIES)},
        "LiqPass": liq_pass
    })
    all_scores.append(tk_scores)

    if (i + 1) % report_every == 0:
        print(f"[macro_beta_py] {i+1}/{n_tickers} tickers done")

print("[macro_beta_py] Concatenating beta results...")
beta_df = pd.concat(all_scores, ignore_index=True)
beta_df["Date"] = pd.to_datetime(beta_df["Date"])

# ---- 월말 리밸런스 날짜 추출 -----------------------------------------------
print("[macro_beta_py] Computing monthly rebalance dates...")
beta_df["ym"] = beta_df["Date"].dt.to_period("M")
month_ends = beta_df.groupby("ym")["Date"].max().reset_index()
month_ends = month_ends[month_ends["Date"] >= START_DATE].sort_values("Date")

# ---- delta20 lookup --------------------------------------------------------
delta20_df = delta20.reset_index()
delta20_df.columns = ["Date"] + [f"delta20_{s}" for s in TARGET_SERIES]
delta20_df["Date"] = pd.to_datetime(delta20_df["Date"])

# 월말 날짜에서 delta20 값 lookup (날짜 기준 nearest 이전)
rebal_dates = month_ends["Date"].values

# ---- Score 계산 ------------------------------------------------------------
print("[macro_beta_py] Computing scores at rebalance dates...")
score_rows = []

for rd in rebal_dates:
    # beta_df에서 해당 월말 날짜 행 추출
    rd_dt = pd.Timestamp(rd)
    panel = beta_df[beta_df["Date"] == rd_dt].copy()
    if len(panel) == 0:
        continue

    # delta20 lookup: rd 이전 최근 FRED 날짜
    d20_sub = delta20_df[delta20_df["Date"] <= rd_dt]
    if len(d20_sub) == 0:
        continue
    d20_row = d20_sub.iloc[-1]

    # Score = sum_j (beta_j × delta20_j)
    score = np.zeros(len(panel))
    for s in TARGET_SERIES:
        beta_col = f"beta_{s}"
        d20_val = d20_row[f"delta20_{s}"]
        if not np.isnan(d20_val):
            score += panel[beta_col].fillna(0).values * d20_val

    # NA beta가 있는 종목은 score = 0이 아니라 제외
    valid_mask = ~np.any(panel[[f"beta_{s}" for s in TARGET_SERIES]].isna().values, axis=1)

    out = panel[valid_mask].copy()
    out["Score"] = score[valid_mask]
    out["Date"] = rd_dt
    score_rows.append(out[["Date", "Ticker", "Score", "LiqPass"]])

print(f"[macro_beta_py] Collecting {len(score_rows)} rebal months...")
if score_rows:
    factors = pd.concat(score_rows, ignore_index=True)
    factors = factors[factors["LiqPass"] == True].drop(columns=["LiqPass"])
    factors = factors[factors["Score"].notna() & np.isfinite(factors["Score"])]
    factors = factors.sort_values(["Date", "Ticker"]).reset_index(drop=True)
    print(f"[macro_beta_py] FACTORS: {len(factors)} rows | "
          f"{factors['Date'].nunique()} dates | {factors['Ticker'].nunique()} tickers")

    # 저장
    out_path = os.path.join(PROJ, ".cache", "macro_beta_scores.parquet")
    factors.to_parquet(out_path, index=False)
    print(f"[macro_beta_py] Saved to: {out_path}")
else:
    print("[macro_beta_py] ERROR: No scores computed!")
    sys.exit(1)

print("[macro_beta_py] Done.")
