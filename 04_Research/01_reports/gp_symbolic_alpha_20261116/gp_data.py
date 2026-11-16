"""gp_data.py — GP 알파 탐색용 일별 패널 적재기 (gpa_v2 · 2026-11-16)

무엇: 로그 캐시(rawdata_log · 단말) · RAWDATA(위생 · 표적) · 재무 캐시(분기 · TTM → 규모 없는 비율) · KOSPI200 · CD91 을
  (날짜 T × 종목 N) float32 행렬로 펴고(store_dir 가 있으면 .npy memmap)
  측정 축 위생 멤버(일별) · 월말 색인 · 다음 달 보유 수익(표적) · 월간 벤치 · 무위험 수익을 만든다.
PIT:
  - 위생 멤버(t) = 관리 · 정지 · 불성실공시 표식(t) 아님 ∧ 20일 평균 거래대금(t−1 까지) ≥ 2e8 ∧ 전날 수정 종가 ≥ 1,000
    (contracts/measurement_axis.R::ma_adv20_l1 · ma_close_l1 · factor_z_standard.R::corp_action_member 와 같은 정의 — 결측 표식 = 표식 아님).
  - 재무 값(t) = Factor_Date ≤ t 인 마지막 행(fund_access.R::fa_latest 와 같은 규칙) · 기간 말이 t − 15개월보다 앞서면 버림.
  - 재무 비율 · 수익률형 로그 단말은 날짜별 단면 1%/99% 윈저(그날 단면 통계만).
  - 수정주가 수준(open/high/low/close) · 수정 거래량 수준은 단말로 쓰지 않는다(그 뒤 기업행위 수정 계수가 거꾸로 들어 있다).
    단 위생의 동전주 바닥(전날 수정 종가 ≥ 1,000)은 측정 축 epoch 정의 그대로 RAWDATA Close 를 쓴다(축의 기록된 PIT 경계).
  - 표적: 월말 m 신호 → 다음 달(m+1) 첫 거래일 ~ 마지막 거래일 일별 Ret 복리(결측일 = 0 · 상장폐지 뒤 현금 취급 · 기록).
  - 벤치 = 공표 KOSPI200(BM_Src = quantiwise_iks200) 같은 달 복리 · 무위험 = 월말 m 의 CD91 연율 / 12(보유 시작 전 값).
쓰기 = store_dir 의 .npy(패널 사본)뿐 · 원천은 읽기 전용.
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


def _shift_down(a: np.ndarray, k: int = 1) -> np.ndarray:
    out = np.full(a.shape, np.nan, dtype=a.dtype)
    if k < a.shape[0]:
        out[k:] = a[:-k]
    return out


class _Store:
    """필드 저장소 — store_dir 가 있으면 (T,N) 배열을 .npy 로 쓰고 읽기 전용 memmap 으로 다시 연다(RSS = 건드린 쪽만 ·
    EXP 후반 해 4 GB 상한 대응). 없으면 메모리에 둔다(시험용)."""

    def __init__(self, store_dir):
        self.d = store_dir
        if store_dir:
            os.makedirs(store_dir, exist_ok=True)

    def put(self, name, a):
        if not self.d:
            return a
        path = os.path.join(self.d, name + ".npy")
        np.save(path, a)
        del a
        return np.load(path, mmap_mode="r")


def _read_col(path, col, flt):
    return ds.dataset(path).to_table(columns=[col], filter=flt).column(0).to_numpy(zero_copy_only=False)


def build_panel(cfg: dict, start: str, end: str, tickers: list | None = None, fund: bool = True,
                verbose: bool = True, store_dir: str | None = None) -> Panel:
    """단말(gpa_v2 · 2026-11-16 도훈 결정):
      가격 · 거래 = 로그 캐시 .cache/rawdata_log.parquet 의 LogRet · LogBMRet · LogSize · LogFloatCap · LogAmount · LogHL · LogCO · LogGap
        (수정주가 수준 open/high/low/close 는 그 뒤 분할 · 증자 수정 계수가 거꾸로 들어 있어 뺀다 · LogVol 도 수정 거래량 수준이라 뺀다 — README §2)
      재무 = 규모 없는 비율만(÷ 시가총액(그날 RAWDATA Size) · ÷ 총자산 · 성장률) — 원 단위 수준 · 주당 값 없음
    위생 · 유니버스 · 표적 수익 = RAWDATA(그대로)."""
    D = cfg["data"]
    U = cfg["universe"]
    q = tuple(cfg["grammar"]["winsor_q"])
    st = _Store(store_dir)
    raw = os.path.join(ROOT, D["rawdata"])
    flt = (pc.field("Date") >= pd.Timestamp(start).date()) & (pc.field("Date") <= pd.Timestamp(end).date())
    if tickers is not None:
        flt = flt & pc.field("Ticker").isin(list(tickers))
    key = ds.dataset(raw).to_table(columns=["Date", "Ticker"], filter=flt).to_pandas()
    dates = np.array(sorted(key["Date"].unique()), dtype="datetime64[D]")
    tick = np.array(sorted(key["Ticker"].unique()))
    T, N = len(dates), len(tick)
    di = np.searchsorted(dates, key["Date"].to_numpy(dtype="datetime64[D]"))
    ti = np.searchsorted(tick, key["Ticker"].to_numpy())
    del key

    def piv(path, col, di_, ti_):
        a = np.full((T, N), np.nan, dtype=F32)
        a[di_, ti_] = _read_col(path, col, flt).astype(np.float64).astype(F32)
        return a

    f = {}
    # RAWDATA — 위생 · 표적에만(단말 아님)
    close = piv(raw, "Close", di, ti)
    vol = piv(raw, "Vol", di, ti)
    amount = (close.astype(np.float64) * vol).astype(F32)
    del vol
    adv_l1 = _shift_down(bn.move_mean(amount, U["adv_window"], min_count=U["adv_window"], axis=0), U["lag_days"])
    del amount
    close_l1 = _shift_down(close, U["lag_days"])
    elig = np.isfinite(adv_l1) & (adv_l1 >= U["liq_min_krw"]) & np.isfinite(close_l1) & (close_l1 >= U["price_floor_krw"])
    del adv_l1, close_l1
    for k in U["excluded_flags"]:
        a = piv(raw, k, di, ti)
        elig &= ~(a == 1)
        del a
    elig &= np.isfinite(close)
    del close
    f["ret_raw"] = st.put("ret_raw", piv(raw, "Ret", di, ti))
    size = piv(raw, "Size", di, ti)            # 그날 시가총액(원) — 재무 ÷ 시총용(PIT: 결정일 값)
    # 로그 캐시 단말
    lg = os.path.join(ROOT, D["rawdata_log"])
    lkey = ds.dataset(lg).to_table(columns=["Date", "Ticker"], filter=flt).to_pandas()
    ldi = np.searchsorted(dates, lkey["Date"].to_numpy(dtype="datetime64[D]"))
    lti = np.searchsorted(tick, lkey["Ticker"].to_numpy())
    okk = (ldi < T) & (lti < N)
    okk[okk] &= (dates[ldi[okk]] == lkey["Date"].to_numpy(dtype="datetime64[D]")[okk]) & (tick[lti[okk]] == lkey["Ticker"].to_numpy()[okk])
    if not okk.all():
        raise ValueError(f"[gp_data] 로그 캐시 키 {int((~okk).sum())}행이 RAWDATA 격자 밖")
    del lkey
    wins = set(cfg["grammar"]["winsor_inputs"])
    for col in cfg["grammar"]["terminals_log"]:
        a = piv(lg, col, ldi, lti)
        if col in wins:
            a = cs_winsor(a, q)
        f[col] = st.put(col, a)
    # 재무 비율
    if fund:
        f.update(_fund_ratios(cfg, dates, tick, size, q, st, verbose))
    del size
    elig = st.put("elig", elig)
    # 벤치 · 무위험(일별 정렬)
    bm = ds.dataset(os.path.join(ROOT, D["benchmark"])).to_table().to_pandas()
    bm = bm[bm["BM_Src"] == D["benchmark_src"]]
    bm_daily = pd.Series(bm["BM_Ret"].to_numpy(), index=pd.to_datetime(bm["Date"])).reindex(pd.to_datetime(dates)).to_numpy()
    rf = ds.dataset(os.path.join(ROOT, D["rf"])).to_table().to_pandas()
    rf = rf[rf["Series"] == D["rf_series"]]
    rfs = pd.Series(rf["Value"].to_numpy(), index=pd.to_datetime(rf["Date"])).sort_index()
    rf_daily = rfs.reindex(pd.to_datetime(dates), method="ffill").to_numpy()  # 과거 값만 앞으로 채움
    me_idx = _month_end_index(dates, end)
    p = Panel(dates, tick, f, elig, me_idx, dates[me_idx], None, None, None, None, {},
              {"start": start, "end": end, "_bm_daily": bm_daily, "_rf_daily": rf_daily, "store_dir": store_dir})
    _attach_targets(p, bm_daily, rf_daily)
    p.std_factors = std_factors(p)
    if verbose:
        print(f"[gp_data] panel T={T} N={N} months={len(me_idx)} terminals={len([k for k in f if k != 'ret_raw'])} "
              f"bytes={sum(v.nbytes for v in f.values())/2**20:.0f}MB({'memmap' if store_dir else 'ram'}) elig/day={np.asarray(elig).sum(1).mean():.0f}")
    return p


def _asof_item(t, it, dates, tick, min_pd):
    """한 항목의 (T,N) as-of 값 — Factor_Date ≤ t 인 마지막 행(fa_latest) · 기간 말이 15개월보다 오래면 NA."""
    T, N = len(dates), len(tick)
    x = t[t["Item"] == it].sort_values(["Ticker", "Factor_Date", "Period_Date"])
    val = np.full((T, N), np.nan, dtype=F32)
    pdv = np.full((T, N), np.datetime64("NaT"), dtype="datetime64[D]")
    fd = x["Factor_Date"].to_numpy(dtype="datetime64[D]")
    row = np.searchsorted(dates, fd, side="left")      # Factor_Date ≤ dates[row] 인 첫 거래일
    tic = np.searchsorted(tick, x["Ticker"].to_numpy())
    ok = row < T
    x, row, tic = x[ok], row[ok], tic[ok]
    if not len(x):
        raise ValueError(f"[gp_data] 재무 항목 {it} 행 0 — 캐시 항목 이름 확인")
    k = tic.astype(np.int64) * (T + 1) + row
    last = np.r_[k[1:] != k[:-1], True]
    val[row[last], tic[last]] = x["Value"].to_numpy()[last].astype(F32)
    pdv[row[last], tic[last]] = x["Period_Date"].to_numpy(dtype="datetime64[D]")[last]
    val = _ffill(val)
    pdv = _ffill_dt(pdv)
    val[~(pdv >= min_pd[:, None])] = np.nan
    return val


def _fund_ratios(cfg, dates, tick, size, q, st, verbose) -> dict:
    """규모 없는 재무 비율(README §2 표 · 근거 문헌). 분자 · 분모 각각 fa_latest 규칙 · 시총 = 그날 Size.
    비율 = 분모 ≤ 0 이면 NA(음수 시총 · 자산 없음) · 날짜별 단면 1/99 윈저."""
    D = cfg["data"]
    R = D["fund_ratios"]
    items = sorted({i for r in R.values() for i in r["num"] + ([r["den"]] if r["den"] not in ("cap", "none") else [])})
    t = ds.dataset(os.path.join(ROOT, D["fund_q"])).to_table(
        columns=["Ticker", "Period_Date", "Factor_Date", "Item", "Value"],
        filter=pc.field("Item").isin(items) & pc.field("Ticker").isin(list(tick))).to_pandas()
    t = t[np.isfinite(t["Value"])]
    t["Factor_Date"] = pd.to_datetime(t["Factor_Date"])
    t["Period_Date"] = pd.to_datetime(t["Period_Date"])
    min_pd = (pd.to_datetime(dates) - pd.DateOffset(months=D["fund_max_age_months"])).to_numpy(dtype="datetime64[D]")
    cache = {}
    for it in items:   # 항목 배열은 임시 memmap(메모리 정점 ↓ · 비율 다 만들면 지움) — 저장소 없으면 메모리
        cache[it] = st.put("_item_" + it, _asof_item(t, it, dates, tick, min_pd))
    del t
    out = {}
    with np.errstate(invalid="ignore", divide="ignore"):
        for name, r in R.items():
            num = cache[r["num"][0]].astype(np.float64)
            if len(r["num"]) == 2:       # 차(발생액 = 순이익 − 영업현금흐름)
                num = num - cache[r["num"][1]]
            if r["den"] == "none":
                v = num
            else:
                den = size.astype(np.float64) if r["den"] == "cap" else cache[r["den"]].astype(np.float64)
                v = np.where(den > 0, num / den, np.nan)
            v = np.where(np.isfinite(v), v, np.nan).astype(F32)
            out["fr_" + name] = st.put("fr_" + name, cs_winsor(v, q))
    del cache
    if st.d:
        import gc
        gc.collect()
        for it in items:
            try:
                os.remove(os.path.join(st.d, "_item_" + it + ".npy"))
            except OSError:
                pass
    if verbose:
        print(f"[gp_data] fund ratios={len(out)} items={len(items)}")
    return out


def _ffill(a: np.ndarray) -> np.ndarray:
    T = a.shape[0]
    idx = np.where(np.isfinite(a), np.arange(T, dtype=np.int32)[:, None], np.int32(0))
    np.maximum.accumulate(idx, axis=0, out=idx)
    out = a[idx, np.arange(a.shape[1])[None, :]]
    seen = np.maximum.accumulate(np.isfinite(a), axis=0)
    out[~seen] = np.nan
    return out


def _ffill_dt(a: np.ndarray) -> np.ndarray:
    T = a.shape[0]
    fin = ~np.isnat(a)
    idx = np.where(fin, np.arange(T, dtype=np.int32)[:, None], np.int32(0))
    np.maximum.accumulate(idx, axis=0, out=idx)
    out = a[idx, np.arange(a.shape[1])[None, :]]
    seen = np.maximum.accumulate(fin, axis=0)
    out[~seen] = np.datetime64("NaT")
    return out


def std_factors(p: Panel) -> dict:
    """중복 벌점용 표준 팩터(로그 캐시로 직접 · 월말 값 · 과거 값만):
    MOM12_1 = Σ LogRet(t−251 … t−21) (Jegadeesh & Titman 1993) · STREV = Σ LogRet(t−20 … t) (Jegadeesh 1990)
    SIZE = LogSize(t) (Banz 1981) · LOWVOL = −std(LogRet, 60)(t) (Ang, Hodrick, Xing & Zhang 2006).
    로그 수익 합 = 수정 계수가 상쇄된 실제 누적 수익(수정주가 수준을 쓰지 않는다)."""
    r = np.asarray(p.fields["LogRet"], dtype=np.float64)
    me = p.me_idx
    def mv(fn, w, mc):   # 패널이 창보다 짧으면 전부 NaN
        return fn(r, w, min_count=mc, axis=0) if r.shape[0] >= w else np.full(r.shape, np.nan)
    s21 = mv(bn.move_sum, 21, 16)
    mom = _shift_down(mv(bn.move_sum, 231, 174), 21)
    vol = mv(bn.move_std, 60, 45)
    return {"MOM12_1": mom[me].astype(F32), "STREV": s21[me].astype(F32),
            "SIZE": np.asarray(p.fields["LogSize"])[me].astype(F32), "LOWVOL": (-vol[me]).astype(F32)}


# ---------------------------------------------------------------- 별도 프로세스 적재(메모리 정점 분리)
def save_panel(p: Panel, d: str) -> None:
    """패널 전부를 d 에 저장(필드 · 위생은 build_panel 이 이미 .npy 로 썼다 · 나머지 작은 배열 + 메타)."""
    np.save(os.path.join(d, "dates.npy"), p.dates)
    np.save(os.path.join(d, "tickers.npy"), p.tickers.astype("U12"))
    np.save(os.path.join(d, "me_idx.npy"), p.me_idx)
    np.save(os.path.join(d, "bm_daily.npy"), p.meta["_bm_daily"])
    np.save(os.path.join(d, "rf_daily.npy"), p.meta["_rf_daily"])
    for k, v in p.std_factors.items():
        np.save(os.path.join(d, f"std_{k}.npy"), v)
    meta = {"fields": sorted(p.fields), "std": sorted(p.std_factors), "start": p.meta["start"], "end": p.meta["end"]}
    with open(os.path.join(d, "panel_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f)


def load_panel(d: str) -> Panel:
    """save_panel 결과를 memmap 으로 다시 연다(이 프로세스는 적재 임시 배열을 한 번도 갖지 않는다)."""
    with open(os.path.join(d, "panel_meta.json"), encoding="utf-8") as f:
        meta = json.load(f)
    L = lambda n, mm=True: np.load(os.path.join(d, n + ".npy"), mmap_mode="r" if mm else None)
    dates = L("dates", False); tick = L("tickers", False).astype(str)
    fields = {k: L(k) for k in meta["fields"]}
    bm_daily, rf_daily = L("bm_daily", False), L("rf_daily", False)
    me_idx = L("me_idx", False)
    p = Panel(dates, tick, fields, L("elig"), me_idx, dates[me_idx], None, None, None, None,
              {k: L("std_" + k, False) for k in meta["std"]},
              {"start": meta["start"], "end": meta["end"], "_bm_daily": bm_daily, "_rf_daily": rf_daily, "store_dir": d})
    _attach_targets(p, bm_daily, rf_daily)
    return p


def build_panel_subprocess(cfg_path: str | None, start: str, end: str, tickers: list | None, store_dir: str,
                           python: str | None = None) -> Panel:
    """적재를 자식 프로세스에서 돌리고(정점 메모리는 자식이 지고 끝나면 반환) 부모는 memmap 으로 연다."""
    import subprocess
    import sys
    os.makedirs(store_dir, exist_ok=True)
    tk = os.path.join(store_dir, "_tickers.json")
    with open(tk, "w", encoding="utf-8") as f:
        json.dump(tickers, f)
    code = ("import sys,json; sys.path.insert(0, %r); from gp_data import *; cfg=load_cfg(%r); "
            "t=json.load(open(%r,encoding='utf-8')); p=build_panel(cfg,%r,%r,tickers=t,store_dir=%r); save_panel(p,%r); "
            "import psutil; mi=psutil.Process().memory_info(); print('[gp_data] 자식 적재 정점 사유 %%.2fGB' %% (getattr(mi,'peak_pagefile',mi.rss)/2**30))"
            % (HERE, cfg_path, tk, start, end, store_dir, store_dir))
    r = subprocess.run([python or sys.executable, "-W", "ignore", "-c", code], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("[gp_data] 자식 적재 실패:\n" + r.stderr[-2000:])
    print(r.stdout.strip())
    return load_panel(store_dir)
