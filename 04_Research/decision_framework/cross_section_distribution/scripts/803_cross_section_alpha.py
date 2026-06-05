"""
CSDA Phase 4 — Cross-section multi-dim composite alpha

Inputs:
  - outputs/per_stock_forecasts.parquet (raw forecasts, 469 tickers)

Logic (per sig_date t):
  1. Filter universe (n_valid stocks at t)
  2. Per-Date cross-sectional z-score:
       mu_z          (higher = better)
       sigma_z       (lower  = better, uncertainty penalty)
       lam_z         (higher = better, right skew preferred)
       p_minus_5pct_z (lower = better, defensive)
  3. Composite alpha (default weights):
       alpha = 0.40 * mu_z + 0.20 * (-sigma_z) + 0.20 * lam_z + 0.20 * (-p_minus_5pct_z)
  4. Per-Date rank (descending alpha) + percentile

Output:
  - outputs/cross_section_alpha.parquet
    columns: Date, Ticker, mu, sigma, lam, p_minus_5pct, mu_z, sigma_z, lam_z, p_minus_5pct_z,
             alpha, rank_per_date, pct_per_date, n_universe_per_date
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

BASE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR = BASE / "04_Research/decision_framework/cross_section_distribution/outputs"

W_MU = 0.40
W_SIGMA = 0.20
W_LAM = 0.20
W_P5 = 0.20


def cs_zscore(s: pd.Series) -> pd.Series:
    mu = s.mean()
    sd = s.std(ddof=0)
    if sd == 0 or np.isnan(sd):
        return pd.Series(np.zeros(len(s)), index=s.index)
    return (s - mu) / sd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(OUT_DIR / "per_stock_forecasts.parquet"))
    ap.add_argument("--output", default=str(OUT_DIR / "cross_section_alpha.parquet"))
    args = ap.parse_args()

    t0 = time.time()
    df = pd.read_parquet(args.input)
    df["Date"] = pd.to_datetime(df["Date"])
    print(f"[CS-Alpha] rows={len(df)} tickers={df['Ticker'].nunique()} dates={df['Date'].nunique()}")

    needed = ["mu", "sigma", "lam", "p_minus_5pct"]
    for c in needed:
        if c not in df.columns:
            raise SystemExit(f"missing column {c}")

    df = df.dropna(subset=needed).copy()

    df["mu_z"] = df.groupby("Date")["mu"].transform(cs_zscore)
    df["sigma_z"] = df.groupby("Date")["sigma"].transform(cs_zscore)
    df["lam_z"] = df.groupby("Date")["lam"].transform(cs_zscore)
    df["p_minus_5pct_z"] = df.groupby("Date")["p_minus_5pct"].transform(cs_zscore)

    df["alpha"] = (
        W_MU * df["mu_z"]
        + W_SIGMA * (-df["sigma_z"])
        + W_LAM * df["lam_z"]
        + W_P5 * (-df["p_minus_5pct_z"])
    )

    df["rank_per_date"] = df.groupby("Date")["alpha"].rank(ascending=False, method="first").astype(int)
    df["n_universe_per_date"] = df.groupby("Date")["alpha"].transform("size").astype(int)
    df["pct_per_date"] = 1.0 - (df["rank_per_date"] - 1) / df["n_universe_per_date"]

    keep = ["Date", "Ticker", "mu", "sigma", "lam", "p_minus_5pct",
            "mu_z", "sigma_z", "lam_z", "p_minus_5pct_z",
            "alpha", "rank_per_date", "pct_per_date", "n_universe_per_date"]
    if "y_actual" in df.columns:
        keep.append("y_actual")
    out = df[keep].copy().sort_values(["Date", "rank_per_date"]).reset_index(drop=True)
    out.to_parquet(args.output, index=False)

    n_dates = out["Date"].nunique()
    avg_universe = out.groupby("Date").size().mean()
    summary = {
        "phase": "CSDA Phase 4 Cross-section composite alpha",
        "weights": {"mu": W_MU, "sigma_neg": W_SIGMA, "lam": W_LAM, "p_minus_5pct_neg": W_P5},
        "n_rows": int(len(out)),
        "n_dates": int(n_dates),
        "n_tickers": int(out["Ticker"].nunique()),
        "avg_universe_per_date": float(avg_universe),
        "elapsed_min": (time.time() - t0) / 60,
        "built_at": pd.Timestamp.now().isoformat(),
    }

    if "y_actual" in out.columns:
        rho_list = []
        for d, g in out.groupby("Date"):
            if g["y_actual"].notna().sum() < 10:
                continue
            r = g["alpha"].corr(g["y_actual"], method="spearman")
            if not np.isnan(r):
                rho_list.append(r)
        if rho_list:
            summary["ic_rank_mean"] = float(np.mean(rho_list))
            summary["ic_rank_std"] = float(np.std(rho_list))
            summary["icir"] = float(np.mean(rho_list) / np.std(rho_list)) if np.std(rho_list) > 0 else None
            summary["n_dates_with_ic"] = len(rho_list)

        top20 = out[out["rank_per_date"] <= 20]
        ls_ret = []
        for d, g in out.groupby("Date"):
            if g["y_actual"].notna().sum() < 40:
                continue
            top = g.nsmallest(20, "rank_per_date")["y_actual"].dropna()
            bot = g.nlargest(20, "rank_per_date")["y_actual"].dropna()
            if len(top) > 0 and len(bot) > 0:
                ls_ret.append(top.mean() - bot.mean())
        if ls_ret:
            summary["top20_minus_bot20_mean_pct"] = float(np.mean(ls_ret))
            summary["top20_minus_bot20_std_pct"] = float(np.std(ls_ret))
            summary["top20_minus_bot20_t_stat"] = float(np.mean(ls_ret) / (np.std(ls_ret) / np.sqrt(len(ls_ret)))) if np.std(ls_ret) > 0 else None
            summary["n_dates_top_bot"] = len(ls_ret)

    meta_path = Path(args.output).with_suffix(".meta.json")
    meta_path.write_text(json.dumps(summary, indent=2))
    print(f"[CS-Alpha] Done. saved {args.output}")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
