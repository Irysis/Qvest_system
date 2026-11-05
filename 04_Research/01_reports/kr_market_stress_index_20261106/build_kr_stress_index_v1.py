#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""KR-CISS v1 — 한국 자본시장 전체 스트레스 지수(아이디어 연구 · 도훈 2026-11-06 확장 지시 "주가지수 말고 자본시장 전체").

v0(build_kr_stress_index.py · 7축 14지표 · 축 수준 집계)에서 바뀐 것
  * 범위: 주식(KOSPI200 + 코스닥 · 중소형) · 시장 폭 · 유동성 · 국채 금리 · 신용 · 단기자금 · 외환 · 금융기관 · 외국인 수급 · 글로벌 · 시장 간 전이
    = 12축 34지표. 데이터는 Qvest 캐시 + 연구용 직접 수급(fetch_research_inputs.py — ECOS 817Y002 올바른 항목 · 731Y001/002 · FRED).
  * 방법: 새 CISS(Chavleishvili & Kremer 2023, ECB WP 2842 · Review of Finance 2025 "CISS of death")
      - 변동성 = 일별 로그수익(또는 금리 변화) 제곱의 EWMA(λ = 0.85)
      - 표준화 = 재귀 확률적분변환(PIT · 경험 CDF) — v0 과 같음
      - 집계 = 하위지수 없이 **지표 수준에서 한 번에**, 전체 N×N 시변 순위상관(EWMA λ = 0.85) · 지표 동일 가중
      - 축 기여 = 지표 기여의 합(합 = 지수) — 분해는 유지
  * 검증 추가: (a) 분위회귀 — 60거래일 선행 KOSPI200 수익의 하위 분위가 지수에 얼마나 반응하나(Adrian · Boyarchenko · Giannone 2019 GaR 방식 ·
    블록 부트스트랩 CI · τ_D 이후 표본외 핀볼 손실) (b) 잡음/신호 비율로 고른 2단 임계치(Kaminsky · Lizondo · Reinhart 1998 · 한국은행 FSI 2023 개편 방식 · τ_D 이전 표본에서 선택 · 이후 표본외 평가)
    (c) v0 · V-KOSPI · 축 수준 집계 · 선형 평균과 나란히.

PIT: 표준화 · 상관 · 백분위 = 확장 창(C1) · 해외 · ECOS 계열 = fred_asof_join(C11 · 연구용 규칙 사본) · 유니버스 위생 t−1(C10) · 검증만 미래 사용.
쓰기 = output/v1/ 뿐. 등급 · BOOK · 등록부 · 국면 원장 · .cache 무접촉.
실행: <repo>/.venv_qvest_ml/Scripts/python.exe build_kr_stress_index_v1.py   (사전: fetch_research_inputs.py)
"""
from __future__ import annotations

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
PULL = HERE + "/output"
OUT = HERE + "/output/v1"
RULES = PULL + "/fred_availability_rules_research.json"
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT + "/02_Infrastructure/data")
import build_kr_stress_index as v0  # noqa: E402  (공통 도우미 재사용 — 계산 규약은 아래 PARAMS 가 정한다)
from fred_availability import fred_asof_join, fred_avail_rules_meta  # noqa: E402

NEWCISS = "Chavleishvili & Kremer (2023) 'Measuring systemic financial stress and its risks for growth', ECB WP 2842 (Review of Finance 29(3), 2025)"
CISS = "Holló, Kremer & Lo Duca (2012) CISS, ECB WP 1426"
CLIFS = "Duprey, Klaus & Peltonen (2017) CLIFS, J. Financial Stability 32"
AMRO = "AMRO WP 18-02 (2018) 'Assessing Financial Stress in China, Japan, Korea and ASEAN-5'"
PARAMS = {
    "ewma_vol_lambda": {"value": 0.85, "source": NEWCISS + " Table 3 주석 — 변동성 = 일별 로그수익 제곱의 EWMA λ = 0.85."},
    "ewma_vol_seed_obs": {"value": 60, "source": "설계 선택(PIT) — 새 CISS 는 첫 2년 분산으로 초기화(Engle 2009)하나 그것은 워밍업 안 미래참조라, 첫 60관측 분산으로 씨를 두고 재귀. λ=0.85 라 30일이면 씨의 영향이 사라진다."},
    "ewma_corr_lambda_daily": {"value": 0.85, "source": NEWCISS + " §4.4 — 순위상관 EWMA 'calibrated smoothing parameter (or decay factor) λ = 0.85'(일간)."},
    "corr_lambda_sensitivity": {"value": [0.93 ** (1 / 5), 0.97], "source": "v0 값(CISS 2012 주간 0.93 의 일간 환산) · 느린 대안 0.97."},
    "aggregation": {"value": "indicator-level, equal weight 1/N, full N×N EWMA rank correlation",
                    "source": NEWCISS + " 각주 2 — '하위지수 없이 한 번에 집계 · 전체 15×15 상관 · 지표 동일 가중(실물 영향 가중은 자의적이라는 비판)'."},
    "ewma_demean": {"value": 0.5, "source": CISS + " §3.4 — 이론 중앙값 0.5 차감."},
    "ewma_init": {"value": {"var": 1 / 12, "cov": 0.0}, "source": "균등분포 분산 · 무상관 초기화(완전 재귀)."},
    "ecdf_min_history_years": {"value": 3, "source": CISS + " §3.3 — 약 3년 사전 구간. 이력 3년 미만 = 미유효."},
    "pit_rolling_indicators": {
        "value": ["L1", "L2"],
        "source": CLIFS + " §2.2 각주 18 · §5 — '10-year rolling window can be used to gradually discard older periods'. "
                  "Amihud 비유동성은 시장이 깊어지며 구조적으로 하락한다(이 표본: 상위 500 중앙값 2006 0.012 → 2026 0.0027 · 확장 창 PIT 는 2026 급락에도 ≤ 0.11) — "
                  "확장 창 순위로는 영영 켜지지 않으므로 유동성 두 지표만 10년 이동 창 PIT. 나머지 지표는 확장 창."},
    "pit_rolling_window_obs": {"value": 2520, "source": CLIFS + " — 10년(≈ 2,520 거래일)."},
    "pit_rolling_min_obs": {"value": 750, "source": "설계 선택 — 3년 이력(ecdf_min_history_years 와 같은 바닥)."},
    "score_pct_min_obs": {"value": 250, "source": "설계 선택 — 재귀 백분위는 자기 이력 250관측 뒤부터(첫 관측 백분위 = 1 인공물 차단)."},
    "cmax_window_days": {"value": 730, "source": NEWCISS + " Table 3 — CMAX 2년(520 영업일) · Patel & Sarkar (1998)."},
    "fx_cmax_window_days": {"value": 183, "source": CLIFS + " §2.1 — 환율 누적 변화 6개월 · 신흥국은 절하 방향(Balakrishnan et al. 2011, IMF WP 09/133)."},
    "cmin_window_days": {"value": 730, "source": CLIFS + " §2.1 식(4) — 국채 금리의 2년 최저 대비 상승폭(CMIN)."},
    "breadth_drawdown": {"value": 0.20, "source": "Lunde & Timmermann (2004) 약세장 관례 0.2 · behavior_card.json crisis_lambda."},
    "breadth_high_window_obs": {"value": 252, "source": "George & Hwang (2004) JF — 52주 고가."},
    "breadth_high_min_obs": {"value": 200, "source": "설계 선택 — 52주 창의 약 80%."},
    "breadth_universe_topn": {"value": 500, "source": "설계 선택 — 직전일 시총 상위 500(KR_TOP500 유니버스 규모)."},
    "price_floor_krw": {"value": 1000, "source": "측정 축 epoch all_hyg_px1000_2000_v1 — 전날 종가 1,000원 미만 제외."},
    "corr_window_obs": {"value": 21, "source": "Pollet & Wilson (2010) JFE — 1개월 일별 수익 평균 쌍별 상관."},
    "corr_topn": {"value": 100, "source": "설계 선택 — 시총 상위 100."},
    "rel_return_window_obs": {"value": 60, "source": "설계 선택 — 1분기 상대 수익(코스닥 · 금융업 vs KOSPI200)."},
    "amihud_window_obs": {"value": 20, "source": "Amihud (2002) J. Financial Markets 5(1) — |수익|/거래대금 의 기간 평균 · 1개월."},
    "amihud_small_rank": {"value": [501, 1500], "source": "설계 선택 — 시총 501~1500위 = 중소형 유동성."},
    "flow_windows_obs": {"value": [20, 60], "source": "v0 — Choe, Kho & Stulz (1999) · Richards (2005)."},
    "flow_breadth_window_obs": {"value": 20, "source": "설계 선택 — 20일 순매도 종목 비중."},
    "fin_sectors": {"value": ["은행", "증권", "보험"], "source": CISS + " 'financial intermediaries' 축 · 분류 = universe_support/us_sector_lv1(월별 스냅샷 · 직전 스냅샷 사용)."},
    "beta_window_obs": {"value": 500, "source": CISS + " Table 1 — 은행 고유수익 = 2년(522 영업일) 이동 OLS 잔차."},
    "contagion_long_window_obs": {"value": 1040, "source": CISS + " Table 1 — 주식·채권 상관의 장기 기준 4년(1040 영업일)."},
    "qr_taus": {"value": [0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95], "source": "Adrian, Boyarchenko & Giannone (2019) AER 'Vulnerable Growth' — 분위회귀 τ 격자."},
    "qr_horizon_obs": {"value": 60, "source": "설계 선택 — 60거래일(1분기) 선행 KOSPI200 로그수익(GDP 대신 시장 수익 — GDP 는 분기라 표본 부족)."},
    "qr_block_obs": {"value": 60, "source": "설계 선택 — 겹치는 60일 창 → 블록 길이 60 의 이동 블록 부트스트랩."},
    "qr_boot_reps": {"value": 200, "source": "설계 선택 — 신뢰구간 2.5/97.5 백분위."},
    "nsr_grid": {"value": [0.50, 0.99, 0.01], "source": "Kaminsky, Lizondo & Reinhart (1998) IMF Staff Papers — 임계치 격자에서 잡음/신호 최소화."},
    "nsr_event_horizon_obs": {"value": 60, "source": "설계 선택 — 사건 = LT −20% 첫 통과(위기 확정)가 앞으로 60거래일 안."},
    "nsr_min_signal_days": {"value": 20, "source": "설계 선택 — 신호일 20일 미만 임계치는 제외."},
    "nsr_warn_tpr_floor": {"value": 0.5, "source": "설계 선택 — '주의' = 적중률 ≥ 0.5 제약 아래 NSR 최소 · '위험' = 제약 없는 NSR 최소(한국은행 FSI 2단 임계치 12/24 의 구조를 따름)."},
    "tau_d": {"value": "2022-12-31", "source": "정보 경계 τ_D(CLAUDE.md · D6) — 임계치 선택 · 분위회귀 적합은 이전, 이후는 표본외."},
    "crisis_lambda": {"value": [0.20, 0.20], "source": "contracts/behavior_card.R::bc_crises_lt — Lunde & Timmermann (2004)."},
    "hit_drawdown": {"value": -0.10, "source": "v0 — 경보 뒤 60거래일 안 −10%."},
    "alarm_percentile": {"value": 0.80, "source": "v0."},
    "alarm_cooloff_obs": {"value": 20, "source": "v0."},
}
P = {k: v["value"] for k, v in PARAMS.items()}
for k in ("cmax_window_days", "fx_cmax_window_days", "breadth_drawdown", "breadth_high_window_obs", "breadth_high_min_obs",
          "breadth_universe_topn", "price_floor_krw", "corr_window_obs", "corr_topn", "flow_windows_obs", "score_pct_min_obs",
          "ecdf_min_history_years", "alarm_percentile", "alarm_cooloff_obs", "hit_drawdown"):
    v0.P[k] = P[k]   # 재사용하는 v0 도우미가 같은 수치를 쓰게 한다

AXES = ["equity", "smallcap", "breadth", "liquidity", "rates", "credit", "funding", "fx", "financial", "flow", "global", "contagion"]
AXIS_KO = {"equity": "주식(KOSPI200)", "smallcap": "중소형·코스닥", "breadth": "시장 폭", "liquidity": "유동성",
           "rates": "국채 금리", "credit": "신용 스프레드", "funding": "단기자금", "fx": "외환", "financial": "금융기관",
           "flow": "외국인 수급", "global": "글로벌 전이", "contagion": "시장 간 전이"}
# (id, axis, 이름, 정의, 원천, 가용 규칙 id 또는 None = 국내 장 마감 당일)
INDICATORS = [
    ("E1", "equity", "KOSPI200 변동성", "일별 로그수익² EWMA(λ.85) 제곱근", "benchmark.parquet", None),
    ("E2", "equity", "KOSPI200 CMAX(2년)", "1 − P/2년 최고", "benchmark.parquet", None),
    ("E3", "equity", "V-KOSPI200", "내재변동성 지수", "indices.parquet(kospi200_vol)", None),
    ("S1", "smallcap", "코스닥 변동성", "일별 로그수익² EWMA", "indices.parquet(kosdaq)", None),
    ("S2", "smallcap", "코스닥 CMAX(2년)", "1 − P/2년 최고", "indices.parquet(kosdaq)", None),
    ("S3", "smallcap", "코스닥 상대 약세(60일)", "−(코스닥 60일 로그수익 − KOSPI200 60일)", "indices · benchmark", None),
    ("B1", "breadth", "약세 종목 비중", "시총 상위 500 중 52주 고가 대비 −20% 이하 비중", "RAWDATA", None),
    ("B2", "breadth", "대형주 평균 상관", "시총 상위 100 의 21일 평균 쌍별 상관", "RAWDATA", None),
    ("B3", "breadth", "중앙 종목 60일 하락", "−(시총 상위 500 의 60일 수익 중앙값)", "RAWDATA", None),
    ("L1", "liquidity", "대형주 비유동성(Amihud)", "|수익|/거래대금 20일 평균의 상위 500 중앙값", "RAWDATA", None),
    ("L2", "liquidity", "중소형 비유동성(Amihud)", "같은 값 · 시총 501~1500위 중앙값", "RAWDATA", None),
    ("R1", "rates", "국고채 10년 금리 변동성", "일별 금리 변화² EWMA", "research_pull_ecos_817Y002(KR_Gov10Y)", "KR_Gov10Y"),
    ("R2", "rates", "국고채 3년 2년 누적 상승(CMIN)", "y − 2년 최저(%p)", "research_pull(KR_Gov3Y · 올바른 3년물)", "KR_Gov3Y"),
    ("R3", "rates", "수익률곡선 역전", "국고채 1년 − 10년(%p)", "research_pull(KR_Gov1Y · KR_Gov10Y)", "KR_Gov10Y"),
    ("C1", "credit", "회사채 AA- 스프레드", "AA- 3년 − 국고채 3년(%p)", "research_pull(KR_CorpAA · KR_Gov3Y)", "KR_CorpAA"),
    ("C2", "credit", "회사채 BBB- 스프레드", "BBB- 3년 − 국고채 3년(%p)", "research_pull(KR_CorpBBB · KR_Gov3Y)", "KR_CorpBBB"),
    ("C3", "credit", "저신용 프리미엄", "BBB- − AA-(%p)", "research_pull", "KR_CorpBBB"),
    ("M1", "funding", "CD − 콜 스프레드", "CD91 − 콜 1일(%p)", "research_pull(KR_CD91 · KR_Call1D)", "KR_Call1D"),
    ("M2", "funding", "CP − CD 스프레드", "CP91 − CD91(%p · 단기 신용증권 프리미엄)", "research_pull(KR_CP91 · KR_CD91)", "KR_CP91"),
    ("M3", "funding", "CD 금리 변동성", "일별 CD91 변화² EWMA", "research_pull(KR_CD91)", "KR_CD91"),
    ("X1", "fx", "원/달러 변동성", "일별 로그변화² EWMA", "research_pull_ecos_krw(731Y001)", "ECOS_KRW_USD"),
    ("X2", "fx", "원화 가치 CMAX(6개월)", "1 − 6개월 최저 원/달러 / 현재", "research_pull_ecos_krw", "ECOS_KRW_USD"),
    ("X3", "fx", "원화 고유 약세(20일)", "Δlog 원/달러 20일 − Δlog DXY 프록시 20일", "research_pull_ecos_krw · fx_majors", "ECOS_KRW_USD"),
    ("F1", "financial", "금융업 CMAX(2년)", "은행·증권·보험 시총가중 지수의 2년 CMAX", "RAWDATA + us_sector_lv1", None),
    ("F2", "financial", "금융업 고유 변동성", "2년 이동 OLS 잔차² EWMA(KOSPI200 대비)", "RAWDATA + us_sector_lv1 · benchmark", None),
    ("F3", "financial", "금융업 상대 약세(60일)", "−(금융업 60일 로그수익 − KOSPI200 60일)", "RAWDATA + us_sector_lv1", None),
    ("N1", "flow", "외국인 순매도 강도(20일)", "−Σ20일 외국인 순매수 / 시총", "investor_wide + RAWDATA", None),
    ("N2", "flow", "외국인 순매도 강도(60일)", "60일 판", "investor_wide + RAWDATA", None),
    ("N3", "flow", "외국인 순매도 폭", "시총 상위 500 중 20일 순매도 종목 비중", "investor_wide + RAWDATA", None),
    ("G1", "global", "VIX", "CBOE VIX", "research_pull_fred(VIXCLS)", "VIXCLS"),
    ("G2", "global", "세인트루이스 연준 FSI", "STLFSI4(주간)", "research_pull_fred(STLFSI4)", "STLFSI4"),
    ("G3", "global", "달러 강세(20일)", "Δlog DXY 프록시 20일", "research_pull_ecos_fx_majors(731Y002)", "ECOS_DXY_PROXY"),
    ("T1", "contagion", "주식·원화 동반 약세", "−corr21(KOSPI200 수익, Δlog 원/달러)", "benchmark · research_pull_ecos_krw", "ECOS_KRW_USD"),
    ("T2", "contagion", "주식·국채 상관 이탈", "|corr21 − corr1040|(KOSPI200 수익, Δ국고채 3년)", "benchmark · research_pull(KR_Gov3Y)", "KR_Gov3Y"),
]
IND_AXIS = {i[0]: i[1] for i in INDICATORS}
IND_RULE = {i[0]: i[5] for i in INDICATORS}
IDS = [i[0] for i in INDICATORS]
log = v0.log


# ─────────────────────────────────────────────────────────────────────────────
# 도구
# ─────────────────────────────────────────────────────────────────────────────
def ewma_vol(x: pd.Series, lam: float, seed_obs: int) -> pd.Series:
    """제곱의 EWMA 제곱근(새 CISS). 결측일은 갱신 없이 직전 값 유지."""
    a = x.values.astype(float)
    out = np.full(len(a), np.nan)
    v = None
    buf = []
    for i, r in enumerate(a):
        if np.isnan(r):
            if v is not None:
                out[i] = v
            continue
        if v is None:
            buf.append(r)
            if len(buf) >= seed_obs:
                v = float(np.mean(np.square(buf)))
                out[i] = v
            continue
        v = lam * v + (1 - lam) * r * r
        out[i] = v
    return pd.Series(np.sqrt(out), index=x.index)


def rolling_resid(y: pd.Series, x: pd.Series, w: int) -> pd.Series:
    df = pd.DataFrame({"y": y, "x": x}).astype(float)
    mx = df.x.rolling(w, min_periods=w).mean()
    my = df.y.rolling(w, min_periods=w).mean()
    cov = (df.x * df.y).rolling(w, min_periods=w).mean() - mx * my
    var = (df.x * df.x).rolling(w, min_periods=w).mean() - mx * mx
    beta = cov / var
    return df.y - ((my - beta * mx) + beta * df.x)


def asof(series: pd.Series, sid: str, cal_dates: list):
    """연구용 규칙 사본으로 가용일 결합(등록부 원본 무변경)."""
    s = series.dropna()
    df = pd.DataFrame({"Date": [d.date() for d in s.index], "Value": s.values, "Series": sid})
    j = fred_asof_join(cal_dates, df, sid, mode="decision_close", kr_calendar=cal_dates, rules=RULES)
    idx = pd.to_datetime(j["kr_date"])
    return (pd.Series(pd.to_numeric(j["value"], errors="coerce").values, index=idx),
            pd.Series(pd.to_datetime(j["obs_date"]).values, index=idx))


def pull_rates():
    r = pd.read_parquet(PULL + "/research_pull_ecos_817Y002.parquet")
    r["Date"] = pd.to_datetime(r["Date"])
    return {s: g.set_index("Date")["Value"].astype(float).sort_index() for s, g in r.groupby("Series")}


def load_rawdata_v1(start):
    cols = ["Date", "Ticker", "Close", "Ret", "Size", "Vol", "AdminStock", "TradingHalt"]
    t = v0._retry(lambda: ds.dataset(CACHE + "/RAWDATA.parquet").to_table(columns=cols, filter=pc.field("Date") >= start))
    dates = pd.to_datetime(t.column("Date").to_pandas())
    d_codes, d_uni = pd.factorize(dates, sort=True)
    t_codes, t_uni = pd.factorize(t.column("Ticker").to_pandas(), sort=True)
    shape = (len(d_uni), len(t_uni))
    A = {}
    for c in ["Close", "Ret", "Size", "Vol", "AdminStock", "TradingHalt"]:
        a = np.full(shape, np.nan, dtype=np.float32)
        a[d_codes, t_codes] = t.column(c).to_numpy(zero_copy_only=False).astype(np.float32)
        A[c] = a
    del t
    return pd.DatetimeIndex(d_uni), pd.Index(t_uni), A


def fin_membership(rd_dates, tickers):
    """월별 업종 스냅샷 → RAWDATA 날짜별 금융업 소속(직전 스냅샷 · PIT)."""
    s = v0._retry(pd.read_parquet, CACHE + "/universe_support/us_sector_lv1.parquet")
    s["Date"] = pd.to_datetime(s["Date"])
    s = s[s["Sector_Lv1"].isin(P["fin_sectors"])]
    snaps = sorted(s["Date"].unique())
    snap_mask = np.zeros((len(snaps), len(tickers)), dtype=bool)
    for k, d in enumerate(snaps):
        ti = tickers.get_indexer(s.loc[s["Date"] == d, "Ticker"].unique())
        snap_mask[k, ti[ti >= 0]] = True
    pos = np.searchsorted(np.array(snaps, dtype="datetime64[ns]"), rd_dates.values, side="left") - 1  # 직전 스냅샷
    mem = np.zeros((len(rd_dates), len(tickers)), dtype=bool)
    ok = pos >= 0
    mem[ok] = snap_mask[pos[ok]]
    return mem, len(snaps)


def shift_rows(a, k):
    out = np.full_like(a, np.nan)
    out[k:] = a[:-k]
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 지표
# ─────────────────────────────────────────────────────────────────────────────
def build_indicators():
    bm = v0.load_benchmark()
    cal = bm.index
    cal_dates = [d.date() for d in cal]
    raw = pd.DataFrame(index=cal, dtype=float)
    obs = pd.DataFrame(index=cal, dtype="datetime64[ns]")
    meta = {}
    lam_v, seed = P["ewma_vol_lambda"], P["ewma_vol_seed_obs"]
    same = pd.Series(cal, index=cal)
    W60 = P["rel_return_window_obs"]

    # ── 주식(KOSPI200) · 내재변동성 ──
    px = bm["BM_Close"].astype(float)
    lr = np.log(px).diff()
    raw["E1"] = ewma_vol(lr, lam_v, seed); obs["E1"] = same
    raw["E2"] = 1.0 - px / px.rolling(f"{P['cmax_window_days']}D").max(); obs["E2"] = same
    ix = v0._retry(pd.read_parquet, CACHE + "/indices.parquet")
    ix["Date"] = pd.to_datetime(ix["Date"])
    ix = ix.set_index("Date").sort_index()
    raw["E3"], obs["E3"] = v0.on_calendar(ix["kospi200_vol"].astype(float), cal)

    # ── 중소형 · 코스닥 ──
    kq = ix["kosdaq"].astype(float).dropna()
    lkq = np.log(kq).diff()
    raw["S1"], obs["S1"] = v0.on_calendar(ewma_vol(lkq, lam_v, seed), cal)
    raw["S2"], obs["S2"] = v0.on_calendar(1.0 - kq / kq.rolling(f"{P['cmax_window_days']}D").max(), cal)
    kq_c = kq.reindex(cal).ffill()
    rel = -(np.log(kq_c).diff(W60) - np.log(px).diff(W60))
    raw["S3"] = rel.where(kq_c.notna()); obs["S3"] = same

    # ── 금리 · 신용 · 단기자금(연구용 직접 수급 · 올바른 항목) ──
    R = pull_rates()
    g1, g3, g10 = R["KR_Gov1Y"], R["KR_Gov3Y"], R["KR_Gov10Y"]
    aa, bbb, cd, cp, call = R["KR_CorpAA"], R["KR_CorpBBB"], R["KR_CD91"], R["KR_CP91"], R["KR_Call1D"]
    raw["R1"], obs["R1"] = asof(ewma_vol(g10.diff(), lam_v, seed), "KR_Gov10Y", cal_dates)
    raw["R2"], obs["R2"] = asof((g3 - g3.rolling(f"{P['cmin_window_days']}D").min()).dropna(), "KR_Gov3Y", cal_dates)
    raw["R3"], obs["R3"] = asof((g1 - g10).dropna(), "KR_Gov10Y", cal_dates)
    raw["C1"], obs["C1"] = asof((aa - g3).dropna(), "KR_CorpAA", cal_dates)
    raw["C2"], obs["C2"] = asof((bbb - g3).dropna(), "KR_CorpBBB", cal_dates)
    raw["C3"], obs["C3"] = asof((bbb - aa).dropna(), "KR_CorpBBB", cal_dates)
    raw["M1"], obs["M1"] = asof((cd - call).dropna(), "KR_Call1D", cal_dates)
    raw["M2"], obs["M2"] = asof((cp - cd).dropna(), "KR_CP91", cal_dates)
    raw["M3"], obs["M3"] = asof(ewma_vol(cd.diff(), lam_v, seed), "KR_CD91", cal_dates)

    # ── 외환 ──
    kr = pd.read_parquet(PULL + "/research_pull_ecos_krw.parquet")
    kr["Date"] = pd.to_datetime(kr["Date"])
    krw = kr.drop_duplicates("Date").set_index("Date")["Value"].astype(float).sort_index()
    fxm = pd.read_parquet(PULL + "/research_pull_ecos_fx_majors.parquet")
    fxm["Date"] = pd.to_datetime(fxm["Date"])
    dxy = fxm.set_index("Date")["DXY_PROXY"].astype(float).sort_index().dropna()
    lk = np.log(krw)
    raw["X1"], obs["X1"] = asof(ewma_vol(lk.diff(), lam_v, seed), "ECOS_KRW_USD", cal_dates)
    raw["X2"], obs["X2"] = asof((1.0 - krw.rolling(f"{P['fx_cmax_window_days']}D").min() / krw).dropna(), "ECOS_KRW_USD", cal_dates)
    dxy_on_krw = dxy.reindex(lk.index, method="ffill")
    raw["X3"], obs["X3"] = asof((lk.diff(20) - np.log(dxy_on_krw).diff(20)).dropna(), "ECOS_KRW_USD", cal_dates)

    # ── 글로벌 ──
    fr = pd.read_parquet(PULL + "/research_pull_fred.parquet")
    fr["Date"] = pd.to_datetime(fr["Date"])
    vix = fr[fr.Series_ID == "VIXCLS"].set_index("Date")["Value"].astype(float).dropna()
    stl = fr[fr.Series_ID == "STLFSI4"].set_index("Date")["Value"].astype(float).dropna()
    raw["G1"], obs["G1"] = asof(vix, "VIXCLS", cal_dates)
    raw["G2"], obs["G2"] = asof(stl, "STLFSI4", cal_dates)
    raw["G3"], obs["G3"] = asof(np.log(dxy).diff(20).dropna(), "ECOS_DXY_PROXY", cal_dates)

    # ── 시장 간 전이 ──
    ret = bm["BM_Ret"].astype(float)
    dk = lk.diff().reindex(cal)
    t1 = -ret.rolling(P["corr_window_obs"], min_periods=P["corr_window_obs"]).corr(dk)
    raw["T1"], obs["T1"] = asof(t1.dropna(), "ECOS_KRW_USD", cal_dates)
    dy = g3.diff().reindex(cal)
    c_s = ret.rolling(P["corr_window_obs"], min_periods=P["corr_window_obs"]).corr(dy)
    c_l = ret.rolling(P["contagion_long_window_obs"], min_periods=500).corr(dy)
    raw["T2"], obs["T2"] = asof((c_s - c_l).abs().dropna(), "KR_Gov3Y", cal_dates)

    # ── RAWDATA 기반: 폭 · 유동성 · 금융업 · 수급 ──
    t0 = time.time()
    rd, tickers, A = load_rawdata_v1(dt.date(1995, 1, 1))
    log(f"RAWDATA {rd[0].date()}~{rd[-1].date()} · {len(tickers)} 종목 · {time.time() - t0:.0f}s")
    meta["rawdata_range"] = [str(rd[0].date()), str(rd[-1].date())]
    close, retm, size, vol = A["Close"], A["Ret"], A["Size"], A["Vol"]
    bad = (np.nan_to_num(A["AdminStock"]) > 0) | (np.nan_to_num(A["TradingHalt"]) > 0)
    size_lag, close_lag = shift_rows(size, 1), shift_rows(close, 1)
    base_elig = (close_lag >= P["price_floor_krw"]) & (~bad) & (~np.isnan(size_lag)) & (~np.isnan(close))
    rank_all = pd.DataFrame(np.where(base_elig, size_lag, np.nan)).rank(axis=1, ascending=False, method="first").values
    top = base_elig & (rank_all <= P["breadth_universe_topn"])
    mid = base_elig & (rank_all >= P["amihud_small_rank"][0]) & (rank_all <= P["amihud_small_rank"][1])
    n_top = top.sum(axis=1)
    enough = n_top >= P["breadth_universe_topn"] * 0.5
    meta["breadth_universe_n_median"] = float(np.median(n_top[n_top > 0]))

    # B1 — 52주 고가 대비 −20% 이하 비중
    hi = pd.DataFrame(close).rolling(P["breadth_high_window_obs"], min_periods=P["breadth_high_min_obs"]).max().values
    e1 = top & ~np.isnan(hi)
    deep = e1 & (close <= (1.0 - P["breadth_drawdown"]) * hi)
    n1 = e1.sum(axis=1)
    b1 = np.where(enough & (n1 > 0), deep.sum(axis=1) / np.maximum(n1, 1), np.nan)
    raw["B1"], obs["B1"] = v0.on_calendar(pd.Series(b1, index=rd), cal)
    del hi, deep, e1

    # B2 — 상위 100 평균 쌍별 상관
    Wc, K = P["corr_window_obs"], P["corr_topn"]
    valid_ret = pd.DataFrame(~np.isnan(retm)).rolling(Wc, min_periods=Wc).sum().values == Wc
    elig2 = valid_ret & (~bad) & (~np.isnan(size_lag))
    rank2 = pd.DataFrame(np.where(elig2, size_lag, np.nan)).rank(axis=1, ascending=False, method="first").values
    b2 = np.full(len(rd), np.nan)
    for t in range(Wc - 1, len(rd)):
        cols = np.where(rank2[t] <= K)[0]
        if len(cols) < K * 0.8:
            continue
        Rm = retm[t - Wc + 1:t + 1, cols].astype(np.float64)
        Z = Rm - Rm.mean(axis=0)
        sd = Z.std(axis=0, ddof=1)
        Z = Z[:, sd > 0] / sd[sd > 0]
        k = Z.shape[1]
        C = (Z.T @ Z) / (Wc - 1)
        b2[t] = (C.sum() - k) / (k * (k - 1))
    raw["B2"], obs["B2"] = v0.on_calendar(pd.Series(b2, index=rd), cal)
    del valid_ret, elig2, rank2

    # B3 — 상위 500 의 60일 수익 중앙값(부호 반전)
    r60 = close / shift_rows(close, W60) - 1.0
    b3 = -np.nanmedian(np.where(top & ~np.isnan(r60), r60, np.nan), axis=1)
    b3[~enough] = np.nan
    raw["B3"], obs["B3"] = v0.on_calendar(pd.Series(b3, index=rd), cal)
    del r60

    # L1 · L2 — Amihud 비유동성(×1e9 · 1원 거래대금당 |수익|)
    tv = close.astype(np.float64) * vol.astype(np.float64)
    ill = np.where(tv > 0, np.abs(retm.astype(np.float64)) / tv, np.nan) * 1e9
    ill20 = pd.DataFrame(ill).rolling(P["amihud_window_obs"], min_periods=15).mean().values
    l1 = np.nanmedian(np.where(top & ~np.isnan(ill20), ill20, np.nan), axis=1)
    l2 = np.nanmedian(np.where(mid & ~np.isnan(ill20), ill20, np.nan), axis=1)
    l1[~enough] = np.nan
    l2[mid.sum(axis=1) < 300] = np.nan
    raw["L1"], obs["L1"] = v0.on_calendar(pd.Series(l1, index=rd), cal)
    raw["L2"], obs["L2"] = v0.on_calendar(pd.Series(l2, index=rd), cal)
    del tv, ill, ill20

    # F1~F3 — 금융업(은행·증권·보험) 시총가중 지수
    mem, n_snap = fin_membership(rd, tickers)
    meta["fin_sector_snapshots"] = n_snap
    okf = mem & ~np.isnan(retm) & ~np.isnan(size_lag) & ~bad
    wsum = np.where(okf, size_lag, 0).sum(axis=1)
    rf = np.where(wsum > 0, np.where(okf, size_lag * np.nan_to_num(retm), 0).sum(axis=1) / np.maximum(wsum, 1e-9), np.nan)
    rf = pd.Series(rf, index=rd)
    meta["fin_members_median"] = float(np.median(okf.sum(axis=1)[okf.sum(axis=1) > 0]))
    lvl = (1 + rf.fillna(0)).cumprod().where(rf.notna())
    raw["F1"], obs["F1"] = v0.on_calendar(1.0 - lvl / lvl.rolling(f"{P['cmax_window_days']}D").max(), cal)
    bmr = bm["BM_Ret"].astype(float).reindex(rd)
    resid = rolling_resid(rf, bmr, P["beta_window_obs"])
    raw["F2"], obs["F2"] = v0.on_calendar(ewma_vol(resid, lam_v, seed), cal)
    rel_f = -(np.log(lvl).diff(W60) - np.log(px.reindex(rd)).diff(W60))
    raw["F3"], obs["F3"] = v0.on_calendar(rel_f, cal)
    del mem, okf

    # N1~N3 — 외국인 수급
    nf, inv_dates, n_drop, n_ok = v0.load_foreign_flows(rd, tickers, size)
    meta["investor_rows_joined"], meta["investor_rows_unmatched"] = n_ok, n_drop
    meta["investor_range"] = [str(inv_dates[0].date()), str(inv_dates[-1].date())]
    cov = (~np.isnan(nf)) & (~np.isnan(size))
    net = np.where(cov, nf, 0.0).sum(axis=1)
    mcap = np.where(cov, size.astype(np.float64), 0.0).sum(axis=1)
    has = cov.sum(axis=1) > 0
    net_s = pd.Series(np.where(has, net, np.nan), index=rd)
    mcap_s = pd.Series(np.where(has, mcap, np.nan), index=rd)
    for col, wnd in zip(["N1", "N2"], P["flow_windows_obs"]):
        raw[col], obs[col] = v0.on_calendar(-net_s.rolling(wnd, min_periods=wnd).sum() / mcap_s, cal)
    Wf = P["flow_breadth_window_obs"]
    nf0 = np.nan_to_num(nf)
    cs = np.cumsum(nf0, axis=0)
    s20 = cs.copy()
    s20[Wf:] = cs[Wf:] - cs[:-Wf]
    cnt = np.cumsum(~np.isnan(nf), axis=0).astype(np.float64)
    c20 = cnt.copy()
    c20[Wf:] = cnt[Wf:] - cnt[:-Wf]
    e3 = top & (c20 >= Wf * 0.75)
    n3 = np.where(e3.sum(axis=1) >= P["breadth_universe_topn"] * 0.5, (e3 & (s20 < 0)).sum(axis=1) / np.maximum(e3.sum(axis=1), 1), np.nan)
    raw["N3"], obs["N3"] = v0.on_calendar(pd.Series(n3, index=rd), cal)
    del nf, nf0, cs, s20, cnt, c20, A, close, retm, size, vol
    return bm, raw, obs, meta


# ─────────────────────────────────────────────────────────────────────────────
# 표준화 · 집계
# ─────────────────────────────────────────────────────────────────────────────
def ecdf_all(raw, ecdf="recursive"):
    Z = pd.DataFrame(index=raw.index)
    valid = pd.DataFrame(index=raw.index)
    first = {}
    for i in IDS:
        x = raw[i]
        if ecdf != "recursive":
            Z[i] = v0.fullsample_ecdf(x)
        elif i in P["pit_rolling_indicators"]:   # 10년 이동 창 PIT(추세 지표) — 창 안 관측만 쓴다(C1)
            Z[i] = x.rolling(P["pit_rolling_window_obs"], min_periods=P["pit_rolling_min_obs"]).rank(method="average", pct=True)
        else:
            Z[i] = v0.recursive_ecdf(x.values.astype(float))
        f = x.first_valid_index()
        first[i] = f
        valid[i] = (raw.index >= f + pd.DateOffset(years=P["ecdf_min_history_years"])) & x.notna()
    return Z, valid, first


def aggregate(Zm: np.ndarray, lam: float):
    """새 CISS 식: score = (w∘z)' C_t (w∘z) · C_t = EWMA 순위상관(0.5 차감). 반환 score · 지표 기여 · 평균 상관."""
    n, k = Zm.shape
    w = np.full(k, 1.0 / k)
    score = np.full(n, np.nan)
    contrib = np.full((n, k), np.nan)
    corr_avg = np.full(n, np.nan)
    sig = np.eye(k) * P["ewma_init"]["var"] + (1 - np.eye(k)) * P["ewma_init"]["cov"]
    for t in range(n):
        z = Zm[t]
        if np.isnan(z).any():
            continue
        d = z - P["ewma_demean"]
        sig = lam * sig + (1 - lam) * np.outer(d, d)
        sd = np.sqrt(np.diag(sig))
        C = sig / np.outer(sd, sd)
        y = w * z
        Cy = C @ y
        contrib[t] = y * Cy
        score[t] = float(y @ Cy)
        corr_avg[t] = (C.sum() - k) / (k * (k - 1))
    return score, contrib, corr_avg


def compute(raw, lam_corr, ecdf="recursive"):
    Z, valid, first = ecdf_all(raw, ecdf)
    allv = valid[IDS].all(axis=1)
    t0 = allv[allv].index[0]
    Zm = Z[IDS].values.astype(float)
    Zm[~allv.values] = np.nan
    score, contrib, corr_avg = aggregate(Zm, lam_corr)
    res = pd.DataFrame(index=raw.index)
    res["score"] = 100 * score
    res["score_linear"] = 100 * np.where(allv, Zm.mean(axis=1), np.nan)
    res["avg_corr"] = corr_avg
    for j, i in enumerate(IDS):
        res[f"ci_{i}"] = 100 * contrib[:, j]
        res[f"z_{i}"] = Z[i]
    for ax in AXES:
        mem = [i for i in IDS if IND_AXIS[i] == ax]
        res[f"c_{ax}"] = res[[f"ci_{i}" for i in mem]].sum(axis=1, min_count=len(mem))
        res[f"s_{ax}"] = Z[mem].mean(axis=1, skipna=False)
    # 축 수준 집계(v0 방식) — 비교용
    S = pd.DataFrame({ax: res[f"s_{ax}"] for ax in AXES})
    Sm = S.values.astype(float)
    Sm[~allv.values] = np.nan
    sc_ax, _, _ = aggregate(Sm, lam_corr)
    res["score_axis_level"] = 100 * sc_ax
    res = res[res.index >= t0]
    return res, Z, valid, first, t0


# ─────────────────────────────────────────────────────────────────────────────
# 검증
# ─────────────────────────────────────────────────────────────────────────────
def fwd_logret(px: pd.Series, h: int) -> pd.Series:
    return (np.log(px.shift(-h)) - np.log(px)) * 100


def quantile_regression(signals: dict, y: pd.Series, taus, tau_d: str):
    from statsmodels.regression.quantile_regression import QuantReg
    rows, oos_rows = [], []
    rng = np.random.default_rng(20261106)
    H = P["qr_block_obs"]
    for name, x in signals.items():
        df = pd.DataFrame({"x": x, "y": y}).dropna()
        if len(df) < 500:
            continue
        X = np.column_stack([np.ones(len(df)), df.x.values])
        yv = df.y.values
        fit = {tau: QuantReg(yv, X).fit(q=tau, max_iter=5000) for tau in taus}
        # 블록 부트스트랩(τ = 0.05 · 0.50 기울기)
        n = len(df)
        boots = {0.05: [], 0.50: []}
        for _ in range(P["qr_boot_reps"]):
            starts = rng.integers(0, n - H, size=int(np.ceil(n / H)))
            idx = np.concatenate([np.arange(s, s + H) for s in starts])[:n]
            for tau in boots:
                try:
                    boots[tau].append(QuantReg(yv[idx], X[idx]).fit(q=tau, max_iter=5000).params[1])
                except Exception:  # noqa: BLE001
                    pass
        for tau in taus:
            r = {"signal": name, "tau": tau, "n": n, "intercept": fit[tau].params[0], "slope": fit[tau].params[1]}
            if tau in boots and boots[tau]:
                r["slope_ci_lo"], r["slope_ci_hi"] = np.percentile(boots[tau], [2.5, 97.5])
            rows.append(r)
        # 표본외 핀볼 손실(τ_D 이전 적합 → 이후 평가) vs 무조건부 분위
        ins, oos = df[df.index <= tau_d], df[df.index > tau_d]
        if len(ins) > 500 and len(oos) > 100:
            Xi = np.column_stack([np.ones(len(ins)), ins.x.values])
            Xo = np.column_stack([np.ones(len(oos)), oos.x.values])
            for tau in (0.05, 0.10, 0.50):
                f = QuantReg(ins.y.values, Xi).fit(q=tau, max_iter=5000)
                q_cond = Xo @ f.params
                q_unc = np.quantile(ins.y.values, tau)
                e1, e2 = oos.y.values - q_cond, oos.y.values - q_unc
                pb = lambda e: np.mean(np.maximum(tau * e, (tau - 1) * e))  # noqa: E731
                oos_rows.append({"signal": name, "tau": tau, "n_in": len(ins), "n_out": len(oos),
                                 "pinball_conditional": pb(e1), "pinball_unconditional": pb(e2),
                                 "ratio_cond_over_unc": pb(e1) / pb(e2), "coverage_conditional": float(np.mean(oos.y.values < q_cond)),
                                 "coverage_unconditional": float(np.mean(oos.y.values < q_unc))})
    return pd.DataFrame(rows), pd.DataFrame(oos_rows)


def nsr_thresholds(signals: dict, px: pd.Series, eps: pd.DataFrame, tau_d: str):
    """잡음/신호 비율(KLR 1998) — 사건 = LT −20% 확정이 앞으로 H 거래일 안. τ_D 이전에서 임계치 선택, 이후 표본외."""
    H = P["nsr_event_horizon_obs"]
    idx = px.index
    conf_pos = np.array(sorted(idx.get_indexer(pd.to_datetime(eps["confirm"].dropna()))))
    conf_pos = conf_pos[conf_pos >= 0]
    E = np.zeros(len(idx), dtype=bool)
    for cpos in conf_pos:
        E[max(0, cpos - H):cpos] = True          # t ∈ [c−H, c) → 확정이 (t, t+H] 안
    E_s = pd.Series(E, index=idx)
    known = pd.Series(np.arange(len(idx)) < len(idx) - H, index=idx)  # 마지막 H 일은 사건 여부 미확정
    lo, hi, st = P["nsr_grid"]
    grid = np.round(np.arange(lo, hi + 1e-9, st), 2)
    rows, sel = [], {}
    for name, pct in signals.items():
        d = pd.DataFrame({"p": pct, "E": E_s, "k": known}).dropna()
        d = d[d.k]
        ins, oos = d[d.index <= tau_d], d[d.index > tau_d]
        best = {}
        for th in grid:
            S = ins.p >= th
            if S.sum() < P["nsr_min_signal_days"]:
                continue
            tpr = float(S[ins.E].mean()) if ins.E.any() else np.nan
            fpr = float(S[~ins.E].mean())
            nsr = fpr / tpr if tpr and tpr > 0 else np.nan
            prec = float(ins.E[S].mean()) if S.any() else np.nan
            rows.append({"signal": name, "threshold": th, "sample": "in(<=tau_d)", "n": len(ins), "signal_days": int(S.sum()),
                         "tpr": tpr, "fpr": fpr, "nsr": nsr, "precision": prec, "base_rate": float(ins.E.mean())})
            if np.isfinite(nsr):
                best[th] = (nsr, tpr)
        if best:
            th_risk = min(best, key=lambda t: best[t][0])
            cand = {t: v for t, v in best.items() if v[1] >= P["nsr_warn_tpr_floor"]}
            th_warn = min(cand, key=lambda t: cand[t][0]) if cand else None
            out = {"threshold_risk": th_risk, "nsr_risk_in": best[th_risk][0], "tpr_risk_in": best[th_risk][1],
                   "threshold_warn": th_warn, "nsr_warn_in": None if th_warn is None else best[th_warn][0],
                   "tpr_warn_in": None if th_warn is None else best[th_warn][1]}
            for lab, th in (("risk", th_risk), ("warn", th_warn)):
                if th is None or len(oos) == 0:
                    continue
                S = oos.p >= th
                tpr = float(S[oos.E].mean()) if oos.E.any() else np.nan
                fpr = float(S[~oos.E].mean()) if (~oos.E).any() else np.nan
                out[f"oos_{lab}_tpr"], out[f"oos_{lab}_fpr"] = tpr, fpr
                out[f"oos_{lab}_nsr"] = fpr / tpr if tpr and tpr > 0 else np.nan
                out[f"oos_{lab}_signal_days"], out[f"oos_{lab}_event_days"], out["oos_n"] = int(S.sum()), int(oos.E.sum()), len(oos)
            sel[name] = out
    return pd.DataFrame(rows), sel


def validate(res, px, signals_pct, t0):
    l_down, l_up = P["crisis_lambda"]
    eps = v0.lt_crises(px, l_down, l_up)
    eps_cov = eps[eps["peak"] >= t0].reset_index(drop=True)
    rows, axrows = [], []
    axis_pct = {ax: v0.recursive_pct(res[f"s_{ax}"]) for ax in AXES}
    for _, ep in eps_cov.iterrows():
        ip, iq = px.index.get_loc(ep["peak"]), px.index.get_loc(ep["trough"])
        win = res["score"].reindex(px.index).iloc[ip:iq + 1]
        r = {"peak": ep["peak"].date(), "confirm_minus20": ep["confirm"].date(), "trough": ep["trough"].date(), "depth": ep["depth"],
             "ongoing": ep["ongoing"], "td_peak_to_confirm": px.index.get_loc(ep["confirm"]) - ip,
             "score_at_peak": res["score"].get(ep["peak"]), "score_max": win.max(),
             "score_max_date": win.idxmax().date() if win.notna().any() else None}
        for name, pc_ in signals_pct.items():
            for thr in (P["alarm_percentile"], 0.90):
                tt = v0.alarm_timing(pc_, px, ep, thr)
                for k, v in tt.items():
                    r[f"{name}_{int(thr * 100)}_{k}"] = v
        rows.append(r)
        for ax in AXES:
            tt = v0.alarm_timing(axis_pct[ax], px, ep, P["alarm_percentile"])
            axrows.append({"peak": ep["peak"].date(), "axis": ax, **tt})
    ev = pd.DataFrame(rows)
    ax_t = pd.DataFrame(axrows)

    H = 60
    pv = px.values
    m = np.full(len(pv), np.nan)
    for i in range(len(pv) - H):
        m[i] = pv[i + 1:i + H + 1].min() / pv[i] - 1
    fw_min = pd.Series(m, index=px.index)
    hit_rows = []
    base = fw_min.reindex(res.index).dropna()
    for name, pc_ in signals_pct.items():
        for thr in (P["alarm_percentile"], 0.90):
            ons = v0.alarm_onsets(pc_.reindex(res.index).dropna(), thr, P["alarm_cooloff_obs"])
            done = fw_min.reindex(ons).dropna()
            hit_rows.append({"signal": name, "threshold": thr, "n_onsets": len(ons), "n_evaluable": len(done),
                             "hit_rate_dd10_60d": float((done <= P["hit_drawdown"]).mean()) if len(done) else None,
                             "base_rate_dd10_60d": float((base <= P["hit_drawdown"]).mean()),
                             "onsets": ";".join(str(d.date()) for d in ons)})
    hits = pd.DataFrame(hit_rows)

    y60 = fwd_logret(px, P["qr_horizon_obs"]).reindex(res.index)
    bins = [0, 0.5, 0.8, 0.95, 1.0001]
    lab = ["<50", "50-80", "80-95", ">=95"]
    X = pd.DataFrame({"y60": y60, "mindd60": fw_min.reindex(res.index)})
    X["bucket"] = pd.cut(signals_pct["v1"].reindex(res.index), bins=bins, labels=lab, right=False)
    bucket = X.groupby("bucket", observed=False).agg(n=("y60", "size"), fwd_logret_60_mean=("y60", "mean"),
                                                     fwd_logret_60_q05=("y60", lambda s: s.quantile(0.05)),
                                                     fwd_mindd_60_median=("mindd60", "median")).reset_index()
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
    return eps, ev, ax_t, hits, bucket, evst, axis_pct, y60


# ─────────────────────────────────────────────────────────────────────────────
def main():
    os.makedirs(OUT, exist_ok=True)
    t_start = time.time()
    bm, raw, obs, meta = build_indicators()
    log(f"indicators built {time.time() - t_start:.0f}s · n={len(IDS)}")
    lam = P["ewma_corr_lambda_daily"]
    res, Z, valid, first, t0 = compute(raw, lam)
    res["score_pct"] = v0.recursive_pct(res["score"])
    res["score_linear_pct"] = v0.recursive_pct(res["score_linear"])
    res["score_axis_level_pct"] = v0.recursive_pct(res["score_axis_level"])
    log(f"composite start t0={t0.date()} · last={res.index[-1].date()} · score={res['score'].iloc[-1]:.2f} · pct={res['score_pct'].iloc[-1]:.3f}")

    # 비교 신호 — V-KOSPI · v0
    vk = raw["E3"]
    vk_pct = v0.recursive_pct(vk)
    signals_pct = {"v1": res["score_pct"], "v1_linear": res["score_linear_pct"], "v1_axis_level": res["score_axis_level_pct"],
                   "vkospi": vk_pct.reindex(res.index)}
    v0_path = PULL + "/kr_stress_daily.parquet"
    if os.path.exists(v0_path):
        d0 = pd.read_parquet(v0_path)
        d0.index = pd.to_datetime(d0.index)
        signals_pct["v0"] = d0["score_pct"].reindex(res.index)
        res["v0_score"] = d0["score"].reindex(res.index)

    # 강건성
    rob = []

    def _rob_row(name, s):
        both = pd.concat([res["score"], s], axis=1).dropna()
        return {"variant": name, "pearson": both.corr().iloc[0, 1], "spearman": both.corr(method="spearman").iloc[0, 1],
                "latest_main": res["score"].iloc[-1], "latest_main_pct": res["score_pct"].iloc[-1],
                "latest_variant": s.dropna().iloc[-1], "latest_variant_pct": v0.recursive_pct(s.dropna()).iloc[-1]}

    for lw in P["corr_lambda_sensitivity"]:
        r2, *_ = compute(raw, lw)
        rob.append(_rob_row(f"corr_lambda_{lw:.4f}", r2["score"]))
    r3, *_ = compute(raw, lam, ecdf="fullsample")
    rob.append(_rob_row("fullsample_ecdf_DIAGNOSTIC_lookahead", r3["score"]))
    for alt in ["score_linear", "score_axis_level"] + (["v0_score"] if "v0_score" in res else []):
        rob.append(_rob_row(alt, res[alt]))
    # 축 하나씩 제외(leave-one-axis-out) — 지수 상관과 최근값
    for ax in AXES:
        keep = [i for i in IDS if IND_AXIS[i] != ax]
        Zm = Z[keep].values.astype(float)
        allv = valid[IDS].all(axis=1).values
        Zm[~allv] = np.nan
        sc, _, _ = aggregate(Zm, lam)
        rob.append(_rob_row(f"drop_axis_{ax}", pd.Series(100 * sc, index=raw.index).reindex(res.index)))
    pd.DataFrame(rob).to_csv(OUT + "/robustness.csv", index=False, encoding="utf-8-sig")

    # 검증
    px = bm["BM_Close"].astype(float)
    eps, ev, ax_t, hits, bucket, evst, axis_pct, y60 = validate(res, px, signals_pct, t0)
    tq0 = time.time()
    qr, qr_oos = quantile_regression(signals_pct, y60, P["qr_taus"], P["tau_d"])
    log(f"quantile regression {time.time() - tq0:.0f}s")
    nsr_grid, nsr_sel = nsr_thresholds(signals_pct, px, eps, P["tau_d"])

    # ── 저장 ──
    daily = res.copy()
    daily["vkospi"] = vk.reindex(res.index)
    daily["vkospi_pct"] = vk_pct.reindex(res.index)
    for ax in AXES:
        daily[f"pct_{ax}"] = axis_pct[ax].reindex(res.index)
    for i in IDS:
        daily[f"x_{i}"] = raw[i].reindex(res.index)
    daily.index.name = "Date"
    daily.to_parquet(OUT + "/kr_stress_v1_daily.parquet")
    slim = ["score", "score_pct", "score_linear", "score_axis_level", "avg_corr"] + [f"c_{a}" for a in AXES] + [f"s_{a}" for a in AXES] + ["vkospi"]
    daily[slim].round(5).to_csv(OUT + "/kr_stress_v1_daily.csv", encoding="utf-8-sig")
    eps.to_csv(OUT + "/crisis_episodes_lt2020_kospi200.csv", index=False, encoding="utf-8-sig")
    ev.to_csv(OUT + "/crisis_validation.csv", index=False, encoding="utf-8-sig")
    ax_t.to_csv(OUT + "/axis_alarm_timing.csv", index=False, encoding="utf-8-sig")
    hits.to_csv(OUT + "/alarm_hit_rate.csv", index=False, encoding="utf-8-sig")
    bucket.to_csv(OUT + "/forward_by_percentile_bucket.csv", index=False, encoding="utf-8-sig")
    evst.to_csv(OUT + "/event_study_paths.csv", index=False, encoding="utf-8-sig")
    qr.to_csv(OUT + "/quantile_regression.csv", index=False, encoding="utf-8-sig")
    qr_oos.to_csv(OUT + "/quantile_regression_oos.csv", index=False, encoding="utf-8-sig")
    nsr_grid.to_csv(OUT + "/nsr_threshold_grid.csv", index=False, encoding="utf-8-sig")
    json.dump(nsr_sel, open(OUT + "/nsr_selected.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2, default=str)

    last = res.index[-1]
    i_l = len(res) - 1
    d20, d60 = res.index[max(0, i_l - 20)], res.index[max(0, i_l - 60)]
    st_rows = []
    for (iid, ax, name, defi, src, rule) in INDICATORS:
        od = obs[iid].get(last)
        lag_td = None if pd.isna(od) else int(((raw.index > od) & (raw.index <= last)).sum())
        st_rows.append({"id": iid, "axis": ax, "axis_ko": AXIS_KO[ax], "name": name, "definition": defi, "value": raw[iid].get(last),
                        "ecdf_pct": Z[iid].get(last), "contrib": res.loc[last, f"ci_{iid}"], "value_20td_ago": raw[iid].get(d20),
                        "ecdf_pct_20td_ago": Z[iid].get(d20), "last_obs_date": None if pd.isna(od) else od.date(),
                        "stale_trading_days": lag_td, "history_start": first[iid].date(), "source": src, "availability_rule": rule or "당일 마감"})
    status = pd.DataFrame(st_rows)
    status.to_csv(OUT + "/indicator_status_latest.csv", index=False, encoding="utf-8-sig")

    latest = {
        "date": str(last.date()), "score": float(res["score"].iloc[-1]), "score_pct": float(res["score_pct"].iloc[-1]),
        "score_linear": float(res["score_linear"].iloc[-1]), "score_axis_level": float(res["score_axis_level"].iloc[-1]),
        "avg_corr": float(res["avg_corr"].iloc[-1]),
        "contrib": {ax: float(res.loc[last, f"c_{ax}"]) for ax in AXES}, "subindex": {ax: float(res.loc[last, f"s_{ax}"]) for ax in AXES},
        "axis_pct": {ax: float(axis_pct[ax].get(last)) for ax in AXES},
        "score_20td_ago": float(res.loc[d20, "score"]), "date_20td_ago": str(d20.date()),
        "contrib_20td_ago": {ax: float(res.loc[d20, f"c_{ax}"]) for ax in AXES},
        "score_60td_ago": float(res.loc[d60, "score"]), "date_60td_ago": str(d60.date()),
        "vkospi": float(vk.get(last)), "vkospi_pct": float(vk_pct.get(last)),
        "v0_score": None if "v0_score" not in res else float(res["v0_score"].iloc[-1]),
        "max_score_since_t0": float(res["score"].max()), "max_score_date": str(res["score"].idxmax().date()),
        "top_indicators": status.sort_values("contrib", ascending=False).head(8)[["id", "name", "contrib", "ecdf_pct"]].to_dict("records"),
        "nsr_selected": nsr_sel.get("v1"),
    }
    ns = nsr_sel.get("v1") or {}
    p_now = latest["score_pct"]
    latest["tier"] = ("위험" if ns.get("threshold_risk") is not None and p_now >= ns["threshold_risk"]
                      else "주의" if ns.get("threshold_warn") is not None and p_now >= ns["threshold_warn"] else "정상")
    pull_meta = json.load(open(PULL + "/research_pull_meta.json", encoding="utf-8"))
    run_meta = {"run_at": dt.datetime.now().isoformat(timespec="seconds"), "composite_start_t0": str(t0.date()), "last_date": str(last.date()),
                "axes": AXES, "axis_ko": AXIS_KO, "n_indicators": len(IDS),
                "indicators": [dict(zip(["id", "axis", "name", "definition", "source", "availability_rule"], i)) for i in INDICATORS],
                "indicator_history_start": {k: str(v.date()) for k, v in first.items()},
                "data_files": {f: {"mtime": v0._mtime(p)} for f, p in {
                    "RAWDATA.parquet": CACHE + "/RAWDATA.parquet", "investor_wide.parquet": CACHE + "/investor_stock/investor_wide.parquet",
                    "benchmark.parquet": CACHE + "/benchmark.parquet", "indices.parquet": CACHE + "/indices.parquet",
                    "us_sector_lv1.parquet": CACHE + "/universe_support/us_sector_lv1.parquet",
                    "research_pull_ecos_817Y002": PULL + "/research_pull_ecos_817Y002.parquet",
                    "research_pull_ecos_krw": PULL + "/research_pull_ecos_krw.parquet",
                    "research_pull_ecos_fx_majors": PULL + "/research_pull_ecos_fx_majors.parquet",
                    "research_pull_fred": PULL + "/research_pull_fred.parquet"}.items()},
                "data_ranges": meta, "research_pull_meta": pull_meta,
                "fred_availability_rules": fred_avail_rules_meta(RULES), "params": PARAMS, "latest": latest,
                "elapsed_sec": round(time.time() - t_start, 1)}
    json.dump(run_meta, open(OUT + "/run_meta.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2, default=str)
    log(json.dumps({k: latest[k] for k in ("date", "score", "score_pct", "score_linear", "avg_corr", "vkospi_pct", "v0_score")}, ensure_ascii=False))
    log("contrib", json.dumps({k: round(v, 2) for k, v in latest["contrib"].items()}, ensure_ascii=False))
    log(f"done {time.time() - t_start:.0f}s")


if __name__ == "__main__":
    main()
