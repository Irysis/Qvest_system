"""arm A — 평균-표적 XGBoost 워크포워드 스코어 산출 (FQ233_ARMA_20260813)

사전등록 = PREREG_armA_20260813.md (측정 전 고정). 이 파일은 그 사양의 구현이며 사양을 바꾸지 않는다.

★역할 경계 (python-policy §4): 여기서는 **스코어까지만** 낸다.
  포트폴리오 수익률 구성/성과는 R `canonical_screen_bt()` 가 한다 — 손계산 금지.

실행: cd <ROOT> && .venv_qvest_ml/Scripts/python.exe stage_artifacts/fq233_probe0_20260813/armA_score.py
"""
import json, time
import numpy as np
import pandas as pd
import xgboost as xgb

OUT = "stage_artifacts/fq233_probe0_20260813"
PANEL = f"{OUT}/lane_a_feature_panel.parquet"

# ── 사전등록 §1: 중복 확정 alias 7종 드롭 (cor>0.999 실측분만) ──────────────
DROP_ALIAS = ["V19_Debt_to_Market", "M25_Earnings_Mom_Streak", "M29_Mom_5d",
              "C10_SUE_Persistence", "C13_Revision_Breadth_3m",
              "R12_Idiosyncratic_Risk", "CR04_Ownership_Concentration"]
# ── 사전등록 §2: 하이퍼파라미터 사전 고정 · HPO 없음 ────────────────────────
PARAMS = dict(n_estimators=300, max_depth=4, learning_rate=0.05, subsample=0.8,
              colsample_bytree=0.8, min_child_weight=10, reg_lambda=1.0,
              random_state=0, n_jobs=-1, tree_method="hist")
BURN_IN = 60
META = ["anchor", "sig_date", "Ticker", "fwd_ret_1m"]

def main():
    pan = pd.read_parquet(PANEL)
    pan["sig_date"] = pd.to_datetime(pan["sig_date"])
    feats = [c for c in pan.columns if c not in META and c not in DROP_ALIAS]
    print(f"패널 {len(pan):,}행 · 피처 {len(feats)}종 (드롭 {len(DROP_ALIAS)}) · "
          f"{pan['sig_date'].nunique()}개월", flush=True)
    assert len(feats) == 324, f"사전등록 피처 324종과 불일치: {len(feats)}"

    months = np.sort(pan["sig_date"].unique())
    print(f"학습 시작 = {BURN_IN+1}번째 달 ({pd.Timestamp(months[BURN_IN]).date()}) · "
          f"예측 대상 {len(months)-BURN_IN}개월", flush=True)

    # 월내 횡단면 중앙값 대체 (사전등록 §1 — 0 대체 금지)
    g = pan.groupby("sig_date")[feats]
    pan[feats] = pan[feats].fillna(g.transform("median"))
    pan[feats] = pan[feats].fillna(0.0)   # 그 달 전건 결측인 피처만 (중앙값도 NaN)

    rows, t0 = [], time.time()
    for i in range(BURN_IN, len(months)):
        m = months[i]
        tr = pan[pan["sig_date"] < m]                 # ★확장창 · 미래 미포함
        te = pan[pan["sig_date"] == m]
        if len(te) == 0 or len(tr) < 1000:
            continue
        model = xgb.XGBRegressor(**PARAMS)
        model.fit(tr[feats].to_numpy(np.float32), tr["fwd_ret_1m"].to_numpy(np.float32))
        pred = model.predict(te[feats].to_numpy(np.float32))
        rows.append(pd.DataFrame({
            "Date": te["anchor"].values,          # 보유월 앵커 = canonical_screen_bt 가 쓰는 축
            "sig_date": te["sig_date"].values,
            "Ticker": te["Ticker"].values,
            "score": pred.astype(np.float64),
        }))
        if (i - BURN_IN + 1) % 25 == 0:
            print(f"  {i-BURN_IN+1}/{len(months)-BURN_IN} ({(time.time()-t0)/60:.1f}분)", flush=True)

    sc = pd.concat(rows, ignore_index=True)
    fp = f"{OUT}/armA_scores.parquet"
    sc.to_parquet(fp, index=False)
    print(f"\n스코어 저장: {fp} — {len(sc):,}행 · {sc['sig_date'].nunique()}개월", flush=True)

    # 진단만(성과 아님): 스코어 vs 실현의 월별 rank-IC. ★포트 성과는 R 이 낸다.
    j = sc.merge(pan[["sig_date", "Ticker", "fwd_ret_1m"]], on=["sig_date", "Ticker"], how="left")
    ic = (j.dropna(subset=["fwd_ret_1m"])
            .groupby("sig_date")
            .apply(lambda d: d["score"].corr(d["fwd_ret_1m"], method="spearman"),
                   include_groups=False))
    ic = ic.dropna()
    n = len(ic); mu = float(ic.mean()); sd = float(ic.std(ddof=1))
    print(f"진단 rank-IC 평균 {mu:+.4f} · ICIR {mu/sd if sd else float('nan'):+.3f} · n={n}", flush=True)
    print("  ※이것은 진단이다. 판정 1급 결과량은 R canonical_screen_bt 의 net SR 이다.", flush=True)

    json.dump({"round_id": "FQ233_ARMA_20260813", "prereg": "PREREG_armA_20260813.md",
               "n_features": len(feats), "dropped_alias": DROP_ALIAS, "params": PARAMS,
               "burn_in_months": BURN_IN, "n_pred_months": int(sc["sig_date"].nunique()),
               "n_scores": int(len(sc)), "diag_rank_ic_mean": mu,
               "diag_icir": (mu/sd if sd else None), "diag_n_months": int(n),
               "note": "스코어 산출까지만. 성과는 R canonical_screen_bt 경유(python-policy §4)."},
              open(f"{OUT}/armA_score_meta.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("메타 저장 완료", flush=True)

if __name__ == "__main__":
    main()
