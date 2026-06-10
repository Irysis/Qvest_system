#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_ortho_feature_builder.py — Qvest v8.x: DPL feature panel + this-cycle 직교 알파 factor 추가.

목적 (measurement-graduation §5 — "실패한 standalone 알파 = DPL 입력 피처"):
  자동진행 직교 슬리브 사냥(alpha-search)에서 long-short로 검증된 직교 알파들 —
    value(BM) (LS Carhart4 t=3.28, OOS retention +0.41 — 유일 강+OOS-robust 직교원),
    earnings-revision consensus (LS t=3.61 IS최강; standalone OOS는 붕괴),
    reversal (LS t=2.76, OOS유지) —
  은 long-only standalone에서 시장베타에 가려 전부 grade F. §5대로 폐기 않고 DPL 피처로 추가.
  DPL이 net Sharpe 직접최적화로 비선형 결합(standalone OOS 붕괴를 극복하는지 측정).

핵심 정합 (project-orthogonal-sleeve-hunt 메모리):
  - "value(BM)는 OOS-robust 직교원이나 STR_1715엔 부재" + 기존 90f 패널은 V02_EP/V12_Composite_Value/
    V14_EBIT_EV(EV·earnings 기반 value)만 있고 **순수 book-to-market V01_BM은 부재** → 추가의 핵심.
  - earnings-revision은 기존 C01_SUE/C02_EPS_Chg_1m 보다 풍부한 revision-breadth 추가.
  - reversal은 기존 M11_ST_Reversal(단기) 외 장기/intensity 추가.

추가 factor (기존 90f → 102f, 34 factor × 3 stat):
  value:     + V01_BM                  (순수 BM; 직교 value 축, dir=higher_better, coverage 88~99%)
  consensus: + C13_Revision_Breadth_3m (earnings-revision breadth, coverage ~99%)
  momentum:  + M12_LR_Reversal         (장기 reversal, coverage 56~81%)
  liquidity: + L35_Reversal_Intensity  (reversal intensity, coverage ~95%)
  (sparse한 C19/SE02/M27 analyst-consensus는 KR coverage 26~38% → 결측 z=0 noise 회피 위해 제외.)

NOTE: dir=lower_better factor(M11/M12 reversal)도 raw level-z로 넣고 MLP가 sign 학습(end-to-end
  DPL은 fixed-sign screen 아님 — 부호 정렬 불요). PIT는 원 builder와 동일(backward rolling/forward label).

출력: stage_artifacts/WT_DPL_ORTHO/  (기존 WT_DPL_GPU_SWEEP 90f baseline 비손상 — apples-to-apples 별도).
실행: cd <root> && G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe \
        02_Infrastructure/ml_pipeline/dpl_ortho_feature_builder.py
"""
import os
import sys
import json

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, THIS_DIR)
import dpl_feature_builder as fb  # noqa: E402  (build_features / build_labels_and_universe 재사용)

# ── 직교 factor 추가 (기존 SELECTED_FACTORS 카테고리에 append) ──────────────
# 기존 dict를 deepcopy해 수정 (원 모듈 전역 오염 방지하되, build_features는 모듈전역 참조라
# fb.SELECTED_FACTORS 자체를 교체해야 반영됨 → 명시적 교체 + meta에 변경 기록).
import copy
ORIG = copy.deepcopy(fb.SELECTED_FACTORS)
ADDED = {
    "value":     ["V01_BM"],
    "consensus": ["C13_Revision_Breadth_3m"],
    "momentum":  ["M12_LR_Reversal"],
    "liquidity": ["L35_Reversal_Intensity"],
}
NEW = copy.deepcopy(ORIG)
for cat, fs in ADDED.items():
    NEW.setdefault(cat, [])
    for f in fs:
        if f not in NEW[cat]:
            NEW[cat].append(f)

# 원 모듈 전역 + 출력 디렉토리 교체 (build_features/build_labels_and_universe가 모듈전역 사용)
fb.SELECTED_FACTORS = NEW
OUT_DIR = os.path.join(fb.PROJECT_ROOT, "stage_artifacts", "WT_DPL_ORTHO")
os.makedirs(OUT_DIR, exist_ok=True)
fb.OUT_DIR = OUT_DIR


def main():
    print("[ortho-feat] building rolling features (90f baseline + 4 직교 factor = 102f) ...")
    print(f"[ortho-feat] ADDED: {ADDED}")
    snap, feat_cols = fb.build_features()
    print("[ortho-feat] building forward labels + universe ...")
    labels, bm_m = fb.build_labels_and_universe()

    import pandas as pd
    panel = snap.merge(labels, on=["ym", "Ticker"], how="inner")
    panel = panel[(panel["adv"].isna()) | (panel["adv"] >= fb.LIQ_MIN)].copy()

    out_panel = os.path.join(OUT_DIR, "dpl_feature_panel.parquet")
    panel["date"] = panel["ym"].dt.to_timestamp("M")
    panel.to_parquet(out_panel, index=False)
    bm_path = os.path.join(OUT_DIR, "benchmark_monthly.parquet")
    bm_m["date"] = bm_m["ym"].dt.to_timestamp("M")
    bm_m.to_parquet(bm_path, index=False)

    meta = {
        "variant": "ortho — 90f baseline + 4 직교 알파 factor (value BM / earnings-rev breadth / reversal LR / reversal intensity)",
        "n_feature_cols": len(feat_cols),
        "feature_cols": feat_cols,
        "n_selected_factors": sum(len(v) for v in NEW.values()),
        "added_factors": ADDED,
        "added_rationale": {
            "V01_BM": "순수 book-to-market — 직교 슬리브 사냥서 유일 강(LS t3.28)+OOS-robust(+0.41) 직교 value축. 기존 90f엔 부재(EV/earnings value만).",
            "C13_Revision_Breadth_3m": "earnings-revision breadth — STR_1715 고SR 알파원(earnings-rev) 보강. standalone OOS는 붕괴(착시)이나 §5대로 DPL 피처.",
            "M12_LR_Reversal": "장기 reversal — 기존 M11 단기 reversal 보완. reversal LS OOS 유지(turnover↑).",
            "L35_Reversal_Intensity": "reversal intensity (liquidity 계열) — reversal 신호 강도 축.",
        },
        "excluded_sparse": {
            "C19_Composite_Earnings": "KR coverage 26~34% — 결측 z=0 noise",
            "SE02_Consensus_Revision": "coverage 26~38%",
            "M27_Analyst_Rev_Mom": "coverage 26~38%",
        },
        "panel_rows": int(len(panel)),
        "n_months": int(panel["ym"].nunique()),
        "month_range": [str(panel["ym"].min()), str(panel["ym"].max())],
        "lockbox": str(fb.LOCKBOX.date()),
        "liq_min": fb.LIQ_MIN,
        "universe": "KOSPI200 ∪ KOSDAQ150 (K200|KQ150 flag, month-end)",
        "pit_note": "rolling features backward-only; label=forward 1M (shift(-1)); "
                    "R dpl_pit_audit(bear_date + forward recompute) PASS 의무.",
        "baseline_panel_ref": "stage_artifacts/WT_DPL_GPU_SWEEP/dpl_feature_panel.parquet (90f, apples-to-apples 비교군)",
        "out_panel": out_panel,
        "out_benchmark": bm_path,
    }
    with open(os.path.join(OUT_DIR, "feature_panel_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f"[ortho-feat] panel -> {out_panel}  rows={len(panel):,}  feats={len(feat_cols)}  "
          f"months={panel['ym'].nunique()}")
    print(f"[ortho-feat] meta -> {os.path.join(OUT_DIR, 'feature_panel_meta.json')}")


if __name__ == "__main__":
    main()
