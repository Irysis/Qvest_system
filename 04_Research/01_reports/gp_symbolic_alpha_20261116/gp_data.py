"""gp_data.py — GP 알파 탐색용 일별 패널 적재기 (gpa_v1 · 2026-11-16)

무엇: RAWDATA · 재무 캐시(분기 · TTM) · KOSPI200 · CD91 을 (날짜 T × 종목 N) float32 행렬로 펴고
  측정 축 위생 멤버(일별) · 월말 색인 · 다음 달 보유 수익(표적) · 월간 벤치 · 무위험 수익을 만든다.
PIT:
  - 위생 멤버(t) = 관리 · 정지 · 불성실공시 표식(t) 아님 ∧ 20일 평균 거래대금(t−1 까지) ≥ 2e8 ∧ 전날 수정 종가 ≥ 1,000
    (contracts/measurement_axis.R::ma_adv20_l1 · ma_close_l1 · factor_z_standard.R::corp_action_member 와 같은 정의 — 결측 표식 = 표식 아님).
  - 재무 값(t) = Factor_Date ≤ t 인 마지막 행(fund_access.R::fa_latest 와 같은 규칙) · 기간 말이 t − 15개월보다 앞서면 버림.
  - 재무 입력은 날짜별 단면 1%/99% 윈저(그날 단면 통계만).
  - 표적: 월말 m 신호 → 다음 달(m+1) 첫 거래일 ~ 마지막 거래일 일별 Ret 복리(결측일 = 0 · 상장폐지 뒤 현금 취급 · 기록).
  - 벤치 = 공표 KOSPI200(BM_Src = quantiwise_iks200) 같은 달 복리 · 무위험 = 월말 m 의 CD91 연율 / 12(보유 시작 전 값).
쓰기 없음(읽기 전용).
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

import bottleneck as bn
import numpy as np
import pandas as pd
import pyarrow.compute as pc
import pyarrow.dataset as ds

ROOT = os.environ.get("QM_ROOT", "G:/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
HERE = os.path.dirname(os.path.abspath(__file__))
F32 = np.float32


def load_cfg(path: str | None = None) -> dict:
    with open(path or os.path.join(HERE, "gp_config.json"), encoding="utf-8") as f:
        return json.load(f)


def cs_winsor(x: np.ndarray, q=(0.01, 0.99)) -> np.ndarray:
    """날짜(행)별 단면 윈저 — 그 행의 유한값 분위만 쓴다(PIT: 다른 날짜 무접촉)."""
    x = np.where(np.isfinite(x), x, np.nan).astype(F32, copy=False)
    r = bn.nanrankdata(x, axis=1)
    n = np.sum(np.isfinite(x), axis=1, keepdims=True).astype(F32)
    with np.errstate(invalid="ignore", divide="ignore"):
        p = (r - 1.0) / np.maximum(n - 1.0, 1.0)
    with np.errstate(all="ignore"), __import__("warnings").catch_warnings():
        __import__("warnings").simplefilter("ignore", RuntimeWarning)
        lo = np.nanmin(np.where(p >= q[0], x, np.nan), axis=1, keepdims=True)
        hi = np.nanmax(np.where(p <= q[1], x, np.nan), axis=1, keepdims=True)
    return np.clip(x, lo, hi).astype(F32)


@dataclass
class Panel:
    dates: np.ndarray            # datetime64[D] (T,)
    tickers: np.ndarray          # str (N,)
    fields: dict                 # name -> (T,N) float32
    elig: np.ndarray             # (T,N) bool — 위생 멤버
    me_idx: np.ndarray           # 월말 거래일 행 색인 (M,)
    me_dates: np.ndarray         # (M,)
    fwd_ret: np.ndarray          # (M,N) float32 — 월말 m 신호의 다음 달 보유 수익(마지막 월은 NaN)
    fwd_valid: np.ndarray        # (M,) bool — 다음 달이 데이터 안에 완전히 있는가
    bm_fwd: np.ndarray           # (M,) 다음 달 KOSPI200 수익
    rf_fwd: np.ndarray           # (M,) 다음 달 무위험 수익(월말 m 의 CD91/12)
    std_factors: dict = field(default_factory=dict)  # name -> (M,N) 월말 표준 팩터
    meta: dict = field(default_factory=dict)

    def slice_to(self, end_date) -> "Panel":
        """end_date(포함)까지만 남긴 패널 — 그 뒤 데이터는 사라진다(창 진화용 · 표적은 다시 계산)."""
        end = np.datetime64(pd.Timestamp(end_date).date(), "D")
        t = int(np.searchsorted(self.dates, end, side="right"))
        keep_m = np.isin(self.me_idx, _month_end_index(self.dates[:t], end_date))
        me_idx = self.me_idx[keep_m]
        fl = {k: v[:t] for k, v in self.fields.items()}
        p = Panel(self.dates[:t], self.tickers, fl, self.elig[:t], me_idx, self.me_dates[keep_m],
                  None, None, None, None, {k: v[keep_m] for k, v in self.std_factors.items()}, dict(self.meta))
        _attach_targets(p, self.meta["_bm_daily"][:t], self.meta["_rf_daily"][:t])
        return p


def _month_end_index(dates: np.ndarray, end) -> np.ndarray:
    """달의 마지막 거래일 행. 패널 마지막 행은 적재 끝(end)이 그 달 말일 이후일 때만 월말로 친다
    (중간에서 자른 패널의 마지막 행을 월말로 오인하면 직전 월말의 다음 달 표적이 잘린 달이 된다)."""
    ym = dates.astype("datetime64[M]")
    end_complete = (pd.Timestamp(end) + pd.Timedelta(days=1)).to_datetime64().astype("datetime64[M]") > ym[-1]
    last = np.r_[ym[1:] != ym[:-1], bool(end_complete)]
    return np.nonzero(last)[0]


def _attach_targets(p: Panel, bm_daily: np.ndarray, rf_daily: np.ndarray) -> None:
    """월말 m → 다음 달 보유 수익. 다음 달이 패널 끝 안에서 완결(그 달 마지막 거래일까지 존재)될 때만 유효.
    패널 끝이 월말이 아니면 마지막 월말의 다음 달은 미완결 → 무효(미래 쪽 잘림 처리)."""
    ret = p.fields["ret_raw"]
    T = len(p.dates)
    M = len(p.me_idx)
    fwd = np.full((M, ret.shape[1]), np.nan, dtype=F32)
    bm = np.full(M, np.nan)
    rf = np.full(M, np.nan)
    valid = np.zeros(M, dtype=bool)
    # 패널 마지막 행이 달의 마지막 거래일인지는 패널 안에서 알 수 없다 → 마지막 월말 행(= 패널 끝 행)의 다음 달은 늘 미완결.
    for m in range(M - 1):
        a, b = p.me_idx[m] + 1, p.me_idx[m + 1] + 1
        if b > T:
            break
        r = ret[a:b]
        fwd[m] = (np.nanprod(1.0 + np.where(np.isfinite(r), r, 0.0), axis=0) - 1.0).astype(F32)
        # 그 달 내내 행이 하나도 없는 종목(이미 상장폐지 등)은 NaN — 보유 불가였다는 뜻은 아니므로 0 취급은 포트폴리오 쪽에서
        anyrow = np.any(np.isfinite(r), axis=0)
        fwd[m, ~anyrow] = np.nan
        bm[m] = np.prod(1.0 + np.nan_to_num(bm_daily[a:b])) - 1.0
        rf[m] = rf_daily[p.me_idx[m]] / 100.0 / 12.0 if np.isfinite(rf_daily[p.me_idx[m]]) else np.nan
        valid[m] = True
    p.fwd_ret, p.bm_fwd, p.rf_fwd, p.fwd_valid = fwd, bm, rf, valid


def _pivot(df: pd.DataFrame, col: str, di: np.ndarray, ti: np.ndarray, T: int, N: int) -> np.ndarray:
    a = np.full((T, N), np.nan, dtype=F32)
    a[di, ti] = df[col].to_numpy(dtype=np.float64).astype(F32)
    return a


def _shift_down(a: np.ndarray, k: int = 1) -> np.ndarray:
    out = np.full_like(a, np.nan)
    if k < a.shape[0]:
        out[k:] = a[:-k]
    return out


def build_panel(cfg: dict, start: str, end: str, tickers: list | None = None, fund: bool = True,
                verbose: bool = True) -> Panel:
    D = cfg["data"]
    U = cfg["universe"]
    cols = ["Date", "Ticker", "Open", "High", "Low", "Close", "Vol", "Size", "Ret"] + U["excluded_flags"]
    flt = (pc.field("Date") >= pd.Timestamp(start).date()) & (pc.field("Date") <= pd.Timestamp(end).date())
    if tickers is not None:
        flt = flt & pc.field("Ticker").isin(list(tickers))
    df = ds.dataset(os.path.join(ROOT, D["rawdata"])).to_table(columns=cols, filter=flt).to_pandas()
    dates = np.array(sorted(df["Date"].unique()), dtype="datetime64[D]")
    tick = np.array(sorted(df["Ticker"].unique()) if tickers is None else sorted(set(tickers) & set(df["Ticker"].unique())))
    T, N = len(dates), len(tick)
    di = np.searchsorted(dates, df["Date"].to_numpy(dtype="datetime64[D]"))
    ti = np.searchsorted(tick, df["Ticker"].to_numpy())
    f = {}
    f["open"] = _pivot(df, "Open", di, ti, T, N)
    f["high"] = _pivot(df, "High", di, ti, T, N)
    f["low"] = _pivot(df, "Low", di, ti, T, N)
    f["close"] = _pivot(df, "Close", di, ti, T, N)
    f["volume"] = _pivot(df, "Vol", di, ti, T, N)
    f["cap"] = _pivot(df, "Size", di, ti, T, N)
    f["ret_raw"] = _pivot(df, "Ret", di, ti, T, N)
    f["amount"] = (f["close"].astype(np.float64) * f["volume"]).astype(F32)
    flags = {k: _pivot(df, k, di, ti, T, N) for k in U["excluded_flags"]}
    del df
    # 위생 멤버(t)
    adv = bn.move_mean(f["amount"], U["adv_window"], min_count=U["adv_window"], axis=0)
    adv_l1 = _shift_down(adv, U["lag_days"])
    close_l1 = _shift_down(f["close"], U["lag_days"])
    elig = np.isfinite(adv_l1) & (adv_l1 >= U["liq_min_krw"]) & np.isfinite(close_l1) & (close_l1 >= U["price_floor_krw"])
    for k, a in flags.items():
        elig &= ~(a == 1)
    elig &= np.isfinite(f["close"])  # 그날 행이 있어야 보유 가능
    # 입력 윈저: ret 은 날짜별 단면 1/99
    q = tuple(cfg["grammar"]["winsor_q"])
    f["ret"] = cs_winsor(f["ret_raw"], q)
    # 재무(as-of)
    if fund:
        f.update(_fund_asof(cfg, dates, tick, q, verbose))
    # 벤치 · 무위험(일별 정렬)
    bm = ds.dataset(os.path.join(ROOT, D["benchmark"])).to_table().to_pandas()
    bm = bm[bm["BM_Src"] == D["benchmark_src"]]
    bm_daily = pd.Series(bm["BM_Ret"].to_numpy(), index=pd.to_datetime(bm["Date"])).reindex(pd.to_datetime(dates)).to_numpy()
    rf = ds.dataset(os.path.join(ROOT, D["rf"])).to_table().to_pandas()
    rf = rf[rf["Series"] == D["rf_series"]]
    rfs = pd.Series(rf["Value"].to_numpy(), index=pd.to_datetime(rf["Date"])).sort_index()
    rf_daily = rfs.reindex(pd.to_datetime(dates), method="ffill").to_numpy()  # 과거 값만 앞으로 채움(ffill)
    me_idx = _month_end_index(dates, end)
    p = Panel(dates, tick, f, elig, me_idx, dates[me_idx], None, None, None, None, {},
              {"start": start, "end": end, "_bm_daily": bm_daily, "_rf_daily": rf_daily})
    _attach_targets(p, bm_daily, rf_daily)
    p.std_factors = std_factors(p)
    if verbose:
        print(f"[gp_data] panel T={T} N={N} months={len(me_idx)} fields={len(f)} "
              f"mem={sum(v.nbytes for v in f.values())/2**20:.0f}MB elig/day={elig.sum(1).mean():.0f}")
    return p


def _fund_asof(cfg, dates, tick, q, verbose) -> dict:
    D = cfg["data"]
    items = D["fund_items_ttm"] + D["fund_items_bal"]
    t = ds.dataset(os.path.join(ROOT, D["fund_q"])).to_table(
        columns=["Ticker", "Period_Date", "Factor_Date", "Item", "Value"],
        filter=pc.field("Item").isin(items) & pc.field("Ticker").isin(list(tick))).to_pandas()
    t = t[np.isfinite(t["Value"])]
    t["Factor_Date"] = pd.to_datetime(t["Factor_Date"])
    t["Period_Date"] = pd.to_datetime(t["Period_Date"])
    T, N = len(dates), len(tick)
    dts = pd.to_datetime(dates)
    min_pd = (dts - pd.DateOffset(months=D["fund_max_age_months"])).to_numpy(dtype="datetime64[D]")
    out = {}
    for it in items:
        x = t[t["Item"] == it].sort_values(["Ticker", "Factor_Date", "Period_Date"])
        val = np.full((T, N), np.nan, dtype=F32)
        pdv = np.full((T, N), np.datetime64("NaT"), dtype="datetime64[D]")
        # 각 행: 쓸 수 있는 첫 거래일 행 = searchsorted(dates, Factor_Date, left) — Factor_Date ≤ t 인 첫 t
        fd = x["Factor_Date"].to_numpy(dtype="datetime64[D]")
        row = np.searchsorted(dates, fd, side="left")
        tic = np.searchsorted(tick, x["Ticker"].to_numpy())
        ok = row < T
        x, row, tic = x[ok], row[ok], tic[ok]
        # 같은 (종목, 첫 사용 행)에 여러 행이면 마지막(정렬상 Factor_Date · Period_Date 가장 늦은 것) — fa_latest roll 과 같음
        key = tic.astype(np.int64) * (T + 1) + row
        last = np.r_[key[1:] != key[:-1], True]
        val[row[last], tic[last]] = x["Value"].to_numpy()[last].astype(F32)
        pdv[row[last], tic[last]] = x["Period_Date"].to_numpy(dtype="datetime64[D]")[last]
        # 앞으로 채움(과거 → 현재만)
        val = _ffill(val)
        pdv = _ffill_dt(pdv)
        stale = ~(pdv >= min_pd[:, None])
        val[stale] = np.nan
        out["fund_" + it] = cs_winsor(val, q)
    if verbose:
        print(f"[gp_data] fund items={len(items)} rows={len(t)}")
    return out


def _ffill(a: np.ndarray) -> np.ndarray:
    T = a.shape[0]
    idx = np.where(np.isfinite(a), np.arange(T)[:, None], 0)
    np.maximum.accumulate(idx, axis=0, out=idx)
    out = a[idx, np.arange(a.shape[1])[None, :]]
    first = np.isfinite(a)
    seen = np.maximum.accumulate(first, axis=0)
    out[~seen] = np.nan
    return out


def _ffill_dt(a: np.ndarray) -> np.ndarray:
    T = a.shape[0]
    fin = ~np.isnat(a)
    idx = np.where(fin, np.arange(T)[:, None], 0)
    np.maximum.accumulate(idx, axis=0, out=idx)
    out = a[idx, np.arange(a.shape[1])[None, :]]
    seen = np.maximum.accumulate(fin, axis=0)
    out[~seen] = np.datetime64("NaT")
    return out


def std_factors(p: Panel) -> dict:
    """중복 벌점용 표준 팩터(RAWDATA 로 직접 · 월말 값 · 과거 값만):
    MOM12_1 = close(t−21)/close(t−252) − 1 (Jegadeesh & Titman 1993) · STREV = close(t)/close(t−21) − 1 (Jegadeesh 1990)
    SIZE = log cap(t) (Banz 1981) · LOWVOL = −std(ret, 60)(t) (Ang, Hodrick, Xing & Zhang 2006)."""
    c = p.fields["close"].astype(np.float64)
    me = p.me_idx

    def lag(a, k):
        return _shift_down(a, k)

    with np.errstate(invalid="ignore", divide="ignore"):
        mom = lag(c, 21) / lag(c, 252) - 1.0
        strev = c / lag(c, 21) - 1.0
        size = np.log(p.fields["cap"].astype(np.float64))
    vol = bn.move_std(p.fields["ret"], 60, min_count=45, axis=0)
    return {"MOM12_1": mom[me].astype(F32), "STREV": strev[me].astype(F32),
            "SIZE": size[me].astype(F32), "LOWVOL": (-vol[me]).astype(F32)}
