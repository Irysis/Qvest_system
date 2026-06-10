#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_c2_panel_augment.py — Qvest DPL cycle2: 90f baseline + 직교/방어 피처 다양화.

90f base panel(WT_DPL_GPU_SWEEP, momentum/value/quality/accrual/consensus/defense/flow 보유)에
task 명시 *추가* 피처를 PIT-정합 month-key merge로 결합:
  RESIDMOM__lvl/__slp  (WT-D20260606_001 잔차모멘텀 alpha_score; R05 return_cor -0.061 직교)
  PIOTROSKI__lvl/__slp (F-Score 0..9; crisis 방어/quality 종합)        [dpl_c2_quality_features.R]
  MOHANRAM__lvl/__slp  (G-Score 신호율; 저BM growth 방어)              [동상]
  NETISSUE__lvl/__slp  (-Δlog shares YoY; Pontiff-Woodgate, IN04 직교)  [동상]
→ 90 + 8 = 98f. (각 신규 alpha당 __lvl=cross-section z, __slp=backward 1-lag Δ. __vol 미부여.)

PIT:
  - 모든 신규 score는 month-end signal(t-known, t→t+1 예측). 기존 90f와 동일 semantics.
  - __lvl = same-month cross-section z(단면 PIT). __slp = score(t)-score(t-1) backward diff(과거만).
  - merge=ym,Ticker left on base(label Ret_1m=forward 유지, 재계산 안 함). 결측 z=0(중립).
  - R dpl_c2_pit_audit.R forward-label recompute + 신규피처 concurrent-lookahead 검사 PASS 의무.

출력: stage_artifacts/WT_DPL_C2/dpl_feature_panel.parquet + benchmark/regime(복사) + meta.
실행: G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe dpl_c2_panel_augment.py
"""
import os
import json
import numpy as np
import pandas as pd

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
SRC_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_C2")
os.makedirs(OUT_DIR, exist_ok=True)

BASE_PANEL = os.path.join(SRC_DIR, "dpl_feature_panel.parquet")
BASE_BENCH = os.path.join(SRC_DIR, "benchmark_monthly.parquet")
BASE_REGIME = os.path.join(SRC_DIR, "regime_monthly.parquet")
RESIDMOM = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_WT-D20260606_001", "alpha_scores.parquet")
EXTRA = os.path.join(OUT_DIR, "extra_scores.parquet")   # dpl_c2_quality_features.R 산출


def csz(s):
    """cross-section z within group (PIT: same-month only)."""
    return (s - s.mean()) / (s.std(ddof=0) + 1e-9)


def add_lvl_slp(out, score_df, name, score_col):
    """score_df(ym,Ticker,score) → out에 {name}__lvl(단면z) + {name}__slp(backward Δ) 병합."""
    df = score_df[["ym", "Ticker", score_col]].copy()
    df["ym"] = df["ym"].astype(str)
    df[f"{name}__lvl"] = df.groupby("ym")[score_col].transform(csz)
    df = df.sort_values(["Ticker", "ym"])
    df["_prev"] = df.groupby("Ticker")[f"{name}__lvl"].shift(1)
    df[f"{name}__slp"] = (df[f"{name}__lvl"] - df["_prev"]).fillna(0.0)
    feat = df[["ym", "Ticker", f"{name}__lvl", f"{name}__slp"]]
    merged = out.merge(feat, on=["ym", "Ticker"], how="left")
    for c in (f"{name}__lvl", f"{name}__slp"):
        merged[c] = merged[c].fillna(0.0)
    cov = (merged[f"{name}__lvl"] != 0).mean()
    print(f"[c2-aug]   +{name}: cols=2  coverage_on_base={cov:.2%}")
    return merged, [f"{name}__lvl", f"{name}__slp"], float(cov)


def main():
    print("[c2-aug] loading base 90f panel ...")
    panel = pd.read_parquet(BASE_PANEL)
    panel["ym"] = panel["ym"].astype(str)
    base_feat = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    print(f"[c2-aug] base rows={len(panel):,} feats={len(base_feat)} months={panel['ym'].nunique()}")

    out = panel
    new_feat = list(base_feat)
    cov = {}

    # residual-momentum alpha_score
    print("[c2-aug] merging residual-mom (WT-D20260606_001) ...")
    rm = pd.read_parquet(RESIDMOM)
    rm["Date"] = pd.to_datetime(rm["Date"])
    rm["ym"] = rm["Date"].dt.to_period("M").astype(str)
    out, f, c = add_lvl_slp(out, rm.rename(columns={"alpha_score": "s"}), "RESIDMOM", "s")
    new_feat += f; cov["RESIDMOM"] = c

    # Piotroski / Mohanram / NetIssue (R 산출)
    if not os.path.exists(EXTRA):
        raise RuntimeError(f"extra_scores.parquet 부재 — dpl_c2_quality_features.R 먼저 실행: {EXTRA}")
    ex = pd.read_parquet(EXTRA)
    ex["ym"] = ex["ym"].astype(str)
    print(f"[c2-aug] extra_scores rows={len(ex):,} cols={[c for c in ex.columns if c not in ('ym','Ticker')]}")
    for name, col in [("PIOTROSKI", "PIOTROSKI"), ("MOHANRAM", "MOHANRAM"), ("NETISSUE", "NETISSUE")]:
        sub = ex[["ym", "Ticker", col]].dropna(subset=[col])
        out, f, c = add_lvl_slp(out, sub, name, col)
        new_feat += f; cov[name] = c

    print(f"[c2-aug] augmented feats = {len(new_feat)} (base {len(base_feat)} + {len(new_feat)-len(base_feat)} new)")

    out_panel = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
    out.to_parquet(out_panel, index=False)
    pd.read_parquet(BASE_BENCH).to_parquet(os.path.join(OUT_DIR, "benchmark_monthly.parquet"), index=False)
    if os.path.exists(BASE_REGIME):
        pd.read_parquet(BASE_REGIME).to_parquet(os.path.join(OUT_DIR, "regime_monthly.parquet"), index=False)

    meta = {
        "variant": "c2 — 90f baseline + residmom + Piotroski-F + Mohanram-G + NetIssue (98f)",
        "n_feature_cols": len(new_feat),
        "base_feature_cols": len(base_feat),
        "added_blocks": {
            "RESIDMOM": "WT-D20260606_001 residual-mom alpha (R05 return_cor -0.061 직교)",
            "PIOTROSKI": "F-Score 0..9 (crisis 방어/quality 종합, Piotroski 2000)",
            "MOHANRAM": "G-Score 신호율 (저BM growth 방어, Mohanram 2005)",
            "NETISSUE": "-Δlog(CapitalStock) YoY (Pontiff-Woodgate 2008; IN04 직교 proxy)",
        },
        "added_feature_cols": [c for c in new_feat if c not in base_feat],
        "coverage_on_base_rows": cov,
        "panel_rows": int(len(out)),
        "n_months": int(out["ym"].nunique()),
        "month_range": [str(out["ym"].min()), str(out["ym"].max())],
        "lockbox": "2023-12-22",
        "pit_note": "신규 score=month-end signal(t-known, forward-1M predict, 90f 동일 semantics). "
                    "__lvl=단면z, __slp=backward 1-lag Δ(past-only). label(Ret_1m forward)=base 유지. "
                    "merge=ym,Ticker left. R dpl_c2_pit_audit forward-recompute + concurrent-lookahead PASS 의무.",
        "baseline_ref": "stage_artifacts/WT_DPL_GPU_SWEEP/ (90f) + WT_DPL_C1 (92f residmom)",
        "out_panel": out_panel,
    }
    with open(os.path.join(OUT_DIR, "feature_panel_meta.json"), "w", encoding="utf-8") as fpo:
        json.dump(meta, fpo, indent=2, ensure_ascii=False)
    print(f"[c2-aug] panel -> {out_panel}")
    print(f"[c2-aug] meta  -> {os.path.join(OUT_DIR, 'feature_panel_meta.json')}")


if __name__ == "__main__":
    main()
