"""aif_riskcov.py — 위험 평가 모형 2부: 팩터 공분산 · 종목 고유 위험(FOLLOWUP_PLAN.md '위험 평가 모형' · USE4 방법론 노트 4 · 5장 — paper_notes/barra_use4_2011.md 5 · 6절).

1부(aif_riskmodel.py)가 남긴 일별 순수 팩터 수익과 고유수익으로, 신호일(월말)마다 그날까지의 값만 써서 다음 보유월의 위험 예측 재료를 만든다.
모형 둘(본 모형 16개 · 대조 판 17개 — 1부의 MODELS) × 판 둘(반응형 S · 안정형 L — USE4 표 4.1 · 5.1 의 값).
  cov   팩터 공분산 F0 = 상관(반감기 504일 · Newey–West 시차 2) × 변동성(반감기 84 / 252일 · 시차 5)
  eig   고유팩터 위험 조정 — F0 의 고유팩터마다 모의실험으로 변동성 편향 v(k)를 구해 곱한다(부록 B 의 B1~B7 · B9 · B10 — 생산판과 같은 모의판 · 배율판 B8 은 쓰지 않는다)
  vra   변동성 국면 조정 — 팩터 횡단면 편향 통계의 지수 가중 평균(반감기 42 / 168일)으로 전체 수준을 맞추는 배수 λ_F
  spec  종목 고유 위험 — 고유수익의 지수 가중 변동성(반감기 84 / 252일) × 계열상관 조정(시차 5 · 자기상관 반감기 252일) → 구조 모형과 혼합
        → 규모 10분위 안 베이즈 축소(q = 0.1) → 국면 조정 λ_S
값은 모두 하루 단위다. 달 단위 예측 = 하루 분산 × 그 보유월의 거래일 수(3부에서 곱한다 — 원문에 변환식이 없다 · 계열상관은 Newey–West 가 반영).
최종 예측(3부가 쓰는 것): 팩터 공분산 = λ_F² × Feig · 종목 고유 변동성 = λ_S × sp_sh. 조정을 하나씩 켠 판을 견줄 수 있게 단계마다의 값을 따로 남긴다.
미래참조: 신호일 s 의 값은 날짜 위치 <= sig_idx[s] 인 일별 값만 쓴다(그날 종가까지 — 그 일별 값은 그 전 신호일의 노출로 낸 것이다).
  --check 가 그 뒤의 일별 값을 잘라 낸 입력으로 다시 만든 값과 같은지 본다.
원문과 다르게 둔 곳 · 정한 값(README '위험 평가 모형 2부'에 표로 적는다):
  결측 팩터 수익(늦게 시작한 스타일의 앞 구간)은 원문의 EM 대신 쌍별 공통 구간으로 상관을 내고 고유값을 잘라 양반정치를 맞춘다 ·
  추정 창 = 상관 반감기의 6배(3,024일 — 그 앞의 가중 합 1.6%) · 모의 이력 길이 = 그 창의 길이 · 모의 횟수 100 ·
  팩터가 공분산에 들어오는 관측 하한 252일 · 하루 예측 변동성(국면 조정의 분모)은 계열상관 조정 없는 지수 가중 표준편차(관측 60일부터) ·
  혼합 계수 γ = min(1, max(0, (h − 60) ÷ 120)) × min(1, max(0, exp(1 − Z))) (h = 최근 252일의 유효 관측 수 · Z = |표준편차 ÷ 강건 표준편차 − 1| ·
    강건 표준편차 = 사분위 범위 ÷ 1.35 — Barra 의 다른 모형 문서에서 Q 가 기억하는 식이고 문서로 확인하지 못했다) ·
  구조 모형의 회귀 가중 = √시총 · E0 = 적합 표본의 exp(잔차) 가중 평균 · 계열상관 조정 배수의 하한 0.2 ·
  고유 위험의 국면 조정에 쓰는 하루 예측 변동성 = 축소 · 혼합 전의 지수 가중 표준편차(원문은 축소 뒤 값에서 계열상관 조정을 뺀 것) ·
  고유 국면 조정의 횡단면 가중 = 시총(원문) — 시총이 한 종목에 몰린 시장이라 √시총 가중 판(lamS_sqrt)도 함께 남긴다.
산출(.cache/aif_research/followup/risk/): cov_<모형>_<판>.npz + results/followup/risk/cov_checks.json · stage_summary_nl_risk.json(텔레그램 결과 통)
실행: python py/aif_riskcov.py [--force] [--check] [--smoke] [--only main:L]     (감시 셸: ops/aif_run.py --track followup --job nl_risk --stage nl_risk)
"""
import argparse
import os
import sys
import time
import warnings

import numpy as np

import aif_common as ac
import aif_riskmodel as rm

F32 = np.float32
VERSION = 2                                 # 2 = 하루 예측 변동성의 충분 조건을 '최근의 유효 가중'으로(전체 관측 수로 보면 오래 쉬었다 돌아온 종목이 관측 한두 개로 통과한다)
STAGE, PART_FROM, PART_TO = "nl_risk", 0.40, 0.75
# ── USE4 방법론 노트 표 4.1 · 5.1(단위 = 거래일) ───────────────────────────────────────────────────────
VARIANTS = {"S": dict(vol_hl=84, vol_lag=5, cor_hl=504, cor_lag=2, vra_hl=42, sp_hl=84, sp_lag=5, sp_ac_hl=252, q=0.1),
            "L": dict(vol_hl=252, vol_lag=5, cor_hl=504, cor_lag=2, vra_hl=168, sp_hl=252, sp_lag=5, sp_ac_hl=252, q=0.1)}
VARIANT_KO = {"S": "반응형", "L": "안정형"}
# ── 정한 값(원문에 수치가 없다) ────────────────────────────────────────────────────────────────────────
WIN_F = 6 * 504                             # 팩터 공분산의 추정 창 · 모의 이력의 길이
WIN_S = 6 * 252                             # 고유 위험의 추정 창
MIN_OBS_F = 252                             # 팩터가 공분산에 들어오는 데 필요한 일별 관측 수(창 안)
MIN_OBS_D = 60                              # 하루 예측 변동성을 내는 데 필요한 관측 — 최근 60일이 다 있을 때의 지수 가중 합 이상(유효 가중으로 본다)
MIN_FAC_B = 10                              # 팩터 횡단면 편향 통계를 내는 데 필요한 팩터 수
N_SIM = 100                                 # 고유팩터 모의 횟수(계획)
EPS_EIG = 1e-10                             # 상관 행렬의 고유값 하한(양반정치 맞추기)
NW_FLOOR = 0.2                              # 계열상관 조정 배수(분산 단위)의 하한
GAMMA_WIN, GAMMA_H0, GAMMA_H1 = 252, 60, 120
N_DECILE = 10
SEED = 20261123


def RK(*parts):
    return ac.out("followup", ac.smoke_name("risk"), *parts)


# ── 추정기 ───────────────────────────────────────────────────────────────────────────────────────────
def wts(T, hl):
    """지수 가중(오래된 날 → 최근 · 최근 = 1)."""
    return 0.5 ** (np.arange(T - 1, -1, -1) / float(hl))


def _centered(Y, w):
    """계열마다 자기 가중 평균을 뺀 값(결측 = 0) · 있음 표시."""
    M = np.isfinite(Y)
    if M.all():
        return Y - (w @ Y) / w.sum(), None
    Z = np.where(M, Y, 0.0)
    with np.errstate(all="ignore"):
        mu = (w @ Z) / (w @ M)
    return np.where(M, Y - mu, 0.0), M.astype(np.float64)


def nw_var(Y, w, lag):
    """계열마다의 Newey–West 분산(바틀렛 가중 1 − l ÷ (lag + 1) · 지수 가중 w · 결측은 건너뜀) — 돌려주는 것: 조정한 분산 · 시차 0 의 분산."""
    Zc, M = _centered(Y, w)
    with np.errstate(all="ignore"):
        g0 = (w @ (Zc * Zc)) / (w.sum() if M is None else (w @ M))
        v = g0.copy()
        for l in range(1, lag + 1):
            num = w[l:] @ (Zc[l:] * Zc[:-l])
            den = w[l:].sum() if M is None else (w[l:] @ (M[l:] * M[:-l]))
            v = v + 2.0 * (1.0 - l / (lag + 1.0)) * np.where(den > 0, num / den, 0.0)
    return np.where(v > 0, v, g0), g0


def nw_cov(Y, w, lag):
    """Newey–West 공분산 행렬(바틀렛 가중 · 지수 가중 w). 결측이 있으면 쌍마다 둘 다 있는 날로 낸다."""
    Zc, M = _centered(Y, w)
    Zw = Zc * w[:, None]
    with np.errstate(all="ignore"):
        if M is None:
            G0 = (Zw.T @ Zc) / w.sum()
            C = G0.copy()
            for l in range(1, lag + 1):
                G = (Zw[l:].T @ Zc[:-l]) / w[l:].sum()
                C += (1.0 - l / (lag + 1.0)) * (G + G.T)
        else:
            Mw = M * w[:, None]
            G0 = (Zw.T @ Zc) / (Mw.T @ M)
            C = G0.copy()
            for l in range(1, lag + 1):
                G = (Zw[l:].T @ Zc[:-l]) / (Mw[l:].T @ M[:-l])
                G = np.where(np.isfinite(G), G, 0.0)
                C += (1.0 - l / (lag + 1.0)) * (G + G.T)
    return C if (np.diag(C) > 0).all() else G0


def psd_corr(R):
    """상관 행렬을 양반정치로 맞춘다(고유값을 하한에서 자르고 대각을 1 로) — 돌려주는 것: 행렬 · 자르기 전 가장 작은 고유값."""
    ev, U = np.linalg.eigh(R)
    lo = float(ev[0])
    if lo < EPS_EIG:
        R = (U * np.maximum(ev, EPS_EIG)) @ U.T
        d = np.sqrt(np.diag(R))
        R = R / np.outer(d, d)
    return R, lo


def fcov(Y, par):
    """팩터 공분산(하루 단위) = 상관(반감기 cor_hl · 시차 cor_lag) × 변동성(반감기 vol_hl · 시차 vol_lag) — 돌려주는 것: 행렬 · 상관의 가장 작은 고유값(자르기 전)."""
    T = len(Y)
    var, _ = nw_var(Y, wts(T, par["vol_hl"]), par["vol_lag"])
    C = nw_cov(Y, wts(T, par["cor_hl"]), par["cor_lag"])
    d = np.sqrt(np.diag(C))
    R, lo = psd_corr(C / np.outer(d, d))
    s = np.sqrt(var)
    return R * np.outer(s, s), lo


def eigen_adjust(F0, T, par, rng, n_sim):
    """고유팩터 위험 조정(USE4 부록 B 의 모의판). F0 을 참 공분산으로 두고 길이 T 의 정규 수익 이력을 n_sim 번 모의해, 같은 추정기로 낸 공분산의
    고유팩터가 실제로 갖는 분산 ÷ 추정된 분산의 평균을 고유팩터마다 구한다(v² — 고유값이 작은 것부터). 돌려주는 것: 조정한 공분산 · v."""
    d0, U0 = np.linalg.eigh(F0)
    d0 = np.maximum(d0, EPS_EIG * d0[-1])
    sd, acc = np.sqrt(d0), np.zeros(len(d0))
    for _ in range(n_sim):
        f = (rng.standard_normal((T, len(d0))) * sd) @ U0.T
        Fm, _ = fcov(f, par)
        dm, Um = np.linalg.eigh(Fm)
        acc += ((F0 @ Um) * Um).sum(0) / np.maximum(dm, 1e-300)
    v = np.sqrt(acc / n_sim)
    return (U0 * (v * v * d0)) @ U0.T, v


def min_weight(hl, min_obs):
    """최근 min_obs 일이 다 있을 때의 지수 가중 합 — 하루 예측 변동성을 낼 만큼 최근 관측이 쌓였는지의 기준."""
    lam = 0.5 ** (1.0 / hl)
    return (1.0 - lam ** min_obs) / (1.0 - lam)


def ew_sigma_daily(Y, hl, min_obs):
    """날마다의 하루 예측 변동성 [T × K] — 그 전날까지의 지수 가중 표준편차(평균 차감 · 계열상관 조정 없음). 최근의 유효 가중이 min_weight 에 못 미치면 NaN."""
    T, K = Y.shape
    lam, wmin = 0.5 ** (1.0 / hl), min_weight(hl, min_obs)
    s0, s1, s2 = np.zeros(K), np.zeros(K), np.zeros(K)
    out = np.full((T, K), np.nan)
    for t in range(T):
        with np.errstate(all="ignore"):
            var = s2 / s0 - (s1 / s0) ** 2
        out[t] = np.where((s0 >= wmin) & (var > 0), np.sqrt(var), np.nan)
        m = np.isfinite(Y[t])
        x = np.where(m, Y[t], 0.0)
        s0, s1, s2 = lam * s0 + m, lam * s1 + x, lam * s2 + x * x
    return out


def ew_mean_daily(b2, hl):
    """b2 [T](결측 NaN)의 지수 가중 평균 — 날마다 그날까지 [T]."""
    lam = 0.5 ** (1.0 / hl)
    a = w = 0.0
    out = np.full(len(b2), np.nan)
    for t, x in enumerate(b2):
        a, w = a * lam, w * lam
        if np.isfinite(x):
            a, w = a + x, w + 1.0
        if w > 0:
            out[t] = a / w
    return out


def factor_b2(FD, hl):
    """팩터 횡단면 편향 통계의 제곱 B_t² [T] = 그날 팩터들의 (수익 ÷ 하루 예측 변동성)² 평균(USE4 식 4.3)."""
    sig = ew_sigma_daily(FD, hl, MIN_OBS_D)
    with np.errstate(all="ignore"), warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        z2 = (FD / sig) ** 2
        b2 = np.nanmean(z2, axis=1)
    return np.where(np.isfinite(z2).sum(1) >= MIN_FAC_B, b2, np.nan)


def spec_b2(U, hl, sig_of_day, EST, CAP):
    """고유 횡단면 편향 통계의 제곱 [T] 두 가지 — 시총 가중(USE4 식 5.10) · √시총 가중. 그날이 속한 보유월의 추정 유니버스와 그 신호일의 시총을 쓴다."""
    T, N = U.shape
    lam, wmin = 0.5 ** (1.0 / hl), min_weight(hl, MIN_OBS_D)
    s0, s1, s2 = np.zeros(N), np.zeros(N), np.zeros(N)
    out = np.full((T, 2), np.nan)
    for t in range(T):
        u = U[t].astype(np.float64)
        m = np.isfinite(u)
        i = sig_of_day[t]
        if i >= 0:
            with np.errstate(all="ignore"):
                var = s2 / s0 - (s1 / s0) ** 2
            ok = m & EST[i] & (s0 >= wmin) & (var > 0)
            if ok.sum() >= rm.MIN_EST:
                z2, c = u[ok] ** 2 / var[ok], CAP[i][ok]
                out[t] = np.dot(c, z2) / c.sum(), np.dot(np.sqrt(c), z2) / np.sqrt(c).sum()
        x = np.where(m, u, 0.0)
        s0, s1, s2 = lam * s0 + m, lam * s1 + x, lam * s2 + x * x
    return out


def spec_ts(Uw, par):
    """고유 변동성의 시계열 추정 [N](하루 단위) · 혼합 계수 γ [N]. Uw = 창 [T × N](결측 NaN · 마지막 행 = 신호일)."""
    T = len(Uw)
    U = Uw.astype(np.float64)
    M = np.isfinite(U)
    Mf = M.astype(np.float64)
    ws, wa = wts(T, par["sp_hl"]), wts(T, par["sp_ac_hl"])
    Z0 = np.where(M, U, 0.0)
    with np.errstate(all="ignore"), warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        Zs = np.where(M, U - (ws @ Z0) / (ws @ Mf), 0.0)
        var = (ws @ (Zs * Zs)) / (ws @ Mf)                                                   # 지수 가중 분산(반감기 sp_hl)
        Za = np.where(M, U - (wa @ Z0) / (wa @ Mf), 0.0)
        a0 = (wa @ (Za * Za)) / (wa @ Mf)
        c = np.ones(U.shape[1])
        for l in range(1, par["sp_lag"] + 1):                                                # 계열상관 조정: 1 + 2 Σ (1 − l ÷ (L + 1)) ρ_l — 자기상관은 반감기 sp_ac_hl 로
            den = wa[l:] @ (Mf[l:] * Mf[:-l])
            rho = np.where((den > 0) & (a0 > 0), (wa[l:] @ (Za[l:] * Za[:-l])) / den / a0, 0.0)
            c += 2.0 * (1.0 - l / (par["sp_lag"] + 1.0)) * rho
        h = M[-GAMMA_WIN:].sum(0)                                                            # 최근 252일의 유효 관측 수
        ts = np.where((h > GAMMA_H0) & (var > 0), np.sqrt(var * np.maximum(c, NW_FLOOR)), np.nan)
        last = np.where(M[-GAMMA_WIN:], U[-GAMMA_WIN:], np.nan)
        q1, q3 = np.nanpercentile(last, [25, 75], axis=0)
        rob = (q3 - q1) / 1.35
        zt = np.abs(np.nanstd(last, axis=0, ddof=1) / rob - 1.0)
        gam = np.clip((h - GAMMA_H0) / float(GAMMA_H1), 0.0, 1.0) * np.clip(np.exp(1.0 - zt), 0.0, 1.0)
    return ts, np.where(np.isfinite(ts) & np.isfinite(gam), gam, 0.0)


def structural(ts, gam, Xi, sec_i, est_i, cap_i, n_sec):
    """구조 모형(USE4 식 5.3 · 5.4): γ = 1 인 추정 유니버스 종목으로 ln(시계열 변동성)을 업종 · 스타일 노출에 회귀(√시총 가중) → 노출이 다 있는 모든 종목의 예측."""
    ks = np.nonzero(np.isfinite(Xi[est_i]).any(0))[0]
    full = np.isfinite(Xi[:, ks]).all(1) & (sec_i >= 0)
    ix = np.nonzero(full)[0]
    Xd = np.zeros((len(ix), n_sec + len(ks)))
    Xd[np.arange(len(ix)), sec_i[ix].astype(np.int64)] = 1.0
    Xd[:, n_sec:] = Xi[ix][:, ks]
    fit = est_i[ix] & (gam[ix] >= 1.0) & np.isfinite(ts[ix]) & (cap_i[ix] > 0)
    out = np.full(len(ts), np.nan)
    if fit.sum() < 2 * Xd.shape[1]:
        return out, np.nan, int(fit.sum())
    v = np.sqrt(cap_i[ix][fit])
    y = np.log(ts[ix][fit])
    b = np.linalg.lstsq(Xd[fit] * np.sqrt(v)[:, None], y * np.sqrt(v), rcond=None)[0]
    pred = Xd @ b
    e0 = float(np.dot(v, np.exp(y - pred[fit])) / v.sum())                                   # 잔차를 지수로 되돌릴 때의 편향 보정(1 보다 조금 크다)
    out[ix] = e0 * np.exp(pred)
    return out, e0, int(fit.sum())


def shrink(sig, cap, est, q):
    """베이즈 축소(USE4 식 5.6~5.9): 추정 유니버스의 규모 10분위마다 시총 가중 평균 쪽으로 — 평균에서 멀수록 더 당긴다. 돌려주는 것: 축소한 값 · 당긴 비중 v."""
    ok = np.isfinite(sig) & (cap > 0)
    base = ok & est
    out, vn = sig.copy(), np.zeros(len(sig))
    if base.sum() < N_DECILE * 5:
        return out, vn
    dec = np.searchsorted(np.quantile(cap[base], np.arange(1, N_DECILE) / N_DECILE), cap, side="right")
    for s in range(N_DECILE):
        b = base & (dec == s)
        if b.sum() < 2:
            continue
        mbar = np.dot(cap[b], sig[b]) / cap[b].sum()
        dlt = np.sqrt(np.mean((sig[b] - mbar) ** 2))
        k = ok & (dec == s)
        dev = np.abs(sig[k] - mbar)
        vn[k] = q * dev / (dlt + q * dev) if dlt > 0 else 0.0
        out[k] = vn[k] * mbar + (1.0 - vn[k]) * sig[k]
    return out, vn


# ── 한 모형 · 한 판 ──────────────────────────────────────────────────────────────────────────────────
class Inputs:
    """1부의 산출과 공통 틀에서 2부가 쓰는 것. cut = 날짜 위치 — 주면 그 뒤의 일별 값을 잘라 낸다(자가 시험)."""

    def __init__(self, f, model, cut=None):
        sfx = "" if model == "main" else "_" + model
        with np.load(RK("reg%s.npz" % sfx), allow_pickle=True) as z:
            self.factors, self.FD = [str(x) for x in z["factors"]], np.array(z["fd"], dtype=np.float64)
        self.U = np.load(RK("spec_daily%s.npy" % sfx), mmap_mode="r")
        with np.load(RK("expo.npz"), allow_pickle=True) as z:
            styles = [str(x) for x in z["styles"]]
            self.X = np.array(z["X"][:, :, [styles.index(s) for s in rm.MODELS[model]]])
            self.EST = np.array(z["EST"])
        with np.load(RK("desc.npz"), allow_pickle=True) as z:
            lncap = np.array(z["D"][:, :, [str(x) for x in z["names"]].index("LNCAP")], dtype=np.float64)
        self.CAP = np.where(np.isfinite(lncap), np.exp(lncap), 0.0)                          # 신호일 시가총액 [신호 × 종목]
        self.sector = np.load(f.path + "/sector.npy")
        self.n_sec = len(ac.read_json(f.path + "/sector.json")["names"])
        self.S = self.X.shape[0]
        self.sig_idx = f.sig_idx[: self.S]
        if cut is not None:
            self.FD, self.U = self.FD[: cut + 1], self.U[: cut + 1]
        self.T = len(self.FD)
        sod = np.full(self.T, -1, dtype=np.int64)                                            # 그날이 속한 보유월의 신호 번호
        for i in range(self.S):
            if f.hold_a[i] < self.T and self.EST[i].any():
                sod[f.hold_a[i]: min(f.hold_b[i], self.T - 1) + 1] = i
        self.sig_of_day = sod


def daily_series(I, par):
    """날마다의 국면 배수(제곱) — 팩터 λ_F² · 고유 λ_S²(시총 가중 · √시총 가중) [T]."""
    bF = factor_b2(I.FD, par["vol_hl"])
    bS = spec_b2(I.U, par["sp_hl"], I.sig_of_day, I.EST, I.CAP)
    return {"b2F": bF, "b2S": bS[:, 0], "b2S_sqrt": bS[:, 1], "lamF2": ew_mean_daily(bF, par["vra_hl"]),
            "lamS2": ew_mean_daily(bS[:, 0], par["vra_hl"]), "lamS2_sqrt": ew_mean_daily(bS[:, 1], par["vra_hl"])}


def blank(P, N):
    """신호 하나의 빈 결과(값을 못 낸 신호 · 건너뛴 신호)."""
    return {"F0": np.full((P, P), np.nan, F32), "Feig": np.full((P, P), np.nan, F32), "v_eig": np.full(P, np.nan, F32), "present": np.zeros(P, bool), "psd_min": np.nan,
            "sp_ts": np.full(N, np.nan, F32), "sp_gamma": np.zeros(N, F32), "sp_str": np.full(N, np.nan, F32), "sp_blend": np.full(N, np.nan, F32),
            "sp_sh": np.full(N, np.nan, F32), "sp_v": np.zeros(N, F32), "e0": np.nan, "n_fit": 0}


def at_signal(I, par, i, seed, n_sim):
    """신호 i 의 팩터 공분산(조정 전 · 고유팩터 조정 뒤)과 종목 고유 위험(단계마다). 그 신호일까지의 일별 값만 쓴다."""
    r = int(I.sig_idx[i])
    o = blank(I.FD.shape[1], I.U.shape[1])
    if r >= I.T:
        return o
    Y = I.FD[max(0, r + 1 - WIN_F): r + 1]
    pres = np.isfinite(Y).sum(0) >= MIN_OBS_F
    if pres.sum() >= 2:
        F0, lo = fcov(Y[:, pres], par)
        Fe, v = eigen_adjust(F0, len(Y), par, np.random.default_rng([seed, i]), n_sim)
        ix = np.ix_(pres, pres)
        o["F0"][ix], o["Feig"][ix], o["present"], o["psd_min"] = F0, Fe, pres, lo
        o["v_eig"][: len(v)] = v
    if not I.EST[i].any():
        return o
    ts, gam = spec_ts(np.asarray(I.U[max(0, r + 1 - WIN_S): r + 1]), par)
    stru, e0, nfit = structural(ts, gam, I.X[i].astype(np.float64), I.sector[i], I.EST[i], I.CAP[i], I.n_sec)
    blend = np.where(gam >= 1.0, ts, np.where(np.isfinite(stru), np.where(np.isfinite(ts), gam * ts + (1.0 - gam) * stru, stru), np.where(gam > 0, ts, np.nan)))
    sh, vn = shrink(blend, I.CAP[i], I.EST[i], par["q"])
    o.update(sp_ts=ts.astype(F32), sp_gamma=gam.astype(F32), sp_str=stru.astype(F32), sp_blend=blend.astype(F32), sp_sh=sh.astype(F32), sp_v=vn.astype(F32), e0=e0, n_fit=nfit)
    return o


def seed_of(model, variant):
    """모의실험의 씨앗(모형 · 판마다 · 신호 번호는 부르는 쪽이 더한다) — 자르기 시험이 같은 난수로 다시 계산한다."""
    return SEED + 1000 * list(rm.MODELS).index(model) + list(VARIANTS).index(variant)


SIG_KEYS = ("F0", "Feig", "v_eig", "present", "psd_min", "sp_ts", "sp_gamma", "sp_str", "sp_blend", "sp_sh", "sp_v", "e0", "n_fit")


def run_one(f, model, variant, sel, n_sim, unit=None):
    par = VARIANTS[variant]
    I = Inputs(f, model)
    seed = seed_of(model, variant)
    dly = daily_series(I, par)
    rows = []
    for i in range(I.S):
        rows.append(at_signal(I, par, i, seed, n_sim) if (sel is None or i in sel) else blank(I.FD.shape[1], I.U.shape[1]))   # sel = 시험 실행에서 계산할 신호
        if unit:
            unit(i + 1, I.S)
    res = {k: np.stack([np.asarray(x[k]) for x in rows]) for k in SIG_KEYS}
    res.update(daily_at_signals(I, dly), factors=np.array(I.factors))
    return I, res


def daily_at_signals(I, dly):
    """날마다 이어 간 국면 배수를 신호일에서 읽은 값 + 날마다의 횡단면 편향 통계(진단용)."""
    at = lambda a: np.where(I.sig_idx < I.T, a[np.minimum(I.sig_idx, I.T - 1)], np.nan)        # noqa: E731 — 신호일의 값
    return dict(lamF=np.sqrt(at(dly["lamF2"])), lamS=np.sqrt(at(dly["lamS2"])), lamS_sqrt=np.sqrt(at(dly["lamS2_sqrt"])), b2F=dly["b2F"], b2S=dly["b2S"], b2S_sqrt=dly["b2S_sqrt"])


def redo_daily(f, model, variant, path):
    """저장분의 신호별 값(공분산 · 고유 위험)은 그대로 두고 국면 배수만 다시 만든다 — 신호별 값은 날마다의 계열에 기대지 않는다."""
    with np.load(path, allow_pickle=True) as z:
        res = {k: z[k] for k in z.files if k != "fp"}
    I = Inputs(f, model)
    res.update(daily_at_signals(I, daily_series(I, VARIANTS[variant])))
    return I, res


def truncation_check(f, model, variant, res, at, n_sim):
    """신호일 뒤의 일별 값을 잘라 낸 입력으로 다시 만든 값이 같은가(신호 번호 at 들에서) — 날마다 이어 가는 국면 배수까지 본다."""
    par = VARIANTS[variant]
    seed = seed_of(model, variant)
    out = []
    for i in at:
        I2 = Inputs(f, model, cut=int(f.sig_idx[i]))
        o = at_signal(I2, par, i, seed, n_sim)
        d2 = daily_series(I2, par)
        diff = 0.0
        for k in ("F0", "Feig", "sp_ts", "sp_str", "sp_blend", "sp_sh"):
            a, b = np.asarray(o[k], dtype=np.float64), np.asarray(res[k][i], dtype=np.float64)
            if not np.array_equal(np.isfinite(a), np.isfinite(b)):
                diff = np.inf
            elif np.isfinite(a).any():
                sc = np.nanmax(np.abs(b))
                diff = max(diff, float(np.nanmax(np.abs(a - b)) / sc))
        for k, kk in (("lamF2", "lamF"), ("lamS2", "lamS"), ("lamS2_sqrt", "lamS_sqrt")):
            a, b = np.sqrt(d2[k][-1]), res[kk][i]
            if np.isfinite(a) != np.isfinite(b):
                diff = np.inf
            elif np.isfinite(a):
                diff = max(diff, abs(float(a - b)) / abs(float(b)))
        out.append({"signal": str(f.sig_dates[i]), "max_rel_diff": diff})
        ac.log("자르기 시험 %s:%s %s — 상대 차이 %.3g", model, variant, str(f.sig_dates[i]), diff)
    return out


def describe(f, I, res, is_end):
    """요약(표본 안 신호일만) — 모형의 성질을 적는 값이고 성과가 아니다."""
    ok = (f.sig_dates[: I.S] <= is_end) & res["present"].any(1)
    ix = np.nonzero(ok)[0]
    ann = np.sqrt(252.0)
    K = res["present"][ix].sum(1)
    v = res["v_eig"][ix]
    vol = np.sqrt(np.stack([np.diag(res["Feig"][i]) for i in ix])) * res["lamF"][ix][:, None] * ann     # 최종 예측의 팩터 변동성(연)
    n_sec = I.n_sec
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        est = I.EST[ix]
        sp = res["sp_sh"][ix] * res["lamS"][ix][:, None] * ann
        d = {"signals": int(len(ix)), "first": str(f.sig_dates[ix[0]]), "factors_min": int(K.min()), "factors_max": int(K.max()),
             "psd_repaired_share": float(np.mean(res["psd_min"][ix] < EPS_EIG)), "psd_min_worst": float(np.nanmin(res["psd_min"][ix])),
             "eig_bias_smallest": float(np.nanmean(v[:, 0])), "eig_bias_largest": float(np.nanmean([v[a, K[a] - 1] for a in range(len(ix))])),
             "eig_bias_mean": float(np.nanmean(v)),
             "market_vol_ann": float(np.nanmean(vol[:, 0])), "industry_vol_ann": float(np.nanmean(vol[:, 1:1 + n_sec])), "style_vol_ann": float(np.nanmean(vol[:, 1 + n_sec:])),
             "lamF_p05_p50_p95": [float(x) for x in np.nanpercentile(res["lamF"][ix], [5, 50, 95])],
             "lamS_p05_p50_p95": [float(x) for x in np.nanpercentile(res["lamS"][ix], [5, 50, 95])],
             "lamS_sqrt_p05_p50_p95": [float(x) for x in np.nanpercentile(res["lamS_sqrt"][ix], [5, 50, 95])],
             "spec_vol_ann_median_estu": float(np.nanmedian(np.where(est, sp, np.nan))),
             "gamma1_share_estu": float(np.mean([np.mean(res["sp_gamma"][i][I.EST[i]] >= 1.0) for i in ix])),
             "structural_only_share_estu": float(np.mean([np.mean(res["sp_gamma"][i][I.EST[i]] <= 0.0) for i in ix])),
             "covered_with_spec_mean": float(np.mean([np.isfinite(res["sp_sh"][i]).sum() for i in ix])),
             "shrink_weight_mean_estu": float(np.mean([np.mean(res["sp_v"][i][I.EST[i]]) for i in ix])),
             "e0_mean": float(np.nanmean(res["e0"][ix]))}
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--check", action="store_true", help="자르기 시험(세 신호일)을 함께 돌린다")
    ap.add_argument("--smoke", action="store_true", help="신호 6개만 · 모의 20회 · 상태 파일을 건드리지 않는다(1부의 본 산출을 읽고 risk 폴더의 cov_smoke_* 에 쓴다)")
    ap.add_argument("--only", default="", help="모형:판 하나만(예: main:L)")
    ap.add_argument("--daily-only", action="store_true", help="저장분의 신호별 값은 두고 국면 배수(날마다 이어 가는 계열)만 다시 만든다")
    a = ap.parse_args()
    if not a.smoke and ac.track() != "followup":
        raise RuntimeError("[aif] 2단계 줄로만 띄운다 — ops/aif_run.py --track followup 또는 AIF_TRACK=followup")
    ac.low_priority()
    f = ac.Frame()
    meta1 = ac.read_json(RK("meta.json")) or {}
    if not meta1.get("tag"):
        raise RuntimeError("[aif] 1부의 산출이 없다 — py/aif_riskmodel.py 를 먼저 돌린다")
    fp = "cov%d|%s|sim%d" % (VERSION, meta1["tag"], 20 if a.smoke else N_SIM)
    jobs = [(m, v) for m in rm.MODELS for v in VARIANTS if not a.only or a.only == "%s:%s" % (m, v)]
    sel = set(range(120, 300, 36)) | {60} if a.smoke else None
    n_sim = 20 if a.smoke else N_SIM
    is_end = np.datetime64(ac.cfg()["measure"]["is_end"], "D")
    if not a.smoke:
        ac.stage_begin(STAGE, 100, "진행(%)", PART_FROM, PART_TO)
    info, t0 = {}, time.perf_counter()
    for j, (m, v) in enumerate(jobs):
        path = RK("cov%s_%s_%s.npz" % ("_smoke" if a.smoke else "", m, v))
        old = None if (a.force or a.check or a.daily_only) else ac.load_ckpt(path, fp)
        key = "%s:%s" % (m, v)
        if old is not None and not a.smoke:
            ac.log("%s — 저장분이 같은 판이다(건너뜀)", key)
            info[key] = (ac.read_json(RK("cov_info.json")) or {}).get(key)
            continue

        def unit(done, total, j=j, key=key):
            if not a.smoke and (done == total or done % 10 == 0):
                ac.stage_unit(int(round(100 * (j + done / total) / len(jobs))), "%s(%s) 신호 %d / %d" % (rm.MODEL_KO[m], VARIANT_KO[v], done, total))

        I, res = redo_daily(f, m, v, path) if a.daily_only else run_one(f, m, v, sel, n_sim, unit)
        d = describe(f, I, res, is_end)
        if a.check:
            d["truncation"] = truncation_check(f, m, v, res, sorted(sel)[::3] if sel else [60, 180, 300], n_sim)

        def w(p, res=res):
            with open(p, "wb") as fh:
                np.savez(fh, fp=fp, **res)
        ac.write_atomic(path, w)
        info[key] = d
        ac.log("%s — %.0f초 · 신호 %d개 · 팩터 %d~%d개 · 고유팩터 편향(가장 작은 것 %.2f · 가장 큰 것 %.2f) · λ_F 중앙 %.2f · λ_S 중앙 %.2f", key, time.perf_counter() - t0,
               d["signals"], d["factors_min"], d["factors_max"], d["eig_bias_smallest"], d["eig_bias_largest"], d["lamF_p05_p50_p95"][1], d["lamS_p05_p50_p95"][1])
        del I, res
    if a.smoke:
        for k, d in info.items():
            ac.log("%s %s", k, {kk: (round(vv, 4) if isinstance(vv, float) else vv) for kk, vv in d.items()})
        return 0
    allinfo = ac.read_json(RK("cov_info.json")) or {}
    allinfo.update({k: v_ for k, v_ in info.items() if v_})
    ac.write_json(allinfo, RK("cov_info.json"))
    rdir = ac.results("followup", "risk")
    os.makedirs(rdir, exist_ok=True)
    ac.write_json({"at": ac._now(), "is_end": str(is_end), "params": {"variants": VARIANTS, "WIN_F": WIN_F, "WIN_S": WIN_S, "MIN_OBS_F": MIN_OBS_F, "MIN_OBS_D": MIN_OBS_D, "N_SIM": N_SIM,
                                                                     "NW_FLOOR": NW_FLOOR, "GAMMA": [GAMMA_WIN, GAMMA_H0, GAMMA_H1]}, "models": allinfo}, rdir + "/cov_checks.json")
    L, S_ = allinfo.get("main:L"), allinfo.get("main:S")
    lines = []
    if L and S_:
        c = allinfo.get("nlbeta:L")
        lines = ["신호일 %d개(%s~ · 표본 안)마다 그날까지의 일별 팩터 수익과 고유수익으로 팩터 공분산과 종목 고유 위험을 만들었습니다(본 모형 · 대조 판 × 반응형 · 안정형)" % (L["signals"], L["first"][:7]),
                 "본 모형 · 안정형 — 공분산에 든 팩터 %d~%d개 · 예측 변동성(연) 시장 %.1f%% · 업종 평균 %.1f%% · 스타일 평균 %.1f%%" % (
                     L["factors_min"], L["factors_max"], 100 * L["market_vol_ann"], 100 * L["industry_vol_ann"], 100 * L["style_vol_ann"]),
                 "고유팩터 위험 조정(모의 %d회) — 변동성이 가장 작은 고유팩터의 편향 %.2f배 · 가장 큰 고유팩터 %.2f배(1 보다 크면 조정 전 예측이 낮았다는 뜻)" % (N_SIM, L["eig_bias_smallest"], L["eig_bias_largest"]),
                 "변동성 국면 배수(5%% · 중앙 · 95%%) — 팩터: 안정형 %.2f · %.2f · %.2f / 반응형 %.2f · %.2f · %.2f" % (*L["lamF_p05_p50_p95"], *S_["lamF_p05_p50_p95"]),
                 "종목 고유 위험 — 추정 유니버스 중앙값 연 %.0f%%(안정형) · 시계열 추정만 쓰는 종목 %.0f%% · 구조 모형만 쓰는 종목 %.1f%% · 축소로 당긴 비중 평균 %.0f%% · 고유 위험을 매긴 종목 평균 %.0f개" % (
                     100 * L["spec_vol_ann_median_estu"], 100 * L["gamma1_share_estu"], 100 * L["structural_only_share_estu"], 100 * L["shrink_weight_mean_estu"], L["covered_with_spec_mean"]),
                 "고유 국면 배수(5%% · 중앙 · 95%%) — 시총 가중 %.2f · %.2f · %.2f / √시총 가중 %.2f · %.2f · %.2f(안정형)" % (*L["lamS_p05_p50_p95"], *L["lamS_sqrt_p05_p50_p95"]),
                 "상관 행렬의 양반정치 맞추기가 필요했던 신호일 %.0f%%(가장 작은 고유값 %.1e)" % (100 * L["psd_repaired_share"], L["psd_min_worst"])]
        if c:
            lines.append("대조 판(비선형 베타 포함) · 안정형 — 스타일 예측 변동성 평균 연 %.1f%% · 가장 작은 고유팩터의 편향 %.2f배 — 3부에서 편향 통계로 견줍니다" % (100 * c["style_vol_ann"], c["eig_bias_smallest"]))
        tr = [t for d in allinfo.values() if d for t in d.get("truncation", [])]
        if tr:
            lines.append("자르기 시험(신호일 뒤의 일별 값을 잘라 내고 다시 계산) — 가장 큰 상대 차이 %.1e" % max(t["max_rel_diff"] for t in tr))
    ac.write_json({"at": ac._now(), "title": "위험 평가 모형 2부 — 팩터 공분산 · 종목 고유 위험", "lines": lines, "charts": [], "chart_names": []}, ac.out("followup", "stage_summary_nl_risk.json"))
    for ln in lines:
        ac.log("%s", ln)
    ac.stage_unit(100, "2부 끝")
    ac.status_set(stage_state="done", detail="2부 끝 — 다음 작업 대기")
    return 0


if __name__ == "__main__":
    sys.exit(main())
