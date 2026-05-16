"""Sigmoid Cash-Replacement Prototype (옵션 4) — 84m backtest.

도훈 mandate 2026-05-16: STR_1715 PG2 regime overlay cash 부분을 M6 Ensemble로
sigmoid smooth tilt 대체. cash_baseline × sigmoid(-(Score-50)*k) 가중치 schedule.

Architecture:
  w_STR(t)  = regime_β(t)                  # STR_1715 weight unchanged (regime overlay)
  cash_base = 1 - regime_β(t)
  ml_activ  = sigmoid(-(Score - 50) * k)
  w_ML(t)   = cash_base * ml_activ
  w_cash(t) = cash_base * (1 - ml_activ)

Inputs:
  - STR_1715 returns (ret_net) from 03_period_returns.csv
  - STR_1715 regime weight implicit from overlay (cash_baseline = 1 - ret_gross/risk_only_ret)
  - M6 Ensemble alpha + top-30 EW monthly returns (m6_ew_top30_monthly_returns.parquet)
  - unified_regime_signal_daily.parquet (Score 0-100 continuous)

Output:
  - prototype_returns.parquet (monthly portfolio returns)
  - prototype_metrics.json (SR / CAGR / MDD / TO / vs baseline)
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(x))


def compute_metrics(rets):
    """PerformanceAnalytics standard 계산."""
    r = np.asarray(rets)
    n = len(r)
    mean_m = r.mean()
    std_m = r.std(ddof=1)
    sr = (mean_m / std_m * np.sqrt(12)) if std_m > 0 else float("nan")
    cagr = (1 + r).prod() ** (12 / n) - 1
    cum = (1 + r).cumprod()
    peak = np.maximum.accumulate(cum)
    dd = (cum - peak) / peak
    mdd = dd.min()
    sortino_denom = r[r < 0].std(ddof=1) if (r < 0).any() else std_m
    sortino = (mean_m / sortino_denom * np.sqrt(12)) if sortino_denom > 0 else float("nan")
    calmar = (cagr / abs(mdd)) if mdd < 0 else float("nan")
    return {"sr": float(sr), "cagr": float(cagr), "mdd": float(mdd),
             "sortino": float(sortino), "calmar": float(calmar), "n": n}


def main():
    PROJECT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
    OUT = PROJECT / "stage_artifacts/WT_D20260516_001_sigmoid_prototype"
    OUT.mkdir(exist_ok=True, parents=True)

    print("[1/5] Load STR_1715 production returns + holdings...")
    str_periods = pd.read_csv(PROJECT / "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
    str_periods["date"] = pd.to_datetime(str_periods["date"])
    str_periods["ym"] = str_periods["date"].dt.strftime("%Y-%m")

    str_holdings = pd.read_csv(PROJECT / "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/04_holdings.csv")
    str_holdings["date"] = pd.to_datetime(str_holdings["date"])
    str_holdings["ym"] = str_holdings["date"].dt.strftime("%Y-%m")
    # cash_weight derived from holdings
    cash_w = str_holdings[str_holdings["ticker"].str.contains("CASH", na=False)].copy()
    cash_w = cash_w.groupby("ym")["target_weight"].sum().reset_index()
    cash_w.columns = ["ym", "cash_weight"]
    print(f"  STR_1715 periods: {len(str_periods)} months ({str_periods['date'].min()} ~ {str_periods['date'].max()})")
    print(f"  Cash weight extracted: {len(cash_w)} months (mean {cash_w['cash_weight'].mean():.3f})")

    print("[2/5] Load M6 Ensemble EW top-30 monthly returns...")
    m6 = pd.read_parquet(PROJECT / "stage_artifacts/WT_D20260515_002/m6_ew_top30_monthly_returns.parquet")
    print(f"  M6 cols: {list(m6.columns)} rows: {len(m6)}")
    # Adapt columns - try common names
    if "realization_ym" in m6.columns:
        m6["ym"] = m6["realization_ym"]
    elif "Date" in m6.columns:
        m6["ym"] = pd.to_datetime(m6["Date"]).dt.strftime("%Y-%m")
    elif "ym_signal" in m6.columns:
        m6["ym"] = m6["ym_signal"]
    ret_col = next((c for c in ["m6_ret", "ml_ret", "port_ret", "ret", "ret_net", "monthly_return"]
                     if c in m6.columns), None)
    if ret_col:
        m6 = m6[["ym", ret_col]].rename(columns={ret_col: "m6_ret"})
    print(f"  M6 monthly: {len(m6)} months, mean ret {m6['m6_ret'].mean():.4f}")

    print("[3/5] Load unified_regime_signal_daily (Crisis_Score)...")
    regime = pd.read_parquet(PROJECT / ".cache/unified_regime_signal_daily.parquet")
    regime["Date"] = pd.to_datetime(regime["Date"])
    # Monthly aggregate: last available Score per month-end
    regime["ym"] = regime["Date"].dt.strftime("%Y-%m")
    regime_m = regime.sort_values("Date").groupby("ym")["Regime_Score"].last().reset_index()
    regime_m.columns = ["ym", "crisis_score"]
    print(f"  Regime monthly: {len(regime_m)} months, Score mean {regime_m['crisis_score'].mean():.1f}")

    print("[4/5] Build sigmoid cash-replacement portfolio (k=0.15, midpoint=50)...")
    # Join all on ym
    df = str_periods[["ym", "ret_net"]].rename(columns={"ret_net": "str_ret"})
    df = df.merge(cash_w, on="ym", how="left")
    df["cash_weight"] = df["cash_weight"].fillna(0)
    df["str_weight"] = 1 - df["cash_weight"]
    df = df.merge(m6, on="ym", how="left")
    df = df.merge(regime_m, on="ym", how="left")

    # Sigmoid activation
    k = 0.15
    midpoint = 50
    df["ml_activ"] = sigmoid((df["crisis_score"] - midpoint) * k)

    # Cash-replacement weights
    df["w_str"] = df["str_weight"]
    df["w_ml"] = df["cash_weight"] * df["ml_activ"]
    df["w_cash"] = df["cash_weight"] * (1 - df["ml_activ"])

    # Portfolio return = w_str × str_ret + w_ml × m6_ret + w_cash × 0
    # str_ret is already weighted (includes overlay cash drag), so we need to back out
    # raw_str_return = str_ret / str_weight (gross of cash drag) — approximate
    # Simpler: compute as if str_ret IS the str sleeve component (includes its own cash internally)
    # → Alternative: use str_ret as-is for w_str×str_ret_per_unit
    df["raw_str_ret_per_unit"] = df.apply(
        lambda r: r["str_ret"] / r["str_weight"] if r["str_weight"] > 0.05 else 0, axis=1
    )

    # Total return: w_str × (raw_str_ret_per_unit) + w_ml × m6_ret + w_cash × 0
    df["portfolio_ret"] = df["w_str"] * df["raw_str_ret_per_unit"] + df["w_ml"].fillna(0) * df["m6_ret"].fillna(0)

    # Drop rows without M6 (pre-2019)
    overlap = df.dropna(subset=["m6_ret", "crisis_score"]).copy()
    overlap = overlap[overlap["str_weight"] > 0]
    overlap = overlap.sort_values("ym").reset_index(drop=True)
    print(f"  Overlap (M6 + STR + regime): {len(overlap)} months")
    if len(overlap) < 12:
        print("  ❌ Not enough overlap data")
        return

    print("[5/5] Compute metrics + save...")
    # Baseline (STR_1715 alone as-is, ret_net)
    baseline_metrics = compute_metrics(overlap["str_ret"].values)
    # New prototype
    proto_metrics = compute_metrics(overlap["portfolio_ret"].values)
    # M6 alone
    m6_only_metrics = compute_metrics(overlap["m6_ret"].fillna(0).values)
    # STR_1715 raw (cash drag retain — for sanity)
    str_raw_metrics = compute_metrics(overlap.apply(lambda r: r["raw_str_ret_per_unit"] if r["str_weight"] > 0.05 else 0, axis=1).values)

    # Turnover proxy (weight changes month-to-month)
    overlap["w_ml_lag"] = overlap["w_ml"].shift(1).fillna(0)
    overlap["w_cash_lag"] = overlap["w_cash"].shift(1).fillna(0)
    overlap["dw_ml"] = (overlap["w_ml"] - overlap["w_ml_lag"]).abs()
    overlap["dw_cash"] = (overlap["w_cash"] - overlap["w_cash_lag"]).abs()
    proto_to_yr = (overlap["dw_ml"] + overlap["dw_cash"]).mean() * 12

    summary = {
        "architecture": "sigmoid_cash_replacement_option_4",
        "params": {"k": k, "midpoint": midpoint},
        "n_overlap_months": len(overlap),
        "overlap_range": [overlap["ym"].iloc[0], overlap["ym"].iloc[-1]],
        "mean_weights": {
            "w_str": float(overlap["w_str"].mean()),
            "w_ml": float(overlap["w_ml"].mean()),
            "w_cash": float(overlap["w_cash"].mean()),
        },
        "weight_distribution": {
            "w_ml_max": float(overlap["w_ml"].max()),
            "w_ml_min": float(overlap["w_ml"].min()),
            "w_cash_max": float(overlap["w_cash"].max()),
            "w_cash_min": float(overlap["w_cash"].min()),
        },
        "metrics_baseline_str1715_ret_net_as_is": baseline_metrics,
        "metrics_prototype_sigmoid_cash_replacement": proto_metrics,
        "metrics_m6_only": m6_only_metrics,
        "metrics_str_raw_no_cash_drag": str_raw_metrics,
        "turnover_replacement_layer_yr": float(proto_to_yr),
        "delta_sr_vs_baseline": float(proto_metrics["sr"] - baseline_metrics["sr"]),
        "delta_cagr_vs_baseline": float(proto_metrics["cagr"] - baseline_metrics["cagr"]),
    }

    overlap.to_parquet(OUT / "prototype_returns.parquet", index=False)
    (OUT / "prototype_metrics.json").write_text(json.dumps(summary, indent=2, default=str))

    print("\n=== Sigmoid Cash-Replacement Prototype Results ===")
    print(f"Overlap: {summary['n_overlap_months']} months ({summary['overlap_range']})")
    print(f"Mean weights: STR={summary['mean_weights']['w_str']:.3f} ML={summary['mean_weights']['w_ml']:.3f} cash={summary['mean_weights']['w_cash']:.3f}")
    print(f"Replacement TO/yr: {summary['turnover_replacement_layer_yr']:.2f}")
    print()
    print("Metrics comparison:")
    print(f"  Baseline (STR_1715 ret_net as-is):    SR={baseline_metrics['sr']:.3f}  CAGR={baseline_metrics['cagr']*100:.2f}%  MDD={baseline_metrics['mdd']*100:.2f}%")
    print(f"  Prototype (sigmoid cash-replacement): SR={proto_metrics['sr']:.3f}  CAGR={proto_metrics['cagr']*100:.2f}%  MDD={proto_metrics['mdd']*100:.2f}%")
    print(f"  M6 only:                              SR={m6_only_metrics['sr']:.3f}  CAGR={m6_only_metrics['cagr']*100:.2f}%  MDD={m6_only_metrics['mdd']*100:.2f}%")
    print(f"  STR_1715 raw (no cash drag):          SR={str_raw_metrics['sr']:.3f}  CAGR={str_raw_metrics['cagr']*100:.2f}%  MDD={str_raw_metrics['mdd']*100:.2f}%")
    print()
    print(f"⭐ Δ SR vs baseline:    {summary['delta_sr_vs_baseline']:+.3f}")
    print(f"⭐ Δ CAGR vs baseline:  {summary['delta_cagr_vs_baseline']*100:+.2f}pp")
    print(f"\nSaved: {OUT}/prototype_metrics.json + prototype_returns.parquet")


if __name__ == "__main__":
    main()
