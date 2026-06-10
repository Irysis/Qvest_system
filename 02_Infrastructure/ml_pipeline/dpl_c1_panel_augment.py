#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_c1_panel_augment.py — Qvest cycle1: 90f baseline panel + residual-momentum 직교 피처.

목적: 기존 검증된 90f DPL feature panel(stage_artifacts/WT_DPL_GPU_SWEEP/dpl_feature_panel.parquet)에
  WT-D20260606_001 residual-momentum(M08+M14, R05 return_cor -0.061) alpha_score 패널을
  PIT-정합 month-key merge로 추가 → 92f. (factor DB 재빌드 불요 — alpha_scores는 이미
  canonical-screen PIT 산출물. measurement-graduation §5: 실패 standalone 알파 = DPL 피처.)

추가 피처 2종:
  RESIDMOM__lvl : month-end residual-mom alpha_score (cross-section z 재표준화, 단면 PIT)
  RESIDMOM__slp : 직전월 대비 변화(Δ, 보유 1-lag) — 모멘텀 가속/감속 신호(backward only)
  (__vol 미부여 — 월간 단일 signal에 spurious rolling vol 회피. naming은 sweep feat_cols 규약 endswith.)

PIT:
  - residmom alpha_score는 month-end signal(t에서 알 수 있는 값, t→t+1 예측). 기존 90f와 동일 semantics.
  - __slp = score(t) - score(t-1) = backward diff(과거 정보만). forward 없음.
  - merge는 ym(year-month) inner — label(Ret_1m=forward)은 기존 panel 것 유지(재계산 안 함).
  - 결측 종목 z=0(중립) 대체 — alpha coverage 차이 허용(ortho builder와 동일 정책).

출력: stage_artifacts/WT_DPL_C1/dpl_feature_panel.parquet (92f) + benchmark_monthly(복사) + meta.
실행: G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe \
        02_Infrastructure/ml_pipeline/dpl_c1_panel_augment.py
"""
import os
import json
import numpy as np
import pandas as pd

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
SRC_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_C1")
os.makedirs(OUT_DIR, exist_ok=True)

BASE_PANEL = os.path.join(SRC_DIR, "dpl_feature_panel.parquet")
BASE_BENCH = os.path.join(SRC_DIR, "benchmark_monthly.parquet")
BASE_REGIME = os.path.join(SRC_DIR, "regime_monthly.parquet")
RESIDMOM = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_WT-D20260606_001", "alpha_scores.parquet")


def main():
    print("[c1-aug] loading base 90f panel ...")
    panel = pd.read_parquet(BASE_PANEL)
    panel["ym"] = panel["ym"].astype(str)
    base_feat = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    print(f"[c1-aug] base panel rows={len(panel):,} feats={len(base_feat)} months={panel['ym'].nunique()}")

    print("[c1-aug] loading residual-mom alpha_scores (WT-D20260606_001) ...")
    rm = pd.read_parquet(RESIDMOM)
    rm["Date"] = pd.to_datetime(rm["Date"])
    rm["ym"] = rm["Date"].dt.to_period("M").astype(str)
    col = "alpha_score"
    # cross-section z per month (PIT: same-month cross-section only)
    rm["RESIDMOM__lvl"] = rm.groupby("ym")[col].transform(
        lambda s: (s - s.mean()) / (s.std(ddof=0) + 1e-9))
    # backward 1-lag delta per ticker (momentum accel; past-only)
    rm = rm.sort_values(["Ticker", "ym"])
    rm["_lvl_prev"] = rm.groupby("Ticker")["RESIDMOM__lvl"].shift(1)
    rm["RESIDMOM__slp"] = (rm["RESIDMOM__lvl"] - rm["_lvl_prev"]).fillna(0.0)
    rm_feat = rm[["ym", "Ticker", "RESIDMOM__lvl", "RESIDMOM__slp"]]

    # merge (left on base panel — keep base universe + label intact; residmom missing -> z=0)
    out = panel.merge(rm_feat, on=["ym", "Ticker"], how="left")
    for c in ["RESIDMOM__lvl", "RESIDMOM__slp"]:
        out[c] = out[c].fillna(0.0)
    new_feat = base_feat + ["RESIDMOM__lvl", "RESIDMOM__slp"]
    rm_cov = (out["RESIDMOM__lvl"] != 0).mean()
    print(f"[c1-aug] augmented panel feats={len(new_feat)} (residmom coverage on base rows={rm_cov:.2%})")

    out_panel = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
    out.to_parquet(out_panel, index=False)
    # copy benchmark + regime for self-contained WT dir
    pd.read_parquet(BASE_BENCH).to_parquet(os.path.join(OUT_DIR, "benchmark_monthly.parquet"), index=False)
    if os.path.exists(BASE_REGIME):
        pd.read_parquet(BASE_REGIME).to_parquet(os.path.join(OUT_DIR, "regime_monthly.parquet"), index=False)

    meta = {
        "variant": "c1 — 90f baseline + residual-momentum (RESIDMOM lvl/slp) = 92f",
        "n_feature_cols": len(new_feat),
        "base_feature_cols": len(base_feat),
        "added": ["RESIDMOM__lvl (month-end residual-mom alpha z)",
                  "RESIDMOM__slp (backward 1-lag delta)"],
        "residmom_source": RESIDMOM,
        "residmom_alpha_pkg": "qepm/mailbox/worktask/WT-D20260606_001/alpha_package.json",
        "residmom_return_cor_vs_R05": -0.061,
        "residmom_coverage_on_base_rows": float(rm_cov),
        "panel_rows": int(len(out)),
        "n_months": int(out["ym"].nunique()),
        "month_range": [str(out["ym"].min()), str(out["ym"].max())],
        "lockbox": "2023-12-22",
        "pit_note": "residmom alpha_score = month-end signal (t-known, forward-1M predict, 기존 90f 동일 semantics). "
                    "__slp = backward diff(past-only). label(Ret_1m forward) = base panel 것 유지. "
                    "merge=ym inner. R dpl_c1_pit_audit forward-recompute + bear_date PASS 의무.",
        "baseline_ref": "stage_artifacts/WT_DPL_GPU_SWEEP/ (90f, apples-to-apples)",
        "out_panel": out_panel,
    }
    with open(os.path.join(OUT_DIR, "feature_panel_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f"[c1-aug] panel -> {out_panel}")
    print(f"[c1-aug] meta  -> {os.path.join(OUT_DIR, 'feature_panel_meta.json')}")


if __name__ == "__main__":
    main()
