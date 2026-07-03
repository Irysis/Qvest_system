"""
333_b1_leading_macro.py — v3 forward-looking LEADING macro features ablation.

도훈 mandate 2026-06-26 (Task 2: new forward-looking leading data sources).

Builds on 331_b1_macro_features.py but swaps the macro feature set for genuinely
*leading* long-history credit / financial-condition series fetched in 332:
  Credit_Baa10Y, YC_10Y3M, NFCI_Credit, NFCI_Leverage, NFCI_Risk, StL_Fin_Stress4
(.cache/fred_leading_macro.parquet — full coverage over 2001-2024).

Combos:
  paper_only        : log_ret + GKYZ baseline
  with_leading      : paper + 6 leading credit/NFCI series        ★ NEW
  with_macro_old    : paper + old coincident macro (331 set)      (control)
  with_all_macro    : paper + leading 6 + old 5                   ★ NEW

EXTENDED window (date_end 2024-12-31) so COVID 2020-02-19 lands in a test fold.

PIT: every external series t-1 lagged (publication delay) + ffill. Forward bear catch
measured at the pre-crash forecast date (Lehman/Euro/COVID).
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import yaml

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


D = _load("distributions", str(ROOT / "03_models" / "distributions.py"))
PF = _load("pf", str(ROOT / "scripts" / "320_b1_paper_faithful.py"))
METRICS = _load("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))
# reuse training/eval/sequence helpers from 331
M331 = _load("m331", str(ROOT / "scripts" / "331_b1_macro_features.py"))

KEY_BEAR_DATES = M331.KEY_BEAR_DATES

LEADING_FEATURES = [
    "Credit_Baa10Y", "YC_10Y3M", "NFCI_Credit",
    "NFCI_Leverage", "NFCI_Risk", "StL_Fin_Stress4",
]
OLD_MACRO_FEATURES = ["Term_Spread", "VIX", "Chi_Fin_Cond", "StL_Fin_Stress", "Init_Claims", "KRW_USD_logret"]


def load_with_leading(cfg: dict):
    """Paper KOSPI + GKYZ + leading 6 + old-macro 6 (both PIT t-1 lagged)."""
    df = pd.read_parquet(PROJECT_ROOT / cfg["data"]["bm_path"]).rename(columns={"BM_Close": "Close"})
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").reset_index(drop=True)
    df["log_ret"] = np.log(df["Close"]).diff()
    df["gkyz_252"] = PF.gkyz_volatility(df, window=252)
    horizons = cfg["data"].get("horizons", [1, 21])
    for h in horizons:
        df[f"ret_fwd_{h}d"] = np.log(df["Close"].shift(-h) / df["Close"])

    # --- NEW leading macro (full-history) ---
    lead_path = PROJECT_ROOT / ".cache" / "fred_leading_macro.parquet"
    lead = pd.read_parquet(lead_path)
    lead["Date"] = pd.to_datetime(lead["Date"])
    lead_cols = [c for c in LEADING_FEATURES if c in lead.columns]
    for c in lead_cols:
        lead[c] = lead[c].ffill().shift(1)  # PIT t-1 lag (publication delay)
    df = df.merge(lead[["Date"] + lead_cols], on="Date", how="left")
    for c in lead_cols:
        df[c] = df[c].ffill().bfill()
    print(f"[lead] leading features: {lead_cols}")

    # --- OLD coincident macro (331 set) as control ---
    fred = pd.read_parquet(PROJECT_ROOT / cfg["data"]["fred_path"])
    fred["Date"] = pd.to_datetime(fred["Date"])
    old_cols = []
    sub = [c for c in ["Term_Spread", "VIX", "Chi_Fin_Cond", "StL_Fin_Stress", "Init_Claims"] if c in fred.columns]
    fred = fred[["Date"] + sub]
    for c in sub:
        fred[c] = fred[c].ffill().shift(1)
        old_cols.append(c)
    df = df.merge(fred, on="Date", how="left")
    for c in old_cols:
        df[c] = df[c].ffill().bfill()
    # KRW/USD logret
    krw = pd.read_parquet(PROJECT_ROOT / cfg["data"]["krw_usd_path"])
    krw["Date"] = pd.to_datetime(krw["Date"])
    krw = krw.sort_values("Date").reset_index(drop=True)
    krw["KRW_USD_logret"] = np.log(krw["KRW_USD"]).diff().shift(1)
    df = df.merge(krw[["Date", "KRW_USD_logret"]], on="Date", how="left")
    df["KRW_USD_logret"] = df["KRW_USD_logret"].ffill().bfill()
    old_cols.append("KRW_USD_logret")

    ds, de = pd.to_datetime(cfg["data"]["date_start"]), pd.to_datetime(cfg["data"]["date_end"])
    df = df[(df["Date"] >= ds) & (df["Date"] <= de)].reset_index(drop=True)
    essential = ["log_ret", "gkyz_252"] + [f"ret_fwd_{h}d" for h in horizons]
    df = df.dropna(subset=essential).reset_index(drop=True)
    if cfg["data"].get("percent_scale", True):
        for c in df.columns:
            if c.startswith(("log_ret", "gkyz_", "ret_fwd_", "KRW_USD_logret")):
                df[c] = df[c] * 100.0
    print(f"[lead] Final shape: {df.shape}, {df['Date'].min().date()} .. {df['Date'].max().date()}")
    return df, lead_cols, old_cols


def run(cfg_path, output_dir, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[lead] device: {device}")
    df, lead_cols, old_cols = load_with_leading(cfg)
    base = ["log_ret", "gkyz_252"]
    seq_len = cfg["training"]["sequence_length"]
    train_min = cfg["walk_forward"]["train_min"]
    test_w = cfg["walk_forward"]["test_window"]
    os.makedirs(output_dir, exist_ok=True)

    feature_sets = {
        "paper_only": base,
        "with_leading": base + lead_cols,
        "with_macro_old": base + old_cols,
        "with_all_macro": base + lead_cols + old_cols,
    }
    combos = [{"horizon": h, "feature_set": fs} for h in [1, 21] for fs in feature_sets]
    all_results = {}

    for combo in combos:
        fs, horizon = combo["feature_set"], combo["horizon"]
        feats = feature_sets[fs]
        tag = f"cnn_sstd_h{horizon}_{fs}"
        print(f"\n[lead] ====== {tag} ({len(feats)} features) ======")
        target_col = f"ret_fwd_{horizon}d"
        X, y, dates = M331.build_sequences(df, seq_len, feats, target_col)
        windows = M331.walk_forward(len(X), train_min=train_min, test=test_w)
        sub_dir = Path(output_dir) / tag
        sub_dir.mkdir(parents=True, exist_ok=True)
        all_preds = []
        win_metrics = []
        for w_idx, (tr_end, te_end) in enumerate(windows):
            X_tr, y_tr = X[:tr_end], y[:tr_end]
            X_te, y_te = X[tr_end:te_end], y[tr_end:te_end]
            dates_te = dates[tr_end:te_end]
            theta_te, best_val = M331.train_eval(X_tr, y_tr, X_te, y_te, "skewed_t", cfg, device, seed=seed)
            ev = M331.evaluate(theta_te, y_te, "skewed_t")
            pred_df = pd.DataFrame({
                "Date": pd.to_datetime(dates_te), "y_actual": y_te,
                "crps": ev["crps_per_obs"], "nll": ev["nll_per_obs"], "pit": ev["pit_values"],
                "var_05": ev["var_05"], "var_01": ev["var_01"],
                "p_minus_5pct": ev["p_minus_5"], "p_minus_7pct": ev["p_minus_7"], "p_minus_10pct": ev["p_minus_10"],
            })
            pred_df.to_parquet(sub_dir / f"window_{w_idx:02d}_predictions.parquet")
            all_preds.append(pred_df)
            var05bt = VARBT.var_backtest_full(y_te, ev["var_05"], alpha=0.05)
            win_metrics.append({"window_idx": w_idx, "crps_mean": float(ev["crps_per_obs"].mean()),
                                "n_obs": len(y_te), "var_05_kupiec_pass": var05bt["kupiec_uc"]["pass_at_005"]})
            print(f"  w[{w_idx}] CRPS={float(ev['crps_per_obs'].mean()):.5f} P(-10%)mean={ev['p_minus_10'].mean():.4f}")
        full = pd.concat(all_preds, ignore_index=True)
        full.to_parquet(sub_dir / "all_predictions.parquet")
        var05p = VARBT.var_backtest_full(full["y_actual"].values, full["var_05"].values, alpha=0.05)
        var01p = VARBT.var_backtest_full(full["y_actual"].values, full["var_01"].values, alpha=0.01)
        pitp = CALIB.pit_chi_square(full["pit"].values, n_bins=10)
        bear = {}
        for label, ds in KEY_BEAR_DATES.items():
            td = pd.to_datetime(ds)
            mask = full["Date"] == td
            if mask.sum() == 0:
                diffs = (full["Date"] - td).abs()
                if diffs.min() <= pd.Timedelta(days=3):
                    row = full.iloc[diffs.idxmin()]
                else:
                    bear[label] = {"in_test_set": False}
                    continue
            else:
                row = full[mask].iloc[0]
            bear[label] = {"in_test_set": True, "forecast_date": str(row["Date"].date()),
                           "y_actual": float(row["y_actual"]),
                           "p_minus_5pct": float(row["p_minus_5pct"]), "p_minus_7pct": float(row["p_minus_7pct"]),
                           "p_minus_10pct": float(row["p_minus_10pct"])}
        all_results[tag] = {
            "config": combo, "n_features": len(feats), "feature_names": feats,
            "n_test_total": int(len(full)), "crps_pooled": float(full["crps"].mean()),
            "nll_pooled": float(full["nll"].mean()),
            "var_05_backtest_pooled": var05p, "var_01_backtest_pooled": var01p,
            "pit_chi_square_pooled": pitp, "window_metrics": win_metrics,
            "bear_date_evaluations": bear,
            "bear_probabilities_summary": {
                "p_minus_5pct_mean": float(full["p_minus_5pct"].mean()),
                "p_minus_5pct_max": float(full["p_minus_5pct"].max()),
                "p_minus_10pct_mean": float(full["p_minus_10pct"].mean()),
                "p_minus_10pct_max": float(full["p_minus_10pct"].max())},
        }
        print(f"[{tag}] POOLED CRPS={all_results[tag]['crps_pooled']:.5f}")

    out = Path(output_dir) / "leading_macro_summary.json"
    with open(out, "w") as f:
        json.dump(all_results, f, indent=2, default=M331._json_default)
    print(f"\n[lead] saved: {out}")
    print("\n" + "=" * 70 + "\nΔ CRPS vs paper_only + forward bear catch\n" + "=" * 70)
    for h in [1, 21]:
        base_tag = f"cnn_sstd_h{h}_paper_only"
        if base_tag not in all_results:
            continue
        bc = all_results[base_tag]["crps_pooled"]
        for fs in feature_sets:
            tag = f"cnn_sstd_h{h}_{fs}"
            if tag in all_results:
                r = all_results[tag]
                delta = (r["crps_pooled"] - bc) / bc * 100
                covid = r["bear_date_evaluations"].get("COVID_2020-02-19", {})
                cp = covid.get("p_minus_10pct", None)
                cps = f"{cp*100:.2f}%" if cp is not None else "NA"
                print(f"  {tag:<38s} CRPS={r['crps_pooled']:.4f} Δ={delta:+6.2f}%  COVID_P(-10%)={cps}")
    return all_results


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--config", default="config/b1_macro_ext.yaml")
    p.add_argument("--output", default="03_models/b1_leading_macro")
    p.add_argument("--seed", type=int, default=0)
    a = p.parse_args()
    run(str(ROOT / a.config), str(ROOT / a.output), seed=a.seed)


if __name__ == "__main__":
    main()
