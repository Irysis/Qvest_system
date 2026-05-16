"""Phase 1 (Uncertainty + Cost-aware) full run 결과 종합 분석.

Usage:
  source /home/quant/qvest_ml_venv/bin/activate
  python 02_Infrastructure/ml_pipeline/phase1_analysis.py \
      --ml-out stage_artifacts/WT_D20260514_014_phase1_full \
      --returns-panel stage_artifacts/WT_D20260514_007/returns_monthly_panel.parquet \
      --admit-returns 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv

분석 4종:
  1. M4 base vs M7 cost-aware turnover 비교 (Phase 1.B Jensen-Kelly 2022 validation)
  2. ConfidentHighLow vs naive (Phase 1.A Liao 2025 RFS reproduce)
  3. M5/M6/M7 × STR_1715 Pareto blend sweep (Sequential Admission FINAL candidate)
  4. Uncertainty-discounted M1 Ridge alpha (Liao 2025 RFS μ̃ = μ̂ - k·SE)
"""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd


def _ann_sr(s: pd.Series) -> float:
    s = s.dropna()
    if len(s) < 12 or s.std(ddof=1) == 0:
        return float("nan")
    return float(s.mean() / s.std(ddof=1) * np.sqrt(12))


def _mdd(s: pd.Series) -> float:
    cum = (1 + s).cumprod()
    return float(((cum - cum.cummax()) / cum.cummax()).min())


def build_top_n_blend(pred: pd.DataFrame, model: str, rets: pd.DataFrame,
                      admit_ret: pd.DataFrame, top_n: int = 30, rebal_freq: int = 2,
                      cost_bps_oneway: float = 15.0,
                      date_col: str = "sig_date", ticker_col: str = "Ticker",
                      ret_col: str = "Ret_1m_fwd"):
    p = pred[pred["model"] == model].copy()
    p[date_col] = pd.to_datetime(p[date_col])
    merged = p.merge(rets[[date_col, ticker_col, ret_col]], on=[date_col, ticker_col], how="inner")
    dates = sorted(merged[date_col].unique())
    portfolio = set()
    ml_port = []
    for i, d in enumerate(dates):
        grp = merged[merged[date_col] == d]
        if i % rebal_freq == 0:
            new_p = set(grp.nlargest(top_n, "score")[ticker_col].values)
            to = len(new_p - portfolio) / top_n if portfolio else 0
            portfolio = new_p
        else: to = 0
        pr = grp[grp[ticker_col].isin(portfolio)][ret_col].mean() if len(portfolio) >= 5 else 0
        cost_drag = to * 2 * cost_bps_oneway / 10000
        realization_dt = pd.to_datetime(d) + pd.offsets.MonthBegin(1)
        ml_port.append({"realization_ym": realization_dt.strftime("%Y-%m"),
                          "ml_ret": pr - cost_drag, "turnover": to})
    ml_df = pd.DataFrame(ml_port)
    j = ml_df.merge(admit_ret, on="realization_ym").sort_values("realization_ym")
    return j, float(ml_df["turnover"].mean() * 12)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ml-out", required=True, help="WT directory with predictions/summary/manifest")
    ap.add_argument("--returns-panel", required=True)
    ap.add_argument("--admit-returns", required=True)
    ap.add_argument("--out-summary", default=None,
                    help="JSON output path (default: ml-out/phase1_analysis.json)")
    args = ap.parse_args()

    out_dir = Path(args.ml_out)
    out_path = Path(args.out_summary) if args.out_summary else out_dir / "phase1_analysis.json"

    print(f"[1/4] Load Phase 1 outputs from {out_dir} ...")
    pred = pd.read_parquet(out_dir / "predictions.parquet")
    summary = json.loads((out_dir / "summary_metrics.json").read_text())
    manifest = json.loads((out_dir / "manifest.json").read_text())
    print(f"  predictions: {pred.shape}")
    print(f"  manifest: features={manifest.get('n_features')} folds={manifest.get('n_folds_total')}")

    rets = pd.read_parquet(args.returns_panel)
    rets["sig_date"] = pd.to_datetime(rets["Date"])

    admit = pd.read_csv(args.admit_returns)
    admit["realization_ym"] = pd.to_datetime(admit["date"]).dt.strftime("%Y-%m")
    admit_ret = admit[["realization_ym", "ret_net"]].rename(columns={"ret_net": "admit_ret"})

    result = {"ml_out_dir": str(out_dir), "manifest": manifest,
               "comparisons": {}}

    # === Analysis 1: M4 base vs M7 cost-aware turnover ===
    print(f"\n[2/4] M4 vs M7 turnover comparison (Phase 1.B Jensen-Kelly 2022)")
    for m in ["M4_XGB_GPU", "M7_XGB_CostAware"]:
        if m not in pred["model"].unique():
            continue
        for mode in ["is", "lockbox", "all"]:
            k = f"{m}_{mode}"
            if k in summary:
                e = summary[k]
                print(f"  {k:30s}: TO_yr={e.get('annualized_turnover', float('nan')):.2f} "
                      f"gross={e.get('gross_port_sr', float('nan')):.3f} "
                      f"net={e.get('net_port_sr', float('nan')):.3f}")
                result["comparisons"].setdefault("cost_aware", {})[k] = {
                    "TO_yr": e.get("annualized_turnover"),
                    "gross_sr": e.get("gross_port_sr"),
                    "net_sr": e.get("net_port_sr"),
                    "cost_drag_pp": e.get("cost_drag_pp"),
                }

    # === Analysis 2: ConfidentHighLow vs naive ===
    print(f"\n[3/4] Confident-High-Low vs naive (Phase 1.A Liao 2025 RFS)")
    chl_keys = [k for k in summary if k.startswith("ConfidentHighLow_")]
    for k in chl_keys:
        e = summary[k]
        print(f"  {k:50s}: naive_sr={e.get('naive_sr_annualized', float('nan')):.3f} "
              f"confident_sr={e.get('confident_sr_annualized', float('nan')):.3f} "
              f"Δ={e.get('sr_improvement', float('nan')):.3f}")
        result["comparisons"].setdefault("uncertainty", {})[k] = e

    # === Analysis 3: M5/M6/M7 × STR_1715 Pareto blend sweep ===
    print(f"\n[4/4] Pareto blend sweep (Sequential Admission FINAL candidate)")
    blend_summary = {}
    for m in ["M5_LGB", "M6_Ensemble", "M7_XGB_CostAware"]:
        if m not in pred["model"].unique():
            continue
        for freq, label in [(1, "monthly"), (2, "bi-monthly")]:
            j, ml_to = build_top_n_blend(pred, m, rets, admit_ret,
                                            top_n=30, rebal_freq=freq)
            if len(j) < 12: continue
            pearson = j["ml_ret"].corr(j["admit_ret"])
            for w in [0.30, 0.40, 0.50]:
                b = w * j["ml_ret"] + (1 - w) * j["admit_ret"]
                sr = _ann_sr(b)
                cagr = (1 + b).prod() ** (12 / len(b)) - 1
                md = _mdd(b)
                k = f"{m}_{label}_w{int(w*100)}"
                blend_summary[k] = {
                    "ml_to_yr": ml_to,
                    "eff_to_yr": float(w * ml_to + (1 - w) * 2.0),  # admit ~2/yr conservative
                    "pearson": float(pearson),
                    "blend_sr": sr, "blend_cagr": float(cagr), "blend_mdd": md,
                    "n_overlap": int(len(j)),
                }
                marker = " ⭐" if sr >= 2.0 and md > -0.20 and w * ml_to + (1 - w) * 2.0 <= 6.0 else ""
                print(f"  {k:32s}: SR={sr:.3f} CAGR={cagr*100:5.2f}% MDD={md*100:6.2f}% "
                      f"eff_TO={w * ml_to + (1 - w) * 2.0:.2f} cor={pearson:.3f}{marker}")
    result["comparisons"]["pareto_blend"] = blend_summary

    # === Save ===
    out_path.write_text(json.dumps(result, indent=2, default=str))
    print(f"\n✓ Saved: {out_path}")


if __name__ == "__main__":
    main()
