"""h1_dr_newsvk.py — K200 일간 위험 브리핑 본 모형 H1(분포 회귀 + V-KOSPI200) · 운영 모듈.

운영 반영: 2026-11-14 도훈 결정 K200-RISK-H1-REPLACE-P3-20261114("즉시 교체 — 다음 아침 브리핑부터 H1 본 모형 ·
이상 입력 점검 포함 · P3 는 비교용"). 검증 = 사전등록 K200RISK-PREREG-v1-20261113 의 H1 `DR_newsvk`
(판정 커밋 9799b31e8 · OOS 2023-01~2026-11 942일 로그 점수 +0.0663/일 · DM t 3.98 · Holm 통과 · 관문 A·B·C 통과).

★모형 · 적합 코드는 연구 코드를 **그대로** 옮겼다(바꾸지 말 것 — 바꾸면 검증된 모형이 아니다):
  04_Research/01_reports/k200_risk_accuracy_20261113/scripts/common.py   hansen_abc · hansen_logpdf · hansen_cdf · hansen_ppf · es_from_ppf
  04_Research/01_reports/k200_risk_accuracy_20261113/scripts/31_challenger_dr.py   build_frame 의 특징 · unpack · nll · fit · 재추정 격자
  같음은 시험으로 확인한다(602 --parity: 연구 워크포워드 fc_DR_newsvk.parquet 과 σ 최대 차이).

모형:  y_{t+1} = μ + σ_t ε_{t+1},  ε ~ Hansen(1994) 비대칭 t 표준화(평균 0 · 분산 1)
       log σ_t = a0 + a'z_t   (z_t = 학습 창 평균 · 표준편차로 표준화한 특징 · 전부 t 종가까지)
       특징 7: lrv5 lrv22 lrv60 = log 실현 표준편차(5·22·60일 · %) · ddz = 낙폭 확장 z · r0 · absr0 = 당일 로그수익 · |r0|
              lvk = log V-KOSPI200(t 종가)
       μ · a0 · a · ν · λ 를 학습 창 로그우도로 한 번에 추정(GAMLSS 형 분포 회귀 — Rigby & Stasinopoulos 2005)
학습 창: 재추정 기준일 t_k 마다 [t_k − 21일 − 12년, t_k − 21일](운영 P3 와 같은 규칙) · t_k = 2013-01-24 부터 21거래일마다
       (연구 워크포워드와 같은 격자) · σ_t 는 매일 t 종가 특징으로 갱신 · μ · ν · λ 는 재추정 창 상수.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import optimize as sp_opt
from scipy import stats as sp_stats
from scipy.special import gammaln

MODEL_ID = "H1"
MODEL_NAME = "DR_newsvk"
FEATS = ("lrv5", "lrv22", "lrv60", "ddz", "r0", "absr0", "lvk")   # 연구 fc_DR_newsvk.meta.json feats 순서 그대로
REFIT_EVERY = 21                       # 연구 31_challenger_dr.py REFIT_EVERY
GRID_START = pd.Timestamp("2013-01-24")  # 연구 워크포워드 첫 예측일(= fc_P3_replica.parquet 첫 날짜) — 재추정 격자 기준점
P3_LOOKBACK_YEARS = 12                 # 운영 P3 사양(601 main() 기본값) — 연구 common.P3_LOOKBACK_YEARS
P3_EMBARGO_CAL_DAYS = 21               # 운영 P3 사양(601 daily_inference) — 연구 common.P3_EMBARGO_CAL_DAYS
TRAIN_MIN_ROWS = 1008                  # 운영 P3 하한(601: "Need >=1008")
DATE_START = pd.Timestamp("2001-01-03")  # 운영 P3 load_data cfg date_start
P3_FEATURE_COLS = ["log_ret_lag_1", "log_ret_lag_2", "log_ret_lag_5", "log_ret_lag_22",
                   "rv_5d", "rv_22d", "rv_60d", "mean_5d", "mean_22d", "mean_60d", "rv_22d_z", "drawdown_z"]
VAR_LEVELS = (0.05, 0.01, 0.005, 0.001)
BEAR_THRESHOLDS = (-5.0, -7.0, -10.0)  # 운영 P3 derive_metrics_per_obs 와 같은 문턱(로그수익 %)


# ─── Hansen(1994) 비대칭 t — 연구 common.py 그대로(σ = 표준편차 · λ ∈ (−1,1)) ─────────────────────────
def hansen_abc(nu, lam):
    nu = np.asarray(nu, dtype=float)
    lam = np.asarray(lam, dtype=float)
    log_c = gammaln((nu + 1.0) / 2.0) - gammaln(nu / 2.0) - 0.5 * np.log(np.pi * (nu - 2.0))
    c = np.exp(log_c)
    a = 4.0 * lam * c * (nu - 2.0) / (nu - 1.0)
    b = np.sqrt(np.maximum(1.0 + 3.0 * lam * lam - a * a, 1e-12))
    return a, b, c


def hansen_logpdf(y, mu, sigma, nu, lam):
    """log f(y) — Hansen 1994 식(밀도). 벡터화."""
    y = np.asarray(y, float); mu = np.asarray(mu, float); sigma = np.asarray(sigma, float)
    nu = np.asarray(nu, float); lam = np.asarray(lam, float)
    a, b, c = hansen_abc(nu, lam)
    z = (y - mu) / sigma
    denom = np.where(z < -a / b, 1.0 - lam, 1.0 + lam)
    u = (b * z + a) / denom
    return np.log(b) + np.log(c) - (nu + 1.0) / 2.0 * np.log1p(u * u / (nu - 2.0)) - np.log(sigma)


def hansen_cdf(y, mu, sigma, nu, lam):
    y = np.asarray(y, float); mu = np.asarray(mu, float); sigma = np.asarray(sigma, float)
    nu = np.asarray(nu, float); lam = np.asarray(lam, float)
    a, b, _ = hansen_abc(nu, lam)
    z = (y - mu) / sigma
    left = z < -a / b
    scale = np.sqrt(nu / (nu - 2.0))
    ul = (b * z + a) / (1.0 - lam)
    ur = (b * z + a) / (1.0 + lam)
    Fl = (1.0 - lam) * sp_stats.t.cdf(ul * scale, df=nu)
    Fr = -lam + (1.0 + lam) * sp_stats.t.cdf(ur * scale, df=nu)
    return np.where(left, Fl, Fr)


def hansen_ppf(p, mu, sigma, nu, lam):
    """분위 — p 는 (N,) 또는 (N,K) · 모수는 (N,) — (N,K) 반환."""
    p = np.asarray(p, float)
    mu = np.asarray(mu, float)[:, None]; sigma = np.asarray(sigma, float)[:, None]
    nu = np.asarray(nu, float)[:, None]; lam = np.asarray(lam, float)[:, None]
    if p.ndim == 1:
        p = np.broadcast_to(p[None, :], (mu.shape[0], p.shape[0]))
    a, b, _ = hansen_abc(nu, lam)
    scale = np.sqrt(nu / (nu - 2.0))
    left = p < (1.0 - lam) / 2.0
    pl = np.clip(p / (1.0 - lam), 1e-12, 1 - 1e-12)
    pr = np.clip((p + lam) / (1.0 + lam), 1e-12, 1 - 1e-12)
    ql = sp_stats.t.ppf(pl, df=nu) / scale
    qr = sp_stats.t.ppf(pr, df=nu) / scale
    zl = ((1.0 - lam) * ql - a) / b
    zr = ((1.0 + lam) * qr - a) / b
    return mu + sigma * np.where(left, zl, zr)


def es_from_ppf(mu, sigma, nu, lam, alpha=0.05, n=400):
    """ES_α = (1/α) ∫_0^α F^-1(u) du — 결정론 중점 규칙(연구 common.es_from_ppf · 운영 P3 는 400점 무작위 MC)."""
    u = (np.arange(1, n + 1) - 0.5) / n * alpha
    q = hansen_ppf(u, mu, sigma, nu, lam)
    return q.mean(axis=1)


# ─── 특징 — 운영 P3 load_data(472_p1_patch_v2.py) 와 같은 식 · 단 마지막 행(ret_fwd 미상)을 남긴다 ──────────
def _expanding_z(s, min_periods=60, eps=1e-8):
    mu = s.expanding(min_periods=min_periods).mean()
    sd = s.expanding(min_periods=min_periods).std() + eps
    return (s - mu) / sd


def p3_feature_frame(bm: pd.DataFrame) -> pd.DataFrame:
    """472 load_data 의 특징 · 표적 계산을 그대로 하되 dropna(ret_fwd) 를 하지 않는다(예측일 행 보존).
    반환: Date ≥ 2001-01-03 전 행 · 퍼센트 척도 · 열 `p3_complete`(P3 특징 12개 완비 여부)."""
    df = bm.rename(columns={"BM_Close": "Close"})[["Date", "Close"]].copy()
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").reset_index(drop=True)
    df["log_ret"] = np.log(df["Close"]).diff()
    for lag in [1, 2, 5, 22]:
        df[f"log_ret_lag_{lag}"] = df["log_ret"].shift(lag)
    for w in [5, 22, 60]:
        df[f"rv_{w}d"] = df["log_ret"].rolling(w, min_periods=max(3, w // 2)).std()
        df[f"mean_{w}d"] = df["log_ret"].rolling(w, min_periods=max(3, w // 2)).mean()
    eps = 1e-8
    cum_max = df["Close"].cummax()
    df["drawdown"] = (df["Close"] - cum_max) / (cum_max + eps)
    df["rv_22d_z"] = _expanding_z(df["rv_22d"])
    df["drawdown_z"] = _expanding_z(df["drawdown"])
    df["ret_fwd"] = np.log(df["Close"].shift(-1) / df["Close"])
    df = df[df["Date"] >= DATE_START].reset_index(drop=True)
    for c in ["log_ret", "ret_fwd"] + [f"log_ret_lag_{l}" for l in [1, 2, 5, 22]] + \
             [f"rv_{w}d" for w in [5, 22, 60]] + [f"mean_{w}d" for w in [5, 22, 60]] + ["drawdown"]:
        df[c] = df[c] * 100.0
    df["p3_complete"] = df[P3_FEATURE_COLS].notna().all(axis=1)
    return df


def build_frame(project_root: Path, bm: pd.DataFrame | None = None, ix: pd.DataFrame | None = None) -> pd.DataFrame:
    """연구 31 build_frame 과 같은 특징(+ 예측일 행). bm · ix 를 주면 그것을 쓴다(시험 주입용)."""
    project_root = Path(project_root)
    if bm is None:
        bm = pd.read_parquet(project_root / ".cache" / "benchmark.parquet")
    if ix is None:
        ix = pd.read_parquet(project_root / ".cache" / "indices.parquet", columns=["Date", "kospi200_vol"])
    bm = bm.copy(); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date").reset_index(drop=True)
    df = p3_feature_frame(bm)
    bm["r0"] = np.log(bm["BM_Close"]).diff() * 100.0
    df = df.merge(bm[["Date", "r0"]], on="Date", how="left")
    df["absr0"] = df["r0"].abs(); df["negr0"] = np.minimum(df["r0"], 0.0)
    df["lrv5"] = np.log(np.maximum(df["rv_5d"], 1e-3)); df["lrv22"] = np.log(np.maximum(df["rv_22d"], 1e-3))
    df["lrv60"] = np.log(np.maximum(df["rv_60d"], 1e-3)); df["ddz"] = df["drawdown_z"]
    ix = ix[["Date", "kospi200_vol"]].copy(); ix["Date"] = pd.to_datetime(ix["Date"]); ix = ix.sort_values("Date")
    ix["lvk"] = np.log(ix["kospi200_vol"]); ix["dlvk"] = ix["lvk"].diff()
    df = df.merge(ix[["Date", "kospi200_vol", "lvk", "dlvk"]], on="Date", how="left")
    return df


def training_rows(df: pd.DataFrame) -> pd.DataFrame:
    """연구의 학습 후보 행 = load_data 출력(P3 특징 완비 · ret_fwd 있음) 위에서 dropna(특징 + 표적)."""
    tr = df[df["p3_complete"] & df["ret_fwd"].notna()]
    return tr.dropna(subset=list(FEATS) + ["ret_fwd"])


# ─── 적합 — 연구 31_challenger_dr.py 그대로 ─────────────────────────────────────────────────────────────
def unpack(th, k):
    mu = th[0]; a0 = th[1]; a = th[2:2 + k]
    nu = 2.05 + np.exp(th[2 + k]); lam = 0.95 * np.tanh(th[3 + k])
    return mu, a0, a, nu, lam


def pack(mu, a0, a, nu, lam):
    """unpack 의 역(연구 적합 기록 fits → 시작점 θ 복원용)."""
    return np.concatenate([[mu, a0], np.asarray(a, float), [math.log(nu - 2.05), math.atanh(lam / 0.95)]])


def nll(th, Z, y, k):
    mu, a0, a, nu, lam = unpack(th, k)
    if nu > 200:
        return 1e10
    ls = a0 + Z @ a
    if np.any(ls > 4) or np.any(ls < -6):
        return 1e10
    v = -float(np.sum(hansen_logpdf(y, mu, np.exp(ls), nu, lam)))
    return v if np.isfinite(v) else 1e10


def fit(Z, y, th0):
    k = Z.shape[1]
    if th0 is None:
        th0 = np.zeros(4 + k); th0[1] = np.log(np.std(y)); th0[2 + k] = np.log(6.0); th0[3 + k] = -0.05
    res = sp_opt.minimize(nll, th0, args=(Z, y, k), method="BFGS", options={"maxiter": 2000, "gtol": 1e-5})
    if not res.success:
        res2 = sp_opt.minimize(nll, res.x, args=(Z, y, k), method="Nelder-Mead",
                               options={"maxiter": 20000, "xatol": 1e-6, "fatol": 1e-6})
        if res2.fun <= res.fun:
            return res2.x, res2, False
    return res.x, res, bool(res.success)


# ─── 재추정 격자 · 창 ─────────────────────────────────────────────────────────────────────────────────
def grid_dates(df: pd.DataFrame) -> list:
    """재추정 격자의 날짜 목록 = 벤치마크 거래일 중 GRID_START 이후(연구 forecast_dates 와 같은 목록 — 2026-11-14 대조 일치)."""
    return [pd.Timestamp(d) for d in df["Date"] if pd.Timestamp(d) >= GRID_START]


def anchor_for(t, dates: list):
    """t 의 재추정 기준일 — 격자 위치 (i // 21) * 21."""
    t = pd.Timestamp(t)
    i = dates.index(t)
    return dates[(i // REFIT_EVERY) * REFIT_EVERY]


def window_for(anchor):
    te = pd.Timestamp(anchor) - pd.Timedelta(days=P3_EMBARGO_CAL_DAYS)
    ts = te - pd.DateOffset(years=P3_LOOKBACK_YEARS)
    return ts, te


def fit_anchor(tr_all: pd.DataFrame, anchor, th0):
    """기준일 anchor 의 학습 창 적합 — 연구 main() 의 루프 본문과 같은 계산."""
    ts, te = window_for(anchor)
    tr = tr_all[(tr_all["Date"] >= ts) & (tr_all["Date"] <= te)]
    X = tr[list(FEATS)].values.astype(float)
    m_ = X.mean(0); s_ = X.std(0); s_[s_ == 0] = 1
    Z = (X - m_) / s_
    th, res, ok = fit(Z, tr["ret_fwd"].values.astype(float), th0)
    return {"anchor": pd.Timestamp(anchor), "theta": np.asarray(th, float), "m": m_, "s": s_, "n": int(len(tr)),
            "nll": float(res.fun), "ok": bool(ok), "train_start": tr["Date"].min(), "train_end": tr["Date"].max(),
            "z_min": Z.min(0) if len(Z) else None, "z_max": Z.max(0) if len(Z) else None}


def forecast_from_fit(fr: dict, x_t: np.ndarray):
    mu, a0, a, nu, lam = unpack(fr["theta"], len(FEATS))
    z = (np.asarray(x_t, float) - fr["m"]) / fr["s"]
    sigma = float(np.exp(a0 + z @ a))
    return {"mu": float(mu), "sigma": sigma, "nu": float(nu), "lam": float(lam), "z": z}


def metrics(mu, sigma, nu, lam):
    """VaR(0.05 · 0.01 · 0.005 · 0.001) · ES 5% · P(y ≤ −5/−7/−10%) — 운영 P3 와 같은 출력 이름 · 척도(로그수익 %)."""
    m_ = np.array([mu]); s_ = np.array([sigma]); n_ = np.array([nu]); l_ = np.array([lam])
    q = hansen_ppf(np.array(VAR_LEVELS), m_, s_, n_, l_)[0]
    es = float(es_from_ppf(m_, s_, n_, l_, alpha=0.05, n=400)[0])
    p = {thr: float(hansen_cdf(np.array([thr]), mu, sigma, nu, lam)[0]) for thr in BEAR_THRESHOLDS}
    return {"var_05": float(q[0]), "var_01": float(q[1]), "var_005": float(q[2]), "var_001": float(q[3]),
            "es_05": es, "p_minus_5pct": p[-5.0], "p_minus_7pct": p[-7.0], "p_minus_10pct": p[-10.0]}


def pit(y, mu, sigma, nu, lam):
    return float(hansen_cdf(np.array([y]), mu, sigma, nu, lam)[0])
