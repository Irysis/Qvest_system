"""aif_daily.py — 일별 원자료(긴 표: Date · Ticker · 값 열들)를 공통 틀의 종목 순서에 맞춘 [날짜 × 종목] 패널로 펴는 적재기.

달력은 공통 틀보다 앞으로 늘린다(과거 창 예열용) — dates = 예열 구간 + 공통 틀 거래일. 종목은 공통 틀의 종목만.
cut(날짜)을 주면 그 뒤의 행을 원천에서 잘라낸다 — 미래 행 잘라내기 자가 시험용(자른 원천으로 만든 값 = 전체로 만든 값이어야 한다).
"""
import numpy as np
import pyarrow.compute as pc
import pyarrow.dataset as ds

import aif_common as ac


def to_days(col):
    return np.asarray(col.to_numpy(zero_copy_only=False)).astype("datetime64[D]")


def date_filter(dset, date_col, lo=None, hi=None, isin=None):
    """날짜 열의 형에 맞춘 걸러내기 식(date32 · timestamp 모두)."""
    ftype = dset.schema.field(date_col).type
    sc = lambda d: pc.scalar(np.datetime64(d, "D").astype(object)).cast(ftype)   # noqa: E731
    f = None
    if lo is not None:
        f = pc.field(date_col) >= sc(lo)
    if hi is not None:
        g = pc.field(date_col) <= sc(hi)
        f = g if f is None else (f & g)
    if isin is not None:
        import pyarrow as pa
        g = pc.field(date_col).isin(pa.array([np.datetime64(d, "D").astype(object) for d in isin]).cast(ftype))
        f = g if f is None else (f & g)
    return f


class DailyGrid:
    """한 원천 파일의 [날짜 × 종목] 격자. 값 열은 한 번에 읽어 두고(self.raw) 필요할 때 패널로 편다."""

    def __init__(self, frame, path, columns, ext_start=None, cut=None, base_dates=None, date_col="Date", ticker_col="Ticker", extra_filter=None):
        self.frame, self.path = frame, path
        dset = ds.dataset(path, format="parquet")
        hi = frame.dates[-1] if cut is None else np.datetime64(cut, "D")
        lo = base_dates[0] if base_dates is not None else np.datetime64(ext_start, "D")
        flt = date_filter(dset, date_col, lo, hi)
        if extra_filter is not None:
            flt = flt & extra_filter
        tab = dset.to_table(columns=[date_col, ticker_col] + list(columns), filter=flt)
        d = to_days(tab.column(date_col))
        tk = tab.column(ticker_col).combine_chunks().dictionary_encode()
        tmap = frame.ticker_index(tk.dictionary.to_pylist())
        ti = tmap[tk.indices.to_numpy(zero_copy_only=False)]
        if base_dates is None:                                   # 이 원천의 날짜로 예열 구간 달력을 만든다
            pre = np.unique(d[d < frame.dates[0]])
            base_dates = np.concatenate([pre, frame.dates])
        self.dates = base_dates[base_dates <= hi]
        self.T, self.N = len(self.dates), frame.nt
        di = np.clip(np.searchsorted(self.dates, d), 0, self.T - 1)
        ok = (self.dates[di] == d) & (ti >= 0)
        self._di, self._ti = di[ok].astype(np.int32), ti[ok].astype(np.int32)
        self.raw = {c: np.asarray(tab.column(c).to_numpy(zero_copy_only=False), dtype=np.float64)[ok] for c in columns}
        self.rows_total, self.rows_used = len(d), int(ok.sum())
        self.offset = int(np.searchsorted(self.dates, frame.dates[0]))          # 공통 틀 첫 거래일의 위치
        s_ok = frame.sig_dates <= hi
        self.sig_sel = np.nonzero(s_ok)[0]                                       # 이 격자가 덮는 신호(공통 틀 색인)
        self.sig_rows = (frame.sig_idx[s_ok] + self.offset).astype(np.int64)     # 그 신호일의 위치(이 달력 안)
        if not np.array_equal(self.dates[self.sig_rows], frame.sig_dates[s_ok]):
            raise RuntimeError("[aif] 달력이 공통 틀과 어긋난다: " + path)

    def panel(self, name, dtype=np.float32, drop=True):
        a = np.full((self.T, self.N), np.nan, dtype=dtype)
        a[self._di, self._ti] = self.raw[name].astype(dtype)
        if drop:
            del self.raw[name]
        return a

    def present(self):
        """그날 그 종목의 행이 있었는가 [T × N]."""
        a = np.zeros((self.T, self.N), dtype=bool)
        a[self._di, self._ti] = True
        return a


def to_signals(frame, sig_sel, x):
    """[len(sig_sel) × N (× k)] → 공통 틀의 신호 격자 [ns × N (× k)](덮지 못한 신호 = NaN)."""
    o = np.full((frame.ns,) + x.shape[1:], np.nan, dtype=np.float32)
    o[sig_sel] = x
    return o


def lag_rows(rows, k=1):
    """신호일보다 k 거래일 앞의 위치(전날까지만 알 수 있는 자료용). 0 아래로는 내려가지 않는다."""
    return np.maximum(rows - k, 0)


def log_path(lr):
    """로그 수익의 누적 경로(결측 = 0 · 첫 유효값 전 = NaN). 수정주가 수준 대신 쓴다 — 창 안 고점 · 저점 대비 위치 계산용."""
    ok = np.isfinite(lr)
    c = np.cumsum(np.where(ok, lr, 0.0), axis=0, dtype=np.float64)
    c[~np.maximum.accumulate(ok, axis=0)] = np.nan
    return c


def wsum(a, rows, w):
    """[T × N] 배열의 창 합(창 = [t − w + 1, t]) 을 rows 에서만. 결측은 부르는 쪽이 0 으로 바꿔 넘긴다."""
    c = np.cumsum(a, axis=0, dtype=np.float64)
    lo = rows - w
    return c[rows] - np.where(lo[:, None] >= 0, c[np.maximum(lo, 0)], 0.0)
