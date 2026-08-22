"""WT-D20260813_001 — q90 상방 분위 표적 예측기 + 절사평균(trim5%) 음성 대조 arm 스코어 산출.

가설(alpha_hypothesis.json 승계, 재작성 금지): long-only top-25 EW 는 보유 종목의 **평균**을 벌고
그 평균은 소수 종목의 상방 점프가 지배하므로, 조건부 **q90**(상방 분위)을 표적으로 학습한
예측기가 top-N 소비 형태와 정합적이다.

★역할 경계 (python-policy §4): 여기서는 **스코어까지만** 낸다.
  포트폴리오 수익률 구성/성과는 R canonical_screen_bt() 가 한다 — 손계산 금지.

★고정 사양 (arm A/B 와 완전 동일 — HPO 금지, 표적만 교체):
  - 동일 패널 lane_a_feature_panel.parquet · 피처 324종(alias 7종 드롭) · burn-in 60 · 확장창
  - 결측은 월내 횡단면 중앙값 대체 → 잔여 0 대체
  - q90: LightGBM objective="quantile", alpha=0.90, arm B 와 **동일한 사전 고정 파라미터**
  - trim5: XGBoost, arm A 와 **동일한 사전 고정 파라미터**, 표적만 절사평균(월내 횡단면 양측 5% trim)

실행: cd <ROOT> && .venv_qvest_ml/Scripts/python.exe stage_artifacts/WT-D20260813_001/run_q90_model.py
"""
import json, time
import numpy as np
import pandas as pd
import lightgbm as lgb
import xgboost as xgb

SRC = "stage_artifacts/fq233_probe0_20260813"
OUT = "stage_artifacts/WT-D20260813_001"
PANEL = f"{SRC}/lane_a_feature_panel.parquet"

# arm A/B 사전등록 §1: 중복 확정 alias 7종 드롭 (cor>0.999 실측분만) — 동일 목록
DROP_ALIAS = ["V19_Debt_to_Market", "M25_Earnings_Mom_Streak", "M29_Mom_5d",
              "C10_SUE_Persistence", "C13_Revision_Breadth_3m",
              "R12_Idiosyncratic_Risk", "CR04_Ownership_Concentration"]

# arm B 와 동일한 사전 고정 LightGBM 파라미터 (q90 pinball)
LGB_PARAMS = dict(objective="quantile", n_estimators=300, learning_rate=0.05, num_leaves=15,
                  min_child_samples=50, subsample=0.8, subsample_freq=1, colsample_bytree=0.8,
                  reg_lambda=1.0, random_state=0, n_jobs=-1, verbose=-1)
Q90_ALPHA = 0.90

# arm A 와 동일한 사전 고정 XGBoost 파라미터 (절사평균 표적 = 음성 대조)
XGB_PARAMS = dict(n_estimators=300, max_depth=4, learning_rate=0.05, subsample=0.8,
                  colsample_bytree=0.8, min_child_weight=10, reg_lambda=1.0,
                  random_state=0, n_jobs=-1, tree_method="hist")
TRIM_FRAC = 0.05     # 양측 5% 절사평균

BURN_IN = 60
META = ["anchor", "sig_date", "Ticker", "fwd_ret_1m"]


def trimmed_target(pan, feats):
    """월내 횡단면 양측 5% 절사 후 종목별 표적 = (원 fwd_ret - 그 달 절사평균) 로 중심화하지 않는다.
    표적 자체는 원 fwd_ret_1m 을 유지하되 **훈련 표본에서 각 달의 양측 극단 5% 를 제외**하여
    '꼬리를 잘라낸 평균' 을 학습하게 한다 (arm A 는 전 표본 평균-제곱오차 = 꼬리 포함).
    → 기전이 참이면 꼬리를 잘라낸 이 대조는 arm A 대비 개선이 없어야 한다."""
    return pan  # 실제 절사는 fit 시점에 달별로 수행 (아래 main 참조)


def main():
    pan = pd.read_parquet(PANEL)
    pan["sig_date"] = pd.to_datetime(pan["sig_date"])
    feats = [c for c in pan.columns if c not in META and c not in DROP_ALIAS]
    assert len(feats) == 324, f"사전등록 324종과 불일치: {len(feats)}"
    print(f"패널 {len(pan):,}행 · 피처 {len(feats)}종 · {pan['sig_date'].nunique()}개월", flush=True)

    # 결측 대체 (arm A/B 동일 규율)
    g = pan.groupby("sig_date")[feats]
    pan[feats] = pan[feats].fillna(g.transform("median"))
    pan[feats] = pan[feats].fillna(0.0)

    months = np.sort(pan["sig_date"].unique())
    print(f"학습 시작 = {BURN_IN+1}번째 달 · 예측 대상 {len(months)-BURN_IN}개월", flush=True)

    rows_q90, rows_trim, t0 = [], [], time.time()
    for i in range(BURN_IN, len(months)):
        m = months[i]
        tr = pan[pan["sig_date"] < m]                 # ★확장창 · 미래 미포함 (PIT)
        te = pan[pan["sig_date"] == m]
        if len(te) == 0 or len(tr) < 1000:
            continue
        Xtr = tr[feats].to_numpy(np.float32)
        ytr = tr["fwd_ret_1m"].to_numpy(np.float32)
        Xte = te[feats].to_numpy(np.float32)

        # ── q90 primary — LightGBM pinball τ=0.9 (arm B 와 동일 파라미터·시드) ──────
        mq = lgb.LGBMRegressor(alpha=Q90_ALPHA, **LGB_PARAMS)
        mq.fit(Xtr, ytr)
        pq = mq.predict(Xte).astype(np.float64)
        rows_q90.append(pd.DataFrame({
            "Date": te["anchor"].values, "sig_date": te["sig_date"].values,
            "Ticker": te["Ticker"].values, "score": pq}))

        # ── trim5 음성 대조 — XGBoost, 훈련 표본에서 달별 양측 5% 절사 후 평균-제곱오차 ──
        tr2 = tr.copy()
        lo = tr2.groupby("sig_date")["fwd_ret_1m"].transform(lambda s: s.quantile(TRIM_FRAC))
        hi = tr2.groupby("sig_date")["fwd_ret_1m"].transform(lambda s: s.quantile(1 - TRIM_FRAC))
        keep = (tr2["fwd_ret_1m"] >= lo) & (tr2["fwd_ret_1m"] <= hi)
        Xtr_t = tr2.loc[keep, feats].to_numpy(np.float32)
        ytr_t = tr2.loc[keep, "fwd_ret_1m"].to_numpy(np.float32)
        mt = xgb.XGBRegressor(**XGB_PARAMS)
        mt.fit(Xtr_t, ytr_t)
        pt = mt.predict(Xte).astype(np.float64)
        rows_trim.append(pd.DataFrame({
            "Date": te["anchor"].values, "sig_date": te["sig_date"].values,
            "Ticker": te["Ticker"].values, "score": pt}))

        if (i - BURN_IN + 1) % 25 == 0:
            print(f"  {i-BURN_IN+1}/{len(months)-BURN_IN} ({(time.time()-t0)/60:.1f}분)", flush=True)

    sc_q90 = pd.concat(rows_q90, ignore_index=True)
    sc_trim = pd.concat(rows_trim, ignore_index=True)
    fp_q90 = f"{OUT}/q90_model_scores.parquet"
    fp_trim = f"{OUT}/trim5_control_scores.parquet"
    sc_q90.to_parquet(fp_q90, index=False)
    sc_trim.to_parquet(fp_trim, index=False)
    print(f"\nq90 스코어 저장: {fp_q90} — {len(sc_q90):,}행 · {sc_q90['sig_date'].nunique()}개월", flush=True)
    print(f"trim5 스코어 저장: {fp_trim} — {len(sc_trim):,}행", flush=True)

    # 진단만(성과 아님): 월별 rank-IC
    def diag_ic(sc, tag):
        j = sc.merge(pan[["sig_date", "Ticker", "fwd_ret_1m"]], on=["sig_date", "Ticker"], how="left")
        j = j.dropna(subset=["fwd_ret_1m"])
        ic = j.groupby("sig_date").apply(
            lambda d: d["score"].corr(d["fwd_ret_1m"], method="spearman"),
            include_groups=False).dropna()
        n = len(ic); mu = float(ic.mean()); sd = float(ic.std(ddof=1))
        icir = mu/sd if sd else None
        print(f"  diag {tag}: rank-IC {mu:+.4f} · ICIR {(icir if icir else float('nan')):+.3f} · n={n}", flush=True)
        return {"rank_ic_mean": mu, "icir": icir, "n_months": n}

    diag = {"q90": diag_ic(sc_q90, "q90"), "trim5": diag_ic(sc_trim, "trim5")}

    # arm B q90 secondary 와 parity 확인 (동일 파라미터·시드이므로 일치해야 함)
    try:
        armB = pd.read_parquet(f"{SRC}/armB_scores.parquet")[["sig_date", "Ticker", "q90"]]
        armB["sig_date"] = pd.to_datetime(armB["sig_date"])
        chk = sc_q90.merge(armB, on=["sig_date", "Ticker"], how="inner")
        parity = float(np.corrcoef(chk["score"], chk["q90"])[0, 1])
        maxdiff = float((chk["score"] - chk["q90"]).abs().max())
        print(f"  arm B q90 parity: cor={parity:.6f} · max|Δ|={maxdiff:.6g} · n={len(chk)}", flush=True)
    except Exception as e:
        parity, maxdiff = None, None
        print(f"  arm B parity 확인 실패: {e}", flush=True)

    json.dump({"round_id": "WT-D20260813_001_Q90", "prereg": "PREREG_q90_20260822.md",
               "primary_score": "q90_pinball_lgbm", "negative_control": "trim5_xgb",
               "n_features": len(feats), "dropped_alias": DROP_ALIAS,
               "lgb_params": LGB_PARAMS, "xgb_params": XGB_PARAMS,
               "q90_alpha": Q90_ALPHA, "trim_frac": TRIM_FRAC, "burn_in_months": BURN_IN,
               "n_pred_months_q90": int(sc_q90["sig_date"].nunique()),
               "n_scores_q90": int(len(sc_q90)), "diag": diag,
               "armB_q90_parity_cor": parity, "armB_q90_parity_maxdiff": maxdiff,
               "note": "스코어 산출까지만. 성과·판정은 R canonical_screen_bt 경유(python-policy §4)."},
              open(f"{OUT}/q90_score_meta.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("메타 저장 완료", flush=True)


if __name__ == "__main__":
    main()
