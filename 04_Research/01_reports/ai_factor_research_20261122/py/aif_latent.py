"""aif_latent.py — 단계 4: 잠재팩터 추출(차원 축소) — PCA · 위험프리미엄 PCA · IPCA.

입력 = 특성(기본 특성 집합의 그 달 멤버 안 순위 · 결측 0 · 상수항 추가)과 다음 달 수익. 해마다 12월 신호일에 그때까지 실현된 달만으로 다시 추정한다(확장 창).
  관리 포트폴리오 수익  x(l, s) = Σ_i z(i, l, s) · r(i, s+1) ÷ N_s      — 특성 l 로 가중한 포트폴리오의 다음 달 수익
  PCA      x 의 공분산을 고유분해한다. 고유벡터 w_k 가 잠재팩터(특성의 선형 결합)이고 팩터 수익은 x · w_k
  RP-PCA   (1/T) X'X + γ x̄ x̄' 를 분해한다 — 평균 수익이 큰 약한 팩터도 잡는다(Lettau & Pelger 2020 RFS https://doi.org/10.1093/rfs/hhaa020 · γ = 10)
  IPCA     r(i, s+1) = z(i, s)' Γ f(s+1) + e 를 Γ 와 f 를 번갈아 최소제곱으로 푼다(Kelly, Pruitt & Su 2019 JFE https://doi.org/10.1016/j.jfineco.2019.05.001)
  종목 기대수익 점수   μ(i, s) = z(i, s)' Γ λ      — λ = 그때까지의 잠재팩터 평균 수익(PCA 계열은 Γ = 고유벡터)
  팩터 수 K = {3, 5, 8} 가운데 창 안 시간순 검증(앞 80% 달로 추정 · 뒤 20% 달에서 점수의 월별 순위 IC)으로 고른다.
산출: 종목 점수 팩터 LAT_PCA · LAT_RPPCA · LAT_IPCA(factors/) · 잠재팩터별 종목 비중 패널(앞 3개 · latent/) · 로딩 상위 표 · 모형 설명력(전체 R² · 예측 R² — 표본 밖 달).
실행: python py/aif_latent.py [--models pca,rppca,ipca] [--smoke] [--force]   ((모형, 해) 하나 = 체크포인트 하나)
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
K_GRID, VAL_FRAC, BURN_YEARS, RP_GAMMA, N_PORT = (3, 5, 8), 0.2, 5, 10.0, 3
IPCA_ITER, IPCA_TOL, RIDGE = 100, 1e-4, 1e-8
PARAM_SRC = {"RP_GAMMA": "Lettau & Pelger 2020 의 권고 범위 10~20 가운데 10", "K_GRID": "팩터 수 후보 3 · 5 · 8 — Kelly, Pruitt & Su 2019 가 본 1~6 과 Lettau & Pelger 의 5 안팎을 덮는 범위",
             "IPCA_ITER · IPCA_TOL": "번갈아 최소제곱의 최대 반복 100 · 수렴 기준(Γ 최대 변화) 1e-4"}
MODELS = {"pca": "LAT_PCA", "rppca": "LAT_RPPCA", "ipca": "LAT_IPCA"}


def moments(Z, r, cp, with_A):
    """달마다 관리 포트폴리오 수익 합 b_s = Z_s' r_s · 종목 수 n_s · (IPCA 용) A_s = Z_s' Z_s. 수익이 없는 종목은 뺀다."""
    ns, L = cp.f.ns, Z.shape[1]
    b, n = np.zeros((ns, L)), np.zeros(ns)
    A = np.zeros((ns, L, L), dtype=np.float32) if with_A else None
    for s in range(ns):
        a0, a1 = cp.seg[s], cp.seg[s + 1]
        k = np.isfinite(r[a0:a1])
        if k.sum() < 30:
            continue
        Zs = Z[a0:a1][k].astype(np.float64)
        b[s], n[s] = Zs.T @ r[a0:a1][k], k.sum()
        if with_A:
            A[s] = (Zs.T @ Zs).astype(np.float32)
    return b, n, A


def pca_fit(X, K, gamma):
    """관리 포트폴리오 수익 X [달 × 특성] → 고유벡터 [특성 × K]. gamma = −1 이면 공분산(보통의 PCA)."""
    T = X.shape[0]
    xb = X.mean(0)
    M = X.T @ X / T + gamma * np.outer(xb, xb)
    w, V = np.linalg.eigh(M)
    return V[:, np.argsort(-w)[:K]]


def ipca_fit(A, b, n, K, G0, log=None):
    """번갈아 최소제곱. A [달 × L × L] = Z'Z · b [달 × L] = Z'r · n = 종목 수. 반환 Γ [L × K](직교 정규) · f [달 × K]."""
    T, L = b.shape
    G = G0.copy()
    A2 = A.reshape(T, L * L)
    iu = [(i, j) for i in range(K) for j in range(i, K)]
    for it in range(IPCA_ITER):
        F = np.zeros((T, K))
        for t in range(T):
            GA = G.T @ A[t].astype(np.float64)
            F[t] = np.linalg.solve(GA @ G + RIDGE * n[t] * np.eye(K), G.T @ b[t])
        # Γ 갱신: vec 순서 = (특성, 팩터) — Σ_t A_t ⊗ f f' 를 한 번의 행렬곱으로 모은다
        P = np.stack([F[:, i] * F[:, j] for i, j in iu], axis=1).astype(np.float32)        # [T × 쌍]
        S = (P.T @ A2).astype(np.float64).reshape(len(iu), L, L)
        H = np.zeros((L * K, L * K))
        for q, (i, j) in enumerate(iu):
            H[i::K, j::K] = S[q]
            if i != j:
                H[j::K, i::K] = S[q]
        rhs = (b[:, :, None] * F[:, None, :]).sum(0).reshape(L * K)
        H[np.diag_indices_from(H)] += RIDGE * np.trace(H) / (L * K)
        Gn = np.linalg.solve(H, rhs).reshape(L, K)
        U, sv, Vt = np.linalg.svd(Gn, full_matrices=False)                                  # 정규화: Γ'Γ = I
        Gn = U
        d = float(np.max(np.abs(np.abs(Gn.T @ G).max(0) - 1.0))) if it else 1.0             # 열 공간이 얼마나 바뀌었나(부호 · 순서 무관)
        G = Gn
        if log and (it % 20 == 0):
            log("    IPCA K=%d 반복 %d · 변화 %.2e", K, it, d)
        if it and d < IPCA_TOL:
            break
    F = np.zeros((T, K))
    for t in range(T):
        GA = G.T @ A[t].astype(np.float64)
        F[t] = np.linalg.solve(GA @ G + RIDGE * n[t] * np.eye(K), G.T @ b[t])
    return G, F, it + 1


def orient(G, F):
    """팩터를 분산이 큰 순서로 놓고, 평균 수익이 양수가 되게 부호를 맞춘다(그때까지의 값으로)."""
    o = np.argsort(-F.var(0))
    G, F = G[:, o], F[:, o]
    sg = np.where(F.mean(0) >= 0, 1.0, -1.0)
    return G * sg, F * sg


def factor_returns(G, A_or_none, b, n, X):
    """추정 창 안의 팩터 수익. IPCA = 달마다 횡단면 회귀(Γ'A Γ)^{-1} Γ'b · PCA 계열 = x · Γ."""
    if A_or_none is None:
        return X @ G
    T, K = b.shape[0], G.shape[1]
    F = np.zeros((T, K))
    for t in range(T):
        GA = G.T @ A_or_none[t].astype(np.float64)
        F[t] = np.linalg.solve(GA @ G + RIDGE * n[t] * np.eye(K), G.T @ b[t])
    return F


def month_ic(score, r, cp, months):
    from scipy.stats import rankdata
    out = []
    for s in months:
        a0, a1 = cp.seg[s], cp.seg[s + 1]
        k = np.isfinite(r[a0:a1]) & np.isfinite(score[a0:a1])
        if k.sum() >= 30:
            x, y = rankdata(score[a0:a1][k]), rankdata(r[a0:a1][k])
            out.append(np.corrcoef(x, y)[0, 1])
    return float(np.mean(out)) if out else float("nan")


def estimate(model, K, win, b, n, A, G_init=None, log=None):
    """창(달 색인 win) 안에서 모형을 추정 → (Γ, λ, 반복 수)."""
    X = b[win] / n[win][:, None]
    if model == "ipca":
        G0 = pca_fit(X, K, RP_GAMMA) if G_init is None else G_init
        G, F, it = ipca_fit(A[win], b[win], n[win], K, G0, log)
    else:
        G = pca_fit(X, K, -1.0 if model == "pca" else RP_GAMMA)
        F, it = X @ G, 0
    G, F = orient(G, F)
    return G, F.mean(0), it


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="pca,rppca,ipca")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--smoke", action="store_true", help="두 해(2010 · 2011) · IPCA 반복 10 — 코드 경로 시험용")
    a = ap.parse_args()
    ac.SMOKE["on"] = a.smoke
    global IPCA_ITER
    if a.smoke:
        IPCA_ITER = 10
    ac.low_priority()
    f = ac.Frame()
    store = FeatureStore(f)
    cp = Compact(f)
    out_dir = ac.out(ac.smoke_name("latent"))
    res_dir = ac.results(ac.smoke_name("stage4_latent"))
    for d in (out_dir, res_dir, ac.out(ac.smoke_name("factors"))):
        os.makedirs(d, exist_ok=True)
    models = [m for m in a.models.split(",") if m in MODELS]
    ac.stage_begin("pca_ipca", 1, "준비", 0.0, 0.03)
    X0, names = load_features(store, cp)
    np.nan_to_num(X0, copy=False, nan=0.0)
    Z = np.concatenate([np.ones((cp.n, 1), dtype=np.float32), X0], axis=1)                 # 상수항(시장 전체) + 특성
    names = ["const"] + names
    del X0
    r = np.asarray(f.fwd(1))[cp.S, cp.J].astype(np.float64)
    b, n, A = moments(Z, r, cp, "ipca" in models)
    fp = "%s|v%d|%d" % (f.meta.get("rawdata_tag"), VERSION, Z.shape[1])
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    if a.smoke:
        sel_years = [2010, 2011]
    ac.stage_begin("pca_ipca", len(sel_years) * len(models), "재추정", 0.03, 0.9)
    manifest, u = [], 0
    for m in models:
        score = np.full(cp.n, np.nan, dtype=np.float32)
        wts = [np.full(cp.n, np.nan, dtype=np.float32) for _ in range(N_PORT)]
        logs, G_prev = [], None
        sse_tot, sse_pred, ss = 0.0, 0.0, 0.0
        for yy in sel_years:
            sY = dec[yy]
            nxt = list(range(sY, min(sY + 12, f.ns)))
            a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
            ck = "%s/%s_%d.npz" % (out_dir, m, yy)
            if os.path.exists(ck) and not a.force:
                z = np.load(ck, allow_pickle=True)
                if str(z["fp"]) == fp:
                    score[a1:b1] = z["score"]
                    for k in range(N_PORT):
                        wts[k][a1:b1] = z["wts"][k]
                    lg = z["log"].item()
                    logs.append(lg)
                    sse_tot, sse_pred, ss = sse_tot + lg["sse_total"], sse_pred + lg["sse_pred"], ss + lg["ss"]
                    u += 1
                    ac.stage_unit(u, "%s %d년 — 저장분 사용" % (m, yy))
                    continue
            t0 = time.time()
            win = np.nonzero((np.arange(f.ns) < sY) & (n > 0))[0]                           # 다음 달 수익이 선택 시점까지 실현된 달
            cut = win[int(len(win) * (1 - VAL_FRAC))]
            w1, w2 = win[win < cut], win[win >= cut]
            val = {}
            for K in K_GRID:                                                               # 팩터 수 고르기(창 안 시간순 검증)
                G, lam, _ = estimate(m, K, w1, b, n, A)
                sc = np.full(cp.n, np.nan)
                lo, hi = cp.seg[w2[0]], cp.seg[w2[-1] + 1]
                sc[lo:hi] = Z[lo:hi].astype(np.float64) @ (G @ lam)
                val[K] = month_ic(sc, r, cp, w2)
            K = max(K_GRID, key=lambda k: (val[k] if np.isfinite(val[k]) else -9, -k))
            G, lam, iters = estimate(m, K, win, b, n, A, log=ac.log if m == "ipca" else None)
            Zx = Z[a1:b1].astype(np.float64)
            sc = (Zx @ (G @ lam)).astype(np.float32)
            score[a1:b1] = sc
            wz = np.full((N_PORT, b1 - a1), np.nan, dtype=np.float32)
            st, sp, s2 = 0.0, 0.0, 0.0
            for s in nxt:                                                                  # 잠재팩터 포트폴리오 비중 = 횡단면 회귀의 가중(순수 팩터 포트폴리오)
                lo, hi = cp.seg[s] - a1, cp.seg[s + 1] - a1
                Zs = Zx[lo:hi]
                if hi - lo < 30:
                    continue
                Wt = np.linalg.solve(G.T @ Zs.T @ Zs @ G + RIDGE * (hi - lo) * np.eye(K), G.T @ Zs.T)   # [K × 종목]
                for k in range(min(N_PORT, K)):
                    g = np.abs(Wt[k]).sum()
                    wz[k, lo:hi] = (2.0 * Wt[k] / g).astype(np.float32) if g > 0 else np.nan            # 총 노출 200%(롱 · 숏 합)로 맞춘다
                rs = r[a1 + lo:a1 + hi]
                kk = np.isfinite(rs)
                if kk.sum() >= 30:                                                         # 모형 설명력(표본 밖 달): 그 달의 팩터 수익으로 · 그때까지의 평균 수익으로
                    fr = np.linalg.solve(G.T @ Zs[kk].T @ Zs[kk] @ G + RIDGE * kk.sum() * np.eye(K), G.T @ Zs[kk].T @ rs[kk])
                    beta = Zs[kk] @ G
                    st += float(((rs[kk] - beta @ fr) ** 2).sum())
                    sp += float(((rs[kk] - beta @ lam) ** 2).sum())
                    s2 += float((rs[kk] ** 2).sum())
            for k in range(N_PORT):
                wts[k][a1:b1] = wz[k]
            top = {}
            for k in range(min(N_PORT, K)):
                o = np.argsort(-np.abs(G[1:, k]))[:12] + 1                                 # 상수항을 뺀 로딩 상위
                top["F%d" % (k + 1)] = [(names[i], round(float(G[i, k]), 4)) for i in o]
            lg = {"model": m, "year": yy, "K": int(K), "val_ic_by_K": {int(k): round(v, 5) for k, v in val.items()}, "lambda": [round(float(x), 6) for x in lam],
                  "iterations": int(iters), "loadings_top": top, "sse_total": st, "sse_pred": sp, "ss": s2, "seconds": round(time.time() - t0, 1)}

            def _save(path, sc=sc, wz=wz, lg=lg):
                with open(path, "wb") as fh:
                    np.savez(fh, fp=fp, score=sc, wts=wz, log=np.array(lg, dtype=object))
            ac.write_atomic(ck, _save)
            logs.append(lg)
            sse_tot, sse_pred, ss = sse_tot + st, sse_pred + sp, ss + s2
            u += 1
            ac.log("%s %d년 — K %d(검증 IC %s) · %.0f초", m, yy, K, " ".join("%d:%.3f" % (k, v) for k, v in val.items()), time.time() - t0)
            ac.stage_unit(u, "%s %d년 재추정 끝" % (m, yy))
        S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
        S[cp.S, cp.J] = score
        p = ac.out(ac.smoke_name("factors")) + "/%s.parquet" % MODELS[m]
        ac.save_factor_panel(p, MODELS[m], S, f)
        label = {"pca": "PCA", "rppca": "위험프리미엄 PCA", "ipca": "IPCA"}[m]
        manifest.append({"id": MODELS[m], "path": p, "direction": 1, "kind": "score", "method": "잠재팩터 · " + label, "desc": "종목 기대수익 점수 = 잠재팩터 노출 × 그때까지의 팩터 평균 수익"})
        for k in range(N_PORT):
            Wm = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
            Wm[cp.S, cp.J] = wts[k]
            nm = "%s_F%d" % (MODELS[m], k + 1)
            pw = out_dir + "/%s.parquet" % nm
            ac.save_factor_panel(pw, nm, Wm, f)
            manifest.append({"id": nm, "path": pw, "direction": 1, "kind": "weights", "method": "잠재팩터 · " + label, "desc": "%d번째 잠재팩터의 종목 비중(순수 팩터 포트폴리오 · 총 노출 200%%)" % (k + 1)})
        r2 = {"total_r2": round(1 - sse_tot / ss, 5) if ss > 0 else None, "pred_r2": round(1 - sse_pred / ss, 6) if ss > 0 else None}
        ac.write_json({"model": m, "r2_oos": r2, "retrains": logs}, res_dir + "/model_log_%s.json" % m)
        ac.log("%s — 표본 밖 전체 R² %s · 예측 R² %s", m, r2["total_r2"], r2["pred_r2"])
    ac.write_json({"at": ac._now(), "stage": "pca_ipca", "factors": manifest,
                   "params": {"K_GRID": K_GRID, "VAL_FRAC": VAL_FRAC, "RP_GAMMA": RP_GAMMA, "IPCA_ITER": IPCA_ITER, "IPCA_TOL": IPCA_TOL, "_source": PARAM_SRC}},
                  ac.out(ac.smoke_name("manifest_latent") + ".json"))
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
