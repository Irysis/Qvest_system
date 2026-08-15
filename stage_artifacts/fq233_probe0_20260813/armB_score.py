"""arm B — 조건부 분위 표적 (LightGBM pinball) 워크포워드 스코어 (FQ233_ARMB_20260813)

사전등록 = PREREG_armB_20260813.md (측정 전 고정). primary = q50 단독.
★역할 경계: 스코어까지만. 성과는 R canonical_screen_bt (python-policy §4).
실행: cd <ROOT> && .venv_qvest_ml/Scripts/python.exe stage_artifacts/fq233_probe0_20260813/armB_score.py
"""
import json, time
import numpy as np
import pandas as pd
import lightgbm as lgb

OUT = "stage_artifacts/fq233_probe0_20260813"
PANEL = f"{OUT}/lane_a_feature_panel.parquet"
DROP_ALIAS = ["V19_Debt_to_Market", "M25_Earnings_Mom_Streak", "M29_Mom_5d",
              "C10_SUE_Persistence", "C13_Revision_Breadth_3m",
              "R12_Idiosyncratic_Risk", "CR04_Ownership_Concentration"]
# 사전등록 §2 — 사전 고정, HPO 없음
PARAMS = dict(objective="quantile", n_estimators=300, learning_rate=0.05, num_leaves=15,
              min_child_samples=50, subsample=0.8, subsample_freq=1, colsample_bytree=0.8,
              reg_lambda=1.0, random_state=0, n_jobs=-1, verbose=-1)
QUANTILES = [0.10, 0.50, 0.90]
BURN_IN = 60
META = ["anchor", "sig_date", "Ticker", "fwd_ret_1m"]

def main():
    pan = pd.read_parquet(PANEL)
    pan["sig_date"] = pd.to_datetime(pan["sig_date"])
    feats = [c for c in pan.columns if c not in META and c not in DROP_ALIAS]
    assert len(feats) == 324, f"사전등록 324종과 불일치: {len(feats)}"
    print(f"패널 {len(pan):,}행 · 피처 {len(feats)}종 · {pan['sig_date'].nunique()}개월", flush=True)

    g = pan.groupby("sig_date")[feats]
    pan[feats] = pan[feats].fillna(g.transform("median"))
    pan[feats] = pan[feats].fillna(0.0)

    months = np.sort(pan["sig_date"].unique())
    print(f"예측 대상 {len(months)-BURN_IN}개월 × 분위 {len(QUANTILES)}종", flush=True)

    rows, t0 = [], time.time()
    for i in range(BURN_IN, len(months)):
        m = months[i]
        tr = pan[pan["sig_date"] < m]
        te = pan[pan["sig_date"] == m]
        if len(te) == 0 or len(tr) < 1000:
            continue
        Xtr = tr[feats].to_numpy(np.float32); ytr = tr["fwd_ret_1m"].to_numpy(np.float32)
        Xte = te[feats].to_numpy(np.float32)
        out = {"Date": te["anchor"].values, "sig_date": te["sig_date"].values,
               "Ticker": te["Ticker"].values}
        for q in QUANTILES:
            mdl = lgb.LGBMRegressor(alpha=q, **PARAMS)
            mdl.fit(Xtr, ytr)
            out[f"q{int(q*100):02d}"] = mdl.predict(Xte).astype(np.float64)
        rows.append(pd.DataFrame(out))
        if (i - BURN_IN + 1) % 25 == 0:
            print(f"  {i-BURN_IN+1}/{len(months)-BURN_IN} ({(time.time()-t0)/60:.1f}분)", flush=True)

    sc = pd.concat(rows, ignore_index=True)
    sc["score"] = sc["q50"]                     # ★사전등록 §3: primary = q50 단독
    fp = f"{OUT}/armB_scores.parquet"
    sc.to_parquet(fp, index=False)
    print(f"\n스코어 저장: {fp} — {len(sc):,}행 · {sc['sig_date'].nunique()}개월", flush=True)

    # 분위 단조성 점검 (q10 <= q50 <= q90 위반율) — pinball 은 교차를 보장하지 않는다
    cross = float(((sc["q10"] > sc["q50"]) | (sc["q50"] > sc["q90"])).mean())
    print(f"분위 교차(비단조) 비율: {cross:.4f}", flush=True)

    j = sc.merge(pan[["sig_date", "Ticker", "fwd_ret_1m"]], on=["sig_date", "Ticker"], how="left")
    j = j.dropna(subset=["fwd_ret_1m"])
    diag = {}
    for c in ("q10", "q50", "q90"):
        ic = j.groupby("sig_date").apply(
            lambda d: d[c].corr(d["fwd_ret_1m"], method="spearman"), include_groups=False).dropna()
        diag[c] = {"rank_ic_mean": float(ic.mean()),
                   "icir": float(ic.mean()/ic.std(ddof=1)) if ic.std(ddof=1) else None,
                   "n_months": int(len(ic))}
        print(f"  diag {c}: rank-IC {diag[c]['rank_ic_mean']:+.4f} · ICIR {diag[c]['icir']:+.3f}", flush=True)
    print("  ※진단이다. 판정은 R 측 total net SR + arm A 대비 paired NW3 t.", flush=True)

    json.dump({"round_id": "FQ233_ARMB_20260813", "prereg": "PREREG_armB_20260813.md",
               "primary_score": "q50", "quantiles": QUANTILES, "n_features": len(feats),
               "params": {k: v for k, v in PARAMS.items()}, "burn_in_months": BURN_IN,
               "n_pred_months": int(sc["sig_date"].nunique()), "n_scores": int(len(sc)),
               "quantile_crossing_rate": cross, "diag": diag,
               "note": "스코어까지만. 성과·판정은 R 경유."},
              open(f"{OUT}/armB_score_meta.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("메타 저장 완료", flush=True)

if __name__ == "__main__":
    main()
