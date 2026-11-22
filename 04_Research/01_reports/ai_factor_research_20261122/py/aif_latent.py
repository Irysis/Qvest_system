"""aif_latent.py — 단계 4: 잠재팩터 추출(차원 축소) — PCA · 위험프리미엄 PCA · IPCA.

입력 = 간추린 특성 약 150개(원자료 묶음 6개의 순위 + 기존 팩터의 카테고리 합성 · 결측 0 · 상수항 추가)와 다음 달 수익. 해마다 12월 신호일에 그때까지 실현된 달만으로 다시 추정한다(확장 창).
  ① 특성 백색화 · 축소   추정 창의 합동 2차 적률 C = Σ_s Z_s'Z_s ÷ Σ_s N_s 를 고유분해해, 평균 고윳값보다 큰 성분만 남기고(카이저 기준) 분산을 1 로 맞춘다 → z̃ = T'z(약 30개).
                         특성끼리 강하게 겹쳐 있어(같은 변수의 창 길이만 다른 것 등) 그대로 쓰면 로딩이 겹치는 방향의 잡음을 맞춘다. 변환 T 도 그때까지의 달만으로 구한다.
  ② 관리 포트폴리오 수익 x̃(s) = Z̃_s' r_{s+1} ÷ N_s        — 백색화한 특성으로 가중한 포트폴리오의 다음 달 수익
  PCA      x̃ 의 공분산을 고유분해한다. 고유벡터 w_k 가 잠재팩터 — 팩터 수익 = x̃ · w_k · 종목 비중 = Z̃ w_k ÷ N(특성 가중 포트폴리오)
  RP-PCA   (1/T) X̃'X̃ + γ x̄ x̄' 를 분해한다 — 평균 수익이 큰 약한 팩터도 잡는다(Lettau & Pelger 2020 RFS https://doi.org/10.1093/rfs/hhaa020 · γ = 10)
  IPCA     r(i, s+1) = z̃(i, s)' Γ f(s+1) + e 를 Γ 와 f 를 번갈아 최소제곱으로 푼다(Kelly, Pruitt & Su 2019 JFE https://doi.org/10.1016/j.jfineco.2019.05.001)
           식별 = Γ'Γ = I · 팩터 2차 적률이 대각이고 내림차순 · 평균 수익 양수. 수렴 = 앞뒤 반복의 Γ 열 공간 거리 < 1e-6(최대 500회).
           달마다의 횡단면 회귀에는 능형 벌점 δ·N 을 둔다 — 2000~2001년처럼 특성이 덜 갖춰진 달에는 일부 방향의 노출이 0 에 가까워 회귀가 폭주하고(팩터 수익 수백 %),
           그 값이 팩터 평균 수익에 섞여 점수를 망친다. δ 는 팩터 수와 함께 창 안 검증으로 고른다. 종목 비중 = 그 회귀의 가중(순수 팩터 포트폴리오).
  종목 기대수익 점수   μ(i, s) = z̃(i, s)' Γ λ      — λ = 그때까지의 잠재팩터 평균 수익(PCA 계열은 Γ = 고유벡터)
  고르기   팩터 수 K = {3, 5, 8}(IPCA 는 δ = {0.01, 0.1, 1} 과 함께)을 창 안 시간순 검증(앞 80% 달로 추정 · 뒤 20% 달에서 점수의 월별 순위 IC)으로 고른다.
산출: 종목 점수 팩터 LAT_PCA · LAT_RPPCA · LAT_IPCA(factors/) · 잠재팩터별 종목 비중 패널(앞 3개 · latent/ · 노출 1 단위당 수익 척도) · 특성과의 상관 상위 표 ·
      모형 설명력(표본 밖 달 — 전체 R² = 그 달 횡단면 회귀로 구한 팩터 수익이 설명하는 비율 · 예측 R² = 그때까지의 팩터 평균 수익이 설명하는 비율).
실행: python py/aif_latent.py [--models pca,rppca,ipca] [--smoke] [--force]   ((모형, 해) 하나 = 체크포인트 하나)
"""
import argparse
import os
import sys
import time

import numpy as np

import aif_common as ac
from aif_enumerate import Compact
from aif_features import FeatureStore

VERSION = 3                                    # 3 = 특성 백색화 · 축소 · PCA 계열 팩터 수익은 투영 · IPCA 는 능형 횡단면 회귀 + 식별 정규화 + 열 공간 수렴 판정
K_GRID, VAL_FRAC, BURN_YEARS, RP_GAMMA, N_PORT = (3, 5, 8), 0.2, 5, 10.0, 3
RIDGE_GRID = (0.01, 0.1, 1.0)
IPCA_ITER, IPCA_TOL, EPS = 500, 1e-6, 1e-10
PARAM_SRC = {"RP_GAMMA": "Lettau & Pelger 2020 의 권고 범위 10~20 가운데 10", "K_GRID": "팩터 수 후보 3 · 5 · 8 — Kelly, Pruitt & Su 2019 가 본 1~6 과 Lettau & Pelger 의 5 안팎을 덮는 범위",
             "특성 축소": "평균 고윳값보다 큰 성분만 남긴다 — Kaiser 1960 https://doi.org/10.1177/001316446002000116 (남는 수 약 30 = Kelly, Pruitt & Su 2019 의 특성 36개와 비슷한 크기)",
             "RIDGE_GRID": "IPCA 횡단면 회귀의 능형 벌점 δ 후보(평균적인 달이 주는 횡단면 정보 대비 1% · 10% · 100%) — 근거 논문 없음 · 이 연구의 설계 선택 · 값은 창 안 검증이 고른다",
             "IPCA_ITER · IPCA_TOL": "번갈아 최소제곱의 최대 반복 500 · 수렴 기준 = 앞뒤 반복의 Γ 열 공간 거리(1 − 주각 코사인의 최솟값) 1e-6 — Kelly, Pruitt & Su 2019 의 기준(원소 최대 변화 1e-6)을 회전에 무관한 꼴로 옮긴 것"}
MODELS = {"pca": "LAT_PCA", "rppca": "LAT_RPPCA", "ipca": "LAT_IPCA"}
LATENT_BLOCKS = ["price", "flow", "macro", "cat", "val", "cons"]


def latent_features(store, cp):
    """잠재 모형의 특성 = 원자료 묶음 6개(가격 · 수급 · 거시 민감도 · 범주 · 가치 · 컨센서스)의 순위 + 기존 팩터의 카테고리 합성(구성원 순위 평균을 다시 순위화).
    특성 수를 표본 달 수보다 넉넉히 작게 둔다 — 617개 전부를 쓰면 로딩(특성 × 팩터 수)이 달 수에 비해 너무 많아 과적합된다.
    재무 변환 203개는 직접 넣지 않고 기존 팩터의 카테고리 합성(가치 · 수익성 · 성장 · 발생액 등)으로 대표한다."""
    import json
    import warnings
    cols, names = [], []
    for b in LATENT_BLOCKS:
        rk, nm = store.open(b, "rank")
        cols.append(np.asarray(rk)[cp.S, cp.J].astype(np.float32))
        names += nm
    ex, exn = store.open("existing", "rank")
    E = np.asarray(ex)[cp.S, cp.J].astype(np.float32)
    with open(ac.root() + "/02_Infrastructure/factor_db/factor_registry.json", encoding="utf-8") as fh:
        reg = json.load(fh)
    cat = [str((reg.get(n) or {}).get("category", "unregistered")) for n in exn]
    comp = []
    for c in sorted(set(cat)):
        idx = [i for i, x in enumerate(cat) if x == c]
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            v = np.nanmean(E[:, idx], axis=1)
        comp.append(cp.rank_pm1(v))
        names.append("xc_" + c)
    del E
    return np.concatenate(cols + [np.stack(comp, axis=1)], axis=1), names


def moments(Z, r, cp):
    """달마다 b_s = Z_s' r_s · 종목 수 n_s · A_s = Z_s' Z_s(수익이 있는 종목만). 배정밀도 — 단정밀도로 모으면 정규방정식에 잡음이 끼어 약한 방향이 반복마다 흔들린다."""
    ns, L = cp.f.ns, Z.shape[1]
    b, n, A = np.zeros((ns, L)), np.zeros(ns), np.zeros((ns, L, L))
    for s in range(ns):
        a0, a1 = cp.seg[s], cp.seg[s + 1]
        k = np.isfinite(r[a0:a1])
        if k.sum() < 30:
            continue
        Zs = Z[a0:a1][k].astype(np.float64)
        b[s], n[s], A[s] = Zs.T @ r[a0:a1][k], k.sum(), Zs.T @ Zs
    return b, n, A


def whiten(A, n, win):
    """추정 창의 합동 2차 적률 C = Σ A_s ÷ Σ n_s 를 고유분해해 평균 고윳값보다 큰 성분만 남기고 분산을 1 로 맞춘다.
    반환 T [L × M](z̃ = T'z 는 창 안에서 서로 직교 · 2차 적률 1) · C."""
    C = A[win].sum(0) / n[win].sum()
    w, V = np.linalg.eigh(C)
    keep = w > w.mean()
    o = np.argsort(-w[keep])
    return (V[:, keep] / np.sqrt(w[keep]))[:, o], C


def prep(A, b, n, win):
    """창의 적률을 백색화한 공간으로 옮긴다."""
    T, C = whiten(A, n, win)
    bt, nt = b[win] @ T, n[win]
    return {"T": T, "C": C, "A": T.T @ A[win] @ T, "b": bt, "n": nt, "X": bt / nt[:, None]}


def pca_fit(X, K, gamma):
    """관리 포트폴리오 수익 X [달 × 성분] → 고유벡터 [성분 × K]. gamma = −1 이면 공분산(보통의 PCA)."""
    xb = X.mean(0)
    w, V = np.linalg.eigh(X.T @ X / X.shape[0] + gamma * np.outer(xb, xb))
    return V[:, np.argsort(-w)[:K]]


def cs_regress(G, A, b, n, ridge):
    """달마다 횡단면 회귀 f_t = (Γ'A_tΓ + δ N_t I)^{-1} Γ'b_t [달 × K]. 능형 벌점 δ 의 단위 = 평균적인 달의 횡단면 정보(백색화한 노출의 2차 적률 N_t · I) 대비 비율."""
    K = G.shape[1]
    return np.linalg.solve(G.T @ A @ G + (ridge * n)[:, None, None] * np.eye(K), (b @ G)[:, :, None])[:, :, 0]


def ipca_fit(A, b, n, K, G0, ridge):
    """번갈아 최소제곱. A [달 × M × M] = Z̃'Z̃ · b [달 × M] = Z̃'r · n = 종목 수. 반환 Γ [M × K] · f [달 × K] · 반복 수 · 마지막 열 공간 거리.
    식별(Kelly, Pruitt & Su 2019 의 정규화): Γ'Γ = I 이고 팩터의 2차 적률 F'F/T 가 대각 · 내림차순 — 그래야 '첫째 · 둘째 … 잠재팩터' 가 정해진다.
    수렴은 앞뒤 반복의 Γ 열 공간 거리로 본다(1 − 주각 코사인의 최솟값). 열 하나하나를 비교하면 공간 안의 회전 때문에 수렴해도 값이 크게 남는다."""
    T, L = b.shape
    G, A2 = G0.copy(), A.reshape(T, L * L)
    iu = [(i, j) for i in range(K) for j in range(i, K)]
    d = 1.0
    for it in range(IPCA_ITER):
        F = cs_regress(G, A, b, n, ridge)
        # Γ 갱신: vec 순서 = (성분, 팩터) — Σ_t A_t ⊗ f f' 를 한 번의 행렬곱으로 모은다
        S = (np.stack([F[:, i] * F[:, j] for i, j in iu], axis=1).T @ A2).reshape(len(iu), L, L)
        H = np.zeros((L * K, L * K))
        for q, (i, j) in enumerate(iu):
            H[i::K, j::K] = S[q]
            if i != j:
                H[j::K, i::K] = S[q]
        H[np.diag_indices_from(H)] += EPS * np.trace(H) / (L * K)
        rhs = (b[:, :, None] * F[:, None, :]).sum(0).reshape(L * K)
        Gn = np.linalg.svd(np.linalg.solve(H, rhs).reshape(L, K), full_matrices=False)[0]   # 열 공간의 직교 정규 기저(Γ'Γ = I)
        d = float(1.0 - np.linalg.svd(Gn.T @ G, compute_uv=False).min())                    # 열 공간이 얼마나 바뀌었나(회전 · 부호 · 순서 무관)
        G = Gn
        if d < IPCA_TOL:
            break
    F = cs_regress(G, A, b, n, ridge)
    w, Q = np.linalg.eigh(F.T @ F / T)                                                      # 공간 안에서 돌려 팩터 2차 적률을 대각 · 내림차순으로
    Q = Q[:, np.argsort(-w)]
    return G @ Q, F @ Q, it + 1, d


def estimate(model, K, ridge, P):
    """백색화한 창 P 에서 모형을 추정 → Gf [L × K](원래 특성 공간의 로딩 · 노출 β = Z · Gf) · lam(팩터 평균 수익) · 반복 수 · 열 공간 거리.
    부호 = 그때까지의 평균 수익이 양수. 순서 = PCA 계열은 고윳값 순 · IPCA 는 팩터 2차 적률 순."""
    if model == "ipca":
        G, F, it, d = ipca_fit(P["A"], P["b"], P["n"], K, pca_fit(P["X"], K, RP_GAMMA), ridge)   # 출발값 = 위험프리미엄 PCA 의 고유벡터
    else:
        G = pca_fit(P["X"], K, -1.0 if model == "pca" else RP_GAMMA)
        F, it, d = P["X"] @ G, 0, 0.0                                                            # 팩터 수익 = 관리 포트폴리오 수익의 투영
    sg = np.where(F.mean(0) >= 0, 1.0, -1.0)
    return {"Gf": P["T"] @ (G * sg), "lam": (F * sg).mean(0), "it": it, "dist": d}


def port_weights(model, B, ridge):
    """잠재팩터 포트폴리오의 종목 비중 [K × 종목] — 노출 B [종목 × K] 에서. PCA 계열 = 특성 가중(노출 ÷ 종목 수) · IPCA = 능형 횡단면 회귀의 가중(순수 팩터 포트폴리오).
    둘 다 '노출 1 단위당 수익' 척도이고, 비중 · 수익의 곱이 그 달의 팩터 수익이다."""
    N, K = B.shape
    return np.linalg.solve(B.T @ B + ridge * N * np.eye(K), B.T) if model == "ipca" else B.T / N


def structure(Gf, C):
    """특성과 잠재팩터 노출의 상관 [L × K](창 안 합동 2차 적률 기준). 특성끼리 겹쳐 있어 계수보다 상관이 '무엇으로 이루어진 팩터인가' 를 더 잘 보여 준다."""
    CG = C @ Gf
    return CG / np.maximum(np.sqrt(np.outer(np.diag(C), np.einsum("lk,lk->k", Gf, CG))), 1e-300)


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="pca,rppca,ipca")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--smoke", action="store_true", help="두 해(2010 · 2011) · IPCA 반복 30 — 코드 경로 시험용")
    a = ap.parse_args()
    ac.SMOKE["on"] = a.smoke
    global IPCA_ITER
    if a.smoke:
        IPCA_ITER = 30
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
    X0, names = latent_features(store, cp)
    np.nan_to_num(X0, copy=False, nan=0.0)
    Z = np.concatenate([np.ones((cp.n, 1), dtype=np.float32), X0], axis=1)                 # 상수항(시장 전체) + 특성
    names = ["const"] + names
    del X0
    r = np.asarray(f.fwd(1))[cp.S, cp.J].astype(np.float64)
    b, n, A = moments(Z, r, cp)
    fp = "%s|v%d|%d" % (f.meta.get("rawdata_tag"), VERSION, Z.shape[1])
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    if a.smoke:
        sel_years = [2010, 2011]
    ac.stage_begin("pca_ipca", len(sel_years) * len(models), "재추정", 0.03, 0.9)
    ac.log("특성 %d개(상수항 포함) · 표본 %d칸 · 모형 %s", Z.shape[1], cp.n, ",".join(models))
    manifest, u = [], 0
    for m in models:
        score = np.full(cp.n, np.nan, dtype=np.float32)
        wts = [np.full(cp.n, np.nan, dtype=np.float32) for _ in range(N_PORT)]
        logs = []
        sse_tot, sse_pred, ss = 0.0, 0.0, 0.0
        combos = [(K, rd) for K in K_GRID for rd in (RIDGE_GRID if m == "ipca" else (0.0,))]
        for yy in sel_years:
            sY = dec[yy]
            nxt = list(range(sY, min(sY + 12, f.ns)))
            a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
            ck = "%s/%s_%d.npz" % (out_dir, m, yy)
            if os.path.exists(ck) and not a.force:
                z = ac.load_ckpt(ck, fp) or {"fp": ""}              # 읽자마자 닫는다(열어 두면 같은 파일을 다시 쓸 수 없다)
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
            P1 = prep(A, b, n, w1)                                                         # 검증용 추정은 앞 80% 달만으로(백색화 변환도)
            lo, hi = cp.seg[w2[0]], cp.seg[w2[-1] + 1]
            Zv = Z[lo:hi].astype(np.float64)
            val = {}
            for K, rd in combos:                                                           # 팩터 수(· 능형 벌점) 고르기 — 창 안 시간순 검증
                e = estimate(m, K, rd, P1)
                sc = np.full(cp.n, np.nan)
                sc[lo:hi] = Zv @ (e["Gf"] @ e["lam"])
                val[(K, rd)] = month_ic(sc, r, cp, w2)
            del Zv, P1
            K, rd = max(combos, key=lambda c: (val[c] if np.isfinite(val[c]) else -9, -c[0], c[1]))   # 같으면 팩터 수가 적고 벌점이 큰 쪽
            P = prep(A, b, n, win)
            e = estimate(m, K, rd, P)
            Gf, lam = e["Gf"], e["lam"]
            Zx = Z[a1:b1].astype(np.float64)
            Bx = Zx @ Gf                                                                   # 노출 [행 × K]
            sc = (Bx @ lam).astype(np.float32)
            score[a1:b1] = sc
            wz = np.full((N_PORT, b1 - a1), np.nan, dtype=np.float32)
            st, sp, s2 = 0.0, 0.0, 0.0
            for s in nxt:
                lo, hi = cp.seg[s] - a1, cp.seg[s + 1] - a1
                if hi - lo < 30:
                    continue
                wz[:, lo:hi] = port_weights(m, Bx[lo:hi], rd)[:N_PORT].astype(np.float32)   # 그 달 멤버 전체의 비중(수익은 아직 모른다)
                rs = r[a1 + lo:a1 + hi]
                kk = np.isfinite(rs)
                if kk.sum() >= 30:                                                         # 모형 설명력(표본 밖 달): 그 달 횡단면 회귀의 팩터 수익으로 · 그때까지의 평균 수익으로
                    Bk = Bx[lo:hi][kk]
                    fr = np.linalg.solve(Bk.T @ Bk + rd * kk.sum() * np.eye(K), Bk.T @ rs[kk]) if m == "ipca" else np.linalg.lstsq(Bk, rs[kk], rcond=None)[0]
                    st += float(((rs[kk] - Bk @ fr) ** 2).sum())
                    sp += float(((rs[kk] - Bk @ lam) ** 2).sum())
                    s2 += float((rs[kk] ** 2).sum())
            for k in range(N_PORT):
                wts[k][a1:b1] = wz[k]
            R = structure(Gf, P["C"])
            top = {}
            for k in range(min(N_PORT, K)):
                o = np.argsort(-np.abs(R[1:, k]))[:12] + 1                                 # 상수항을 뺀 상관 상위
                top["F%d" % (k + 1)] = [(names[i], round(float(R[i, k]), 3)) for i in o]
            lg = {"model": m, "year": yy, "K": int(K), "ridge": float(rd), "M": int(P["T"].shape[1]), "months": int(len(win)),
                  "val_ic": {("%d" % k if m != "ipca" else "%d|%g" % (k, d)): round(v, 5) for (k, d), v in val.items()},
                  "lambda": [round(float(x), 6) for x in lam], "const_corr": [round(float(x), 3) for x in R[0, :min(N_PORT, K)]],
                  "iterations": int(e["it"]), "space_dist": float(e["dist"]), "converged": bool(m != "ipca" or e["dist"] < IPCA_TOL),
                  "loadings_top": top, "sse_total": st, "sse_pred": sp, "ss": s2, "seconds": round(time.time() - t0, 1)}

            def _save(path, sc=sc, wz=wz, lg=lg):
                with open(path, "wb") as fh:
                    np.savez(fh, fp=fp, score=sc, wts=wz, log=np.array(lg, dtype=object))
            ac.write_atomic(ck, _save)
            logs.append(lg)
            sse_tot, sse_pred, ss = sse_tot + st, sse_pred + sp, ss + s2
            u += 1
            best = sorted(val.items(), key=lambda kv: -(kv[1] if np.isfinite(kv[1]) else -9))[:3]
            ac.log("%s %d년 — K %d%s · 성분 %d · 검증 IC 상위 %s%s · %.0f초", m, yy, K, " · δ %g" % rd if m == "ipca" else "", P["T"].shape[1],
                   " ".join(("%d" % k if m != "ipca" else "%d|%g" % (k, d)) + ":%.3f" % v for (k, d), v in best),
                   " · 반복 %d(열 공간 거리 %.0e)" % (e["it"], e["dist"]) if m == "ipca" else "", time.time() - t0)
            ac.stage_unit(u, "%s %d년 재추정 끝" % (m, yy))
        S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
        S[cp.S, cp.J] = score
        p = ac.out(ac.smoke_name("factors")) + "/%s.parquet" % MODELS[m]
        ac.save_factor_panel(p, MODELS[m], S, f)
        label = {"pca": "PCA", "rppca": "위험프리미엄 PCA", "ipca": "IPCA"}[m]
        manifest.append({"id": MODELS[m], "path": p, "direction": 1, "kind": "score", "method": "잠재팩터 · " + label, "desc": "종목 기대수익 점수 = 잠재팩터 노출 × 그때까지의 팩터 평균 수익"})
        how = "순수 팩터 포트폴리오(횡단면 회귀의 가중)" if m == "ipca" else "특성 가중 포트폴리오(노출 ÷ 종목 수)"
        for k in range(N_PORT):
            Wm = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
            Wm[cp.S, cp.J] = wts[k]
            nm = "%s_F%d" % (MODELS[m], k + 1)
            pw = out_dir + "/%s.parquet" % nm
            ac.save_factor_panel(pw, nm, Wm, f)
            manifest.append({"id": nm, "path": pw, "direction": 1, "kind": "weights", "method": "잠재팩터 · " + label, "desc": "%d번째 잠재팩터의 종목 비중 — %s · 노출 1 단위당 수익" % (k + 1, how)})
        r2 = {"total_r2": round(1 - sse_tot / ss, 5) if ss > 0 else None, "pred_r2": round(1 - sse_pred / ss, 6) if ss > 0 else None}
        ac.write_json({"model": m, "r2_oos": r2, "not_converged": [lg["year"] for lg in logs if not lg.get("converged", True)], "retrains": logs}, res_dir + "/model_log_%s.json" % m)
        ac.log("%s — 표본 밖 전체 R² %s · 예측 R² %s", m, r2["total_r2"], r2["pred_r2"])
    ac.write_json({"at": ac._now(), "stage": "pca_ipca", "factors": manifest,
                   "params": {"K_GRID": K_GRID, "RIDGE_GRID": RIDGE_GRID, "VAL_FRAC": VAL_FRAC, "RP_GAMMA": RP_GAMMA, "IPCA_ITER": IPCA_ITER, "IPCA_TOL": IPCA_TOL, "_source": PARAM_SRC}},
                  ac.out(ac.smoke_name("manifest_latent") + ".json"))
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
