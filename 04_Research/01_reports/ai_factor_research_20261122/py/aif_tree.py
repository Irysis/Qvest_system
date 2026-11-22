"""aif_tree.py — 단계 3 생성기 ④-1: 예측 모형 결합 2판 · 트리 AutoML 팔.

특성에서 미래 수익 순위를 맞히는 함수를 학습하고, 그 예측값을 팩터로 쓴다(승인 계획 '머신러닝 방법론').
  입력   = 기본 특성 집합의 그 달 멤버 안 순위(원자료 변환 335 + 기존 팩터 282 · 결측 = 0) + 결측 비율 1열 + 시장 · 거시 상태 변수 23개(재학습 시점까지의 평균 · 표준편차로 표준화)
  표적   = 1m: 다음 1개월 수익의 횡단면 순위 · 12m: 향후 12개월 수익의 횡단면 순위(같은 달 안에서는 KOSPI200 을 빼도 순위가 같다)
  모형   = FLAML 이 선형(sgd) · 랜덤 포레스트 · 엑스트라 트리 · LightGBM · XGBoost 에서 계열과 설정을 재학습마다 60회 시행으로 탐색 →
           계열별 최선을 검증 예측으로 가중 결합(Caruana) → 학습 창 전체로 다시 적합. 탐색 · 결합 · 재적합 함수는 같은 연구 줄기의 nlff_automl 을 그대로 쓴다.
  고르는 지표 = 시간순 검증 구간(표본 달의 마지막 20%)의 월별 순위 IC
  재학습 = 매년 12월 신호일 · 확장 창 · 표적이 재학습일 한 달 전까지 실현된 표본만 · 표본은 1m = 매달, 12m = 분기 말 달
산출: factors/TREE_1M.parquet · TREE_12M.parquet(다음 12달의 예측값) · 재학습마다 고른 모형 · 가중 · 중요 특성 기록.
실행: python py/aif_tree.py [--target 1m|12m|both] [--force]   ((표적, 해) 하나 = 체크포인트 하나)
"""
import argparse
import os
import sys
import time

import numpy as np

import aif_common as ac
from aif_enumerate import Compact
from aif_fboost import load_features
from aif_features import FeatureStore

VERSION = 1
ESTIMATORS = ["lgbm", "xgboost", "rf", "extra_tree", "sgd"]     # 승인 계획 D4 — 선형 · 랜덤 포레스트 · 엑스트라 트리 · LightGBM · XGBoost
VAL_FRAC, EMBARGO_M, BURN_YEARS, SEED = 0.2, 1, 5, 20261123
TARGETS = {"1m": {"h": 1, "name": "TREE_1M", "quarter_only": False, "desc": "다음 1개월 수익 순위 예측(트리 AutoML)"},
           "12m": {"h": 12, "name": "TREE_12M", "quarter_only": True, "desc": "향후 12개월 수익 순위 예측(트리 AutoML)"}}


def _nlff_automl():
    p = ac.root() + "/04_Research/01_reports/nonlinear_fundamental_factors_20261116"
    if p not in sys.path:
        sys.path.insert(0, p)
    import nlff_automl
    import nlff_data
    return nlff_automl, nlff_data.load_cfg()["automl"]


def design(store, cp):
    """모형 입력의 종목 쪽 부분: 순위 특성(결측 0) + 결측 비율. [멤버 칸 × 열]."""
    X, names = load_features(store, cp)
    miss = np.isnan(X).mean(1).astype(np.float32)
    np.nan_to_num(X, copy=False, nan=0.0)
    return np.concatenate([X, miss[:, None]], axis=1), names + ["miss_ratio"]


def target_rank(cp, h):
    """신호 뒤 h 개월 수익의 그 달 멤버 안 순위 (−1, 1). 수익이 없는 칸 = NaN."""
    from scipy.stats import rankdata
    fwd = np.asarray(cp.f.fwd(h))[cp.S, cp.J].astype(np.float64)
    y = np.full(cp.n, np.nan, dtype=np.float32)
    for s in range(cp.f.ns):
        a, b = cp.seg[s], cp.seg[s + 1]
        k = np.isfinite(fwd[a:b])
        n = int(k.sum())
        if n >= 30:
            r = np.full(b - a, np.nan, dtype=np.float32)
            r[k] = 2.0 * (rankdata(fwd[a:b][k]) - 1.0) / (n - 1.0) - 1.0
            y[a:b] = r
    return y


def macro_z(Z, upto):
    """시장 · 거시 상태 변수를 재학습 시점까지의 평균 · 표준편차로 표준화(그 뒤 달의 통계는 쓰지 않는다). 결측 = 0."""
    with np.errstate(invalid="ignore", divide="ignore"):
        mu, sd = np.nanmean(Z[:upto + 1], axis=0), np.nanstd(Z[:upto + 1], axis=0)
        z = (Z - mu) / np.where(sd > 0, sd, np.nan)
    return np.nan_to_num(z, nan=0.0).astype(np.float32)


def importance(models, names):
    """LightGBM 구성원의 이득 중요도(가중 합) 상위 — 해석용."""
    tot = np.zeros(len(names))
    for est, wt in models:
        bst = getattr(getattr(est, "model", None), "booster_", None)
        if bst is not None:
            g = bst.feature_importance(importance_type="gain").astype(np.float64)
            if len(g) == len(names) and g.sum() > 0:
                tot += wt * g / g.sum()
    o = np.argsort(-tot)[:30]
    return [(names[i], round(float(tot[i]), 4)) for i in o if tot[i] > 0]


def run_target(tk, cfg, X, xnames, Z, znames, cp, out_dir, fp, force, unit0, n_units):
    na, acfg0 = _nlff_automl()
    acfg = dict(acfg0, estimator_list=ESTIMATORS)
    na.SEED, na.FIXED_HP = SEED, None
    na.FIXED_HP = na.fixed_hp()
    f = cp.f
    h = cfg["h"]
    y = target_rank(cp, h)
    dates = f.sig_dates[cp.S]
    av_idx = np.minimum(cp.S + h, f.ns - 1)
    avail = f.sig_dates[av_idx]
    usable = np.isfinite(y) & (cp.S + h <= f.ns - 1)
    if cfg["quarter_only"]:
        qm = np.isin(np.array([int(str(d)[5:7]) for d in f.sig_dates]), [3, 6, 9, 12])
        usable &= qm[cp.S]
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    pred = np.full(cp.n, np.nan, dtype=np.float32)
    logs = []
    names = xnames + znames
    for n, yy in enumerate(sel_years):
        sY = dec[yy]
        nxt = list(range(sY, min(sY + 12, f.ns)))
        a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
        ck = "%s/%s_%d.npz" % (out_dir, tk, yy)
        if os.path.exists(ck) and not force:
            z = np.load(ck, allow_pickle=True)
            if str(z["fp"]) == fp:
                pred[a1:b1] = z["pred"]
                logs.append(z["log"].item())
                ac.stage_unit(unit0 + n + 1, "%s %d년 재학습 — 저장분 사용" % (tk, yy))
                continue
        t0 = time.time()
        refit_cut = f.sig_dates[sY - EMBARGO_M]                    # 재학습일 한 달 전까지 실현된 표적만
        w = np.nonzero(usable & (avail <= refit_cut))[0]
        zs = macro_z(Z, sY)
        Xw = np.concatenate([X[w], zs[cp.S[w]]], axis=1)
        tr, va = na.time_split(dates[w], avail[w], VAL_FRAC, refit_cut)
        if tr is None or tr.sum() < 5000 or va.sum() < 1000:
            ac.log("%s %d — 표본이 모자라 건너뜀", tk, yy)
            continue
        log = {"target": tk, "year": yy, "n_train": int(tr.sum()), "n_val": int(va.sum()), "val_from": str(dates[w][va].min()), "refit_cut": str(refit_cut)}
        members = na.fit_refit("regression", Xw[tr], y[w][tr], Xw[va], y[w][va], acfg, int(acfg["max_iter"]), ac.threads(), SEED, log, dates_va=dates[w][va])
        models = na.refit_models("regression", members, Xw, y[w], ac.threads())
        del Xw
        rows = np.arange(a1, b1)
        Xp = np.concatenate([X[rows], zs[cp.S[rows]]], axis=1)
        p = na.predict_ens(models, Xp, "regression").astype(np.float32)
        del Xp
        log["importance_top"] = importance(models, names)
        log["seconds"] = round(time.time() - t0, 1)
        pred[a1:b1] = p

        def _save(path, p=p, log=log):
            with open(path, "wb") as fh:
                np.savez(fh, fp=fp, pred=p, log=np.array(log, dtype=object))
        ac.write_atomic(ck, _save)
        logs.append(log)
        ac.log("%s %d년 재학습 — 학습 %d · 검증 %d · 구성 %s · %.0f초", tk, yy, log["n_train"], log["n_val"],
               " ".join("%s %.2f" % (k, v) for k, v in log.get("ensemble_weights", {}).items()), time.time() - t0)
        ac.stage_unit(unit0 + n + 1, "%s %d년 재학습 끝" % (tk, yy))
        del models
    S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
    S[cp.S, cp.J] = pred
    path = ac.out("factors") + "/%s.parquet" % cfg["name"]
    ac.save_factor_panel(path, cfg["name"], S, f)
    ac.write_json({"target": tk, "retrains": logs}, ac.results("stage3_tree", "retrain_log_%s.json" % tk))
    return {"id": cfg["name"], "path": path, "direction": 1, "method": "예측 모형 2판 · 트리 AutoML", "desc": cfg["desc"]}, len(sel_years)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="both")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    ac.low_priority()
    f = ac.Frame()
    store = FeatureStore(f)
    cp = Compact(f)
    out_dir = ac.out("tree")
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(ac.results("stage3_tree"), exist_ok=True)
    os.makedirs(ac.out("factors"), exist_ok=True)
    ac.stage_begin("tree_automl", 1, "준비", 0.0, 0.02)
    X, xnames = design(store, cp)
    Z = np.load(store.dir + "/macro_state.npy")
    znames = ac.read_json(store.dir + "/macro_state_meta.json")["names"]
    fp = "%s|v%d|%d|%d" % (f.meta.get("rawdata_tag"), VERSION, X.shape[1], Z.shape[1])
    tks = ["1m", "12m"] if a.target == "both" else [a.target]
    n_years = len({int(str(d)[:4]) for d in f.sig_dates}) - BURN_YEARS + 1
    ac.stage_begin("tree_automl", n_years * len(tks), "재학습", 0.02, 0.9)
    manifest, u0 = [], 0
    for tk in tks:
        m, k = run_target(tk, TARGETS[tk], X, xnames, Z, znames, cp, out_dir, fp, a.force, u0, n_years * len(tks))
        manifest.append(m)
        u0 += k
    ac.write_json({"at": ac._now(), "stage": "tree_automl", "factors": manifest,
                   "params": {"estimators": ESTIMATORS, "val_frac": VAL_FRAC, "embargo_months": EMBARGO_M, "seed": SEED,
                              "_source": "승인 계획 '머신러닝 방법론' · 탐색 설정(시행 60 · 앙상블 크기 · 탐색 공간 = 라이브러리 기본)은 nlff_config.json::automl 그대로"}},
                  ac.out("manifest_tree.json"))
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
