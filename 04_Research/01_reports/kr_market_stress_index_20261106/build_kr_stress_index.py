#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""KR-CISS 시제품 — 국내 자본시장 스트레스 지수 (아이디어 연구 · 도훈 2026-11-06 지시)

설계 설명 = 같은 폴더 README.md. 이 파일은 숫자를 본문에 박지 않는다 — 모든 수치는 PARAMS 에 출처와 함께 둔다.

PIT(미래참조 금지) 장치
  * 표준화 = 지표별 재귀(확장 창) 경험분포함수(ECDF · order statistics) — 날짜 t 의 값은 t 까지의 관측만으로 순위를 매긴다(C1).
  * 축 간 상관 = 재귀 EWMA(지수가중 이동평균) — t 까지의 하위지수만 쓴다(C1).
  * ECOS · FRED · 퀀티 거시 계열 = 02_Infrastructure/data/fred_availability.py::fred_asof_join(가용일 규칙 06_Registry/fred_availability_rules.json · C11).
  * 국내 시장 자료(KOSPI200 · RAWDATA · 투자자 수급) = t 일 장 마감 뒤 확정치. 지수 값 t 를 매매 신호로 쓸 땐 t+1 부터 적용한다(C2 · C5).
  * 검증(위기 구간 · 선행 수익)만 미래 자료를 쓴다 — 지수 계산에는 들어가지 않는다.

쓰기 범위 = 이 폴더의 output/ 뿐. 등급 · BOOK · 등록부 · 국면 원장에 쓰지 않는다.
구 MSM 캐시(.cache/msm_daily_latest · msm_hybrid_latest)와 통합 국면 신호는 입력으로 쓰지 않는다(전 표본 모수 · C1).

실행: <repo>/.venv_qvest_ml/Scripts/python.exe build_kr_stress_index.py
"""
from __future__ import annotations

import bisect
import datetime as dt
import json
import os
import sys
import time

import numpy as np
import pandas as pd
import pyarrow.compute as pc
import pyarrow.dataset as ds

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
CACHE = ROOT + "/.cache"
OUT = HERE + "/output"
sys.path.insert(0, ROOT + "/02_Infrastructure/data")
from fred_availability import fred_asof_join, fred_avail_rules_meta  # noqa: E402

# ─────────────────────────────────────────────────────────────────────────────
# 수치 결정 — 값마다 출처(문헌 · 프로젝트 규약 · 설계 선택)를 적는다
# ─────────────────────────────────────────────────────────────────────────────
CISS = "Holló, Kremer & Lo Duca (2012) CISS, ECB WP 1426"
CLIFS = "Duprey, Klaus & Peltonen (2017) CLIFS, J. Financial Stability 32 (BoC SWP 2016-11)"
PARAMS = {
    "ecdf_min_history_years": {
        "value": 3,
        "source": CISS + " §3.3 — 비재귀 초기 구간(1999-01-08~2002-01-04, 약 3년) 뒤 재귀 변환. "
                  "이 시제품은 초기 구간도 재귀로 계산하고(완전 PIT) 이력 3년 미만 지표는 '미유효'로만 표시한다."},
    "rv_window_obs": {
        "value": 20,
        "source": CLIFS + " §2.1 식(2)·(3) — 실현변동성 = 일별 절대 로그수익(금리는 절대 변화) 20개 평균."},
    "cmax_window_days": {
        "value": 730,
        "source": CISS + " Table 1 · " + CLIFS + " §2.1 — CMAX = 2년 이동 창의 최대 누적 손실(Patel & Sarkar 1998, FAJ 54(6)). 2년 = 730역일."},
    "fx_cmax_window_days": {
        "value": 183,
        "source": CLIFS + " §2.1 — 외환 누적 변화(CUMUL) 창 6개월. 원화 약세 한쪽만 스트레스로 보아 CMAX 꼴(원화 가치의 6개월 최대 누적 하락)로 적용 — "
                  "신흥국 FSI 의 환율 압력은 절하 방향(Balakrishnan, Danninger, Elekdag & Tytell 2011, IMF WP 09/133)."},
    "breadth_drawdown": {
        "value": 0.20,
        "source": "Lunde & Timmermann (2004) JBES 22(3) — 약세장 관례 문턱 0.2. 06_Registry/behavior_card.json crisis_lambda_down 과 같은 출처."},
    "breadth_high_window_obs": {
        "value": 252,
        "source": "52주 고가 기준점(George & Hwang 2004, JF 59(5)) — 252 거래일. 최소 관측 200(설계 선택: 창의 약 80%)."},
    "breadth_high_min_obs": {"value": 200, "source": "설계 선택 — 52주 창의 약 80% 이상 거래 이력이 있는 종목만 고가 대비 낙폭을 잰다."},
    "breadth_universe_topn": {
        "value": 500,
        "source": "설계 선택 — 직전일 시가총액 상위 500(프로젝트 유니버스 universe_v2 KR_TOP500 과 같은 규모)."},
    "price_floor_krw": {
        "value": 1000,
        "source": "측정 축 epoch all_hyg_px1000_2000_v1 의 동전주 바닥(전날 수정 종가 1,000원 미만 제외 · 도훈 10-17)."},
    "corr_window_obs": {
        "value": 21,
        "source": "Pollet & Wilson (2010) JFE 96(3) — 월중 일별 수익률로 계산한 평균 쌍별 상관(1개월 ≈ 21 거래일)."},
    "corr_topn": {
        "value": 100,
        "source": "설계 선택 — 직전일 시가총액 상위 100(KOSPI100 규모). Pollet & Wilson 은 미국 대형 500종."},
    "flow_windows_obs": {
        "value": [20, 60],
        "source": "설계 선택 — 1개월 · 1분기 누적 외국인 순매수(시가총액 대비, 부호 반전 = 순매도가 클수록 스트레스). "
                  "외국인 매매의 가격 영향 근거 = Choe, Kho & Stulz (1999) JFE 54(2) · Richards (2005) JFQA 40(1)."},
    "ewma_lambda_weekly": {"value": 0.93, "source": CISS + " §3.4 식(4) — 주간 감쇠 λ = 0.93."},
    "ewma_lambda_daily": {
        "value": 0.93 ** (1 / 5),
        "source": "주간 λ=0.93 의 반감기(ln0.5/ln0.93 ≈ 9.6주 ≈ 48거래일)를 보존하는 일간 환산 λ_d = 0.93^(1/5)."},
    "ewma_demean": {"value": 0.5, "source": CISS + " §3.4 — 하위지수에서 '이론 중앙값' 0.5 를 빼고 공분산을 갱신."},
    "ewma_init": {
        "value": {"var": 1 / 12, "cov": 0.0},
        "source": "균등분포 분산 1/12 · 무상관에서 출발(완전 재귀). CISS 는 초기 구간 평균으로 초기화한다 — "
                  "반감기 약 48거래일이라 3년 유효 대기 동안 초깃값 영향은 사라진다(0.986^750 ≈ 2e-5)."},
    "axis_weights": {
        "value": "equal (1/7)",
        "source": CLIFS + " — 동일 가중 · " + CISS + " 부록 Fig. A.2 — 실물 영향 가중과 동일 가중의 차이가 작다. "
                  "결과(위기 적중)에 맞춘 가중 추정은 하지 않는다(과적합 · C1)."},
    "score_pct_min_obs": {
        "value": 250,
        "source": "설계 선택(검증 표 전용) — 지수 · 축 · V-KOSPI 의 재귀 백분위는 자기 이력 250관측(약 1년) 뒤부터 유효. "
                  "첫 관측의 재귀 백분위는 정의상 1.0 이라 그대로 두면 거짓 경보가 된다."},
    "alarm_percentile": {
        "value": 0.80,
        "source": "설계 선택(검증 표 전용) — 지수의 재귀 백분위가 0.80 이상이면 '경보'. 감도 = 0.90."},
    "alarm_cooloff_obs": {"value": 20, "source": "설계 선택(검증 표 전용) — 경보 해제 후 20거래일 안의 재돌파는 같은 경보로 묶는다."},
    "hit_drawdown": {"value": -0.10, "source": "설계 선택(검증 표 전용) — 경보 뒤 60거래일 안 KOSPI200 이 경보일 대비 −10% 이하면 '적중'. "
                                              "LT 약세장 문턱 0.2 의 절반."},
    "fwd_horizons_obs": {"value": [20, 60], "source": "설계 선택(검증 표 전용) — 1개월 · 1분기 선행."},
    "crisis_lambda": {
        "value": [0.20, 0.20],
        "source": "contracts/behavior_card.R::bc_crises_lt · 06_Registry/behavior_card.json(crisis_lambda_down/up) — Lunde & Timmermann (2004)."},
    "lambda_weekly_sensitivity": {"value": [0.89, 0.97], "source": CISS + " §4 Figure 7 — λ 0.89 · 0.93 · 0.97 감도."},
}
P = {k: v["value"] for k, v in PARAMS.items()}

# 지표 사전 — (id, 축, 이름, 정의, 원천, 가용 규칙)
INDICATORS = [
    ("E1", "equity", "KOSPI200 실현변동성", "20거래일 평균 |일별 로그수익|", "benchmark.parquet(퀀티 IKS200)", "당일 마감"),
    ("E2", "equity", "KOSPI200 CMAX(2년)", "1 − P_t / 2년 최고치", "benchmark.parquet", "당일 마감"),
    ("C1", "credit", "회사채 AA- 신용 스프레드", "회사채 3년 AA- − 국고채 3년(%p)", "ecos_bond_rates.parquet(KR_CorpAA · KR_Gov3Y)", "KR_CorpAA: 다음 거래일"),
    ("C2", "credit", "국고채 10년 금리 실현변동성", "20관측 평균 |일별 금리 변화|(%p)", "ecos_bond_rates.parquet(KR_Gov10Y)", "KR_Gov10Y: 다음 거래일"),
    ("X1", "fx", "원/달러 실현변동성", "20관측 평균 |일별 로그 변화|", "ecos_krw_usd.parquet(ECOS 731Y001)", "ECOS_KRW_USD: 당일(15:30 종가)"),
    ("X2", "fx", "원화 가치 CMAX(6개월)", "1 − 6개월 최저 원/달러 / 현재 원/달러", "ecos_krw_usd.parquet", "ECOS_KRW_USD: 당일"),
    ("F1", "flow", "외국인 순매도 강도(20일)", "−Σ20일 외국인 순매수 / 시가총액", "investor_stock/investor_wide.parquet + RAWDATA Size", "당일 마감"),
    ("F2", "flow", "외국인 순매도 강도(60일)", "−Σ60일 외국인 순매수 / 시가총액", "investor_stock/investor_wide.parquet + RAWDATA Size", "당일 마감"),
    ("B1", "breadth", "약세 종목 비중(폭)", "시총 상위 500 중 52주 고가 대비 −20% 이하 비중", "RAWDATA.parquet", "당일 마감"),
    ("B2", "breadth", "대형주 평균 상관(동조화)", "시총 상위 100 의 21일 평균 쌍별 상관", "RAWDATA.parquet", "당일 마감"),
    ("M1", "funding", "CD91 − 콜 스프레드", "CD 91일 − 콜 1일(%p)", "qw_global_macro.parquet(QW_KR_CD91) · ecos_bond_rates(KR_Call1D)", "KR_Call1D: 2거래일 뒤(엄격 쪽)"),
    ("M2", "funding", "CD91 금리 실현변동성", "20관측 평균 |일별 CD91 변화|(%p)", "qw_global_macro.parquet(QW_KR_CD91)", "QW_KR_CD91: 다음 거래일"),
    ("G1", "global", "VIX", "CBOE VIX 종가", "fred_macro_wide.parquet(VIXCLS)", "VIXCLS: 다음 한국 거래일"),
    ("G2", "global", "세인트루이스 연준 금융스트레스지수", "STLFSI4(주간)", "fred_macro_wide.parquet(STLFSI4)", "STLFSI4: 기준일+7일 & 미 발표일 뒤"),
]
AXES = ["equity", "credit", "fx", "flow", "breadth", "funding", "global"]
AXIS_KO = {"equity": "주식 변동성·낙폭", "credit": "신용·금리", "fx": "환율", "flow": "외국인 수급",
           "breadth": "시장 폭·동조화", "funding": "단기 자금", "global": "글로벌 전이"}
IND_AXIS = {i[0]: i[1] for i in INDICATORS}


def log(*a):
    print("[kr_stress]", *a, flush=True)


def _retry(fn, *a, **k):
    """리프레시가 큰 파일을 다시 쓰는 중이면 읽기가 실패할 수 있다 — 잠시 뒤 다시 읽는다."""
    for i in range(5):
        try:
            return fn(*a, **k)
        except Exception as e:  # noqa: BLE001
            if i == 4:
                raise
            log(f"read retry {i + 1}: {type(e).__name__}: {str(e)[:120]}")
            time.sleep(30)


def _mtime(path):
    try:
        return dt.datetime.fromtimestamp(os.path.getmtime(path)).isoformat(timespec="seconds")
    except OSError:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# 1. 원자료
# ─────────────────────────────────────────────────────────────────────────────
def load_benchmark():
    b = _retry(pd.read_parquet, CACHE + "/benchmark.parquet")
    b["Date"] = pd.to_datetime(b["Date"])
    b = b.sort_values("Date").drop_duplicates("Date", keep="last").set_index("Date")
    return b


def series_long(path, id_col, sid, val_col="Value"):
    df = _retry(pd.read_parquet, path)
    df = df[df[id_col] == sid][["Date", val_col]].dropna()
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").drop_duplicates("Date", keep="last")
    return df.set_index("Date")[val_col].astype(float)


def asof_join(obs: pd.Series, sid: str, cal_dates: list):
    """해외 · ECOS · 퀀티 거시 계열 → 한국 결정일(t 장 마감) 기준 가용 값. 규칙 = fred_availability_rules.json."""
    obs = obs.dropna()
    df = pd.DataFrame({"Date": [d.date() for d in obs.index], "Value": obs.values})
    j = fred_asof_join(cal_dates, df, sid, mode="decision_close", kr_calendar=cal_dates)
    idx = pd.to_datetime(j["kr_date"])
    v = pd.Series(pd.to_numeric(j["value"], errors="coerce").values, index=idx)
    od = pd.Series(pd.to_datetime(j["obs_date"]).values, index=idx)
    return v, od


def on_calendar(s: pd.Series, cal: pd.DatetimeIndex):
    """국내 장 마감 자료 → 기준 달력(같은 날 또는 직전 관측) + 관측일."""
    s = s.dropna().sort_index()
    v = s.reindex(cal, method="ffill")
    od = pd.Series(s.index, index=s.index).reindex(cal, method="ffill")
    return v, od


def load_rawdata_arrays(start):
    """RAWDATA → (dates, tickers, Close, Ret, Size, Admin, Halt) 2차원 배열(float32)."""
    cols = ["Date", "Ticker", "Close", "Ret", "Size", "AdminStock", "TradingHalt"]

    def _read():
        return ds.dataset(CACHE + "/RAWDATA.parquet").to_table(columns=cols, filter=pc.field("Date") >= start)

    t = _retry(_read)
    dates = pd.to_datetime(t.column("Date").to_pandas())
    d_codes, d_uni = pd.factorize(dates, sort=True)
    tk = t.column("Ticker").to_pandas()
    t_codes, t_uni = pd.factorize(tk, sort=True)
    shape = (len(d_uni), len(t_uni))
    out = {}
    for c in ["Close", "Ret", "Size", "AdminStock", "TradingHalt"]:
        a = np.full(shape, np.nan, dtype=np.float32)
        a[d_codes, t_codes] = t.column(c).to_numpy(zero_copy_only=False).astype(np.float32)
        out[c] = a
    del t
    return pd.DatetimeIndex(d_uni), pd.Index(t_uni), out


def load_foreign_flows(dates, tickers, size):
    """외국인 순매수(원) — RAWDATA 와 같은 (날짜 × 종목) 격자에 놓는다."""
    def _read():
        return ds.dataset(CACHE + "/investor_stock/investor_wide.parquet").to_table(
            columns=["Date", "Ticker", "Foreign"], filter=pc.field("Date") >= dates[0].date())

    t = _retry(_read)
    df = t.to_pandas()
    df["Date"] = pd.to_datetime(df["Date"])
    di = dates.get_indexer(df["Date"])
    ti = tickers.get_indexer(df["Ticker"])
    ok = (di >= 0) & (ti >= 0) & df["Foreign"].notna().values
    nf = np.full(size.shape, np.nan, dtype=np.float64)
    nf[di[ok], ti[ok]] = df["Foreign"].values[ok]
    inv_dates = pd.DatetimeIndex(sorted(df["Date"].unique()))
    return nf, inv_dates, int((~ok).sum()), int(ok.sum())


# ─────────────────────────────────────────────────────────────────────────────
# 2. 지표
# ─────────────────────────────────────────────────────────────────────────────
def build_indicators():
    bm = load_benchmark()
    cal = bm.index
    cal_dates = [d.date() for d in cal]
    raw = pd.DataFrame(index=cal, dtype=float)
    obs = pd.DataFrame(index=cal, dtype="datetime64[ns]")
    meta = {}
    rv = P["rv_window_obs"]

    # 주식 — KOSPI200
    px = bm["BM_Close"].astype(float)
    lr = np.log(px).diff()
    raw["E1"] = lr.abs().rolling(rv, min_periods=rv).mean()
    raw["E2"] = 1.0 - px / px.rolling(f"{P['cmax_window_days']}D").max()
    obs["E1"] = obs["E2"] = pd.Series(cal, index=cal)

    # 비교용(지수에 넣지 않음) — V-KOSPI200
    ix = _retry(pd.read_parquet, CACHE + "/indices.parquet")
    ix["Date"] = pd.to_datetime(ix["Date"])
    vk = ix.set_index("Date")["kospi200_vol"].astype(float)
    cmp_vk, cmp_vk_od = on_calendar(vk, cal)

    # 신용 · 금리 — ECOS
    eb = CACHE + "/ecos_bond_rates.parquet"
    g3 = series_long(eb, "Series", "KR_Gov3Y")
    g10 = series_long(eb, "Series", "KR_Gov10Y")
    aa = series_long(eb, "Series", "KR_CorpAA")
    call = series_long(eb, "Series", "KR_Call1D")
    raw["C1"], obs["C1"] = asof_join((aa - g3).dropna(), "KR_CorpAA", cal_dates)
    raw["C2"], obs["C2"] = asof_join(g10.diff().abs().rolling(rv, min_periods=rv).mean(), "KR_Gov10Y", cal_dates)

    # 단기 자금 — CD91(퀀티 · 1994~) · 콜(ECOS)
    cd = series_long(CACHE + "/qw_global_macro.parquet", "Series_ID", "QW_KR_CD91")
    raw["M1"], obs["M1"] = asof_join((cd - call).dropna(), "KR_Call1D", cal_dates)  # 두 원천 중 엄격한 규칙(2거래일)
    raw["M2"], obs["M2"] = asof_join(cd.diff().abs().rolling(rv, min_periods=rv).mean(), "QW_KR_CD91", cal_dates)

    # 환율 — ECOS 원/달러(15:30 종가)
    fx = _retry(pd.read_parquet, CACHE + "/ecos_krw_usd.parquet")
    fx["Date"] = pd.to_datetime(fx["Date"])
    fx = fx.sort_values("Date").drop_duplicates("Date", keep="last").set_index("Date")["KRW_USD"].astype(float)
    raw["X1"], obs["X1"] = asof_join(np.log(fx).diff().abs().rolling(rv, min_periods=rv).mean(), "ECOS_KRW_USD", cal_dates)
    raw["X2"], obs["X2"] = asof_join(1.0 - fx.rolling(f"{P['fx_cmax_window_days']}D").min() / fx, "ECOS_KRW_USD", cal_dates)

    # 글로벌 — FRED
    fw = _retry(pd.read_parquet, CACHE + "/fred_macro_wide.parquet")
    fw["Date"] = pd.to_datetime(fw["Date"])
    fw = fw.sort_values("Date").set_index("Date")
    raw["G1"], obs["G1"] = asof_join(fw["VIX"], "VIXCLS", cal_dates)
    raw["G2"], obs["G2"] = asof_join(fw["StL_Fin_Stress"], "STLFSI4", cal_dates)

    # 수급 · 폭 · 동조화 — RAWDATA + 투자자 수급
    t0 = time.time()
    rd_dates, tickers, A = load_rawdata_arrays(dt.date(1995, 1, 1))
    log(f"RAWDATA {rd_dates[0].date()}~{rd_dates[-1].date()} · {len(tickers)} 종목 · {time.time() - t0:.0f}s")
    meta["rawdata_range"] = [str(rd_dates[0].date()), str(rd_dates[-1].date())]
    close, ret, size = A["Close"], A["Ret"], A["Size"]
    bad = (np.nan_to_num(A["AdminStock"]) > 0) | (np.nan_to_num(A["TradingHalt"]) > 0)
    size_lag = np.vstack([np.full((1, size.shape[1]), np.nan, np.float32), size[:-1]])
    close_lag = np.vstack([np.full((1, close.shape[1]), np.nan, np.float32), close[:-1]])

    # B1 — 52주 고가 대비 −20% 이하 비중(시총 상위 500)
    hi = pd.DataFrame(close).rolling(P["breadth_high_window_obs"], min_periods=P["breadth_high_min_obs"]).max().values
    elig = (~np.isnan(close)) & (~np.isnan(hi)) & (close_lag >= P["price_floor_krw"]) & (~bad) & (~np.isnan(size_lag))
    rank = pd.DataFrame(np.where(elig, size_lag, np.nan)).rank(axis=1, ascending=False, method="first").values
    top = elig & (rank <= P["breadth_universe_topn"])
    deep = top & (close <= (1.0 - P["breadth_drawdown"]) * hi)
    n_top = top.sum(axis=1)
    b1 = np.where(n_top >= P["breadth_universe_topn"] * 0.5, deep.sum(axis=1) / np.maximum(n_top, 1), np.nan)
    meta["breadth_universe_n_median"] = float(np.median(n_top[n_top > 0])) if (n_top > 0).any() else None
    raw["B1"], obs["B1"] = on_calendar(pd.Series(b1, index=rd_dates), cal)

    # B2 — 시총 상위 100 의 21일 평균 쌍별 상관
    W, K = P["corr_window_obs"], P["corr_topn"]
    valid_ret = pd.DataFrame(~np.isnan(ret)).rolling(W, min_periods=W).sum().values == W
    elig2 = valid_ret & (~bad) & (~np.isnan(size_lag))
    rank2 = pd.DataFrame(np.where(elig2, size_lag, np.nan)).rank(axis=1, ascending=False, method="first").values
    b2 = np.full(len(rd_dates), np.nan)
    for t in range(W - 1, len(rd_dates)):
        cols = np.where(rank2[t] <= K)[0]
        if len(cols) < K * 0.8:
            continue
        R = ret[t - W + 1:t + 1, cols].astype(np.float64)
        Z = R - R.mean(axis=0)
        sd = Z.std(axis=0, ddof=1)
        keep = sd > 0
        Z = Z[:, keep] / sd[keep]
        k = Z.shape[1]
        C = (Z.T @ Z) / (W - 1)
        b2[t] = (C.sum() - k) / (k * (k - 1))
    raw["B2"], obs["B2"] = on_calendar(pd.Series(b2, index=rd_dates), cal)

    # F1 · F2 — 외국인 순매도 강도(시총 대비)
    nf, inv_dates, n_drop, n_ok = load_foreign_flows(rd_dates, tickers, size)
    meta["investor_rows_joined"] = n_ok
    meta["investor_rows_unmatched"] = n_drop
    cov = (~np.isnan(nf)) & (~np.isnan(size))
    net = np.where(cov, nf, 0.0).sum(axis=1)
    mcap = np.where(cov, size.astype(np.float64), 0.0).sum(axis=1)
    has = cov.sum(axis=1) > 0
    net_s = pd.Series(np.where(has, net, np.nan), index=rd_dates)
    mcap_s = pd.Series(np.where(has, mcap, np.nan), index=rd_dates)
    for col, wnd in zip(["F1", "F2"], P["flow_windows_obs"]):
        f = -net_s.rolling(wnd, min_periods=wnd).sum() / mcap_s
        raw[col], obs[col] = on_calendar(f, cal)
    meta["investor_range"] = [str(inv_dates[0].date()), str(inv_dates[-1].date())]
    del A, close, ret, size, hi, rank, rank2, nf
    return bm, raw, obs, cmp_vk, cmp_vk_od, meta


# ─────────────────────────────────────────────────────────────────────────────
# 3. 표준화 · 하위지수 · 종합
# ─────────────────────────────────────────────────────────────────────────────
def recursive_ecdf(x: np.ndarray) -> np.ndarray:
    """CISS 식 (1b) — t 까지의 관측에서 x_t 의 순위 / 관측 수. 동률은 평균 순위."""
    out = np.full(len(x), np.nan)
    srt: list = []
    for i, v in enumerate(x):
        if v != v:  # NaN
            continue
        bisect.insort(srt, v)
        lo = bisect.bisect_left(srt, v)
        hi = bisect.bisect_right(srt, v)
        out[i] = (lo + (hi - lo + 1) / 2.0) / len(srt)
    return out


def recursive_pct(s: pd.Series) -> pd.Series:
    """재귀 백분위 + 워밍업(첫 score_pct_min_obs 관측은 NaN)."""
    v = recursive_ecdf(s.values.astype(float))
    k = np.cumsum(~np.isnan(s.values.astype(float)))
    v[k < P["score_pct_min_obs"]] = np.nan
    return pd.Series(v, index=s.index)


def fullsample_ecdf(x: pd.Series) -> pd.Series:
    """진단 전용(미래참조) — 전 표본 순위. CISS Fig.5 와 같은 비교를 위해서만 쓴다."""
    return x.rank(method="average", pct=True)


def subindices(Z: pd.DataFrame, valid: pd.DataFrame):
    S = pd.DataFrame(index=Z.index)
    V = pd.DataFrame(index=Z.index)
    for ax in AXES:
        cols = [i for i in Z.columns if IND_AXIS[i] == ax]
        S[ax] = Z[cols].mean(axis=1, skipna=False)
        V[ax] = valid[cols].all(axis=1)
    return S, V


def ciss_aggregate(S: pd.DataFrame, lam: float):
    """CISS 식 (2)–(4): CISS_t = (w∘s_t)' C_t (w∘s_t), C_t = EWMA 상관(이론 중앙값 0.5 차감)."""
    k = S.shape[1]
    w = np.full(k, 1.0 / k)
    arr = S.values
    n = len(arr)
    ciss = np.full(n, np.nan)
    contrib = np.full((n, k), np.nan)
    corr_avg = np.full(n, np.nan)
    sig = np.eye(k) * P["ewma_init"]["var"] + (1 - np.eye(k)) * P["ewma_init"]["cov"]
    started = False
    for t in range(n):
        s = arr[t]
        if np.isnan(s).any():
            if started:
                log(f"subindex NaN after start at {S.index[t].date()} — skipped")
            continue
        started = True
        d = s - P["ewma_demean"]
        sig = lam * sig + (1 - lam) * np.outer(d, d)
        sd = np.sqrt(np.diag(sig))
        C = sig / np.outer(sd, sd)
        y = w * s
        Cy = C @ y
        contrib[t] = y * Cy
        ciss[t] = float(y @ Cy)
        corr_avg[t] = (C.sum() - k) / (k * (k - 1))
    return ciss, contrib, corr_avg


def compute_index(raw: pd.DataFrame, lam: float, ecdf="recursive"):
    ids = [i[0] for i in INDICATORS]
    Z = pd.DataFrame(index=raw.index)
    valid = pd.DataFrame(index=raw.index)
    first = {}
    for i in ids:
        x = raw[i]
        if ecdf == "recursive":
            Z[i] = recursive_ecdf(x.values.astype(float))
        else:
            Z[i] = fullsample_ecdf(x)
        f = x.first_valid_index()
        first[i] = f
        valid[i] = (raw.index >= f + pd.DateOffset(years=P["ecdf_min_history_years"])) & x.notna()
    S, V = subindices(Z, valid)
    ciss, contrib, corr_avg = ciss_aggregate(S, lam)
    allv = V.all(axis=1)
    t0 = allv[allv].index[0]
    res = pd.DataFrame(index=raw.index)
    res["score"] = 100 * ciss
    res["score_linear"] = 100 * S.mean(axis=1, skipna=False)
    res["score_upper"] = 100 * S.mean(axis=1, skipna=False) ** 2
    res["avg_axis_corr"] = corr_avg
    for j, ax in enumerate(AXES):
        res[f"s_{ax}"] = S[ax]
        res[f"c_{ax}"] = 100 * contrib[:, j]
    res = res[res.index >= t0]
    return res, Z, S, V, t0, first


# ─────────────────────────────────────────────────────────────────────────────
# 4. 검증 — 위기 구간(Lunde-Timmermann 20/20) · 경보 시점 · 선행 관계
# ─────────────────────────────────────────────────────────────────────────────
def lt_crises(px: pd.Series, l_down: float, l_up: float) -> pd.DataFrame:
    """behavior_card.R::bc_crises_lt 와 같은 알고리즘(첫 통과 규칙) + 실시간 확정일(−λ_down 도달일)."""
    Pv = px.values.astype(float)
    D = px.index
    n = len(Pv)
    out = []
    st, ext, exti, pki, confi = 1, Pv[0], 0, None, None

    def rec(pk, frm):
        k = np.where(Pv[frm:] >= Pv[pk])[0]
        return D[frm + k[0]] if len(k) else pd.NaT

    for t in range(1, n):
        if st == 1:
            if Pv[t] >= ext:
                ext, exti = Pv[t], t
            elif Pv[t] <= (1 - l_down) * ext:
                pki, confi, st, ext, exti = exti, t, 0, Pv[t], t
        else:
            if Pv[t] <= ext:
                ext, exti = Pv[t], t
            elif Pv[t] >= (1 + l_up) * ext:
                out.append(dict(peak=D[pki], confirm=D[confi], trough=D[exti], end_confirm=D[t], recover=rec(pki, exti),
                                depth=1 - Pv[exti] / Pv[pki], ongoing=False))
                st, ext, exti = 1, Pv[t], t
    if st == 0:
        out.append(dict(peak=D[pki], confirm=D[confi], trough=D[exti], end_confirm=pd.NaT, recover=pd.NaT,
                        depth=1 - Pv[exti] / Pv[pki], ongoing=True))
    return pd.DataFrame(out)


def alarm_timing(pct: pd.Series, px: pd.Series, ep: pd.Series, thr: float):
    """한 위기에서 경보(재귀 백분위 ≥ thr)가 언제 울렸나 — 고점 대비 · −20% 확정일 대비."""
    idx = px.index
    p, c, q = ep["peak"], ep["confirm"], ep["trough"]
    ip, ic, iq = idx.get_loc(p), idx.get_loc(c), idx.get_loc(q)
    s = pct.reindex(idx)
    pre = s.iloc[max(0, ip - 60):ip + 1]
    window = s.iloc[ip:iq + 1]
    hit = window[window >= thr]
    row = {"pct_at_peak": s.iloc[ip], "pct_max_60d_before_peak": pre.max()}
    if len(hit):
        a = hit.index[0]
        ia = idx.get_loc(a)
        row.update(alarm_date=a.date(), alarm_lag_from_peak_td=ia - ip, alarm_lead_vs_confirm_td=ic - ia,
                   kospi200_dd_at_alarm=px.iloc[ia] / px.iloc[ip] - 1)
    else:
        row.update(alarm_date=None, alarm_lag_from_peak_td=None, alarm_lead_vs_confirm_td=None, kospi200_dd_at_alarm=None)
    return row


def alarm_onsets(pct: pd.Series, thr: float, cool: int):
    on = (pct >= thr).values
    starts, last_on = [], -10 ** 9
    for i in range(len(on)):
        if on[i]:
            if i - last_on > cool:
                starts.append(pct.index[i])
            last_on = i
    return starts


def validate(res, S, px, vk_pct, axis_pct, t0):
    l_down, l_up = P["crisis_lambda"]
    eps = lt_crises(px, l_down, l_up)
    eps_cov = eps[eps["peak"] >= t0].reset_index(drop=True)
    rows, axrows = [], []
    for _, ep in eps_cov.iterrows():
        ip, iq = px.index.get_loc(ep["peak"]), px.index.get_loc(ep["trough"])
        win = res["score"].reindex(px.index).iloc[ip:iq + 1]
        r = {"peak": ep["peak"].date(), "confirm_minus20": ep["confirm"].date(), "trough": ep["trough"].date(),
             "depth": ep["depth"], "ongoing": ep["ongoing"],
             "td_peak_to_confirm": px.index.get_loc(ep["confirm"]) - ip, "td_peak_to_trough": iq - ip,
             "score_at_peak": res["score"].get(ep["peak"]), "score_max": win.max(),
             "score_max_date": win.idxmax().date() if win.notna().any() else None,
             "score_at_trough": res["score"].get(ep["trough"])}
        for name, pc_ in [("ks", res["score_pct"]), ("vkospi", vk_pct)]:
            for thr in (P["alarm_percentile"], 0.90):
                tt = alarm_timing(pc_, px, ep, thr)
                for k, v in tt.items():
                    r[f"{name}_{int(thr * 100)}_{k}"] = v
        rows.append(r)
        for ax in AXES:
            tt = alarm_timing(axis_pct[ax], px, ep, P["alarm_percentile"])
            axrows.append({"peak": ep["peak"].date(), "axis": ax, **tt})
    ev = pd.DataFrame(rows)
    ax_t = pd.DataFrame(axrows)

    # 경보 개시 → 60일 안 −10% 하락 적중률 (무조건 기저율과 비교)
    fw_min = pd.Series(np.nan, index=px.index)
    H = 60
    pv = px.values
    m = np.full(len(pv), np.nan)
    for i in range(len(pv) - H):
        m[i] = pv[i + 1:i + H + 1].min() / pv[i] - 1
    fw_min[:] = m
    hit_rows = []
    for name, pc_ in [("ks_score", res["score_pct"]), ("vkospi", vk_pct.reindex(res.index))]:
        for thr in (P["alarm_percentile"], 0.90):
            ons = alarm_onsets(pc_.dropna(), thr, P["alarm_cooloff_obs"])
            fm = fw_min.reindex(ons)
            done = fm.dropna()
            base = fw_min.reindex(res.index).dropna()
            hit_rows.append({"signal": name, "threshold": thr, "n_onsets": len(ons), "n_evaluable": len(done),
                             "hit_rate_dd10_60d": float((done <= P["hit_drawdown"]).mean()) if len(done) else None,
                             "base_rate_dd10_60d": float((base <= P["hit_drawdown"]).mean()),
                             "onsets": ";".join(str(d.date()) for d in ons)})
    hits = pd.DataFrame(hit_rows)

    # 선행 관계 — 순위상관(겹치는 관측 · 유의성 주장 없음)
    lr = np.log(px).diff()
    fwd = pd.DataFrame(index=px.index)
    for h in P["fwd_horizons_obs"]:
        fwd[f"fwd_ret_{h}"] = px.shift(-h) / px - 1
        fwd[f"fwd_absret_{h}"] = lr.abs()[::-1].rolling(h, min_periods=h).mean()[::-1].shift(-1)
    fwd["fwd_mindd_60"] = fw_min
    X = pd.DataFrame({"ks_score": res["score"], "ks_linear": res["score_linear"], "vkospi": vk_pct.reindex(res.index),
                      "equity_axis": res["s_equity"]}).join(fwd, how="left")
    crow = []
    for per, (a, b) in {"all": (None, None), "2004-2022": (None, "2022-12-31"), "2023-": ("2023-01-01", None)}.items():
        Xp = X.loc[a:b]
        for sig in ["ks_score", "ks_linear", "vkospi", "equity_axis"]:
            r = {"period": per, "signal": sig, "n": int(Xp[sig].notna().sum())}
            for tgt in [c for c in fwd.columns]:
                r[tgt] = Xp[[sig, tgt]].dropna().corr(method="spearman").iloc[0, 1]
            crow.append(r)
    fcorr = pd.DataFrame(crow)

    # 백분위 구간별 선행 분포
    bins = [0, 0.5, 0.8, 0.95, 1.0001]
    lab = ["<50", "50-80", "80-95", ">=95"]
    X["bucket"] = pd.cut(res["score_pct"], bins=bins, labels=lab, right=False)
    bucket = X.groupby("bucket", observed=False).agg(
        n=("ks_score", "size"), fwd_ret_20_mean=("fwd_ret_20", "mean"), fwd_ret_60_mean=("fwd_ret_60", "mean"),
        fwd_ret_60_q05=("fwd_ret_60", lambda s: s.quantile(0.05)), fwd_mindd_60_median=("fwd_mindd_60", "median"),
        fwd_absret_20_mean=("fwd_absret_20", "mean")).reset_index()

    # 사건 연구 — 고점 · 확정일 기준 평균 경로
    ev_rows = []
    sc = res["score"].reindex(px.index)
    for _, ep in eps_cov.iterrows():
        for anchor in ["peak", "confirm"]:
            ia = px.index.get_loc(ep[anchor])
            for off in range(-120, 251):
                j = ia + off
                if 0 <= j < len(sc):
                    ev_rows.append({"peak": ep["peak"].date(), "anchor": anchor, "offset_td": off, "score": sc.iloc[j]})
    evst = pd.DataFrame(ev_rows)
    return eps, ev, ax_t, hits, fcorr, bucket, evst


# ─────────────────────────────────────────────────────────────────────────────
# 5. 실행
# ─────────────────────────────────────────────────────────────────────────────
def main():
    os.makedirs(OUT, exist_ok=True)
    t_start = time.time()
    bm, raw, obs, vk, vk_od, meta = build_indicators()
    log(f"indicators built {time.time() - t_start:.0f}s")

    lam = P["ewma_lambda_daily"]
    res, Z, S, V, t0, first = compute_index(raw, lam)
    res["score_pct"] = recursive_pct(res["score"])
    log(f"composite start t0={t0.date()} · last={res.index[-1].date()} · score={res['score'].iloc[-1]:.1f}")

    # 비교 신호 · 축별 재귀 백분위(검증용 · 같은 워밍업)
    vk_pct = recursive_pct(vk)
    axis_pct = {ax: recursive_pct(S[ax]) for ax in AXES}

    # 감도 — λ · 전 표본 ECDF(진단 · 미래참조)
    rob = {}
    for lw in P["lambda_weekly_sensitivity"]:
        r2, *_ = compute_index(raw, lw ** (1 / 5))
        rob[f"lambda_w{lw}"] = r2["score"]
    r3, *_ = compute_index(raw, lam, ecdf="fullsample")
    rob["fullsample_ecdf_DIAGNOSTIC_lookahead"] = r3["score"]
    rob_df = pd.DataFrame(rob).reindex(res.index)
    rob_rows = []
    for c in rob_df.columns:
        both = pd.concat([res["score"], rob_df[c]], axis=1).dropna()
        rob_rows.append({"variant": c, "pearson_vs_main": both.corr().iloc[0, 1],
                         "spearman_vs_main": both.corr(method="spearman").iloc[0, 1],
                         "mean_abs_diff": (both.iloc[:, 0] - both.iloc[:, 1]).abs().mean(),
                         "latest_main": res["score"].iloc[-1], "latest_variant": rob_df[c].iloc[-1]})
    rob_rows.append({"variant": "linear_equal_weight(no correlation)",
                     "pearson_vs_main": res[["score", "score_linear"]].corr().iloc[0, 1],
                     "spearman_vs_main": res[["score", "score_linear"]].corr(method="spearman").iloc[0, 1],
                     "mean_abs_diff": None, "latest_main": res["score"].iloc[-1], "latest_variant": res["score_linear"].iloc[-1]})
    pd.DataFrame(rob_rows).to_csv(OUT + "/robustness.csv", index=False, encoding="utf-8-sig")

    # 검증
    px = bm["BM_Close"].astype(float)
    eps, ev, ax_t, hits, fcorr, bucket, evst = validate(res, S, px, vk_pct, axis_pct, t0)

    # ── 저장 ──
    daily = res.copy()
    daily["vkospi"] = vk.reindex(res.index)
    daily["vkospi_pct"] = vk_pct.reindex(res.index)
    for ax in AXES:
        daily[f"pct_{ax}"] = axis_pct[ax].reindex(res.index)
    for i in raw.columns:
        daily[f"x_{i}"] = raw[i].reindex(res.index)
        daily[f"z_{i}"] = Z[i].reindex(res.index)
    daily.index.name = "Date"
    daily.to_parquet(OUT + "/kr_stress_daily.parquet")
    slim = ["score", "score_pct", "score_linear"] + [f"c_{a}" for a in AXES] + [f"s_{a}" for a in AXES] + ["vkospi"]
    daily[slim].round(5).to_csv(OUT + "/kr_stress_daily.csv", encoding="utf-8-sig")

    last = res.index[-1]
    i_l = len(res) - 1
    ref = {"d20": res.index[max(0, i_l - 20)], "d60": res.index[max(0, i_l - 60)]}
    st_rows = []
    for (iid, ax, name, defi, src, rule) in INDICATORS:
        od = obs[iid].get(last)
        lag_td = None
        if pd.notna(od):
            lag_td = int(((raw.index > od) & (raw.index <= last)).sum())
        st_rows.append({"id": iid, "axis": ax, "axis_ko": AXIS_KO[ax], "name": name, "definition": defi,
                        "value": raw[iid].get(last), "ecdf_pct": Z[iid].get(last),
                        "value_20td_ago": raw[iid].get(ref["d20"]), "ecdf_pct_20td_ago": Z[iid].get(ref["d20"]),
                        "last_obs_date": None if pd.isna(od) else od.date(), "stale_trading_days": lag_td,
                        "history_start": first[iid].date(), "source": src, "availability": rule})
    status = pd.DataFrame(st_rows)
    status.to_csv(OUT + "/indicator_status_latest.csv", index=False, encoding="utf-8-sig")

    eps.to_csv(OUT + "/crisis_episodes_lt2020_kospi200.csv", index=False, encoding="utf-8-sig")
    ev.to_csv(OUT + "/crisis_validation.csv", index=False, encoding="utf-8-sig")
    ax_t.to_csv(OUT + "/axis_alarm_timing.csv", index=False, encoding="utf-8-sig")
    hits.to_csv(OUT + "/alarm_hit_rate.csv", index=False, encoding="utf-8-sig")
    fcorr.to_csv(OUT + "/forward_rank_correlation.csv", index=False, encoding="utf-8-sig")
    bucket.to_csv(OUT + "/forward_by_percentile_bucket.csv", index=False, encoding="utf-8-sig")
    evst.to_csv(OUT + "/event_study_paths.csv", index=False, encoding="utf-8-sig")

    def contrib_at(d):
        return {ax: float(res.loc[d, f"c_{ax}"]) for ax in AXES}

    latest = {
        "date": str(last.date()), "score": float(res["score"].iloc[-1]), "score_pct": float(res["score_pct"].iloc[-1]),
        "score_linear": float(res["score_linear"].iloc[-1]), "avg_axis_corr": float(res["avg_axis_corr"].iloc[-1]),
        "contrib": contrib_at(last), "subindex": {ax: float(res.loc[last, f"s_{ax}"]) for ax in AXES},
        "axis_pct": {ax: float(axis_pct[ax].get(last)) for ax in AXES},
        "score_20td_ago": float(res.loc[ref["d20"], "score"]), "date_20td_ago": str(ref["d20"].date()),
        "contrib_20td_ago": contrib_at(ref["d20"]),
        "score_60td_ago": float(res.loc[ref["d60"], "score"]), "date_60td_ago": str(ref["d60"].date()),
        "vkospi": float(vk.get(last)), "vkospi_pct": float(vk_pct.get(last)),
        "max_score_since_t0": float(res["score"].max()), "max_score_date": str(res["score"].idxmax().date()),
    }
    files = ["benchmark.parquet", "indices.parquet", "ecos_bond_rates.parquet", "ecos_krw_usd.parquet", "fred_macro_wide.parquet",
             "qw_global_macro.parquet", "RAWDATA.parquet", "investor_stock/investor_wide.parquet"]
    run_meta = {
        "run_at": dt.datetime.now().isoformat(timespec="seconds"),
        "composite_start_t0": str(t0.date()), "last_date": str(last.date()),
        "data_files": {f: {"mtime": _mtime(CACHE + "/" + f)} for f in files},
        "data_ranges": meta, "fred_availability_rules": fred_avail_rules_meta(),
        "indicator_history_start": {k: str(v.date()) for k, v in first.items()},
        "params": PARAMS, "latest": latest,
        "excluded_inputs": {
            "msm_daily_latest/msm_hybrid_latest/unified_regime_signal": "전 표본 모수(PIT C1) — 입력 제외",
            "HY_Spread/BBB_Spread(FRED ICE BofA)": "캐시 이력 2023-10-20~ 뿐 — 역사 검증 불가로 제외",
            "DEXKOUS(FRED 원/달러)": "가용 규칙 prohibited — ECOS 731Y001 사용",
        },
        "elapsed_sec": round(time.time() - t_start, 1),
    }
    with open(OUT + "/run_meta.json", "w", encoding="utf-8") as fh:
        json.dump(run_meta, fh, ensure_ascii=False, indent=2, default=str)
    log(json.dumps(latest, ensure_ascii=False, default=str))
    log(f"done {time.time() - t_start:.0f}s")


if __name__ == "__main__":
    main()
