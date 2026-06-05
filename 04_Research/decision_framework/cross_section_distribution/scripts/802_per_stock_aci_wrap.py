"""
CSDA Phase 3 — Per-stock ACI wrap (gamma=0.005 fixed)

Inputs:
  - outputs/per_stock_forecasts.parquet (raw Hansen+ECDF, var_05, var_01, y_actual)

ACI update (Gibbs-Candes 2021):
  alpha_t = alpha_{t-1} + gamma * (1{y_{t-1} < q_{t-1}} - alpha_target)
  q_t = quantile of forecast at alpha_t  (monotone interpolate)

Per-stock, walk-forward. Skip stocks with < 30 sig_dates.

Outputs:
  - outputs/per_stock_forecasts_aci.parquet
    columns: Date, Ticker, var_05_aci, var_01_aci, alpha_t_05, alpha_t_01, q_adjust_05, q_adjust_01
"""

import argparse
import json
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd

BASE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR = BASE / "04_Research/decision_framework/cross_section_distribution/outputs"

GAMMA = 0.005
ALPHA_05 = 0.05
ALPHA_01 = 0.01
MIN_DATES_PER_STOCK = 30


def aci_update_series(y_actual: np.ndarray, q_raw: np.ndarray, alpha_target: float, gamma: float):
    """
    ACI per series (one stock, var_05 or var_01).
    Linearly maps alpha_t deviation onto q_t via gaussian-equivalent z-scale of raw q.
    Returns (q_aci, alpha_t_path, q_adjust).
    """
    n = len(y_actual)
    alpha_path = np.full(n, alpha_target)
    q_aci = q_raw.copy()
    q_adjust = np.zeros(n)
    # We do not have full predictive CDF here; approximate ACI by translating q by raw_sigma estimate.
    # Use rolling std of q_raw as scale proxy (forecast spread changes over time).
    for t in range(1, n):
        breach = 1.0 if (not np.isnan(y_actual[t - 1])) and (y_actual[t - 1] < q_raw[t - 1] + q_adjust[t - 1]) else 0.0
        alpha_path[t] = alpha_path[t - 1] + gamma * (breach - alpha_target)
        alpha_path[t] = np.clip(alpha_path[t], 1e-4, 0.5)
        # Translate via z-score on standard normal: dq = -(z(alpha_t) - z(alpha_target)) * sigma_proxy
        from scipy.stats import norm
        dz = norm.ppf(alpha_path[t]) - norm.ppf(alpha_target)
        # use abs(q_raw[t]) as scale proxy (typical magnitude). Avoid zero scale.
        scale = max(abs(q_raw[t]), 0.5)
        q_adjust[t] = dz * scale
        q_aci[t] = q_raw[t] + q_adjust[t]
    return q_aci, alpha_path, q_adjust


def process_one_ticker(args):
    ticker, df_t = args
    df_t = df_t.sort_values("Date").reset_index(drop=True)
    if len(df_t) < MIN_DATES_PER_STOCK:
        return None
    y = df_t["y_actual"].values.astype(float)
    q_raw_05 = df_t["var_05"].values.astype(float)
    q_raw_01 = df_t["var_01"].values.astype(float)
    q_aci_05, alpha_05_path, qadj_05 = aci_update_series(y, q_raw_05, ALPHA_05, GAMMA)
    q_aci_01, alpha_01_path, qadj_01 = aci_update_series(y, q_raw_01, ALPHA_01, GAMMA)
    breach_05 = (y[~np.isnan(y)] < q_aci_05[~np.isnan(y)]).mean()
    breach_01 = (y[~np.isnan(y)] < q_aci_01[~np.isnan(y)]).mean()
    return pd.DataFrame({
        "Date": df_t["Date"].values,
        "Ticker": ticker,
        "var_05_aci": q_aci_05,
        "var_01_aci": q_aci_01,
        "alpha_t_05": alpha_05_path,
        "alpha_t_01": alpha_01_path,
        "q_adjust_05": qadj_05,
        "q_adjust_01": qadj_01,
    }), {"ticker": ticker, "n": int(len(df_t)), "breach_05": float(breach_05), "breach_01": float(breach_01)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(OUT_DIR / "per_stock_forecasts.parquet"))
    ap.add_argument("--output", default=str(OUT_DIR / "per_stock_forecasts_aci.parquet"))
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    t0 = time.time()
    df = pd.read_parquet(args.input)
    df["Date"] = pd.to_datetime(df["Date"])
    tickers = df["Ticker"].unique().tolist()
    print(f"[ACI] tickers={len(tickers)} rows={len(df)} gamma={GAMMA}")

    groups = [(tk, df[df["Ticker"] == tk]) for tk in tickers]
    out_frames = []
    stats = []
    done = 0
    skipped = 0
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(process_one_ticker, g): g[0] for g in groups}
        for fut in as_completed(futs):
            res = fut.result()
            done += 1
            if res is None:
                skipped += 1
                continue
            frame, st = res
            out_frames.append(frame)
            stats.append(st)
            if done % 50 == 0:
                elapsed = time.time() - t0
                rate = done / elapsed if elapsed > 0 else 0
                eta = (len(tickers) - done) / rate / 60 if rate > 0 else float("inf")
                print(f"[ACI {done}/{len(tickers)}] rate={rate:.1f}/s ETA={eta:.1f}min skipped={skipped}")

    out = pd.concat(out_frames, ignore_index=True)
    out.to_parquet(args.output, index=False)
    meta = {
        "phase": "CSDA Phase 3 ACI wrap",
        "gamma": GAMMA,
        "alpha_05": ALPHA_05,
        "alpha_01": ALPHA_01,
        "n_tickers_input": len(tickers),
        "n_tickers_output": len(stats),
        "n_skipped": skipped,
        "rows": int(len(out)),
        "elapsed_min": (time.time() - t0) / 60,
        "mean_breach_05": float(np.mean([s["breach_05"] for s in stats])) if stats else None,
        "mean_breach_01": float(np.mean([s["breach_01"] for s in stats])) if stats else None,
        "built_at": pd.Timestamp.now().isoformat(),
    }
    meta_path = Path(args.output).with_suffix(".meta.json")
    meta_path.write_text(json.dumps(meta, indent=2))
    print(f"[ACI] Done. saved {args.output}")
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
