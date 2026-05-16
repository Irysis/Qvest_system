"""Sigmoid Cash-Replacement Prototype v2 — Score-based cash modeling.

v1 실패: STR_1715 holdings.csv sleeve-level (CASH 0% target).
v2 접근: PG2 production rule (m4×β_AR×β_R05)을 unified Score로 reconstruct.

cash_weight model (84m sample 평균 ≈ 27% per Forge attestation):
  Score < 20 (RISK_ON 강): cash 0%
  Score 20-40 (NEUTRAL):    cash 0~10% linear
  Score 40-60 (NEUTRAL+):   cash 10~30% linear
  Score 60-75 (CAUTION):    cash 30~70% linear
  Score >= 75 (RISK_OFF/CRISIS): cash 70~95% linear

이 model로 cash_weight time series → sigmoid cash replacement 적용.

Final portfolio:
  effective_str_ret = ret_net (already includes regime overlay)
  + (cash_weight) × ml_activ × m6_ret  (cash 일부 ML 대체)

ml_activ = sigmoid(-(Score - 50) * k=0.15)

Output: prototype_metrics.json + per-month breakdown
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(x))


def cash_weight_model(score):
    """PG2 production rule을 unified Score로 reconstruct."""
    if score < 20:    return 0.00
    elif score < 40:  return 0.10 * (score - 20) / 20            # 0 → 10%
    elif score < 60:  return 0.10 + 0.20 * (score - 40) / 20     # 10 → 30%
    elif score < 75:  return 0.30 + 0.40 * (score - 60) / 15     # 30 → 70%
    else:             return 0.70 + 0.25 * min(1, (score - 75) / 15)  # 70 → 95%


def compute_metrics(rets):
    r = np.asarray(rets)
    n = len(r)
    if n < 2:
        return {"sr": float("nan"), "cagr": float("nan"), "mdd": float("nan"), "n": n}
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

    print("[1/5] Load STR_1715 production ret_net (84m subsample)...")
    str_periods = pd.read_csv(PROJECT / "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
    str_periods["date"] = pd.to_datetime(str_periods["date"])
    str_periods["ym"] = str_periods["date"].dt.strftime("%Y-%m")
    df = str_periods[["ym", "ret_net"]].rename(columns={"ret_net": "str_ret"})

    print("[2/5] Load M6 Ensemble EW top-30 monthly returns (84m)...")
    m6 = pd.read_parquet(PROJECT / "stage_artifacts/WT_D20260515_002/m6_ew_top30_monthly_returns.parquet")
    m6 = m6.rename(columns={"ym_signal": "ym", "port_ret": "m6_ret"})[["ym", "m6_ret"]]

    print("[3/5] Load unified Regime_Score monthly aggregate...")
    regime = pd.read_parquet(PROJECT / ".cache/unified_regime_signal_daily.parquet")
    regime["Date"] = pd.to_datetime(regime["Date"])
    regime["ym"] = regime["Date"].dt.strftime("%Y-%m")
    regime_m = regime.sort_values("Date").groupby("ym")["Regime_Score"].last().reset_index()
    regime_m.columns = ["ym", "crisis_score"]

    print("[4/5] Build sigmoid cash-replacement (Score-based cash model)...")
    df = df.merge(m6, on="ym").merge(regime_m, on="ym")
    df = df.sort_values("ym").reset_index(drop=True)

    # Synthetic cash weight from Score (PG2 production rule reconstruct)
    df["cash_w_model"] = df["crisis_score"].apply(cash_weight_model)

    # Sigmoid activation
    k = 0.15
    midpoint = 50
    df["ml_activ"] = sigmoid((df["crisis_score"] - midpoint) * k)

    # ML weight within cash portion
    df["w_ml_replace"] = df["cash_w_model"] * df["ml_activ"]
    df["w_cash_retain"] = df["cash_w_model"] * (1 - df["ml_activ"])
    df["w_str_effective"] = 1 - df["cash_w_model"]  # implied by model

    # New portfolio return:
    #   prototype_ret = str_ret + (cash_w × ml_activ) × m6_ret  (ML가 cash 일부 대체)
    # 즉 str_ret는 그대로 (이미 cash drag 적용된 PG2 return), 추가로 cash 일부에 ML alpha 얹기
    # Caveat: 이건 첫 approximation. Full 정확한 모델은 raw str signal-only return 필요.
    df["proto_ret"] = df["str_ret"] + df["w_ml_replace"] * df["m6_ret"]

    # TO proxy
    df["w_ml_lag"] = df["w_ml_replace"].shift(1).fillna(0)
    df["dw_ml"] = (df["w_ml_replace"] - df["w_ml_lag"]).abs()
    proto_to_yr = df["dw_ml"].mean() * 12 * 2  # round-trip

    print("[5/5] Metrics + save...")
    baseline = compute_metrics(df["str_ret"].values)
    proto = compute_metrics(df["proto_ret"].values)
    m6_only = compute_metrics(df["m6_ret"].values)

    summary = {
        "architecture": "sigmoid_cash_replacement_v2_score_based",
        "params": {"k": k, "midpoint": midpoint, "cash_model": "PG2 reconstruct from unified Score"},
        "n_months": len(df),
        "overlap_range": [df["ym"].iloc[0], df["ym"].iloc[-1]],
        "score_distribution": {
            "mean": float(df["crisis_score"].mean()),
            "median": float(df["crisis_score"].median()),
            "p25": float(df["crisis_score"].quantile(0.25)),
            "p75": float(df["crisis_score"].quantile(0.75)),
        },
        "cash_weight_model_stats": {
            "mean": float(df["cash_w_model"].mean()),
            "max": float(df["cash_w_model"].max()),
            "min": float(df["cash_w_model"].min()),
        },
        "ml_activ_stats": {
            "mean": float(df["ml_activ"].mean()),
            "max": float(df["ml_activ"].max()),
            "min": float(df["ml_activ"].min()),
        },
        "mean_weights": {
            "w_str_effective": float(df["w_str_effective"].mean()),
            "w_ml_replace": float(df["w_ml_replace"].mean()),
            "w_cash_retain": float(df["w_cash_retain"].mean()),
        },
        "metrics_baseline_str1715_ret_net": baseline,
        "metrics_prototype_with_ml_cash_replacement": proto,
        "metrics_m6_only": m6_only,
        "replacement_layer_TO_yr": float(proto_to_yr),
        "delta_sr_vs_baseline": float(proto["sr"] - baseline["sr"]),
        "delta_cagr_vs_baseline_pp": float((proto["cagr"] - baseline["cagr"]) * 100),
        "delta_mdd_vs_baseline_pp": float((proto["mdd"] - baseline["mdd"]) * 100),
    }

    df.to_parquet(OUT / "prototype_v2_returns.parquet", index=False)
    (OUT / "prototype_v2_metrics.json").write_text(json.dumps(summary, indent=2, default=str))

    print("\n=== Sigmoid Cash-Replacement v2 Results ===")
    print(f"Overlap: {summary['n_months']} months ({summary['overlap_range']})")
    print(f"Score dist: mean={summary['score_distribution']['mean']:.1f} median={summary['score_distribution']['median']:.1f}")
    print(f"Cash model mean: {summary['cash_weight_model_stats']['mean']:.3f} (target ≈ 0.27 per Forge)")
    print(f"ml_activ mean: {summary['ml_activ_stats']['mean']:.3f}")
    print(f"Replacement TO/yr: {summary['replacement_layer_TO_yr']:.2f}")
    print()
    print("Metrics:")
    print(f"  Baseline (STR_1715 ret_net 84m):    SR={baseline['sr']:.3f}  CAGR={baseline['cagr']*100:6.2f}%  MDD={baseline['mdd']*100:6.2f}%")
    print(f"  Prototype (cash-replacement v2):    SR={proto['sr']:.3f}  CAGR={proto['cagr']*100:6.2f}%  MDD={proto['mdd']*100:6.2f}%")
    print(f"  M6 only:                            SR={m6_only['sr']:.3f}  CAGR={m6_only['cagr']*100:6.2f}%  MDD={m6_only['mdd']*100:6.2f}%")
    print()
    print(f"⭐ Δ SR vs baseline:    {summary['delta_sr_vs_baseline']:+.3f}")
    print(f"⭐ Δ CAGR vs baseline:  {summary['delta_cagr_vs_baseline_pp']:+.2f}pp")
    print(f"⭐ Δ MDD vs baseline:   {summary['delta_mdd_vs_baseline_pp']:+.2f}pp")
    print(f"\nSaved: {OUT}/prototype_v2_metrics.json")


if __name__ == "__main__":
    main()
