"""aif_fboost.py — 단계 3 생성기 ②: 특징 부스팅(쌍 연산 후보를 '기준 모형 위의 증분 기여'로 평가).

방법(OpenFE — Zhang 외 2022 https://arxiv.org/abs/2211.12507 의 FeatureBoost 와 두 단계 가지치기를 따른다). 해마다 12월 신호일에, 그때까지 실현된 자료만으로:
  ① 기준 모형 = 기본 특성(원자료 변환 + 기존 팩터)의 순위로 다음 달 수익 순위를 맞히는 LightGBM. 시간 블록 교차 적합으로 표본 밖 예측을 만든다.
  ② 후보 = 기준 모형에서 이득 중요도가 높은 특성 M 개의 쌍 × 연산 6가지(곱 · 차 · 큰 값 · 작은 값 · 조건부 2가지)
  ③ 1차 가지치기 = 후보 하나만으로 기준 예측의 잔차를 얼마나 더 줄이는가(분위 구간 평균을 앞 70% 달에서 맞추고 뒤 30% 달에서 잰 손실 감소)
  ④ 2차 가지치기 = 살아남은 N 개를 기본 특성과 함께 넣은 모형에서의 이득 중요도 순 → 상위 K(채움 60% 이상 · 이미 뽑힌 것과 상관 0.7 미만)
  ⑤ 뽑힌 K 개를 다음 12달에만 쓴다(방향 = 그때까지의 순위 IC 부호).
산출: factors/FBOOST_C20.parquet(뽑힌 특성의 부호 맞춘 순위 평균) · FBOOST_TOP1~5.parquet · 뽑힌 식 목록 csv.
실행: python py/aif_fboost.py [--force]   (해 하나 = 체크포인트 하나)
"""
import argparse
import csv
import os
import sys
import time

import numpy as np

import aif_common as ac
from aif_enumerate import Compact
from aif_features import FeatureStore

VERSION = 1
BLOCKS = ["price", "flow", "macro", "cat", "val", "cons", "fund", "existing"]
M_TOP, N_KEEP, K_SELECT, N_TOP = 40, 100, 20, 5
N_BINS, SHRINK, FIT_FRAC, N_FOLDS, MIN_COVER, MAX_CORR, BURN_YEARS = 32, 100.0, 0.7, 3, 0.60, 0.70, 5
LGB = dict(objective="regression", learning_rate=0.05, num_leaves=31, min_data_in_leaf=200, feature_fraction=0.3, bagging_fraction=0.7, bagging_freq=1,
           lambda_l2=1.0, max_bin=63, seed=7, verbose=-1, deterministic=True, force_row_wise=True)
N_TREES = 200
PARAM_SRC = {"LGB": "LightGBM 기본값에서 과적합을 줄이는 쪽으로만 옮긴 값(잎 31 = 기본값 · 학습률 0.05 · 잎 최소 표본 200 · 열 30% · 행 70% 표집) — 탐색 없이 고정",
             "M_TOP": "쌍을 만들 특성 수 40 → 쌍 780 × 연산 6 = 후보 4,680개", "N_KEEP": "1차 가지치기 뒤 남기는 후보 100개", "K_SELECT": "합성에 넣는 특성 20개(열거 생성기와 같은 수)",
             "N_BINS": "잔차 구간 평균의 분위 수 32", "MIN_COVER · MAX_CORR": "승인 계획의 선별 기준(채움 60% 이상 · 상관 0.7 미만)"}
OPS = ["mul", "sub", "max", "min", "a_if_b_pos", "b_if_a_pos"]


def op_value(op, a, b):
    if op == "mul":
        return a * b
    if op == "sub":
        return a - b
    if op == "max":
        return np.where(np.isnan(a) | np.isnan(b), np.nan, np.maximum(a, b))
    if op == "min":
        return np.where(np.isnan(a) | np.isnan(b), np.nan, np.minimum(a, b))
    if op == "a_if_b_pos":
        return np.where(np.isnan(a) | np.isnan(b), np.nan, np.where(b > 0, a, 0.0))
    return np.where(np.isnan(a) | np.isnan(b), np.nan, np.where(a > 0, b, 0.0))


def op_text(op, a, b):
    return {"mul": "%s × %s", "sub": "%s − %s", "max": "max(%s, %s)", "min": "min(%s, %s)", "a_if_b_pos": "%s (단 %s > 중앙)", "b_if_a_pos": "%s (단 %s > 중앙)"}[op] % ((b, a) if op == "b_if_a_pos" else (a, b))


def load_features(store, cp):
    cols, names = [], []
    for b in BLOCKS:
        rk, nm = store.open(b, "rank")
        cols.append(np.asarray(rk)[cp.S, cp.J].astype(np.float32))
        names += nm
    return np.concatenate(cols, axis=1), names


def fit_lgb(X, y, feature_names=None):
    import lightgbm as lgb
    ds = lgb.Dataset(X, label=y, feature_name=feature_names or "auto", free_raw_data=False)
    return lgb.train(dict(LGB, num_threads=ac.threads()), ds, num_boost_round=N_TREES)


def stage1_score(v, res, fit, ev):
    """후보 하나의 증분 기여 — 분위 구간별 잔차 평균(줄여서)을 fit 에서 맞추고 ev 에서 잰 제곱 오차 감소(클수록 좋음)."""
    vf = v[fit]
    k = np.isfinite(vf)
    if k.sum() < 2000:
        return -np.inf
    edges = np.unique(np.quantile(vf[k][::8], np.linspace(0, 1, N_BINS + 1)[1:-1]))   # 구간 경계는 8칸에 하나씩 뽑은 표본으로(속도)
    if len(edges) < 3:
        return -np.inf
    nb = len(edges) + 2                                        # 마지막 칸 = 결측
    bf = np.where(k, np.searchsorted(edges, np.where(k, vf, 0.0)), nb - 1)
    s, n = np.bincount(bf, weights=res[fit], minlength=nb), np.bincount(bf, minlength=nb)
    m = s / (n + SHRINK)
    ve = v[ev]
    ke = np.isfinite(ve)
    be = np.where(ke, np.searchsorted(edges, np.where(ke, ve, 0.0)), nb - 1)
    me = m[be]
    return float(np.mean(2.0 * res[ev] * me - me * me))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--smoke", action="store_true", help="한 해(2010)만 · 쌍을 만들 특성 12개 — 코드 경로 시험용")
    a = ap.parse_args()
    ac.SMOKE["on"] = a.smoke
    global M_TOP
    if a.smoke:
        M_TOP = 12
    ac.low_priority()
    f = ac.Frame()
    store = FeatureStore(f)
    cp = Compact(f)
    out_dir = ac.out(ac.smoke_name("fboost"))
    os.makedirs(out_dir, exist_ok=True)
    ac.stage_begin("feature_boost", 1, "준비", 0.0, 0.02)
    X, names = load_features(store, cp)
    with np.errstate(invalid="ignore"):
        n_in = np.array([np.isfinite(cp.fwd_rank[cp.seg[s]:cp.seg[s + 1]]).sum() for s in range(f.ns)])[cp.S]
        y = (2.0 * (cp.fwd_rank - 1.0) / np.maximum(n_in - 1.0, 1.0) - 1.0).astype(np.float32)   # 다음 달 수익의 멤버 안 순위 (−1, 1)
    yok = np.isfinite(y)
    fp = "%s|v%d|%d" % (f.meta.get("rawdata_tag"), VERSION, len(names))
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    if a.smoke:
        sel_years = [2010]
    ac.stage_begin("feature_boost", len(sel_years), "해", 0.02, 0.9)
    comp = np.full(cp.n, np.nan, dtype=np.float32)
    tops = [np.full(cp.n, np.nan, dtype=np.float32) for _ in range(N_TOP)]
    rows = []
    for n, yy in enumerate(sel_years):
        sY = dec[yy]
        ck = "%s/year_%d.npz" % (out_dir, yy)
        nxt = list(range(sY, min(sY + 12, f.ns)))
        a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
        if os.path.exists(ck) and not a.force:
            z = np.load(ck, allow_pickle=True)
            if str(z["fp"]) == fp:
                comp[a1:b1] = z["comp"]
                for k in range(N_TOP):
                    tops[k][a1:b1] = z["tops"][k]
                rows += list(z["rows"])
                ac.stage_unit(n + 1, "%d년 말 선택 — 저장분 사용" % yy)
                continue
        t0 = time.time()
        tr = (cp.S < sY) & yok                                 # 다음 달 수익이 선택 시점까지 실현된 표본만
        idx = np.nonzero(tr)[0]
        months = cp.S[idx]
        um = np.unique(months)
        # ① 시간 블록 교차 적합 → 표본 밖 기준 예측
        bounds = np.array([p[0] for p in np.array_split(um, N_FOLDS)[1:]])   # 달을 시간순으로 N_FOLDS 구간으로 나눈 경계
        fold_of = np.searchsorted(bounds, months, side="right")
        oof = np.full(len(idx), np.nan, dtype=np.float32)
        for k in range(N_FOLDS):
            te = fold_of == k
            mdl = fit_lgb(X[idx[~te]], y[idx[~te]])
            oof[te] = mdl.predict(X[idx[te]], num_threads=ac.threads())
        base = fit_lgb(X[idx], y[idx])
        gain = base.feature_importance(importance_type="gain")
        top = np.argsort(-gain)[:M_TOP]
        res = (y[idx] - oof).astype(np.float64)
        cut_m = um[int(len(um) * FIT_FRAC)]
        fit, ev = np.nonzero(months < cut_m)[0], np.nonzero(months >= cut_m)[0]
        # ② ③ 후보 생성과 1차 가지치기
        cand, score = [], []
        for i in range(M_TOP):
            xa = X[idx, top[i]]
            for j in range(i + 1, M_TOP):
                xb = X[idx, top[j]]
                for op in OPS:
                    cand.append((int(top[i]), int(top[j]), op))
                    score.append(stage1_score(op_value(op, xa, xb), res, fit, ev))
        keep = np.argsort(-np.array(score))[:N_KEEP]
        # ④ 2차 가지치기 — 기본 특성과 함께 넣은 모형에서의 이득
        C = np.stack([op_value(cand[c][2], X[idx, cand[c][0]], X[idx, cand[c][1]]) for c in keep], axis=1).astype(np.float32)
        joint = fit_lgb(np.concatenate([X[idx], C], axis=1), y[idx])
        g2 = joint.feature_importance(importance_type="gain")[X.shape[1]:]
        del C, joint
        order = keep[np.argsort(-g2)]
        a0, b0 = cp.seg[max(0, sY - 11)], cp.seg[sY + 1]       # 상관을 재는 구간(선택 시점까지의 최근 12달 신호)
        c0 = cp.seg[max(0, sY - 36)]
        picked, vals = [], []
        for c in order:
            if len(picked) >= K_SELECT:
                break
            ia, ib, op = cand[c]
            v = op_value(op, X[:, ia], X[:, ib])
            if np.isfinite(v[c0:b0]).mean() < MIN_COVER:
                continue
            ic, _ = cp.ic(v)
            sgn = float(np.sign(np.nanmean(ic[:sY])))          # 방향 = 그때까지의 순위 IC 부호
            if sgn == 0 or not np.isfinite(sgn):
                continue
            r = cp.rank_pm1(v) * sgn
            ok = True
            for q in vals:
                kk = np.isfinite(r[a0:b0]) & np.isfinite(q[a0:b0])
                if kk.sum() > 100 and abs(np.corrcoef(r[a0:b0][kk], q[a0:b0][kk])[0, 1]) >= MAX_CORR:
                    ok = False
                    break
            if ok:
                picked.append(c)
                vals.append(r)
                rows.append({"year_selected": yy, "used_from": str(f.sig_dates[nxt[0]]), "used_to": str(f.sig_dates[nxt[-1]]), "pick": len(picked),
                             "formula": op_text(op, names[ia], names[ib]), "direction": int(sgn), "stage1_gain": float(score[c]),
                             "ic_mean_asof": round(float(np.nanmean(ic[:sY])), 4)})
        cz = np.full(b1 - a1, np.nan, dtype=np.float32)
        tz = np.full((N_TOP, b1 - a1), np.nan, dtype=np.float32)
        if vals:
            Mx = np.stack([q[a1:b1] for q in vals])
            have = np.isfinite(Mx).mean(0)
            cz = np.where(have >= 0.5, np.nanmean(np.where(np.isfinite(Mx), Mx, 0.0), 0), np.nan).astype(np.float32)
            for k in range(min(N_TOP, len(vals))):
                tz[k] = vals[k][a1:b1]
        comp[a1:b1] = cz
        for k in range(N_TOP):
            tops[k][a1:b1] = tz[k]
        yr_rows = [r for r in rows if r["year_selected"] == yy]
        def _save(p, cz=cz, tz=tz, yr_rows=yr_rows):
            with open(p, "wb") as fh:
                np.savez(fh, fp=fp, comp=cz, tops=tz, rows=np.array(yr_rows, dtype=object))
        ac.write_atomic(ck, _save)
        ac.log("%d년 말 — 표본 %d · 후보 %d → %d → 뽑힘 %d · %.0f초", yy, len(idx), len(cand), len(keep), len(picked), time.time() - t0)
        ac.stage_unit(n + 1, "%d년 말 선택 — %d개" % (yy, len(picked)))
        del vals, oof, res
    res_dir = ac.results(ac.smoke_name("stage3_fboost"))
    os.makedirs(res_dir, exist_ok=True)
    with open(res_dir + "/selected_formulas.csv", "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    fac_dir = ac.out(ac.smoke_name("factors"))
    os.makedirs(fac_dir, exist_ok=True)
    manifest = []

    def save(name, vec, desc):
        S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
        S[cp.S, cp.J] = vec
        p = fac_dir + "/%s.parquet" % name
        ac.save_factor_panel(p, name, S, f)
        manifest.append({"id": name, "path": p, "direction": 1, "method": "특징 부스팅", "desc": desc})

    save("FBOOST_C20", comp, "해마다 뽑은 쌍 연산 특성 %d개의 순위 평균(기준 모형 위의 증분 기여 상위)" % K_SELECT)
    for k in range(N_TOP):
        save("FBOOST_TOP%d" % (k + 1), tops[k], "해마다 %d번째로 뽑힌 쌍 연산 특성(식은 해마다 바뀐다)" % (k + 1))
    ac.write_json({"at": ac._now(), "stage": "feature_boost", "factors": manifest, "n_base_features": len(names),
                   "params": {"M_TOP": M_TOP, "N_KEEP": N_KEEP, "K_SELECT": K_SELECT, "N_BINS": N_BINS, "N_FOLDS": N_FOLDS, "N_TREES": N_TREES, "LGB": LGB, "_source": PARAM_SRC},
                   "selected_csv": res_dir + "/selected_formulas.csv"}, ac.out(ac.smoke_name("manifest_fboost") + ".json"))
    ac.log("끝 — 선택 %d해 · 팩터 %d개 저장", len(sel_years), len(manifest))
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
