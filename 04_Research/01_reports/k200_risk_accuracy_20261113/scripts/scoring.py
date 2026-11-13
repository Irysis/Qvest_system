"""scoring.py — 1일 분포 예측 채점 · 역검정 · 사건 지표 · LT 위기(표준 문헌식만).

점수(모두 엄격 적정 · strictly proper/consistent):
  LS      로그 점수 log f(y)                                   (높을수록 좋음)
  CRPS    = 2∫ QS_u du                                         (낮을수록) Gneiting & Raftery 2007; Gneiting & Ranjan 2011
  twCRPS  왼꼬리 가중 = 2∫ QS_u (1−u)^2 du                     (낮을수록) Gneiting & Ranjan 2011 §3
  QS_u    분위 점수(=VaR 의 엄격 일관 점수)                    (낮을수록) Koenker & Bassett 1978
  FZ0     (VaR, ES) 결합 점수 α=5%                             (낮을수록) Patton, Ziegel & Chen 2019 (J. Econometrics 211)
역검정: Kupiec 1995 POF · Christoffersen 1998 CC · Engle & Manganelli 2004 DQ · Berkowitz 2001 LR(AR1) · PIT χ²
사건: Brier · BSS(확장 기후값) · 로그 손실 · ROC-AUC · PR-AUC(평균 정밀도)
비교: Diebold & Mariano 1995 (HAC Newey–West, Bartlett)
"""
from __future__ import annotations

import math

import numpy as np
import pandas as pd
from scipy import stats as sp_stats

import common as C

LEVELS_VAR = (0.01, 0.025, 0.05)
COVER_LEVELS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)
EVENT_THRESHOLDS = (-3.0, -5.0, -7.0, -10.0)


# ─── 일별 점수 표(모형 공통 열) ────────────────────────────────────────────────────────────
def score_hansen(df):
    """df: Date · y · mu · sigma · nu · lam → 일별 점수 열을 붙여 돌려준다."""
    d = df.copy()
    mu, sg, nu, lm, y = (d[c].values.astype(float) for c in ("mu", "sigma", "nu", "lam", "y"))
    d["ls"] = C.hansen_logpdf(y, mu, sg, nu, lm)
    d["pit"] = C.hansen_cdf(y, mu, sg, nu, lm)
    Q = C.hansen_ppf(C.U_GRID, mu, sg, nu, lm)
    d["crps"] = C.crps_from_quantiles(Q, y)
    d["twcrps"] = C.twcrps_left_from_quantiles(Q, y)
    for a in LEVELS_VAR:
        d[f"var_{int(a*1000):03d}"] = C.hansen_ppf(np.array([a]), mu, sg, nu, lm)[:, 0]
    d["es_050"] = C.es_from_ppf(mu, sg, nu, lm, alpha=0.05)
    for c in EVENT_THRESHOLDS:
        d[f"p_le_{int(-c)}"] = C.hansen_cdf(np.full_like(y, c), mu, sg, nu, lm)
    # 예측 분포 표준편차(Hansen 표준화 분포는 분산 1 → σ 가 곧 표준편차 · ν>2)
    d["sd_pred"] = sg
    return _finish(d)


def score_quantile_grid(dates, y, Q, logpdf=None, extra=None):
    """비모수 예측(분위 격자 Q (N,K) on C.U_GRID)용. logpdf 가 없으면 LS = NaN."""
    d = pd.DataFrame({"Date": pd.to_datetime(dates), "y": np.asarray(y, float)})
    Q = np.sort(np.asarray(Q, float), axis=1)
    u = C.U_GRID
    yy = d["y"].values
    d["ls"] = np.nan if logpdf is None else np.asarray(logpdf, float)
    # PIT = 격자 선형 보간 CDF
    pit = np.empty(len(yy))
    for i in range(len(yy)):
        pit[i] = np.interp(yy[i], Q[i], u, left=0.0, right=1.0)
    d["pit"] = pit
    d["crps"] = C.crps_from_quantiles(Q, yy)
    d["twcrps"] = C.twcrps_left_from_quantiles(Q, yy)
    for a in LEVELS_VAR:
        d[f"var_{int(a*1000):03d}"] = np.array([np.interp(a, u, Q[i]) for i in range(len(yy))])
    k = u <= 0.05
    d["es_050"] = Q[:, k].mean(axis=1)
    for c in EVENT_THRESHOLDS:
        d[f"p_le_{int(-c)}"] = np.array([np.interp(c, Q[i], u, left=0.0, right=1.0) for i in range(len(yy))])
    w = np.gradient(u)
    m1 = (Q * w).sum(axis=1) / w.sum()
    d["sd_pred"] = np.sqrt(np.maximum(((Q - m1[:, None]) ** 2 * w).sum(axis=1) / w.sum(), 0))
    if extra is not None:
        for k2, v in extra.items():
            d[k2] = v
    return _finish(d)


def _finish(d):
    y = d["y"].values
    for a in LEVELS_VAR:
        v = d[f"var_{int(a*1000):03d}"].values
        d[f"qs_{int(a*1000):03d}"] = ((y < v).astype(float) - a) * (v - y)
        d[f"hit_{int(a*1000):03d}"] = (y < v).astype(int)
    d["fz0_050"] = fz0_loss(y, d["var_050"].values, d["es_050"].values, 0.05)
    return d


def fz0_loss(y, v, e, alpha):
    """Patton, Ziegel & Chen (2019) 식 (6) FZ0: −1/(αe)·1{y≤v}(v−y) + v/e + log(−e) − 1  — ES e < 0 에서만 정의.
    정의역 밖(e ≥ 0 — 사실상 한 점으로 붕괴한 예측)은 결측(NaN). (11-13 수정: 구판은 e 를 −1e-9 로 눌러 −1천만 같은 값이 나왔다.)
    e 가 v 보다 아주 조금 큰 수치 오차만 v − 1e-9 로 맞춘다."""
    y = np.asarray(y, float); v = np.asarray(v, float); e = np.asarray(e, float)
    e2 = np.where(e < v, e, v - 1e-9)
    e2 = np.where(e2 < 0, e2, np.nan)
    hit = (y <= v).astype(float)
    with np.errstate(invalid="ignore", divide="ignore"):
        return -hit * (v - y) / (alpha * e2) + v / e2 + np.log(-e2) - 1.0


# ─── 역검정 ────────────────────────────────────────────────────────────────────────────
def kupiec(hits, a):
    hits = np.asarray(hits, int); n = len(hits); x = int(hits.sum())
    if n == 0:
        return {"n": 0, "x": 0, "rate": np.nan, "lr": np.nan, "p": np.nan}
    pi = x / n
    def ll(p):
        p = min(max(p, 1e-12), 1 - 1e-12)
        return x * math.log(p) + (n - x) * math.log(1 - p)
    lr = -2 * (ll(a) - ll(pi))
    return {"n": n, "x": x, "rate": pi, "lr": lr, "p": float(1 - sp_stats.chi2.cdf(lr, 1))}


def christoffersen_cc(hits, a):
    h = np.asarray(hits, int)
    if len(h) < 3:
        return {"lr_ind": np.nan, "p_ind": np.nan, "lr_cc": np.nan, "p_cc": np.nan}
    h0, h1 = h[:-1], h[1:]
    n00 = int(((h0 == 0) & (h1 == 0)).sum()); n01 = int(((h0 == 0) & (h1 == 1)).sum())
    n10 = int(((h0 == 1) & (h1 == 0)).sum()); n11 = int(((h0 == 1) & (h1 == 1)).sum())
    def L(p, k0, k1):
        p = min(max(p, 1e-12), 1 - 1e-12)
        return k0 * math.log(1 - p) + k1 * math.log(p)
    p01 = n01 / max(n00 + n01, 1); p11 = n11 / max(n10 + n11, 1); p = (n01 + n11) / max(n00 + n01 + n10 + n11, 1)
    lr_ind = -2 * (L(p, n00 + n10, n01 + n11) - (L(p01, n00, n01) + L(p11, n10, n11)))
    uc = kupiec(h1, a)
    lr_cc = uc["lr"] + lr_ind
    return {"lr_ind": lr_ind, "p_ind": float(1 - sp_stats.chi2.cdf(lr_ind, 1)),
            "lr_cc": lr_cc, "p_cc": float(1 - sp_stats.chi2.cdf(lr_cc, 2)), "n11": n11}


def dq_test(hits, var, a, lags=4):
    """Engle & Manganelli (2004) DQ: Hit_t−α 를 상수 · 과거 Hit 4개 · VaR_t 에 회귀 → χ²(lags+2)."""
    h = np.asarray(hits, float) - a; v = np.asarray(var, float)
    n = len(h)
    if n <= lags + 10:
        return {"dq": np.nan, "p": np.nan}
    Y = h[lags:]
    X = [np.ones(n - lags)] + [h[lags - k:n - k] for k in range(1, lags + 1)] + [v[lags:]]
    X = np.column_stack(X)
    beta, *_ = np.linalg.lstsq(X, Y, rcond=None)
    dq = float(beta @ X.T @ X @ beta / (a * (1 - a)))
    return {"dq": dq, "p": float(1 - sp_stats.chi2.cdf(dq, X.shape[1]))}


def berkowitz_ar1(pit):
    z = sp_stats.norm.ppf(np.clip(np.asarray(pit, float), 1e-6, 1 - 1e-6))
    if len(z) < 30:
        return {"lr": np.nan, "p": np.nan}
    y1, y0 = z[1:], z[:-1]
    X = np.column_stack([np.ones_like(y0), y0])
    b, *_ = np.linalg.lstsq(X, y1, rcond=None)
    res = y1 - X @ b
    s2 = res.var()
    ll1 = -0.5 * len(y1) * math.log(2 * math.pi * s2) - 0.5 * (res ** 2).sum() / s2
    ll0 = -0.5 * len(y1) * math.log(2 * math.pi) - 0.5 * (y1 ** 2).sum()
    lr = -2 * (ll0 - ll1)
    return {"lr": lr, "p": float(1 - sp_stats.chi2.cdf(lr, 3)), "mu": float(b[0] / (1 - b[1])),
            "rho": float(b[1]), "sd": float(math.sqrt(s2 / (1 - b[1] ** 2))) if abs(b[1]) < 1 else np.nan}


def pit_chi2(pit, bins=20):
    cnt, _ = np.histogram(np.asarray(pit, float), bins=bins, range=(0, 1))
    e = len(pit) / bins
    st = float(((cnt - e) ** 2 / e).sum())
    return {"chi2": st, "p": float(1 - sp_stats.chi2.cdf(st, bins - 1)), "counts": cnt.tolist()}


# ─── 비교 검정 ────────────────────────────────────────────────────────────────────────
def nw_lrv(d, lag):
    d = np.asarray(d, float) - np.mean(d)
    n = len(d)
    v = float(d @ d / n)
    for k in range(1, lag + 1):
        if k >= n:
            break
        g = float(d[:-k] @ d[k:] / n)
        v += 2 * (1 - k / (lag + 1)) * g
    return max(v, 1e-18)


def dm_test(loss_a, loss_b, lag=10):
    """d = loss_a − loss_b. 음수 평균 = a 가 더 좋음(손실 기준). 단측 p(a 우위) 함께."""
    d = np.asarray(loss_a, float) - np.asarray(loss_b, float)
    d = d[np.isfinite(d)]
    n = len(d)
    if n < 30:
        return {"n": n, "mean_d": np.nan, "t": np.nan, "p_two": np.nan, "p_a_better": np.nan}
    se = math.sqrt(nw_lrv(d, lag) / n)
    t = float(d.mean() / se)
    return {"n": n, "mean_d": float(d.mean()), "t": t,
            "p_two": float(2 * (1 - sp_stats.norm.cdf(abs(t)))), "p_a_better": float(sp_stats.norm.cdf(t))}


# ─── 사건 지표 ────────────────────────────────────────────────────────────────────────
def auc(p, e):
    p = np.asarray(p, float); e = np.asarray(e, int)
    n1 = int(e.sum()); n0 = len(e) - n1
    if n1 == 0 or n0 == 0:
        return np.nan
    r = sp_stats.rankdata(p)
    return float((r[e == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0))


def avg_precision(p, e):
    p = np.asarray(p, float); e = np.asarray(e, int)
    if e.sum() == 0:
        return np.nan
    o = np.argsort(-p, kind="mergesort")
    e2 = e[o]
    tp = np.cumsum(e2); k = np.arange(1, len(e2) + 1)
    prec = tp / k
    return float((prec * e2).sum() / e2.sum())


def event_metrics(p, e, p_clim):
    p = np.clip(np.asarray(p, float), 1e-6, 1 - 1e-6); e = np.asarray(e, int)
    pc = np.clip(np.asarray(p_clim, float), 1e-6, 1 - 1e-6)
    br = float(((p - e) ** 2).mean()); brc = float(((pc - e) ** 2).mean())
    ll = float(-(e * np.log(p) + (1 - e) * np.log(1 - p)).mean())
    llc = float(-(e * np.log(pc) + (1 - e) * np.log(1 - pc)).mean())
    return {"n": int(len(e)), "events": int(e.sum()), "base_rate": float(e.mean()) if len(e) else np.nan,
            "mean_p": float(p.mean()), "brier": br, "brier_clim": brc, "bss": 1 - br / brc if brc > 0 else np.nan,
            "logloss": ll, "logloss_clim": llc, "auc": auc(p, e), "pr_auc": avg_precision(p, e)}


def alert_metrics(alert, e):
    a = np.asarray(alert, bool); e = np.asarray(e, bool)
    tp = int((a & e).sum()); fp = int((a & ~e).sum()); fn = int((~a & e).sum()); tn = int((~a & ~e).sum())
    return {"alerts": int(a.sum()), "events": int(e.sum()), "tp": tp, "fp": fp, "fn": fn,
            "hit_rate": tp / max(tp + fn, 1), "false_alarm_ratio": fp / max(tp + fp, 1),
            "false_alarm_rate": fp / max(fp + tn, 1), "precision": tp / max(tp + fp, 1)}


def expanding_climatology(y_all_dates, y_all, eval_dates, thr):
    """기후값 = 예측일 t 이전(결과일 ≤ t)까지 실현된 사건 빈도(2001-01 이후 · 확장 창)."""
    s = pd.Series((np.asarray(y_all) <= thr).astype(float), index=pd.to_datetime(y_all_dates)).sort_index()
    cm = s.expanding().mean()
    # 예측일 t 의 기후값 = t 날짜까지 결과가 확정된 사건(결과일 ≤ t) → y 라벨이 날짜 s(=결과 s→s+1)이면 s ≤ t−1
    cm_shift = cm.shift(1)
    return cm_shift.reindex(pd.to_datetime(eval_dates), method="ffill").values


# ─── LT 20/20 위기(behavior_card.R::bc_crises_lt 와 같은 알고리즘) ────────────────────────────
def lt_crises(dates, simple_ret, l_down=0.2, l_up=0.2):
    D = pd.to_datetime(pd.Series(dates)).reset_index(drop=True)
    P = np.cumprod(1 + np.asarray(simple_ret, float))
    n = len(P)
    out = []
    st = 1; ext = P[0]; exti = 0; pki = None
    for t in range(1, n):
        if st == 1:
            if P[t] >= ext:
                ext, exti = P[t], t
            elif P[t] <= (1 - l_down) * ext:
                pki = exti; st = 0; ext, exti = P[t], t
        else:
            if P[t] <= ext:
                ext, exti = P[t], t
            elif P[t] >= (1 + l_up) * ext:
                out.append((pki, exti, False)); st = 1; ext, exti = P[t], t
    if st == 0:
        out.append((pki, exti, True))
    rows = []
    for pk, tr, ong in out:
        conf = next(k for k in range(pk, n) if P[k] <= (1 - l_down) * P[pk])
        rows.append({"peak": D[pk], "confirm": D[conf], "trough": D[tr], "depth": 1 - P[tr] / P[pk], "ongoing": ong})
    return pd.DataFrame(rows)
