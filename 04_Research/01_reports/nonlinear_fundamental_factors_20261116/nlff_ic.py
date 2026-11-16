"""nlff_ic.py — 외부 엔진(auto-sklearn · TPOT)용 모델 선택 지표: 월별 단면 Spearman 순위 IC 평균(nlff_automl.ic_mean 과 같은 정의).

엔진의 지표 함수는 (y_true, y_pred) 만 받으므로 날짜는 환경 변수가 가리키는 파일에서 읽는다(첫 호출 때 · 하위 프로세스도 같은 방식):
  NLFF_VAL_DATES   = 검증 행 날짜(.npy · 일수) — 드라이버가 준 Xva 행 순서 = PredefinedSplit 시험 색인 순서
  NLFF_TRAIN_DATES = 학습 부분 행 날짜(auto-sklearn 이 진단용 train_loss 를 같은 지표로 잰다)
  NLFF_IC_MIN_N    = 달마다 최소 종목 수(설정 automl.selection_metric.min_names_per_month)
어느 배열인지는 길이로 고른다(두 길이가 같으면 중단). 별도 모듈인 이유 = 피클 가능해야 dask · pynisher 하위 프로세스로 넘어간다.
파이썬 3.9 호환 문법(auto-sklearn 환경).
"""
from __future__ import annotations

import os

import numpy as np

_CACHE = {}


def _dates():
    key = (os.environ.get("NLFF_VAL_DATES"), os.environ.get("NLFF_TRAIN_DATES"))
    if key not in _CACHE:
        if not key[0] or not key[1]:
            raise AssertionError("[nlff IC] 날짜 파일 환경 변수가 없다")
        _CACHE.clear()
        _CACHE[key] = (np.load(key[0], allow_pickle=False), np.load(key[1], allow_pickle=False))
    return _CACHE[key]


def ic_mean(y_true, y_pred):
    from scipy.stats import rankdata
    vd, td = _dates()
    min_n = int(os.environ.get("NLFF_IC_MIN_N", "30"))
    y = np.asarray(y_true, np.float64).ravel(); p = np.asarray(y_pred, np.float64).ravel()
    if len(p) != len(y) or len(vd) == len(td):
        raise AssertionError("[nlff IC] 길이 모호 — y %d · p %d · 검증 %d · 학습 %d" % (len(y), len(p), len(vd), len(td)))
    if len(y) == len(vd):
        dd = vd
    elif len(y) == len(td):
        dd = td
    else:
        raise AssertionError("[nlff IC] 날짜 길이 불일치 — y %d · 검증 %d · 학습 %d" % (len(y), len(vd), len(td)))
    out = []
    for d in np.unique(dd):
        m = (dd == d) & np.isfinite(y) & np.isfinite(p)
        if m.sum() < min_n:
            continue
        ry, rp = rankdata(y[m]), rankdata(p[m])
        if ry.std() == 0 or rp.std() == 0:
            out.append(0.0)
            continue
        out.append(float(np.corrcoef(ry, rp)[0, 1]))
    return float(np.mean(out)) if out else -1.0
