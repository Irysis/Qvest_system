"""arm C — 꼬리초과확률 표적 (LightGBM binary 2모델) 워크포워드 스코어 (FQ233_ARMC_20260820)

사전등록 = PREREG_armC_20260820.md (측정 전 고정). primary = P_up - P_dn (§2 ★).
★역할 경계: 스코어까지만. 성과는 R canonical_screen_bt (python-policy §4).
실행: cd <ROOT> && .venv_qvest_ml/Scripts/python.exe stage_artifacts/fq233_probe0_20260813/armC_score.py
"""
import json, time
import numpy as np
import pandas as pd
import lightgbm as lgb
import properscoring as ps

OUT = "stage_artifacts/fq233_probe0_20260813"
PANEL = f"{OUT}/lane_a_feature_panel.parquet"
DROP_ALIAS = ["V19_Debt_to_Market", "M25_Earnings_Mom_Streak", "M29_Mom_5d",
              "C10_SUE_Persistence", "C13_Revision_Breadth_3m",
              "R12_Idiosyncratic_Risk", "CR04_Ownership_Concentration"]
# 사전등록 §1/§2 — arm B 와 동일 고정, HPO 없음. objective 만 quantile → binary
PARAMS = dict(objective="binary", n_estimators=300, learning_rate=0.05, num_leaves=15,
              min_child_samples=50, subsample=0.8, subsample_freq=1, colsample_bytree=0.8,
              reg_lambda=1.0, random_state=0, n_jobs=-1, verbose=-1)
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

    # ── 사전등록 §2: 라벨 = 월내 횡단면 q10/q90 초과 여부 ────────────────────
    #   각 달의 분위는 **그 달의 횡단면만** 쓰고, 워크포워드는 학습월(<m)만 소비한다 → PIT 무결.
    gy = pan.groupby("sig_date")["fwd_ret_1m"]
    q90 = gy.transform(lambda s: s.quantile(0.90))
    q10 = gy.transform(lambda s: s.quantile(0.10))
    pan["y_up"] = (pan["fwd_ret_1m"] > q90).astype(np.int8)
    pan["y_dn"] = (pan["fwd_ret_1m"] < q10).astype(np.int8)
    print(f"라벨 양성비율 — y_up {pan['y_up'].mean():.4f} · y_dn {pan['y_dn'].mean():.4f}", flush=True)

    months = np.sort(pan["sig_date"].unique())
    print(f"예측 대상 {len(months)-BURN_IN}개월 × 모델 2종(up/dn)", flush=True)

    rows, t0 = [], time.time()
    for i in range(BURN_IN, len(months)):
        m = months[i]
        tr = pan[pan["sig_date"] < m]                 # ★확장창 · 미래 미포함
        te = pan[pan["sig_date"] == m]
        if len(te) == 0 or len(tr) < 1000:
            continue
        Xtr = tr[feats].to_numpy(np.float32)
        Xte = te[feats].to_numpy(np.float32)
        out = {"Date": te["anchor"].values, "sig_date": te["sig_date"].values,
               "Ticker": te["Ticker"].values}
        for lab, col in (("y_up", "p_up"), ("y_dn", "p_dn")):
            mdl = lgb.LGBMClassifier(**PARAMS)
            mdl.fit(Xtr, tr[lab].to_numpy(np.int8))
            out[col] = mdl.predict_proba(Xte)[:, 1].astype(np.float64)
        rows.append(pd.DataFrame(out))
        if (i - BURN_IN + 1) % 25 == 0:
            print(f"  {i-BURN_IN+1}/{len(months)-BURN_IN} ({(time.time()-t0)/60:.1f}분)", flush=True)

    sc = pd.concat(rows, ignore_index=True)
    sc["score"] = sc["p_up"] - sc["p_dn"]        # ★사전등록 §2: primary = 꼬리초과확률 스프레드
    fp = f"{OUT}/armC_scores.parquet"
    sc.to_parquet(fp, index=False)
    print(f"\n스코어 저장: {fp} — {len(sc):,}행 · {sc['sig_date'].nunique()}개월", flush=True)

    j = sc.merge(pan[["sig_date", "Ticker", "fwd_ret_1m"]], on=["sig_date", "Ticker"], how="left")
    j = j.dropna(subset=["fwd_ret_1m"])
    diag = {}
    for c in ("score", "p_up", "p_dn"):
        ic = j.groupby("sig_date").apply(
            lambda d: d[c].corr(d["fwd_ret_1m"], method="spearman"), include_groups=False).dropna()
        diag[c] = {"rank_ic_mean": float(ic.mean()),
                   "icir": float(ic.mean()/ic.std(ddof=1)) if ic.std(ddof=1) else None,
                   "n_months": int(len(ic))}
        print(f"  diag {c}: rank-IC {diag[c]['rank_ic_mean']:+.4f} · ICIR {diag[c]['icir']:+.3f}", flush=True)
    print("  ※진단이다. 판정은 R 측 total net SR + arm A 대비 paired NW3 t.", flush=True)

    # ── 사전등록 §3 secondary: Bowley 왜도 (arm B 예측에서 **추가 학습 0회** 파생) ──
    sec = {}
    bfp = f"{OUT}/armB_scores.parquet"
    try:
        b = pd.read_parquet(bfp)
        need = {"sig_date", "Ticker", "q10", "q50", "q90"}
        if not need.issubset(b.columns):
            sec["bowley"] = {"status": "unavailable",
                             "reason": f"armB_scores.parquet 에 분위 컬럼 부재: {sorted(need - set(b.columns))}"}
        else:
            b["sig_date"] = pd.to_datetime(b["sig_date"])
            den = b["q90"] - b["q10"]
            bow = np.where(np.abs(den) > 1e-12,
                           (b["q90"] + b["q10"] - 2 * b["q50"]) / den, np.nan)
            b["bowley"] = bow
            jb = b.merge(pan[["sig_date", "Ticker", "fwd_ret_1m"]],
                         on=["sig_date", "Ticker"], how="left").dropna(subset=["fwd_ret_1m", "bowley"])
            icb = jb.groupby("sig_date").apply(
                lambda d: d["bowley"].corr(d["fwd_ret_1m"], method="spearman"),
                include_groups=False).dropna()
            sec["bowley"] = {"status": "derived_from_armB_no_retrain",
                             "source": "armB_scores.parquet (종목-월 단위 q10/q50/q90 보존됨)",
                             "formula": "(q90+q10-2*q50)/(q90-q10)",
                             "n_rows": int(len(jb)),
                             "rank_ic_mean": float(icb.mean()),
                             "icir": float(icb.mean()/icb.std(ddof=1)) if icb.std(ddof=1) else None,
                             "n_months": int(len(icb)),
                             "note": "진단 rank-IC 만 기록 — 사전등록 §3 이 재학습·primary 교체를 금지."}
            print(f"  secondary Bowley: rank-IC {icb.mean():+.4f} · ICIR "
                  f"{icb.mean()/icb.std(ddof=1):+.3f} · n={len(icb)}", flush=True)

            # CRPS 진단 (arm B q10/50/90 예측 대비 실현) — 3점 근사임을 명시
            obs = jb["fwd_ret_1m"].to_numpy(np.float64)
            ens = jb[["q10", "q50", "q90"]].to_numpy(np.float64)
            crps = float(np.mean(ps.crps_ensemble(obs, ens)))
            pin = float(np.mean([np.mean(np.maximum(q*(obs-jb[c].to_numpy()),
                                                    (q-1)*(obs-jb[c].to_numpy())))
                                 for q, c in ((0.10, "q10"), (0.50, "q50"), (0.90, "q90"))]))
            sec["crps_diag"] = {"crps_ensemble_3point": crps, "mean_pinball_3q": pin,
                                "n_rows": int(len(jb)),
                                "caveat": "★3개 분위만으로 만든 **3점 앙상블 근사** CRPS — 연속 분포 CRPS 가 아니다. "
                                          "arm 간 비교가 아니라 arm B 예측의 채점 진단."}
            print(f"  secondary CRPS(3점 앙상블 근사) {crps:.6f} · 평균 pinball {pin:.6f}", flush=True)
    except FileNotFoundError:
        sec["bowley"] = {"status": "unavailable", "reason": f"{bfp} 부재 — 재학습 금지(사전등록 §3)"}

    json.dump({"round_id": "FQ233_ARMC_20260820", "prereg": "PREREG_armC_20260820.md",
               "primary_score": "p_up - p_dn", "label": {"y_up": "1[y > q90_cs(month)]",
                                                          "y_dn": "1[y < q10_cs(month)]"},
               "label_pos_rate": {"y_up": float(pan["y_up"].mean()), "y_dn": float(pan["y_dn"].mean())},
               "n_features": len(feats), "dropped_alias": DROP_ALIAS,
               "params": {k: v for k, v in PARAMS.items()}, "burn_in_months": BURN_IN,
               "n_pred_months": int(sc["sig_date"].nunique()), "n_scores": int(len(sc)),
               "diag": diag, "secondary": sec,
               "note": "스코어까지만. 성과·판정은 R 경유."},
              open(f"{OUT}/armC_score_meta.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("메타 저장 완료", flush=True)


if __name__ == "__main__":
    main()
