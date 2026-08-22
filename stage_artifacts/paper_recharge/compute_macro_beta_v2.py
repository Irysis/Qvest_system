"""
compute_macro_beta_v2.py — rolling OLS beta 계산 (최적화 버전)
- 유니버스: K200 OR KQ150 종목만 (전체 3,559 → 약 350종목)
- numpy vectorized rolling beta
"""

import sys
import os
import numpy as np
import pandas as pd

PROJ = os.environ.get("CLAUDE_PROJECT_DIR",
       os.environ.get("QM_ROOT",
       "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

BETA_WINDOW = 60
MACRO_WINDOW = 20
TARGET_SERIES = ["Term_Spread", "VIX", "KRW_USD"]
START_DATE = "2005-01-01"
LIQ_THRESHOLD = 2e8

print("[v2] Loading FRED data...")
fred_long = pd.read_parquet(os.path.join(PROJ, ".cache", "fred_macro.parquet"))
fred_sub = fred_long[fred_long["Series"].isin(TARGET_SERIES) &
                     (fred_long["Frequency"] == "d")][["Date", "Series", "Value"]]
fred_sub["Date"] = pd.to_datetime(fred_sub["Date"])
fred_wide = fred_sub.pivot(index="Date", columns="Series", values="Value")
fred_wide = fred_wide.sort_index().ffill()

# delta20 = macro[t-1] - macro[t-21]  (PIT: 당일 FRED 미확정)
delta20 = fred_wide.shift(1) - fred_wide.shift(21)
fred_dm = fred_wide.diff(1)  # 일별 변화량
print(f"[v2] FRED ready: {fred_wide.shape}")

print("[v2] Loading RAWDATA (K200/KQ150 only)...")
raw_all = pd.read_parquet(
    os.path.join(PROJ, ".cache", "RAWDATA.parquet"),
    columns=["Date", "Ticker", "Ret", "Size", "K200", "KQ150"]
)
raw_all["Date"] = pd.to_datetime(raw_all["Date"])

# K200 OR KQ150 멤버만 (PIT 시변 멤버십)
raw_univ = raw_all[(raw_all["K200"] == True) | (raw_all["KQ150"] == True)].copy()
raw_univ = raw_univ[raw_univ["Date"] >= "2004-01-01"]
raw_univ = raw_univ.sort_values(["Ticker", "Date"]).reset_index(drop=True)

# 유동성 필터
raw_univ["AvgSize20"] = raw_univ.groupby("Ticker")["Size"].transform(
    lambda x: x.rolling(20, min_periods=1).mean()
)
raw_univ["LiqPass"] = raw_univ["AvgSize20"] >= LIQ_THRESHOLD

print(f"[v2] Universe panel: {len(raw_univ)} rows, {raw_univ['Ticker'].nunique()} tickers")
del raw_all
import gc; gc.collect()

# ---- FRED 날짜 align -------------------------------------------------------
fred_dm.index = pd.to_datetime(fred_dm.index)
fred_dm_reset = fred_dm.reset_index()
fred_dm_reset.columns = ["Date"] + TARGET_SERIES
raw_merged = raw_univ.merge(fred_dm_reset, on="Date", how="inner")
raw_merged = raw_merged.dropna(subset=TARGET_SERIES)
raw_merged = raw_merged.sort_values(["Ticker", "Date"]).reset_index(drop=True)
print(f"[v2] Aligned panel: {len(raw_merged)} rows, {raw_merged['Ticker'].nunique()} tickers")

# ---- rolling OLS beta (numpy 최적화) --------------------------------------
def rolling_cov_var_betas(ticker_df, window=60, min_obs=15):
    """
    Fast rolling single-factor betas using cumsum trick.
    beta_j = cov(r, m_j) / var(m_j) over rolling window.
    """
    n = len(ticker_df)
    J = len(TARGET_SERIES)
    ret = ticker_df["Ret"].values
    macro = ticker_df[TARGET_SERIES].values  # (n, J)

    betas = np.full((n, J), np.nan)
    if n < window:
        return betas

    for t in range(window - 1, n):
        idx = slice(t - window + 1, t + 1)
        r = ret[idx]
        m = macro[idx, :]
        valid = ~np.isnan(r) & ~np.any(np.isnan(m), axis=1)
        nv = valid.sum()
        if nv < min_obs:
            continue
        rv = r[valid]
        mv = m[valid, :]
        # beta_j = cov(r, m_j) / var(m_j)
        for j in range(J):
            vj = np.var(mv[:, j], ddof=1)
            if vj < 1e-12:
                continue
            betas[t, j] = np.cov(rv, mv[:, j])[0, 1] / vj

    return betas

print("[v2] Computing rolling betas per ticker...")
tickers = raw_merged["Ticker"].unique()
n_tickers = len(tickers)
all_beta_rows = []

for i, tk in enumerate(tickers):
    sub = raw_merged[raw_merged["Ticker"] == tk].reset_index(drop=True)
    betas = rolling_cov_var_betas(sub, window=BETA_WINDOW)

    df_betas = pd.DataFrame(betas, columns=[f"beta_{s}" for s in TARGET_SERIES])
    df_betas["Date"] = sub["Date"].values
    df_betas["Ticker"] = tk
    df_betas["LiqPass"] = sub["LiqPass"].values
    all_beta_rows.append(df_betas)

    if (i + 1) % 50 == 0 or (i + 1) == n_tickers:
        print(f"[v2] {i+1}/{n_tickers} tickers done")

print("[v2] Concatenating betas...")
beta_df = pd.concat(all_beta_rows, ignore_index=True)
beta_df["Date"] = pd.to_datetime(beta_df["Date"])

# ---- 월말 리밸런스 날짜 ----------------------------------------------------
beta_df["ym"] = beta_df["Date"].dt.to_period("M")
month_ends_df = beta_df.groupby("ym")["Date"].max().reset_index()
rebal_dates = month_ends_df[month_ends_df["Date"] >= START_DATE]["Date"].sort_values().values
print(f"[v2] Rebalance dates: {len(rebal_dates)}")

# ---- delta20 lookup --------------------------------------------------------
delta20.index = pd.to_datetime(delta20.index)
delta20_reset = delta20.reset_index()
delta20_reset.columns = ["Date"] + [f"delta20_{s}" for s in TARGET_SERIES]
delta20_reset["Date"] = pd.to_datetime(delta20_reset["Date"])

# ---- Score 계산 ------------------------------------------------------------
print("[v2] Computing scores at rebalance dates...")
score_rows = []

for rd in rebal_dates:
    rd_ts = pd.Timestamp(rd)
    panel = beta_df[beta_df["Date"] == rd_ts].copy()
    if len(panel) == 0:
        continue

    # delta20 lookup: rd 이전 가장 최근 FRED 날짜
    d20_sub = delta20_reset[delta20_reset["Date"] <= rd_ts]
    if len(d20_sub) == 0:
        continue
    d20_row = d20_sub.iloc[-1]

    # beta 완전한 종목만
    beta_cols = [f"beta_{s}" for s in TARGET_SERIES]
    panel = panel.dropna(subset=beta_cols)
    if len(panel) == 0:
        continue

    # Score = sum_j (beta_j × delta20_j)
    score = np.zeros(len(panel))
    valid_macro = True
    for s in TARGET_SERIES:
        d20_val = d20_row[f"delta20_{s}"]
        if np.isnan(d20_val):
            valid_macro = False
            break
        score += panel[f"beta_{s}"].values * d20_val

    if not valid_macro:
        continue

    out = panel[["Ticker", "LiqPass"]].copy()
    out["Date"] = rd_ts
    out["Score"] = score
    score_rows.append(out)

print(f"[v2] Processing {len(score_rows)} months...")
if score_rows:
    factors = pd.concat(score_rows, ignore_index=True)
    factors = factors[factors["LiqPass"] == True].drop(columns=["LiqPass"])
    factors = factors[factors["Score"].notna() & np.isfinite(factors["Score"])]
    factors = factors[["Date", "Ticker", "Score"]].sort_values(["Date", "Ticker"]).reset_index(drop=True)
    print(f"[v2] FACTORS: {len(factors)} rows | "
          f"{factors['Date'].nunique()} dates | {factors['Ticker'].nunique()} tickers")

    out_path = os.path.join(PROJ, ".cache", "macro_beta_scores.parquet")
    factors.to_parquet(out_path, index=False)
    print(f"[v2] Saved to: {out_path}")
else:
    print("[v2] ERROR: No scores computed!")
    sys.exit(1)

print("[v2] Done.")
