"""common.py — K200 일간 위험 예측 정확도 연구(2026-11-13) 공통 도구.

- 운영 P3 모듈(04_Research/decision_framework/bearish_forecast_v3)을 **읽기 전용으로 import** 한다(수정 없음).
- 자료 판본 기록(benchmark md5 · 최신일) · 특징 행렬 · Hansen 비대칭 t 의 pdf/cdf/분위 · 채점 함수.
- 판정 규칙 수치는 여기 두지 않는다(사전등록 파일 prereg/*.json 이 정본).
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats as sp_stats
from scipy.special import gammaln

HERE = Path(__file__).resolve().parent
STUDY = HERE.parent
PROJECT_ROOT = STUDY.parent.parent.parent
P3_DIR = PROJECT_ROOT / "04_Research" / "decision_framework" / "bearish_forecast_v3"
BM_PATH = PROJECT_ROOT / ".cache" / "benchmark.parquet"
OUT = STUDY / "output"
CHARTS = STUDY / "charts"

P_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)
# 운영 P3 사양(601_daily_inference.py main() 기본값 · morning_briefing.sh [6/6] 주석) — 재현용
P3_ALPHA = 6.68e-4
P3_LOOKBACK_YEARS = 12
P3_EMBARGO_CAL_DAYS = 21


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, str(p))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_p3_modules():
    lqm = _load("a1_lasso_quantile_ro", P3_DIR / "03_models" / "a1_lasso_quantile.py")
    p472 = _load("p1_patch_v2_ro", P3_DIR / "scripts" / "472_p1_patch_v2.py")
    hsk3 = _load("p3_hansen_bounded_ro", P3_DIR / "03_models" / "p3_hansen_skewt_bounded.py")
    return lqm, p472, hsk3


def file_md5(p):
    h = hashlib.md5()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def data_vintage():
    bm = pd.read_parquet(BM_PATH, columns=["Date"])
    return {
        "benchmark_path": str(BM_PATH).replace("\\", "/"),
        "benchmark_md5": file_md5(BM_PATH),
        "benchmark_max_date": str(pd.to_datetime(bm["Date"]).max().date()),
        "benchmark_rows": int(len(bm)),
    }


def build_feature_frame(p472):
    """운영과 같은 특징(472 load_data) — 특징은 t 까지 자료만(롤링 · 확장 창). ret_fwd 는 표적(t→t+1)."""
    cfg = {"data": {"bm_path": ".cache/benchmark.parquet", "date_start": "2001-01-03",
                    "date_end": "2099-12-31", "percent_scale": True}}
    cwd = os.getcwd()
    try:
        os.chdir(P3_DIR)  # load_data 는 PROJECT_ROOT 기준 경로라 cwd 무관하지만 운영과 같은 조건으로
        df, feature_cols = p472.load_data(cfg)
    finally:
        os.chdir(cwd)
    df["Date"] = pd.to_datetime(df["Date"])
    return df.sort_values("Date").reset_index(drop=True), list(feature_cols)


# ─── Hansen(1994) 비대칭 t — 운영 모듈과 같은 매개화(σ = 표준편차 · λ ∈ (−1,1)) ───────────────────
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


# 결정론적 분위 격자(중점) — CRPS · ES 수치 적분용
U_GRID = (np.arange(1, 2000) - 0.5) / 1999.0  # 1999점
U_GRID = U_GRID[(U_GRID > 0) & (U_GRID < 1)]


def crps_from_quantiles(qmat, y, u=U_GRID):
    """CRPS = 2 ∫_0^1 QS_u(F^-1(u), y) du (분위 점수 적분 · Gneiting & Ranjan 2011 식 (4)).
    qmat (N,K) = 각 u 의 분위. 중점 규칙."""
    y = np.asarray(y, float)[:, None]
    ind = (y < qmat).astype(float)
    qs = (ind - u[None, :]) * (qmat - y)
    return 2.0 * qs.mean(axis=1)


def twcrps_left_from_quantiles(qmat, y, u=U_GRID):
    """왼꼬리 가중 분위 점수 적분 — w(u) = (1−u)^2 (Gneiting & Ranjan 2011 §3 '왼꼬리' 가중)."""
    y = np.asarray(y, float)[:, None]
    ind = (y < qmat).astype(float)
    qs = (ind - u[None, :]) * (qmat - y)
    w = (1.0 - u) ** 2
    return 2.0 * (qs * w[None, :]).mean(axis=1)


def es_from_ppf(mu, sigma, nu, lam, alpha=0.05, n=400):
    """ES_α = (1/α) ∫_0^α F^-1(u) du — 결정론 중점 규칙(운영은 400점 무작위 MC)."""
    u = (np.arange(1, n + 1) - 0.5) / n * alpha
    q = hansen_ppf(u, mu, sigma, nu, lam)
    return q.mean(axis=1)


def forecast_dates(until="2099-12-31"):
    """평가 날짜 목록 — P3 재현 파일이 정본, 없으면 비교 모형 파일(같은 규칙으로 만든 같은 날짜)."""
    f = OUT / "fc_P3_replica.parquet"
    if not f.exists():
        f = OUT / "sc_GJR.parquet"
    d = pd.read_parquet(f, columns=["Date"])
    return [pd.Timestamp(x) for x in d["Date"] if pd.Timestamp(x) <= pd.Timestamp(until)]


def json_default(o):
    if isinstance(o, (np.bool_,)):
        return bool(o)
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return None if not np.isfinite(o) else float(o)
    if isinstance(o, np.ndarray):
        return o.tolist()
    if isinstance(o, (pd.Timestamp,)):
        return str(o.date())
    raise TypeError(type(o).__name__)


def write_json(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2, default=json_default), encoding="utf-8")
    os.replace(tmp, path)
