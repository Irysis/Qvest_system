"""
STR_1721 Phase 2 — P4 Multi-Horizon ECDF Forecast (22d / 44d / 66d)

Reuses P4-ECDF Stage 3 best #181 spec:
  alpha=9.989e-3, train_min=3528, taus_count=15, embargo=35, n_splits=8

Logic:
  - Load P4 horizon-aware features panel (483_p4_features_horizon.py output for KOSPI200)
  - For each horizon H ∈ {22, 44, 66}:
      * Build forward log return label r_fwd_H (already-shifted forward)
      * Single train walk-forward LASSO Quantile (15 taus) + ECDF
      * Derive mu, sigma, lam, var_05, var_01, p_minus_5pct
      * ACI wrap (gamma=0.005) for var_05, var_01
  - Output: outputs/p4_multi_horizon.parquet (Date × {horizon × 6 statistic})

Reuses code from 04_Research/decision_framework/bearish_forecast_v3/scripts/
  - 483_p4_features_horizon.py (features panel construction)
  - 200_walk_forward_cv.py (PurgedWalkForwardCV)
  - 03_models/a1_lasso_quantile.py (LassoQuantileGaR)
  - 03_models/p1_hansen_skewt.py (derive_metrics_per_obs)
"""

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

BASE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR = BASE / "04_Research/decision_framework/smart_beta_regime/outputs"
BFV3 = BASE / "04_Research/decision_framework/bearish_forecast_v3"

sys.path.insert(0, str(BFV3))
sys.path.insert(0, str(BFV3 / "scripts"))
sys.path.insert(0, str(BFV3 / "03_models"))
sys.path.insert(0, str(BFV3 / "04_evaluation"))

# Best #181 spec from P4-ECDF Stage 3
SPEC = {
    "alpha": 9.989315386097177e-3,
    "train_min": 3528,
    "taus_count": 15,
    "embargo": 35,
    "n_splits": 8,
    "test_size": 504,
}
HORIZONS = [22, 44, 66]
GAMMA_ACI = 0.005


def load_kospi200_panel():
    """Reuse P4 features panel build. KOSPI200 index level (single series + macro)."""
    feat_path = BFV3 / "outputs/p4_features_panel.parquet"
    if not feat_path.exists():
        raise SystemExit(f"P4 features panel not found: {feat_path}")
    df = pd.read_parquet(feat_path)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").reset_index(drop=True)
    return df


def build_forward_label(df: pd.DataFrame, h: int) -> pd.DataFrame:
    """Forward h-day log return label (correct shift convention per .claude/rules/data_table_shift_convention.md)."""
    df = df.copy()
    if "BM_Close" in df.columns:
        close_col = "BM_Close"
    elif "Close" in df.columns:
        close_col = "Close"
    else:
        raise SystemExit("No close column found")
    # Forward h-day return r(t, t+h) = log(BM[t+h] / BM[t]) — CORRECT shift (positive h + lead-equivalent)
    df[f"ret_fwd_{h}"] = np.log(df[close_col].shift(-h) / df[close_col])
    return df


def aci_update(y_actual: np.ndarray, q_raw: np.ndarray, alpha_target: float, gamma: float):
    """ACI wrap (Gibbs-Candes 2021) for var_05 / var_01."""
    from scipy.stats import norm
    n = len(y_actual)
    alpha_path = np.full(n, alpha_target)
    q_adjust = np.zeros(n)
    for t in range(1, n):
        if not np.isnan(y_actual[t - 1]):
            breach = 1.0 if (y_actual[t - 1] < q_raw[t - 1] + q_adjust[t - 1]) else 0.0
            alpha_path[t] = np.clip(alpha_path[t - 1] + gamma * (breach - alpha_target), 1e-4, 0.5)
        else:
            alpha_path[t] = alpha_path[t - 1]
        dz = norm.ppf(alpha_path[t]) - norm.ppf(alpha_target)
        scale = max(abs(q_raw[t]) if not np.isnan(q_raw[t]) else 0.5, 0.5)
        q_adjust[t] = dz * scale
    q_aci = q_raw + q_adjust
    return q_aci, alpha_path


def fit_one_horizon(df: pd.DataFrame, h: int):
    """Walk-forward LASSO Quantile + ECDF + ACI wrap for horizon h."""
    from a1_lasso_quantile import LassoQuantileGaR

    # Walk-forward setup
    df_h = build_forward_label(df, h).dropna().reset_index(drop=True)
    feat_cols = [c for c in df_h.columns if c.startswith(("log_ret_lag", "rv_", "mean_",
                                                          "drawdown", "momentum",
                                                          "vix", "term_spread", "dgs10",
                                                          "nfci", "kr_", "krwusd"))]
    feat_cols = [c for c in feat_cols if c in df_h.columns and df_h[c].notna().mean() > 0.5]
    print(f"  [H={h}d] features: {len(feat_cols)}")

    y = df_h[f"ret_fwd_{h}"].values
    X = df_h[feat_cols].values
    dates = df_h["Date"].values
    n = len(df_h)

    # Walk-forward predictions
    taus = np.linspace(0.05, 0.95, SPEC["taus_count"])
    train_min = SPEC["train_min"]
    test_size = SPEC["test_size"]
    embargo = SPEC["embargo"]

    preds = []
    fold_start = train_min
    fold = 0
    while fold_start + embargo < n:
        train_X = X[:fold_start]
        train_y = y[:fold_start]
        test_start = fold_start + embargo
        test_end = min(test_start + test_size, n)
        if test_end - test_start < 10:
            break
        test_X = X[test_start:test_end]
        model = LassoQuantileGaR(taus=list(taus), alpha=SPEC["alpha"], standardize=True)
        model.fit(train_X, train_y)
        q_pred = model.predict_all_quantiles(test_X, fix_crossing=True)  # (n_test, n_taus)
        for j, idx in enumerate(range(test_start, test_end)):
            preds.append({
                "Date": pd.Timestamp(dates[idx]),
                "fold": fold,
                **{f"q_{int(tau*100):02d}": q_pred[j, k] for k, tau in enumerate(taus)},
                "y_actual": y[idx],
            })
        fold += 1
        fold_start = test_end
    pred_df = pd.DataFrame(preds)
    print(f"  [H={h}d] folds={fold} predictions={len(pred_df)}")

    # Derive ECDF statistics
    q_cols = [c for c in pred_df.columns if c.startswith("q_")]
    qmat = pred_df[q_cols].values  # (n, n_taus)
    # mu = median (q_50)
    mu = pred_df["q_50"].values if "q_50" in pred_df.columns else qmat[:, len(taus) // 2]
    # sigma = (q_75 - q_25) / 1.3490  (Gaussian-equivalent IQR scale)
    q25_col = f"q_{int(0.25 * 100):02d}"
    q75_col = f"q_{int(0.75 * 100):02d}"
    # Interpolate q at tau=0.25 and 0.75
    tau_arr = np.array(taus)
    q25 = np.array([np.interp(0.25, tau_arr, q_row) for q_row in qmat])
    q75 = np.array([np.interp(0.75, tau_arr, q_row) for q_row in qmat])
    sigma = (q75 - q25) / 1.3490
    # lam = Bowley skewness (q_75 + q_25 - 2*q_50) / (q_75 - q_25)
    iqr = q75 - q25
    lam = np.where(iqr > 1e-6, (q75 + q25 - 2 * mu) / iqr, 0.0)
    # VaR
    var_05 = np.array([np.interp(0.05, tau_arr, q_row) for q_row in qmat])
    var_01 = np.array([np.interp(0.01, tau_arr, q_row) for q_row in qmat])
    # p_minus_5pct: cdf at y=-5 (= -0.05 in log return space)
    p_minus_5pct = np.array([np.interp(-5.0 / 100.0, q_row, tau_arr) for q_row in qmat])  # log return ~ -5%
    # ACI wrap
    y_actual = pred_df["y_actual"].values
    var_05_aci, _ = aci_update(y_actual, var_05, 0.05, GAMMA_ACI)
    var_01_aci, _ = aci_update(y_actual, var_01, 0.01, GAMMA_ACI)

    out = pd.DataFrame({
        "Date": pred_df["Date"],
        f"mu_{h}": mu,
        f"sigma_{h}": sigma,
        f"lam_{h}": lam,
        f"var_05_{h}": var_05,
        f"var_01_{h}": var_01,
        f"var_05_aci_{h}": var_05_aci,
        f"var_01_aci_{h}": var_01_aci,
        f"p_minus_5pct_{h}": p_minus_5pct,
        f"y_actual_{h}": y_actual,
    })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default=str(OUT_DIR / "p4_multi_horizon.parquet"))
    args = ap.parse_args()

    t0 = time.time()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("[1] Load KOSPI200 panel (P4 features + close)")
    df = load_kospi200_panel()
    print(f"  rows={len(df)} | range={df['Date'].min()} ~ {df['Date'].max()}")

    print("[2] Fit P4-ECDF per horizon (22/44/66)")
    frames = []
    for h in HORIZONS:
        print(f"  H={h}d ...")
        out_h = fit_one_horizon(df, h)
        frames.append(out_h)

    merged = frames[0]
    for f in frames[1:]:
        merged = merged.merge(f, on="Date", how="outer")
    merged = merged.sort_values("Date").reset_index(drop=True)
    merged.to_parquet(args.output, index=False)

    summary = {
        "strategy_id": "STR_1721_SBETA_P4_Regime",
        "phase": "Phase 2 P4 Multi-Horizon ECDF + ACI",
        "horizons": HORIZONS,
        "spec": SPEC,
        "gamma_aci": GAMMA_ACI,
        "n_rows": int(len(merged)),
        "date_start": str(merged["Date"].min()),
        "date_end": str(merged["Date"].max()),
        "elapsed_min": (time.time() - t0) / 60,
        "built_at": pd.Timestamp.now().isoformat(),
    }
    # ACI breach rate per horizon
    for h in HORIZONS:
        y_col = f"y_actual_{h}"
        if y_col in merged.columns:
            y = merged[y_col].dropna()
            v05 = merged[f"var_05_{h}"].dropna()
            v05a = merged[f"var_05_aci_{h}"].dropna()
            n = min(len(y), len(v05))
            if n > 0:
                summary[f"raw_breach_05_{h}d"] = float((y.iloc[:n] < v05.iloc[:n]).mean())
                summary[f"aci_breach_05_{h}d"] = float((y.iloc[:n] < v05a.iloc[:n]).mean())
    meta_path = Path(args.output).with_suffix(".meta.json")
    meta_path.write_text(json.dumps(summary, indent=2, default=str))
    print(f"[3] Done. saved {args.output}")
    print(json.dumps(summary, indent=2, default=str))


if __name__ == "__main__":
    main()
