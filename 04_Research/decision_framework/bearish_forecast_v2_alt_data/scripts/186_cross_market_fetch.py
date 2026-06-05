#!/usr/bin/env python3
"""186_cross_market_fetch.py — Cycle 58B Phase 1: Cross-Market Features Fetch

Fetches 7 cross-market daily price series and computes lag1 features:
  1. nikkei225_return_lag1       — N225 daily return (Asia same-session, lag1 safe)
  2. sp500_overnight_return_lag1 — SPX daily return (US 16:00 ET = KR 06:00 next day, lag1)
  3. dxy_change_5d_lag1          — Dollar Index 5d % change (US close, lag1)
  4. usdkrw_change_5d_lag1       — KRW/USD 5d change (from .cache/ecos_krw_usd.parquet, lag1)
  5. hangseng_return_lag1        — HSI daily return (HK Asia session, lag1)
  6. wti_change_5d_lag1          — WTI crude oil 5d change (US close, lag1)
  7. vix_change_5d_lag1          — CBOE VIX 5d change (US close, lag1)

Data sources (search order):
  1. .cache/fred_macro_wide.parquet (VIX, KRW_USD already cached)
  2. .cache/ecos_krw_usd.parquet (KRW_USD)
  3. yfinance (^N225, ^GSPC, DX-Y.NYB, ^HSI, CL=F, ^VIX as fallback)

PIT correctness:
  - All 7 series .shift(1) AFTER computation of returns/changes — this represents
    'as of yesterday close' available on today's KR market open.
  - For US-close series (SPX/DXY/VIX/WTI): yfinance Date = US trading date.
    SPX 2020-03-16 close known by KR 2020-03-17 09:00 (KST). lag1 → use on KR 2020-03-17 = SAFE.
  - For Asia-session (N225/HSI): close 15:00 local same day → lag1 = next KR open. SAFE.
  - For USDKRW: ECOS daily KST close → lag1 = next KR open. SAFE.

Output:
  - outputs/01_data/cross_market_daily.csv (Date + 7 lag1 features, 1990-01-01 ~ today)
  - outputs/04_evaluation/cycle58b_cross_market_fetch.json (provenance log)
"""
import sys
import json
import time
from pathlib import Path
from datetime import datetime
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
CACHE = PROJECT_ROOT / ".cache"

DATA.mkdir(parents=True, exist_ok=True)
EVAL.mkdir(parents=True, exist_ok=True)

START_DATE = pd.Timestamp("1990-01-01")
END_DATE = pd.Timestamp("2026-05-21")


def yf_fetch(symbol: str, name: str) -> pd.DataFrame:
    """Fetch via yfinance; return Date + Close."""
    import yfinance as yf
    print(f"  [yfinance] {symbol} ({name})...", end=" ", flush=True)
    t0 = time.time()
    try:
        ticker = yf.Ticker(symbol)
        df = ticker.history(period="max", interval="1d", auto_adjust=False)
        df = df.reset_index()
        # Some yfinance results have Date as tz-aware -> tz-naive
        if hasattr(df["Date"].dt, "tz_localize"):
            try:
                df["Date"] = df["Date"].dt.tz_localize(None)
            except Exception:
                pass
        df["Date"] = pd.to_datetime(df["Date"]).dt.normalize()
        df = df[["Date", "Close"]].rename(columns={"Close": name})
        df = df[(df["Date"] >= START_DATE) & (df["Date"] <= END_DATE)]
        df = df.dropna().drop_duplicates(subset=["Date"], keep="last").sort_values("Date").reset_index(drop=True)
        print(f"OK n={len(df)} range={df['Date'].min().date()}~{df['Date'].max().date()} ({time.time()-t0:.1f}s)")
        return df
    except Exception as e:
        print(f"FAIL: {e}")
        return pd.DataFrame(columns=["Date", name])


def main():
    print("=" * 70)
    print("[Cycle 58B Phase 1] Cross-Market Features Fetch")
    print("=" * 70)
    print(f"  workspace: {WS}")
    print(f"  target range: {START_DATE.date()} ~ {END_DATE.date()}")
    print()

    provenance = {
        "cycle": "58B_phase1_cross_market_fetch",
        "script": "186_cross_market_fetch.py",
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "start_date": str(START_DATE.date()),
        "end_date": str(END_DATE.date()),
        "sources": {},
        "features": [],
    }

    # === STEP 1: Load VIX + KRW_USD from cache ===
    print("[STEP 1] Cache lookup (VIX + KRW_USD)")
    fred = pd.read_parquet(CACHE / "fred_macro_wide.parquet")[["Date", "VIX", "KRW_USD"]]
    fred["Date"] = pd.to_datetime(fred["Date"]).dt.normalize()
    fred = fred[(fred["Date"] >= START_DATE) & (fred["Date"] <= END_DATE)]
    fred = fred.sort_values("Date").drop_duplicates(subset=["Date"], keep="last").reset_index(drop=True)
    print(f"  fred_macro_wide: n={len(fred)} VIX_n_obs={fred['VIX'].notna().sum()} KRW_USD_n_obs={fred['KRW_USD'].notna().sum()}")
    provenance["sources"]["vix"] = {"source": ".cache/fred_macro_wide.parquet", "col": "VIX", "n_obs": int(fred["VIX"].notna().sum())}
    provenance["sources"]["krw_usd"] = {"source": ".cache/fred_macro_wide.parquet", "col": "KRW_USD", "n_obs": int(fred["KRW_USD"].notna().sum())}

    # === STEP 2: Yahoo fetches for ^N225, ^GSPC, DX-Y.NYB, ^HSI, CL=F ===
    print("\n[STEP 2] yfinance fetches")
    yf_symbols = {
        "^N225": "nikkei225",
        "^GSPC": "sp500",
        "DX-Y.NYB": "dxy",
        "^HSI": "hangseng",
        "CL=F": "wti",
    }
    yf_data = {}
    for sym, name in yf_symbols.items():
        df = yf_fetch(sym, name)
        if len(df) == 0:
            print(f"  ⚠️  {sym} empty — will skip {name}")
            yf_data[name] = None
            provenance["sources"][name] = {"source": "yfinance:" + sym, "n_obs": 0, "status": "FAIL"}
        else:
            yf_data[name] = df
            provenance["sources"][name] = {
                "source": "yfinance:" + sym, "n_obs": int(len(df)),
                "range": [str(df["Date"].min().date()), str(df["Date"].max().date())],
                "status": "OK",
            }

    # === STEP 3: Build daily spine (KR trading days from existing panel) ===
    print("\n[STEP 3] KR trading-day spine")
    panel = pd.read_parquet(DATA / "feature_panel_v5f_FIXED2.parquet")[["Date"]]
    panel["Date"] = pd.to_datetime(panel["Date"]).dt.normalize()
    spine = panel.sort_values("Date").reset_index(drop=True)
    print(f"  KR spine: n_days={len(spine)} range={spine['Date'].min().date()}~{spine['Date'].max().date()}")

    out = spine.copy()

    # === STEP 4: Build features (lag1 + returns/changes) ===
    print("\n[STEP 4] Feature engineering (lag1 PIT-safe)")

    # Helper: align series to KR spine via forward-fill of last-available foreign close
    def align_to_spine(df_foreign, name):
        """
        Forward-fill foreign daily close to every KR trading day.
        Returns Series indexed to spine Date.
        Logic: For each KR Date d, look up most recent foreign close on Date <= d.
        Then apply .shift(1) AFTER computing features to ensure we use 'yesterday's' close.

        CODEX C1 FIX (2026-05-21): drop NaN rows in df_foreign[name] BEFORE merge_asof,
        otherwise FRED rows with non-trading-day NaN can become NaN on KR spine instead
        of carrying-forward the most recent valid close. Empirical: pre-fix VIX had 301
        post-first-valid NaN, USDKRW had 384.
        """
        if df_foreign is None or len(df_foreign) == 0:
            return pd.Series(np.nan, index=spine["Date"])
        # CODEX C1 FIX: drop NaN rows in foreign series before as-of
        df_clean = df_foreign[["Date", name]].dropna(subset=[name]).sort_values("Date")
        # Merge_asof: for each spine Date, use latest foreign close on or before that Date
        merged = pd.merge_asof(
            spine.sort_values("Date"),
            df_clean,
            on="Date", direction="backward"
        )
        return merged[name].reset_index(drop=True)

    # ---- Feature 1: nikkei225_return_lag1 ----
    n225 = align_to_spine(yf_data.get("nikkei225"), "nikkei225")
    n225_ret = n225 / n225.shift(1) - 1.0
    out["nikkei225_return_lag1"] = n225_ret.shift(1)  # use yesterday's return
    provenance["features"].append({"name": "nikkei225_return_lag1", "formula": "(close[t-1]/close[t-2]) - 1", "n_valid": int(out["nikkei225_return_lag1"].notna().sum())})

    # ---- Feature 2: sp500_overnight_return_lag1 ----
    sp500 = align_to_spine(yf_data.get("sp500"), "sp500")
    sp500_ret = sp500 / sp500.shift(1) - 1.0
    out["sp500_overnight_return_lag1"] = sp500_ret.shift(1)
    provenance["features"].append({"name": "sp500_overnight_return_lag1", "formula": "(spx_close[t-1]/spx_close[t-2]) - 1", "n_valid": int(out["sp500_overnight_return_lag1"].notna().sum())})

    # ---- Feature 3: dxy_change_5d_lag1 ----
    dxy = align_to_spine(yf_data.get("dxy"), "dxy")
    dxy_change5d = dxy / dxy.shift(5) - 1.0
    out["dxy_change_5d_lag1"] = dxy_change5d.shift(1)
    provenance["features"].append({"name": "dxy_change_5d_lag1", "formula": "(dxy[t-1]/dxy[t-6]) - 1", "n_valid": int(out["dxy_change_5d_lag1"].notna().sum())})

    # ---- Feature 4: usdkrw_change_5d_lag1 (from FRED cache) ----
    krw_aligned = align_to_spine(fred[["Date", "KRW_USD"]].rename(columns={"KRW_USD": "krw"}), "krw")
    krw_change5d = krw_aligned / krw_aligned.shift(5) - 1.0
    out["usdkrw_change_5d_lag1"] = krw_change5d.shift(1)
    provenance["features"].append({"name": "usdkrw_change_5d_lag1", "formula": "(krw_usd[t-1]/krw_usd[t-6]) - 1, KRW/USD direct", "n_valid": int(out["usdkrw_change_5d_lag1"].notna().sum())})

    # ---- Feature 5: hangseng_return_lag1 ----
    hsi = align_to_spine(yf_data.get("hangseng"), "hangseng")
    hsi_ret = hsi / hsi.shift(1) - 1.0
    out["hangseng_return_lag1"] = hsi_ret.shift(1)
    provenance["features"].append({"name": "hangseng_return_lag1", "formula": "(hsi_close[t-1]/hsi_close[t-2]) - 1", "n_valid": int(out["hangseng_return_lag1"].notna().sum())})

    # ---- Feature 6: wti_change_5d_lag1 ----
    wti = align_to_spine(yf_data.get("wti"), "wti")
    wti_change5d = wti / wti.shift(5) - 1.0
    out["wti_change_5d_lag1"] = wti_change5d.shift(1)
    provenance["features"].append({"name": "wti_change_5d_lag1", "formula": "(wti_close[t-1]/wti_close[t-6]) - 1", "n_valid": int(out["wti_change_5d_lag1"].notna().sum())})

    # ---- Feature 7: vix_change_5d_lag1 (from FRED cache) ----
    vix_aligned = align_to_spine(fred[["Date", "VIX"]].rename(columns={"VIX": "vix"}), "vix")
    vix_change5d = vix_aligned / vix_aligned.shift(5) - 1.0
    out["vix_change_5d_lag1"] = vix_change5d.shift(1)
    provenance["features"].append({"name": "vix_change_5d_lag1", "formula": "(vix[t-1]/vix[t-6]) - 1", "n_valid": int(out["vix_change_5d_lag1"].notna().sum())})

    # === STEP 5: Summary + save ===
    feat_cols = [c for c in out.columns if c != "Date"]
    print("\n[STEP 5] Feature summary:")
    for c in feat_cols:
        n_valid = int(out[c].notna().sum())
        n_total = len(out)
        first_valid = out[out[c].notna()]["Date"].min()
        first_valid_str = str(first_valid.date()) if pd.notna(first_valid) else "NONE"
        print(f"  {c:38s} n_valid={n_valid}/{n_total} ({100*n_valid/n_total:.1f}%) first_valid={first_valid_str}")

    out_path = DATA / "cross_market_daily.csv"
    out.to_csv(out_path, index=False)
    print(f"\n[saved] {out_path}")

    # Also parquet for fast load
    out.to_parquet(DATA / "cross_market_daily.parquet", index=False)
    print(f"[saved] {DATA / 'cross_market_daily.parquet'}")

    # Correlation between cross-market features and check vs us_stlfsi
    print("\n[STEP 6] Correlation matrix (cross-market features):")
    cor = out[feat_cols].corr()
    print(cor.round(3).to_string())

    # vs us_stlfsi check (VIX vs us_stlfsi requested)
    v5f = pd.read_parquet(DATA / "feature_panel_v5f_FIXED2.parquet")[["Date", "us_stlfsi_lag1"]]
    v5f["Date"] = pd.to_datetime(v5f["Date"]).dt.normalize()
    merged = out.merge(v5f, on="Date", how="left")
    cor_vix_stl = merged[["vix_change_5d_lag1", "us_stlfsi_lag1"]].corr().iloc[0, 1]
    print(f"\n  Correlation vix_change_5d_lag1 vs us_stlfsi_lag1: {cor_vix_stl:.3f}")
    provenance["correlation_vix_vs_us_stlfsi"] = float(cor_vix_stl) if not np.isnan(cor_vix_stl) else None

    # Persist provenance
    eval_path = EVAL / "cycle58b_cross_market_fetch.json"
    with open(eval_path, "w") as f:
        json.dump(provenance, f, indent=2, ensure_ascii=False, default=str)
    print(f"\n[saved] {eval_path}")
    print("\n[DONE] Phase 1 complete.")


if __name__ == "__main__":
    main()
