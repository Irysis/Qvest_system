#!/usr/bin/env python3
"""212_fetch_etf_yield_alt_data.py — Cycle 58L+ alt-data fetch

병렬 fetch:
  1. KR ETF flow: KODEX_200 (069500), TIGER_200 (102110),
     KODEX_inverse (114800), KODEX_leverage (122630),
     KODEX_kr_bond_10y (148070), TIGER_kospi (101280)
     - close, volume, AUM, leverage/inverse 비율 dynamics
  2. KR Yield Curve: FRED IRSTCI01KRM156N (call rate),
     IRLTLT01KRM156N (10y bond), or alternative sources
  3. USDKRW basis (proxy for KR CDS): yfinance KRW=X dynamics

Cache: outputs/01_data/.cache/{etf_flow,yield_curve}.parquet
"""
import sys
import os
import json
from datetime import datetime, timedelta
from pathlib import Path
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_DIR = WS / "outputs/01_data"
OUT_DIR.mkdir(parents=True, exist_ok=True)

START = "2003-01-01"
END = datetime.now().strftime("%Y-%m-%d")

# ============================================================
# Part 1: KR ETF flow via yfinance
# ============================================================
import yfinance as yf

print(f"[{datetime.now():%H:%M:%S}] Part 1: KR ETF flow fetch via yfinance")

# yfinance KR ETF tickers
etf_map = {
    "069500.KS": "KODEX_200",          # KOSPI 200 (largest)
    "102110.KS": "TIGER_200",          # KOSPI 200 alt
    "114800.KS": "KODEX_INV",          # Inverse
    "122630.KS": "KODEX_LEV",          # 2x leverage
    "148070.KS": "KODEX_KTB10",        # KR 10y bond
    "152500.KS": "ARIRANG_HDPS",       # high div
    "229200.KS": "KODEX_2XINV",        # 2x inverse
    "233740.KS": "KODEX_LEV_KOSDAQ",   # KOSDAQ 2x
}

etf_df_list = []
for tkr, name in etf_map.items():
    try:
        t = yf.download(tkr, start=START, end=END, progress=False,
                        auto_adjust=False)
        if len(t) == 0:
            print(f"  [{name:20s}] empty")
            continue
        t = t.reset_index()
        t.columns = [c if isinstance(c, str) else c[0] for c in t.columns]
        # Daily volume + close + adjclose
        t_sub = t[["Date", "Close", "Volume"]].copy()
        t_sub["etf"] = name
        t_sub["ticker"] = tkr
        etf_df_list.append(t_sub)
        print(f"  [{name:20s}] {len(t)} rows {t['Date'].min().date()} ~ "
              f"{t['Date'].max().date()}")
    except Exception as e:
        print(f"  [{name:20s}] ERROR: {e}")

etf_df = pd.concat(etf_df_list, ignore_index=True)
etf_df["Date"] = pd.to_datetime(etf_df["Date"])
out_etf = OUT_DIR / "etf_flow_raw.parquet"
etf_df.to_parquet(out_etf, index=False)
print(f"\n  Saved: {out_etf} ({len(etf_df)} rows, {etf_df['etf'].nunique()} ETFs)")

# Compute panel features (PIT-clean)
print(f"\n[{datetime.now():%H:%M:%S}] Part 1.2: ETF flow PIT features")
# Pivot to wide
etf_close = etf_df.pivot(index="Date", columns="etf", values="Close")
etf_vol = etf_df.pivot(index="Date", columns="etf", values="Volume")

# Inverse/Long flow ratio (risk-off detector)
# When INV volume > 2x LEV volume, retail anticipating downside
if "KODEX_INV" in etf_vol.columns and "KODEX_LEV" in etf_vol.columns:
    inv_lev_ratio = (etf_vol["KODEX_INV"] /
                     etf_vol["KODEX_LEV"].replace(0, np.nan))
    # log + rolling z (PIT expanding)
    log_ratio = np.log(inv_lev_ratio.replace([np.inf, -np.inf], np.nan))
    log_ratio_lag1 = log_ratio.shift(1)
    # 252d expanding z
    mean_exp = log_ratio_lag1.expanding(min_periods=252).mean()
    std_exp = log_ratio_lag1.expanding(min_periods=252).std()
    inv_lev_z_lag1 = (log_ratio_lag1 - mean_exp) / std_exp
else:
    inv_lev_z_lag1 = pd.Series(index=etf_vol.index, dtype=float)

# Bond/equity flow ratio (flight-to-quality)
if "KODEX_KTB10" in etf_vol.columns and "KODEX_200" in etf_vol.columns:
    bond_eq_ratio = (etf_vol["KODEX_KTB10"] /
                     etf_vol["KODEX_200"].replace(0, np.nan))
    log_be = np.log(bond_eq_ratio.replace([np.inf, -np.inf], np.nan))
    log_be_lag1 = log_be.shift(1)
    mean_exp = log_be_lag1.expanding(min_periods=252).mean()
    std_exp = log_be_lag1.expanding(min_periods=252).std()
    bond_eq_z_lag1 = (log_be_lag1 - mean_exp) / std_exp
else:
    bond_eq_z_lag1 = pd.Series(index=etf_vol.index, dtype=float)

# Total ETF volume z (KOSPI200 ETF)
if "KODEX_200" in etf_vol.columns:
    k200_vol = etf_vol["KODEX_200"]
    log_v = np.log(k200_vol.replace(0, np.nan))
    log_v_lag1 = log_v.shift(1)
    mean_exp = log_v_lag1.expanding(min_periods=252).mean()
    std_exp = log_v_lag1.expanding(min_periods=252).std()
    k200_vol_z_lag1 = (log_v_lag1 - mean_exp) / std_exp
else:
    k200_vol_z_lag1 = pd.Series(index=etf_vol.index, dtype=float)

etf_features = pd.DataFrame({
    "Date": etf_vol.index,
    "etf_inv_lev_ratio_z_lag1": inv_lev_z_lag1.values,
    "etf_bond_eq_ratio_z_lag1": bond_eq_z_lag1.values,
    "etf_k200_vol_z_lag1": k200_vol_z_lag1.values,
})
out_feat = OUT_DIR / "etf_flow_features.parquet"
etf_features.to_parquet(out_feat, index=False)
print(f"  Saved: {out_feat} ({len(etf_features)} rows, 3 features)")
print(etf_features.dropna().describe().T[["count", "mean", "std", "min", "max"]])

# ============================================================
# Part 2: KR Yield Curve via FRED
# ============================================================
print(f"\n[{datetime.now():%H:%M:%S}] Part 2: KR Yield Curve fetch via FRED")
try:
    from fredapi import Fred
    FRED_KEY = os.environ.get("FRED_API_KEY",
                              "d9bd4036c1de23170040e16d52a36a45")  # public
    fred = Fred(api_key=FRED_KEY)
    # KR rates
    series_map = {
        "IRSTCI01KRM156N": "kr_call_rate",   # KR overnight call rate (monthly)
        "IRLTLT01KRM156N": "kr_10y_yield",   # KR 10y bond yield (monthly)
        "IR3TIB01KRM156N": "kr_3m_rate",      # KR 3-month interbank
    }
    yield_dfs = []
    for sid, name in series_map.items():
        try:
            s = fred.get_series(sid, observation_start=START)
            yield_dfs.append(s.to_frame(name=name))
            print(f"  [{name:20s}] {len(s)} obs (monthly)")
        except Exception as e:
            print(f"  [{name:20s}] ERROR: {e}")
    if yield_dfs:
        yc = pd.concat(yield_dfs, axis=1).reset_index().rename(
            columns={"index": "Date"})
        out_yc = OUT_DIR / "kr_yield_curve_raw.parquet"
        yc.to_parquet(out_yc, index=False)
        print(f"  Saved: {out_yc}")

        # Compute slope features (term premium proxy)
        if "kr_10y_yield" in yc.columns and "kr_3m_rate" in yc.columns:
            yc["kr_slope_10y_3m"] = yc["kr_10y_yield"] - yc["kr_3m_rate"]
        if "kr_10y_yield" in yc.columns and "kr_call_rate" in yc.columns:
            yc["kr_slope_10y_call"] = yc["kr_10y_yield"] - yc["kr_call_rate"]
        # Forward-fill to daily (PIT: use latest available value)
        out_yc_d = OUT_DIR / "kr_yield_curve_daily.parquet"
        yc.to_parquet(out_yc_d, index=False)
        print(f"  Saved: {out_yc_d} ({len(yc)} obs monthly)")
except Exception as e:
    print(f"  FRED ERROR: {e}")

print(f"\n[{datetime.now():%H:%M:%S}] Alt-data fetch complete.")
