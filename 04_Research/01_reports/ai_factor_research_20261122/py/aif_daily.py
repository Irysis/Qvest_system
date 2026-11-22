"""aif_daily.py — 일별 원자료를 공통 틀의 종목 순서에 맞춘 [날짜 × 종목] 패널로 펴는 적재기.

달력은 공통 틀보다 앞으로 늘린다(과거 창 예열용) — ext_dates = 예열 구간 + 공통 틀 거래일. 종목은 공통 틀의 종목만.
cut(날짜)을 주면 그 뒤의 행을 원천에서 잘라낸다 — 미래 행 잘라내기 자가 시험용(자른 원천으로 만든 값 = 전체로 만든 값이어야 한다).
"""
import numpy as np
import pyarrow.compute as pc
import pyarrow.dataset as ds

import aif_common as ac


def _to_days(col):
    return col.to_numpy(zero_copy_only=False).astype("datetime64[D]")


class DailyGrid:
    """한 원천 파일(긴 표: Date · Ticker · 값 열들)의 [날짜 × 종목] 격자. 값 열은 필요할 때 하나씩 편다."""

    def __init__(self, frame, path, ext_start, cut=None, date_col="Date", ticker_col="Ticker", base_dates=None):
        self.frame, self.path, self.date_col, self.ticker_col = frame, path, date_col, ticker_col
        self.dset = ds.dataset(path, format="parquet")
        lo = np.datetime64(ext_start, "D")
        hi = frame.dates[-1] if cut is None else np.datetime64(cut, "D")
        ftype = self.dset.schema.field(date_col).type
        self._flt = (pc.field(date_col) >= pc.scalar(lo.astype(object)).cast(ftype)) & (pc.field(date_col) <= pc.scalar(hi.astype(object)).cast(ftype))
        key = self.dset.to_table(columns=[date_col, ticker_col], filter=self._flt)
        d = _to_days(key.column(0))
        tk = key.column(1).to_numpy(zero_copy_only=False)
        if base_dates is None:                                   # 이 원천의 날짜로 달력을 만든다(예열 구간) + 공통 틀 거래일
            pre = np.unique(d[d < frame.dates[0]])
            base_dates = np.concatenate([pre, frame.dates[frame.dates <= hi]])
        self.dates = base_dates
        self.T, self.N = len(self.dates), frame.nt
        di = np.searchsorted(self.dates, d)
        di = np.clip(di, 0, self.T - 1)
        ti = frame.ticker_index(tk)
        self._ok = (self.dates[di] == d) & (ti >= 0)
        self._di, self._ti = di[self._ok].astype(np.int32), ti[self._ok].astype(np.int32)
        self.rows_total, self.rows_used = len(d), int(self._ok.sum())
        self.offset = int(np.searchsorted(self.dates, frame.dates[0]))          # 공통 틀 첫 거래일의 위치
        s_ok = frame.sig_dates <= hi
        self.sig_rows = (frame.sig_idx[s_ok] + self.offset).astype(np.int64)    # 신호일의 위치(이 달력 안)
        self.sig_sel = np.nonzero(s_ok)[0]
        if not np.array_equal(self.dates[self.sig_rows], frame.sig_dates[s_ok]):
            raise RuntimeError("[aif] 달력이 공통 틀과 어긋난다: " + path)

    def col(self, name, dtype=np.float32):
        v = self.dset.to_table(columns=[name], filter=self._flt).column(0).to_numpy(zero_copy_only=False)
        a = np.full((self.T, self.N), np.nan, dtype=dtype)
        a[self._di, self._ti] = v[self._ok].astype(np.float64).astype(dtype)
        return a

    def to_signals(self, x):
        """[len(sig_rows) × N] → 공통 틀의 신호 격자 [ns × N](cut 뒤의 신호는 NaN)."""
        o = np.full((self.frame.ns, self.N), np.nan, dtype=np.float32)
        o[self.sig_sel] = x
        return o


def lag_rows(rows, k=1):
    """신호일보다 k 거래일 앞의 위치(전날까지만 알 수 있는 자료용). 0 아래로는 내려가지 않는다."""
    return np.maximum(rows - k, 0)


def log_path(lr):
    """로그 수익의 누적 경로(결측 = 0 · 첫 유효값 전 = NaN). 수정주가 수준 대신 쓴다 — 창 안 고점 · 저점 대비 위치 계산용."""
    ok = np.isfinite(lr)
    c = np.cumsum(np.where(ok, lr, 0.0), axis=0, dtype=np.float64)
    seen = np.maximum.accumulate(ok, axis=0)
    c[~seen] = np.nan
    return c


if __name__ == "__main__":
    fr = ac.Frame()
    g = DailyGrid(fr, ac.root() + "/.cache/rawdata_log.parquet", "1996-01-01")
    ac.log("일별 격자 — 날짜 %d(%s ~ %s) · 종목 %d · 행 %d 중 %d 사용 · 예열 %d일", g.T, g.dates[0], g.dates[-1], g.N, g.rows_total, g.rows_used, g.offset)
