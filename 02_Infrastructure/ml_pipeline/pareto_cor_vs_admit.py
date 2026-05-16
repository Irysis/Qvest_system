"""Pareto realized cor: ML M6 Ensemble (top-20 EW) vs STR_1715 PG2 admit returns.

Sequential Admission gate per Charter v1.7 §10:
  cor < 0.40 PASS (orthogonal alpha source candidate)
  cor ≥ 0.40 FAIL (redundant with admitted PG2)

Usage:
  source /home/quant/qvest_ml_venv/bin/activate
  python 02_Infrastructure/ml_pipeline/pareto_cor_vs_admit.py \
      --ml-predictions stage_artifacts/WT_D20260514_010/predictions.parquet \
      --returns-panel  stage_artifacts/WT_D20260514_007/returns_monthly_panel.parquet \
      --admit-returns  04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv \
      --model M6_Ensemble \
      --out stage_artifacts/WT_D20260514_010/pareto_vs_str1715.json
"""
import argparse
import json
from pathlib import Path
import pandas as pd
import numpy as np


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ml-predictions", required=True)
    ap.add_argument("--returns-panel", required=True)
    ap.add_argument("--admit-returns", required=True)
    ap.add_argument("--model", default="M6_Ensemble")
    ap.add_argument("--target-col", default="Ret_1m_fwd")
    ap.add_argument("--date-col", default="sig_date")
    ap.add_argument("--ticker-col", default="Ticker")
    ap.add_argument("--top-n", type=int, default=20)
    ap.add_argument("--ret-net-col", default="ret_net",
                    help="STR_1715 period returns column (default ret_net)")
    ap.add_argument("--cost-bps-oneway", type=float, default=0.0,
                    help="Apply cost adjust to ML side (default 0 = gross). Use 15 for KR retail net")
    ap.add_argument("--mode-filter", default="all",
                    choices=["all", "is", "lockbox"],
                    help="Filter predictions by mode (all/is/lockbox). lockbox = OOS pure.")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    print(f"[1/4] Load ML predictions ({args.ml_predictions}) ...")
    pred = pd.read_parquet(args.ml_predictions)
    pred = pred[pred["model"] == args.model].copy()
    if args.mode_filter != "all" and "mode" in pred.columns:
        pred = pred[pred["mode"] == args.mode_filter].copy()
    pred[args.date_col] = pd.to_datetime(pred[args.date_col])
    print(f"  predictions: {pred.shape}, models filtered to {args.model} mode={args.mode_filter}")

    print(f"[2/4] Load returns panel ({args.returns_panel}) ...")
    rets = pd.read_parquet(args.returns_panel)
    if args.date_col not in rets.columns and "Date" in rets.columns:
        rets = rets.rename(columns={"Date": args.date_col})
    rets[args.date_col] = pd.to_datetime(rets[args.date_col])
    print(f"  returns: {rets.shape}")

    print(f"[3/4] Build top-{args.top_n} EW portfolio returns from {args.model} ...")
    merged = pred.merge(rets[[args.date_col, args.ticker_col, args.target_col]],
                          on=[args.date_col, args.ticker_col], how="inner")
    ml_port = []
    prev_top_tickers = set()
    for d in sorted(merged[args.date_col].unique()):
        grp = merged[merged[args.date_col] == d]
        if len(grp) < args.top_n:
            continue
        top = grp.nlargest(args.top_n, "score")
        top_tickers = set(top[args.ticker_col].values)
        # Realization YM = sig_date + 1 month (Ret_1m_fwd is forward return)
        realization_dt = pd.to_datetime(d) + pd.offsets.MonthBegin(1)
        # One-way turnover = new entries / N
        if len(prev_top_tickers) == 0:
            to_oneway = 0.0
        else:
            new_entries = len(top_tickers - prev_top_tickers)
            to_oneway = new_entries / args.top_n
        # Net = gross - round-trip cost (turnover × 2 × bps / 1e4)
        cost_drag_this_period = to_oneway * 2 * args.cost_bps_oneway / 10000.0
        gross = top[args.target_col].mean()
        net = gross - cost_drag_this_period
        ml_port.append({"realization_ym": realization_dt.strftime("%Y-%m"),
                          "ml_ret_gross": gross,
                          "ml_ret_net": net,
                          "ml_turnover_oneway": to_oneway})
        prev_top_tickers = top_tickers
    ml_port_df = pd.DataFrame(ml_port).sort_values("realization_ym")
    # Use net if cost specified, else gross
    ml_port_df["ml_ret"] = ml_port_df["ml_ret_net"] if args.cost_bps_oneway > 0 else ml_port_df["ml_ret_gross"]
    print(f"  ML top-{args.top_n} portfolio months: {len(ml_port_df)} "
          f"({ml_port_df['realization_ym'].min()} ~ {ml_port_df['realization_ym'].max()})")

    print(f"[4/4] Load admit (STR_1715) returns ({args.admit_returns}) ...")
    admit = pd.read_csv(args.admit_returns)
    admit["date"] = pd.to_datetime(admit["date"])
    # STR_1715 date is start-of-month of realization month
    admit["realization_ym"] = admit["date"].dt.strftime("%Y-%m")
    admit_ret = admit[["realization_ym", args.ret_net_col]].rename(columns={args.ret_net_col: "admit_ret"})
    print(f"  admit returns months: {len(admit_ret)} "
          f"({admit_ret['realization_ym'].min()} ~ {admit_ret['realization_ym'].max()})")

    joined = ml_port_df.merge(admit_ret, on="realization_ym", how="inner")
    joined["date"] = pd.to_datetime(joined["realization_ym"] + "-01")
    joined = joined.dropna(subset=["ml_ret", "admit_ret"])
    print(f"  joined months: {len(joined)} (overlap)")

    if len(joined) < 12:
        result = {"error": "insufficient overlap (< 12 months)",
                   "n_overlap": len(joined),
                   "n_ml": len(ml_port_df),
                   "n_admit": len(admit_ret)}
        Path(args.out).write_text(json.dumps(result, indent=2, default=str))
        print(f"FAIL: insufficient overlap. saved {args.out}")
        return

    pearson = float(joined["ml_ret"].corr(joined["admit_ret"]))
    spearman = float(joined["ml_ret"].corr(joined["admit_ret"], method="spearman"))
    kendall = float(joined["ml_ret"].corr(joined["admit_ret"], method="kendall"))

    # Lower-tail dependence (TDC empirical bottom 10% quantile)
    q10_ml = joined["ml_ret"].quantile(0.10)
    q10_admit = joined["admit_ret"].quantile(0.10)
    tail_overlap = ((joined["ml_ret"] <= q10_ml) & (joined["admit_ret"] <= q10_admit)).sum()
    n_tail = (joined["ml_ret"] <= q10_ml).sum()
    tdc_lower = float(tail_overlap / max(n_tail, 1))

    # Upper-tail dependence (TDC empirical top 10% quantile, useful for upside co-movement)
    q90_ml = joined["ml_ret"].quantile(0.90)
    q90_admit = joined["admit_ret"].quantile(0.90)
    upper_overlap = ((joined["ml_ret"] >= q90_ml) & (joined["admit_ret"] >= q90_admit)).sum()
    n_upper = (joined["ml_ret"] >= q90_ml).sum()
    tdc_upper = float(upper_overlap / max(n_upper, 1))

    # Information Ratio of difference (ML - Admit) — captures alpha source distinction
    diff_ret = joined["ml_ret"] - joined["admit_ret"]
    ir_diff = float(diff_ret.mean() / max(diff_ret.std(ddof=1), 1e-12) * np.sqrt(12))

    # Diversification ratio
    ml_var = joined["ml_ret"].var(ddof=1)
    admit_var = joined["admit_ret"].var(ddof=1)
    cov = joined["ml_ret"].cov(joined["admit_ret"])
    # 50/50 blend
    blend = 0.5 * joined["ml_ret"] + 0.5 * joined["admit_ret"]
    blend_var = blend.var(ddof=1)
    weighted_avg_var = 0.5 * ml_var + 0.5 * admit_var
    div_ratio = float(weighted_avg_var / max(blend_var, 1e-12))  # >1 = diversifying

    # Sharpe comparisons
    def _sr(s):
        s = s.dropna()
        if len(s) < 12 or s.std(ddof=1) == 0:
            return float("nan")
        return float(s.mean() / s.std(ddof=1) * np.sqrt(12))

    sr_ml = _sr(joined["ml_ret"])
    sr_admit = _sr(joined["admit_ret"])
    sr_blend = _sr(blend)

    pareto_pass = pearson < 0.40

    annualized_to = float(ml_port_df["ml_turnover_oneway"].mean() * 12) if len(ml_port_df) > 0 else float("nan")
    result = {
        "ml_model": args.model,
        "ml_mode_filter": args.mode_filter,
        "admit_strategy": "STR_1715_WT016_Iter31_GridBestProd",
        "ml_cost_bps_oneway": args.cost_bps_oneway,
        "ml_ret_basis": "net" if args.cost_bps_oneway > 0 else "gross",
        "ml_annualized_turnover_oneway": annualized_to,
        "n_overlap_months": int(len(joined)),
        "overlap_start": joined["date"].min().strftime("%Y-%m-%d"),
        "overlap_end": joined["date"].max().strftime("%Y-%m-%d"),
        "pareto_cor": {
            "pearson": pearson,
            "spearman": spearman,
            "kendall": kendall,
            "tdc_lower_10pct": tdc_lower,
            "tdc_upper_10pct": tdc_upper,
            "diversification_ratio_50_50": div_ratio,
            "ir_difference_annualized": ir_diff,
        },
        "sharpe_proxies": {
            "ml_only_top20_ew": sr_ml,
            "admit_str1715_net": sr_admit,
            "blend_50_50": sr_blend,
            "blend_improvement_pp": sr_blend - max(sr_ml, sr_admit),
        },
        "sequential_admission_gate": {
            "threshold_pearson": 0.40,
            "actual_pearson": pearson,
            "pass": pareto_pass,
            "note": ("PASS — alpha source 직교 후보 (cor < 0.40)" if pareto_pass else
                     "FAIL — STR_1715와 redundant (cor ≥ 0.40), admit 어려움"),
        },
    }
    Path(args.out).write_text(json.dumps(result, indent=2, default=str))
    print(f"\n=== Pareto cor results ===")
    print(f"  Pearson: {pearson:.4f} | Spearman: {spearman:.4f} | Kendall: {kendall:.4f}")
    print(f"  TDC (10% lower): {tdc_lower:.4f} | Div ratio: {div_ratio:.4f}")
    print(f"  SR — ML: {sr_ml:.3f} | Admit: {sr_admit:.3f} | Blend: {sr_blend:.3f}")
    print(f"  Sequential admission gate (cor < 0.40): {'PASS' if pareto_pass else 'FAIL'}")
    print(f"  Saved: {args.out}")


if __name__ == "__main__":
    main()
