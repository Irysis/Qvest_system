"""604_h1_guard_calibrate.py — H1 입력 · 출력 점검 문턱을 자료에서 계산해 03_models/h1_guard_config.json 에 쓴다.

손으로 친 수치 없음 — 모든 문턱은 아래 자료 · 규칙에서 계산하고 근거를 함께 적는다.
  가격제한폭: 한국거래소 유가증권시장 업무규정 제20조 — 2015-06-15 부터 일간 ±30%. 지수는 구성 종목의 한계를 넘을 수 없으므로
             지수 일간 로그수익(%) ∈ [100·ln(0.7), 100·ln(1.3)].
  EWMA: J.P. Morgan/Reuters, RiskMetrics — Technical Document 4th ed.(1996) §5.3 · 일간 감쇠 λ = 0.94.
  W1 · W2 범위: 연구 워크포워드(04_Research/01_reports/k200_risk_accuracy_20261113/output/fc_DR_newsvk.parquet · fc_P3_replica.parquet)
             의 σ/EWMA · σ 전일 대비 최솟값 · 최댓값 — B7 이 잡는 자료 오류일(과 그 다음 날)은 범위 계산에서 뺀다.
  B7: |Δlog V-KOSPI200| 의 99.9% 분위(전 이력) · 같은 날 |r| < 1 × EWMA σ(t−1).
  B3 배수 0.5 · 2.0: 역대 최저의 절반 · 역대 최고의 두 배 — 실제 수준 변화가 아니라 단위 · 열 착오(×100 · 다른 지수 값)만 잡는 관례 폭.
사용: .venv_qvest_ml/Scripts/python.exe scripts/604_h1_guard_calibrate.py [--out 03_models/h1_guard_config.json]
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
STUDY_OUT = PROJECT_ROOT / "04_Research" / "01_reports" / "k200_risk_accuracy_20261113" / "output"


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, str(p))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


G = _load("h1_guard", ROOT / "03_models" / "h1_guard.py")


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as fh:
        for ch in iter(lambda: fh.read(1 << 20), b""):
            h.update(ch)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "03_models" / "h1_guard_config.json"))
    args = ap.parse_args()
    lam = 0.94
    bm_p = PROJECT_ROOT / ".cache" / "benchmark.parquet"; ix_p = PROJECT_ROOT / ".cache" / "indices.parquet"
    b = G.bench_frame(pd.read_parquet(bm_p), lam)
    ix = pd.read_parquet(ix_p, columns=["Date", "kospi200_vol"]); ix["Date"] = pd.to_datetime(ix["Date"])
    v = b.merge(ix, on="Date", how="inner").dropna(subset=["kospi200_vol"]).reset_index(drop=True)
    v["dl"] = np.log(v["kospi200_vol"]).diff()
    q999 = float(v["dl"].abs().quantile(0.999))
    k = 1.0
    hits = v[(v["dl"].abs() > q999) & (v["r"].abs() < k * v["ewma_prev"])]["Date"]
    hit_set = set(hits)
    nxt = {d: n for d, n in zip(b["Date"], b["Date"].shift(-1))}
    excl = hit_set | {nxt[d] for d in hit_set if pd.notna(nxt.get(d))}

    def band(fc_path, exclude):
        fc = pd.read_parquet(fc_path, columns=["Date", "sigma"]); fc["Date"] = pd.to_datetime(fc["Date"])
        j = fc.merge(b[["Date", "ewma"]], on="Date", how="left")
        j["ratio"] = j["sigma"] / j["ewma"]; j["dod"] = j["sigma"] / j["sigma"].shift(1)
        jj = j[~j["Date"].isin(exclude)]
        return {"lo": float(jj["ratio"].min()), "hi": float(jj["ratio"].max()),
                "lo_date": str(jj.loc[jj["ratio"].idxmin(), "Date"].date()), "hi_date": str(jj.loc[jj["ratio"].idxmax(), "Date"].date()),
                "n": int(len(jj)), "first": str(jj["Date"].min().date()), "last": str(jj["Date"].max().date())}, \
               {"lo": float(jj["dod"].min()), "hi": float(jj["dod"].max()),
                "lo_date": str(jj.loc[jj["dod"].idxmin(), "Date"].date()), "hi_date": str(jj.loc[jj["dod"].idxmax(), "Date"].date())}

    h1_ratio, h1_dod = band(STUDY_OUT / "fc_DR_newsvk.parquet", excl)
    p3_ratio, _ = band(STUDY_OUT / "fc_P3_replica.parquet", set())
    vk_hist = v["kospi200_vol"]
    cfg = {
        "version": "h1_guard_v1",
        "decision": "K200-RISK-H1-REPLACE-P3-20261114",
        "made_at": datetime.now().isoformat(timespec="seconds"),
        "made_by": "04_Research/decision_framework/bearish_forecast_v3/scripts/604_h1_guard_calibrate.py",
        "inputs": {"benchmark_md5": md5(bm_p), "benchmark_max_date": str(b["Date"].max().date()),
                   "indices_md5": md5(ix_p), "fc_DR_newsvk_md5": md5(STUDY_OUT / "fc_DR_newsvk.parquet"),
                   "fc_P3_replica_md5": md5(STUDY_OUT / "fc_P3_replica.parquet")},
        "price_limit": {"down_log_pct": 100.0 * math.log(0.7), "up_log_pct": 100.0 * math.log(1.3),
                        "basis": "한국거래소 유가증권시장 업무규정 제20조 · 2015-06-15 가격제한폭 ±30% — 지수 일간 로그수익(%) 물리 한계 = 100·ln(0.7) · 100·ln(1.3)"},
        "ewma_lambda": lam,
        "ewma_basis": "J.P. Morgan/Reuters RiskMetrics Technical Document 4th ed.(1996) §5.3 — 일간 λ = 0.94 · 초깃값 = 처음 60개 수익 분산",
        "w1_ratio_ewma": {**h1_ratio, "basis": "H1 워크포워드 σ/EWMA 최솟값 · 최댓값(B7 자료 오류일 · 다음 날 제외)"},
        "w2_day_over_day": {**h1_dod, "basis": "H1 워크포워드 σ 전일 대비 비 최솟값 · 최댓값(B7 자료 오류일 · 다음 날 제외)"},
        "p3_w1_ratio_ewma": {**p3_ratio, "basis": "P3 재현 워크포워드 σ/EWMA 최솟값 · 최댓값(대체 발송 시 경고 표시용)"},
        "w3_extrapolation": {"show_if_abs_effect_ge": 0.10,
                             "basis": "외삽 경고는 늘 기록하고, 범위 밖 부분이 σ 를 10% 이상 바꿀 때만 브리핑에 표시(표시 관례 폭 — 작은 외삽 반복 표시는 경고를 무디게 한다)"},
        "b3_vk_range": {"lo_factor": 0.5, "hi_factor": 2.0,
                        "hist_min": float(vk_hist.min()), "hist_min_date": str(v.loc[vk_hist.idxmin(), "Date"].date()),
                        "hist_max": float(vk_hist.max()), "hist_max_date": str(v.loc[vk_hist.idxmax(), "Date"].date()),
                        "basis": "실행 때 그날 이전 이력의 최저 × 0.5 · 최고 × 2.0 — 단위 · 열 착오만 잡는 관례 폭(수준 변화는 막지 않는다)"},
        "b7_vk_jump": {"abs_dlog": q999, "index_move_k": k,
                       "history_hits": [str(d.date()) for d in sorted(hit_set)], "history_days": int(len(v)),
                       "basis": "|Δlog V-KOSPI200| 99.9% 분위(전 이력) 초과 ∧ 같은 날 |r| < 1 × EWMA σ(t−1) — 하루 튀고 되돌아온 자료 오류 형태"},
    }
    out = Path(args.out); tmp = out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8"); os.replace(tmp, out)
    print(json.dumps({k_: cfg[k_] for k_ in ("w1_ratio_ewma", "w2_day_over_day", "p3_w1_ratio_ewma", "b7_vk_jump")}, ensure_ascii=False, indent=1))
    print(f"[saved] {out}")


if __name__ == "__main__":
    main()
