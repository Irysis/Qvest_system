"""
STR_1721 Phase 1 v2 — K200 6-Family Smart Beta Factor Panel (학술 정합 multi-proxy composite)

Academic-grade composite (Asness/Frazzini/Pedersen + Carhart + Frazzini-Pedersen):

  value     5-proxy  V01_BM + V02_EP + V03_CFP + V20_SP + V14_EBIT_EV
            (Asness-Frazzini 2013 "The Devil in HML's Details" composite)
  quality   4-proxy  Q02_ROE + Q03_ROA + Q17_ROIC + GR05_ROE_Growth
            (Asness-Frazzini-Pedersen 2019 QMJ Profitability + Growth)
  momentum  3-proxy  M01_Mom_12_1 + M02_Mom_6_1 + M03_Mom_3_1
            (Asness-Moskowitz-Pedersen 2014 multi-horizon)
  low_vol   4-proxy  D01_IdioVol + D02_Beta + D03_RealVol + D04_Downside_Beta
            (Frazzini-Pedersen 2014 BAB + Ang 2006 IVOL + Baker-Bradley-Wurgler 2011)
  size      1-proxy  -S01_Size (sign flip = SMB small > large, Banz 1981 convention)
  dividend  3-proxy  V06_fDY + V11_Shareholder_Yield + V17_Payout_Ratio
            (Boudoukh 2007 Shareholder Yield extension)

Composite construction:
  1. Per sig_date t, K200 universe (per_stock_features.K200==1.0)
  2. Per factor proxy: Z_Score from factor_db, direction-aligned (lower_better → -Z)
  3. Family composite = equal-weight Z-average over proxies (Asness style)
  4. Top quintile = top 40 stocks within K200 by composite Z (200 × 0.2)
  5. t forward 21d return (features.ret_h_21d_forward, in %) → equal-weight mean

PIT (C13/C14/C15):
  - factor_db Z_Score is already PIT (Factor_Date <= sig_d)
  - No NEGATE_FACTORS for direction='higher_better'; explicit -Z only for direction='lower_better'
  - SIZE family: -S01_Size is academic SMB convention, NOT a sign flip violation
    (size is universally a "small-cap premium" anomaly; direction=higher in registry just means raw size, not factor return sign)
  - Forward return: features.ret_h_21d_forward (already forward via correct shift convention)

Output:
  - outputs/k200_factor_returns_monthly.parquet
  - outputs/k200_factor_returns_monthly.meta.json
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

BASE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR = BASE / "04_Research/decision_framework/smart_beta_regime/outputs"
FACTOR_DB = BASE / ".cache/factor_db"
FEATURES = BASE / "04_Research/decision_framework/cross_section_distribution/outputs/per_stock_features.parquet"

# Academic-grade multi-proxy composites
FAMILIES = {
    "value": {
        "proxies": [
            ("V01_BM", "higher_better"),
            ("V02_EP", "higher_better"),
            ("V03_CFP", "higher_better"),
            ("V20_SP", "higher_better"),
            ("V14_EBIT_EV", "higher_better"),
        ],
        "ref": "Asness-Frazzini 2013 (Devil in HML's Details)",
    },
    "quality": {
        "proxies": [
            ("Q02_ROE", "higher_better"),
            ("Q03_ROA", "higher_better"),
            ("Q17_ROIC", "higher_better"),
            ("GR05_ROE_Growth", "higher_better"),
        ],
        "ref": "Asness-Frazzini-Pedersen 2019 QMJ (Profitability + Growth)",
    },
    "momentum": {
        "proxies": [
            ("M01_Mom_12_1", "higher_better"),
            ("M02_Mom_6_1",  "higher_better"),
            ("M03_Mom_3_1",  "higher_better"),
        ],
        "ref": "Asness-Moskowitz-Pedersen 2014 multi-horizon momentum",
    },
    "low_vol": {
        "proxies": [
            ("D01_IdioVol",       "lower_better"),
            ("D02_Beta",          "lower_better"),
            ("D03_RealVol",       "lower_better"),
            ("D04_Downside_Beta", "lower_better"),
        ],
        "ref": "Frazzini-Pedersen 2014 BAB + Ang 2006 IVOL + Baker-Bradley-Wurgler 2011",
    },
    "size": {
        "proxies": [("S01_Size", "lower_better")],  # SMB convention: small > large
        "ref": "Banz 1981 SMB (sign flip from raw size)",
    },
    "dividend": {
        "proxies": [
            ("V06_fDY",               "higher_better"),
            ("V11_Shareholder_Yield", "higher_better"),
            ("V17_Payout_Ratio",      "higher_better"),
        ],
        "ref": "Boudoukh-Michaely-Richardson-Roberts 2007 Shareholder Yield",
    },
}

TOP_QUINTILE_N = 40  # K200 200 × 0.2 = 40


def load_factor_db_long(start_ym="200501", end_ym="202606", factor_ids=None):
    """Load monthly factor_db parquet long-format, filtered by factor_ids."""
    files = sorted(FACTOR_DB.glob("factor_db_*.parquet"))
    frames = []
    for f in files:
        ym = f.stem.split("_")[-1]
        if start_ym <= ym <= end_ym:
            df = pd.read_parquet(f, columns=["Date", "Ticker", "Factor_Name", "Z_Score", "Z_Sector"])
            if factor_ids:
                df = df[df["Factor_Name"].isin(factor_ids)]
            if len(df) > 0:
                frames.append(df)
    if not frames:
        raise SystemExit("No factor_db data loaded")
    out = pd.concat(frames, ignore_index=True)
    out["Date"] = pd.to_datetime(out["Date"])
    return out


def compute_composite_z(fdb_at_date: pd.DataFrame, family_spec: dict) -> pd.DataFrame:
    """Per-Date, per-family composite Z (equal-weight average of direction-aligned proxy Z)."""
    proxies = family_spec["proxies"]
    proxy_frames = []
    for fid, direction in proxies:
        sub = fdb_at_date[fdb_at_date["Factor_Name"] == fid][["Ticker", "Z_Score"]]
        if len(sub) == 0:
            continue
        if direction == "lower_better":
            sub = sub.assign(Z_aligned=-sub["Z_Score"])
        else:
            sub = sub.assign(Z_aligned=sub["Z_Score"])
        proxy_frames.append(sub[["Ticker", "Z_aligned"]].rename(columns={"Z_aligned": f"Z_{fid}"}))
    if not proxy_frames:
        return pd.DataFrame(columns=["Ticker", "Z_composite"])
    # Outer-merge across proxies (some tickers missing some proxies)
    out = proxy_frames[0]
    for f in proxy_frames[1:]:
        out = out.merge(f, on="Ticker", how="outer")
    z_cols = [c for c in out.columns if c.startswith("Z_")]
    out["Z_composite"] = out[z_cols].mean(axis=1, skipna=True)
    out["n_proxies_used"] = out[z_cols].notna().sum(axis=1)
    return out[["Ticker", "Z_composite", "n_proxies_used"]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default=str(OUT_DIR / "k200_factor_returns_monthly.parquet"))
    ap.add_argument("--ret_var", default="ret_h_21d_forward", help="forward return column (% scale)")
    args = ap.parse_args()

    t0 = time.time()

    print("[1] Load features panel (K200 universe + forward return)")
    feat = pd.read_parquet(FEATURES, columns=["Date", "Ticker", "K200", args.ret_var])
    feat["Date"] = pd.to_datetime(feat["Date"])
    feat = feat[feat["K200"] == 1.0].dropna(subset=[args.ret_var]).copy()
    feat["forward_ret"] = feat[args.ret_var] / 100.0  # % → decimal
    print(f"  K200 rows: {len(feat):,} | tickers: {feat['Ticker'].nunique()}")

    all_proxy_ids = []
    for fam, sp in FAMILIES.items():
        for fid, _ in sp["proxies"]:
            if fid not in all_proxy_ids:
                all_proxy_ids.append(fid)
    print(f"[2] Load factor_db long for {len(all_proxy_ids)} proxies")
    fdb = load_factor_db_long(factor_ids=all_proxy_ids)
    print(f"  factor_db rows: {len(fdb):,} | distinct factor_names: {fdb['Factor_Name'].nunique()}")

    sig_dates = sorted(fdb["Date"].unique())
    print(f"  sig_dates: {len(sig_dates)} | range: {sig_dates[0]} ~ {sig_dates[-1]}")

    print("[3] Compute composite Z + top quintile + forward return per sig_date")
    rows = []
    for sd in sig_dates:
        sd_pd = pd.Timestamp(sd)
        # K200 universe at sd (within ±10 days of sig_date)
        univ = feat[(feat["Date"] >= sd_pd - pd.Timedelta(days=10))
                    & (feat["Date"] <= sd_pd + pd.Timedelta(days=10))][["Ticker", "forward_ret"]]
        univ = univ.drop_duplicates(subset=["Ticker"], keep="last")
        if len(univ) < 100:
            continue

        fdb_at_date = fdb[fdb["Date"] == sd_pd]
        if len(fdb_at_date) == 0:
            continue

        out_row = {"Date": sd_pd, "n_universe": int(len(univ))}
        for fam, sp in FAMILIES.items():
            comp = compute_composite_z(fdb_at_date, sp)
            if len(comp) == 0:
                out_row[fam] = np.nan
                continue
            m = comp.merge(univ, on="Ticker", how="inner")
            if len(m) < 50:
                out_row[fam] = np.nan
                continue
            m = m.dropna(subset=["Z_composite"])
            top = m.nlargest(min(TOP_QUINTILE_N, len(m)), "Z_composite")
            out_row[fam] = float(top["forward_ret"].mean())
            out_row[f"{fam}_n"] = int(len(top))
            out_row[f"{fam}_avg_proxies"] = float(top["n_proxies_used"].mean())
        rows.append(out_row)

    out = pd.DataFrame(rows).sort_values("Date").reset_index(drop=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out.to_parquet(args.output, index=False)

    summary = {
        "strategy_id": "STR_1721_SBETA_P4_Regime",
        "phase": "Phase 1 v2 — Academic-grade multi-proxy composite",
        "families": {f: {"proxies": [p[0] for p in s["proxies"]],
                          "directions": [p[1] for p in s["proxies"]],
                          "ref": s["ref"]} for f, s in FAMILIES.items()},
        "top_quintile_n": TOP_QUINTILE_N,
        "n_dates": int(len(out)),
        "date_start": str(out["Date"].min()),
        "date_end": str(out["Date"].max()),
        "elapsed_min": (time.time() - t0) / 60,
        "built_at": pd.Timestamp.now().isoformat(),
    }
    for fam in FAMILIES:
        if fam in out.columns:
            s = out[fam].dropna()
            if len(s) > 0:
                ann_ret = s.mean() * 12
                ann_vol = s.std() * np.sqrt(12)
                sr = ann_ret / ann_vol if ann_vol > 0 else None
                summary[f"{fam}_n_months"] = int(len(s))
                summary[f"{fam}_ann_ret"] = float(ann_ret)
                summary[f"{fam}_ann_vol"] = float(ann_vol)
                summary[f"{fam}_sr"] = float(sr) if sr else None

    meta_path = Path(args.output).with_suffix(".meta.json")
    meta_path.write_text(json.dumps(summary, indent=2, default=str))
    print(f"[4] Done. saved {args.output}")
    print(json.dumps(summary, indent=2, default=str))


if __name__ == "__main__":
    main()
