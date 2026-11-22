"""aif_roll.py — 일별 패널 [날짜 × 종목] 에서 '신호일 시점의 과거 창 통계'를 뽑는 도구.

모든 함수는 rows(신호일의 날짜 위치)에서 끝나는 창만 본다 — 창은 [t − w + 1, t] 이고 t 뒤의 행은 읽지 않는다(PIT).
누적합 방식이라 결측은 0 으로 두고 유효 개수를 따로 센다. 유효 개수가 min_obs 에 못 미치면 NaN.
돌려주는 배열 = [len(rows) × 종목] float32.
"""
import warnings

import numpy as np


class Cum:
    """한 패널의 누적합(값 · 제곱 · 개수)을 한 번 만들어 여러 창에 쓴다. x = [T × N] (NaN = 결측)."""

    def __init__(self, x, power=2):
        ok = np.isfinite(x)
        z = np.where(ok, x, 0.0).astype(np.float64)
        pad = lambda a: np.vstack([np.zeros((1, a.shape[1]), dtype=np.float64), np.cumsum(a, axis=0)])   # noqa: E731 — 앞에 0 행을 붙여 C[t+1] − C[t+1−w]
        self.n = pad(ok.astype(np.float64))
        self.s1 = pad(z)
        self.s2 = pad(z * z) if power >= 2 else None
        self.s3 = pad(z ** 3) if power >= 3 else None
        self.T = x.shape[0]

    def _win(self, C, rows, w):
        hi = rows + 1
        lo = np.maximum(hi - w, 0)
        return C[hi] - C[lo]

    def count(self, rows, w):
        return self._win(self.n, rows, w)

    def sum(self, rows, w, min_obs=None):
        n = self.count(rows, w)
        o = self._win(self.s1, rows, w)
        return _mask(o, n, w if min_obs is None else min_obs)

    def mean(self, rows, w, min_obs=None):
        n = self.count(rows, w)
        with np.errstate(invalid="ignore", divide="ignore"):
            o = self._win(self.s1, rows, w) / n
        return _mask(o, n, w if min_obs is None else min_obs)

    def std(self, rows, w, min_obs=None):
        n = self.count(rows, w)
        s1, s2 = self._win(self.s1, rows, w), self._win(self.s2, rows, w)
        with np.errstate(invalid="ignore", divide="ignore"):
            v = (s2 - s1 * s1 / n) / (n - 1.0)
            o = np.sqrt(np.maximum(v, 0.0))
        return _mask(o, n, max(3, w if min_obs is None else min_obs))

    def skew(self, rows, w, min_obs=None):
        n = self.count(rows, w)
        s1, s2, s3 = self._win(self.s1, rows, w), self._win(self.s2, rows, w), self._win(self.s3, rows, w)
        with np.errstate(invalid="ignore", divide="ignore"):
            m = s1 / n
            v = s2 / n - m * m
            o = (s3 / n - 3 * m * s2 / n + 2 * m ** 3) / np.power(np.maximum(v, 1e-30), 1.5)
            o = np.where(v > 1e-18, o, np.nan)
        return _mask(o, n, max(8, w if min_obs is None else min_obs))


def _mask(o, n, min_obs):
    return np.where(n >= min_obs, o, np.nan).astype(np.float32)


def cross(x, y, rows, w, min_obs=None):
    """창 안에서 x(종목) 를 y(종목 또는 시장 공통 [T] 벡터)에 회귀한 기울기 · 잔차 표준편차 · 상관. 둘 다 유효한 날만 쓴다."""
    if y.ndim == 1:
        y = np.broadcast_to(y[:, None], x.shape)
    ok = np.isfinite(x) & np.isfinite(y)
    xz, yz = np.where(ok, x, 0.0).astype(np.float64), np.where(ok, y, 0.0).astype(np.float64)
    pad = lambda a: np.vstack([np.zeros((1, a.shape[1])), np.cumsum(a, axis=0)])   # noqa: E731
    hi = rows + 1
    lo = np.maximum(hi - w, 0)
    win = lambda a: (lambda C: C[hi] - C[lo])(pad(a))   # noqa: E731
    n, sx, sy, sxx, syy, sxy = win(ok.astype(np.float64)), win(xz), win(yz), win(xz * xz), win(yz * yz), win(xz * yz)
    with np.errstate(invalid="ignore", divide="ignore"):
        cxy, vy, vx = sxy - sx * sy / n, syy - sy * sy / n, sxx - sx * sx / n
        beta = cxy / vy
        resid = np.sqrt(np.maximum(vx - beta * cxy, 0.0) / (n - 2.0))
        corr = cxy / np.sqrt(vx * vy)
    m = max(10, w // 2 if min_obs is None else min_obs)
    bad = ~(vy > 1e-18)
    out = []
    for a in (beta, resid, corr):
        a = np.where(bad, np.nan, a)
        out.append(_mask(a, n, m))
    return out


def window_max(x, rows, w, min_obs=None, fn=np.nanmax):
    """창 안 최댓값(또는 fn). 누적합으로 못 구하는 통계 — 신호일마다 창을 잘라 본다."""
    o = np.full((len(rows), x.shape[1]), np.nan, dtype=np.float32)
    m = w if min_obs is None else min_obs
    for i, t in enumerate(rows):
        a = x[max(0, t - w + 1): t + 1]
        n = np.isfinite(a).sum(axis=0)
        k = n >= m
        if k.any():
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", RuntimeWarning)       # 창 안이 전부 결측인 열은 위에서 걸렀지만, 일부 결측 경고는 조용히 넘긴다
                o[i, k] = fn(a[:, k], axis=0)
    return o


def last_valid(x, rows, max_age=None):
    """신호일까지의 마지막 유효값(as-of). max_age(행 수)보다 오래된 값은 NaN. x = [T × N]."""
    T, N = x.shape
    ok = np.isfinite(x)
    idx = np.where(ok, np.arange(T)[:, None], -1)
    np.maximum.accumulate(idx, axis=0, out=idx)
    li = idx[rows]
    o = np.where(li >= 0, x[np.clip(li, 0, T - 1), np.arange(N)[None, :]], np.nan)
    if max_age is not None:
        o = np.where((rows[:, None] - li) <= max_age, o, np.nan)
    return o.astype(np.float32)
