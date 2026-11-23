"""aif_riskmodel.py — 위험 평가 모형 1부: 지표 → 노출 → 횡단면 회귀(FOLLOWUP_PLAN.md '위험 평가 모형' · 걸음 1 '원문 재현 판'의 선형 모형).

Barra USE4 의 구조를 한국 자료로 만든다: 수익 = 시장 + 업종 + 스타일 + 고유.
  desc   지표 19개(USE4 Empirical Notes 부록 A 의 정의) — 신호일(월말)마다, 그날까지의 자료로
           가격 · 거래: BETA · HSIGMA · DASTD · CMRA · RSTR · STOM · STOQ · STOA · LNCAP
           재무 · 컨센서스: EPFWD · CETOP · ETOP · EGRO · SGRO · YILD · BTOP · MLEV · DTOA · BLEV
  expo   스타일 노출 12개 — 지표 표준화(평균 = 추정 유니버스 시총 가중 · 표준편차 = 동일가중 · 3 표준편차 절단) → 부록 A 의 가중으로 합성 → 다시 표준화
           → 결측은 업종과 규모에 회귀해 채움 → 잔차 변동성은 베타에 직교화 → 비선형 규모 · 비선형 베타(세제곱 → 직교화 → 절단 → 표준화)
  reg    횡단면 회귀 — √시총 가중 · 업종 팩터 수익의 시총 가중 합 = 0. 노출은 신호일 값으로 그 보유월 내내 고정.
           월간(유의성 · 설명력 평가용)과 일간(팩터 공분산 · 고유 위험의 재료 = 순수 팩터 수익 · 고유수익)
  stats  팩터 통계표(USE4 표 4.2 의 열) — 평균 |t| · |t|>2 인 달의 비율 · 연 수익 · 연 변동성 · 추정 유니버스와의 상관 · 노출 안정 계수 · 분산팽창계수
           설정을 고르는 데 쓰는 표이므로 표본 안(설정 measure.is_end 까지)만 낸다. 그 뒤 구간의 팩터 수익은 저장만 하고 여기서 요약하지 않는다.
추정 유니버스 = 측정 축 멤버(공통 틀) 가운데 그날 행과 업종이 있는 종목. 노출은 행이 있는 모든 종목에 매긴다(표준화의 평균 · 표준편차는 추정 유니버스에서).
미래참조: 지표는 신호일까지의 일별 자료 · 재무는 쓸 수 있는 첫날(Factor_Date)이 신호일 이전인 값 · 컨센서스는 신호일 전날까지의 마지막 값.
  --check 가 자료를 신호일에서 자른 뒤 다시 만든 지표 · 노출이 온 자료로 만든 것과 같은지 확인한다.
원문과 다르게 둔 곳(자료 사정 · 원문에 없는 값 — README '위험 평가 모형 1부'에 표로 적는다):
  예상 이익수익률 = 컨센서스 1년 EPS ÷ 1년 BPS × 장부가/시가(주당 추정치를 수정주가 수준과 나누지 않는다) · 성장에 애널리스트 장기 성장 예상이 없다 ·
  창 안 관측 하한 50% · 표준화 전 10 표준편차 밖은 자료 오류로 버림 · 성장의 분모는 절댓값 평균 · 장기부채 = 이자부부채 − 단기차입금 − 유동성 사채.
산출(.cache/aif_research/followup/risk/): desc.npz · expo.npz · reg.npz · spec_daily.npy · meta.json + results/followup/risk/factor_stats_is.csv · checks.json
실행: python py/aif_riskmodel.py [--force] [--check] [--smoke]     (감시 셸: ops/aif_run.py --track followup --job nl_risk --stage nl_risk)
"""
import argparse
import csv
import os
import sys
import time
import warnings

import numpy as np

import aif_blocks as ab
import aif_common as ac
import aif_daily as ad
from aif_roll import last_valid

F32 = np.float32
VERSION = 1
STAGE, PART_TO = "nl_risk", 0.40          # 위험 평가 모형 단계의 1부(지표 · 노출 · 회귀) — 2부(공분산 · 고유 위험) · 3부(평가 · 검증)가 뒤를 잇는다

# ── USE4 Empirical Notes 부록 A 의 값(창 · 반감기 · 지표 가중) · 방법론 노트 2.2 의 절단 ──────────────────────
BETA_WIN, BETA_HL = 252, 63                 # 베타 · 베타 회귀의 잔차 변동성(HSIGMA)
DASTD_HL = 42                               # 일별 초과수익 변동성(창은 베타와 같은 252일)
RSTR_WIN, RSTR_LAG, RSTR_HL = 504, 21, 126  # 상대 강도(모멘텀)
CMRA_MONTHS, MONTH_DAYS = 12, 21            # 누적 범위 — 21거래일 한 달 × 12
STYLE_DEF = {                               # 스타일: [(지표, 가중)]
    "BETA": [("BETA", 1.0)],
    "MOMENTUM": [("RSTR", 1.0)],
    "SIZE": [("LNCAP", 1.0)],
    "EARNYILD": [("EPFWD", 0.75), ("CETOP", 0.15), ("ETOP", 0.10)],
    "RESVOL": [("DASTD", 0.75), ("CMRA", 0.15), ("HSIGMA", 0.10)],
    "GROWTH": [("EGRO", 0.20), ("SGRO", 0.10)],                      # 원문은 애널리스트 장기 성장 예상 0.70 을 더한다 — 한국 자료에 없어 남은 둘(2 : 1)만 쓴다
    "DIVYILD": [("YILD", 1.0)],
    "BTOP": [("BTOP", 1.0)],
    "LEVERAGE": [("MLEV", 0.75), ("DTOA", 0.15), ("BLEV", 0.10)],
    "LIQUIDITY": [("STOM", 0.35), ("STOQ", 0.35), ("STOA", 0.30)],
}
ORTH = {"RESVOL": "BETA"}                   # 잔차 변동성은 베타에 직교화
CUBE = {"NLSIZE": "SIZE", "NLBETA": "BETA"} # 비선형 규모 · 비선형 베타 = 표준화 노출의 세제곱 → 원래 노출에 직교화 → 절단 → 표준화
STYLES = list(STYLE_DEF) + list(CUBE)
STYLE_KO = {"BETA": "베타", "MOMENTUM": "모멘텀", "SIZE": "규모", "EARNYILD": "이익수익률", "RESVOL": "잔차 변동성", "GROWTH": "성장", "DIVYILD": "배당수익률",
            "BTOP": "장부가/시가", "LEVERAGE": "레버리지", "LIQUIDITY": "유동성", "NLSIZE": "비선형 규모", "NLBETA": "비선형 베타"}
CLIP_SD = 3.0
# ── 정한 값(원문에 수치가 없다) ────────────────────────────────────────────────────────────────────────
OUT_SD = 10.0                               # 표준화 전 이만큼 벗어난 값은 자료 오류로 보고 버린다(원문은 '자료 오류 무리'의 경계를 밝히지 않았다)
MIN_FRAC = 0.5                              # 창 안에서 행이 있는 날의 비율 하한(새로 상장한 종목은 반년쯤 지나야 가격 지표가 생긴다 — 그전에는 업종 · 규모로 채운다)
MIN_EST = 30                                # 표준화 · 회귀에 필요한 최소 종목 수
MAX_AGE_CONS = 20                           # 컨센서스 값의 유효 기간(거래일) — 1단계 컨센서스 묶음과 같다
GROWTH_LAGS = (16, 12, 8, 4, 0)             # 성장 지표의 연간 다섯 점 = 최근 4분기 합을 4분기 간격으로(오래된 것 → 최근)
ANCHOR = "TotalAssets"                      # 재무 기간을 잡는 기준 항목(모든 회사에 있다)
FUND_NOW = [ANCHOR, "NetIncomeParent", "CashEarnings", "EquityParent", "PreferredCapital", "InterestBearingDebt", "CurrentBorr", "CurrentBonds",
            "LongTermBorr", "Bonds", "ConvBonds", "ExchBonds", "BondsWithWarrants", "CurrentLiab"]
FUND_LAG = ["EPSParentAdj", "Revenue", "SharesCommonAvgAdj"]
FUND_ASOF = ["CashDivTotal"]                # 항목 자체의 as-of 로 읽는 것 — 배당은 원천에 2013년 기간 행이 없어(분기 · 연간 캐시 모두 0건) 같은 기간 맞춤으로는 2013-07~2015-04 가 통째로 빈다.
                                            #   마지막으로 알려진 12개월 배당을 연간 자료의 묵은 값 하한(24개월)까지 쓴다 → 빈 달이 2015-01~04 넉 달로 준다. 무배당 회사는 0 행이 있다(결측 ≠ 0).
DESC_NAMES = ["BETA", "HSIGMA", "DASTD", "CMRA", "RSTR", "STOM", "STOQ", "STOA", "LNCAP", "EPFWD", "CETOP", "ETOP", "EGRO", "SGRO", "YILD", "BTOP", "MLEV", "DTOA", "BLEV"]
assert BETA_WIN == CMRA_MONTHS * MONTH_DAYS
assert set(d for p in STYLE_DEF.values() for d, _ in p) == set(DESC_NAMES)


def RK(*parts):
    return ac.out("followup", ac.smoke_name("risk"), *parts)


def _save_npz(path, **arr):
    def w(p):
        with open(p, "wb") as fh:
            np.savez(fh, **arr)
    ac.write_atomic(path, w)


def _save_npy(path, arr):
    def w(p):
        with open(p, "wb") as fh:
            np.save(fh, arr)
    ac.write_atomic(path, w)


# ── 일별 패널 · 추정 유니버스 수익 ─────────────────────────────────────────────────────────────────────
class Daily:
    """일별 패널(로그 수익 · 로그 시총 · 로그 거래대금) — 예열 구간(1996~)까지 편 달력. cut 을 주면 그날 뒤의 행을 원천에서 자른다(자가 시험)."""

    def __init__(self, f, cut=None):
        g = ad.DailyGrid(f, ac.root() + "/.cache/rawdata_log.parquet", ["LogRet", "LogSize", "LogAmount"], ext_start=ab.EXT_START, cut=cut)
        self.f, self.g, self.cut = f, g, cut
        self.lr, self.ls, self.la = g.panel("LogRet"), g.panel("LogSize"), g.panel("LogAmount")
        self.T, self.N, self.offset = g.T, g.N, g.offset
        rf = np.fromfile(f.path + "/rf_daily.f32", dtype="<f4").astype(np.float64)           # 공통 틀 날짜의 일별 무위험 수익(단리)
        self.rf = np.concatenate([np.full(g.offset, rf[0]), rf])[: g.T]                      # 예열 구간에는 첫 값을 쓴다(2000년 전 값이 틀에 없다)
        self.lrf = np.log1p(self.rf)
        self.sig_sel, self.sig_rows = g.sig_sel, g.sig_rows
        self.mem = f.mem[g.sig_sel]


def estu_return(D):
    """추정 유니버스의 시총 가중 일별 초과수익 [T]. 그날의 구성 = 그날보다 앞선 마지막 신호일의 멤버(첫 신호 전 = 행이 있는 전 종목) · 비중 = 전날 시총.
    모형의 입력(베타 회귀의 설명변수 · 시장 팩터 점검의 기준)이지 성과 측정이 아니다 — 포트폴리오 성과는 R 측정기로 잰다(3부)."""
    out = np.full(D.T, np.nan)
    k = np.searchsorted(D.sig_rows, np.arange(D.T), side="left") - 1
    for t in range(1, D.T):
        w = D.ls[t - 1].astype(np.float64); r = D.lr[t].astype(np.float64)
        ok = np.isfinite(w) & np.isfinite(r)
        if k[t] >= 0:
            ok &= D.mem[k[t]]
        if ok.any():
            w = np.exp(w[ok])
            out[t] = np.dot(w, np.expm1(r[ok])) / w.sum() - D.rf[t]
    return out


# ── 지표(가격 · 거래) ────────────────────────────────────────────────────────────────────────────────
def desc_price(D, mkt, sel=None, progress=None):
    S, N = len(D.sig_rows), D.N
    out = {k: np.full((S, N), np.nan, F32) for k in ("BETA", "HSIGMA", "DASTD", "CMRA", "RSTR", "STOM", "STOQ", "STOA", "LNCAP")}
    wb = 0.5 ** (np.arange(BETA_WIN - 1, -1, -1) / BETA_HL)[:, None]                         # 오래된 날 → 최근(가중 1)
    wd = 0.5 ** (np.arange(BETA_WIN - 1, -1, -1) / DASTD_HL)[:, None]
    wr = 0.5 ** (np.arange(RSTR_WIN - 1, -1, -1) / RSTR_HL)[:, None]
    row = np.isfinite(D.ls)                                                                  # 그날 행이 있었나
    first = np.where(row.any(0), row.argmax(0), D.T)                                         # 첫 행의 위치(그 앞은 상장 전)
    with np.errstate(all="ignore"):                                                          # 일 회전율 = 거래대금 ÷ 시총(주식 수 회전율과 같은 비율) · 거래가 없던 날 = 0
        to = np.exp(D.la.astype(np.float64) - D.ls.astype(np.float64))
    to[~np.isfinite(to)] = 0.0
    C = np.cumsum(to, axis=0); del to
    Cn = np.cumsum(row, axis=0, dtype=np.int32)
    mk = np.nan_to_num(mkt)
    for i, r in enumerate(D.sig_rows):
        if sel is not None and i not in sel:
            continue
        out["LNCAP"][i] = D.ls[r]
        a = r - BETA_WIN + 1
        if a >= 1:                                                                           # 추정 유니버스 수익은 둘째 날부터 있다
            lr = D.lr[a:r + 1].astype(np.float64); ok = np.isfinite(lr)
            n = ok.sum(0)
            y = np.where(ok, np.expm1(lr) - D.rf[a:r + 1, None], 0.0)                        # 일별 초과수익(행이 없는 날은 가중 0)
            m = mk[a:r + 1, None]
            w = wb * ok; W = w.sum(0)
            with np.errstate(all="ignore"):
                mm, my = (w * m).sum(0) / W, (w * y).sum(0) / W
                vm = (w * m * m).sum(0) / W - mm ** 2
                cv = (w * m * y).sum(0) / W - mm * my
                b = cv / vm
                rs = (w * y * y).sum(0) / W - my ** 2 - b * cv                               # 잔차의 가중 분산
                good = (n >= MIN_FRAC * BETA_WIN) & (vm > 0)
                out["BETA"][i] = np.where(good, b, np.nan)
                out["HSIGMA"][i] = np.where(good, np.sqrt(np.maximum(rs, 0.0)), np.nan)
                w2 = wd * ok; W2 = w2.sum(0); mu = (w2 * y).sum(0) / W2
                out["DASTD"][i] = np.where(n >= MIN_FRAC * BETA_WIN, np.sqrt(np.maximum((w2 * y * y).sum(0) / W2 - mu ** 2, 0.0)), np.nan)
            # 누적 범위: 최근 T 개월(T = 1..12) 누적 초과 로그수익의 최대 − 최소. 원문 식 ln(1 + Zmax) − ln(1 + Zmin) 에서 Z 를 누적 단리 수익으로 읽은 것과 같다
            x = np.where(ok, lr - D.lrf[a:r + 1, None], 0.0)
            Z = np.cumsum(x.reshape(CMRA_MONTHS, MONTH_DAYS, N).sum(1)[::-1], axis=0)
            out["CMRA"][i] = np.where(n >= MIN_FRAC * BETA_WIN, Z.max(0) - Z.min(0), np.nan)
        b1 = r - RSTR_LAG; b0 = b1 - RSTR_WIN + 1
        if b0 >= 0:                                                                          # 상대 강도: 최근 21일을 뺀 504일의 초과 로그수익 지수 가중 합
            lr = D.lr[b0:b1 + 1].astype(np.float64); ok = np.isfinite(lr)
            x = np.where(ok, lr - D.lrf[b0:b1 + 1, None], 0.0)                               # 상장 뒤 행이 없는 날(정지) = 수익 0
            live = np.arange(b0, b1 + 1)[:, None] >= first[None, :]
            wl = (wr * live).sum(0)
            with np.errstate(all="ignore"):                                                  # 상장 전 날의 가중만큼 키운다(창이 덜 찬 종목의 합이 작게 나오지 않게)
                out["RSTR"][i] = np.where(live.sum(0) >= MIN_FRAC * RSTR_WIN, (wr * x).sum(0) * (wr.sum() / wl), np.nan)
        for nm, win, months in (("STOM", MONTH_DAYS, 1.0), ("STOQ", 3 * MONTH_DAYS, 3.0), ("STOA", 12 * MONTH_DAYS, 12.0)):
            if r - win >= 0:                                                                 # 회전율의 로그: 1개월 합 · 3개월의 월평균 · 12개월의 월평균
                s_, n_ = C[r] - C[r - win], Cn[r] - Cn[r - win]
                with np.errstate(all="ignore"):
                    out[nm][i] = np.where((n_ >= MIN_FRAC * win) & (s_ > 0), np.log(s_ / months), np.nan)
        if progress:
            progress(i + 1, S)
    return out


# ── 재무 · 컨센서스 ──────────────────────────────────────────────────────────────────────────────────
def fund_panel(f, sig_sel, cut=None, chunk=500, progress=None):
    """재무 값 dict[(항목, 분기 시차)] = [덮는 신호 × 종목].
    신호일마다 기준 항목(총자산)의 as-of 기간 Q(쓸 수 있는 첫날 <= 신호일인 마지막 기간 · 묵은 기간은 버림 — nlff_data 의 규칙)를 잡고,
    다른 항목은 같은 기간 Q(성장용 항목은 Q − 4 · 8 · 12 · 16 도)의 값을 기간 번호로 찾는다 — 항목마다 따로 as-of 를 잡으면 드물게 적히는 항목(사채 · 우선주)의 옛 값이 끌려온다.
    찾은 값의 쓸 수 있는 첫날이 신호일 뒤면 버린다."""
    import pandas as pd
    nd = ab._nlff()
    cfg = nd.load_cfg()
    me = f.sig_dates[sig_sel].astype(np.int64)
    trunc = None if cut is None else int(np.datetime64(cut, "D").astype(np.int64))
    path, stale = nd.p(cfg["paths"]["fund_q"]), int(cfg["staleness_months"]["q"])
    stale_a = int(cfg["staleness_months"]["a"])
    items = FUND_NOW + FUND_LAG
    keys = [(it, 0) for it in items + FUND_ASOF] + [(it, lg) for it in FUND_LAG for lg in GROWTH_LAGS if lg]
    out = {k: np.full((len(me), f.nt), np.nan, F32) for k in keys}
    q0 = 1990 * 4

    def qnum(days):
        d = days.astype("datetime64[D]")
        return (d.astype("datetime64[Y]").astype(np.int64) + 1970) * 4 + (d.astype("datetime64[M]").astype(np.int64) % 12) // 3 - q0

    tk = f.tickers
    for i in range(0, len(tk), chunk):
        part = tk[i:i + chunk]
        L = nd._read_long(path, part[0], part[-1], items + FUND_ASOF, trunc)
        L = L[L["Ticker"].isin(part)]
        nT = len(part)
        for it in FUND_ASOF:
            out[(it, 0)][:, i:i + nT] = nd.asof_dense(L[L["Item"] == it], part, [it], me, stale_a)[0][:, 0, :].T
        _, Pd, _ = nd.asof_dense(L[L["Item"] == ANCHOR], part, [ANCHOR], me, stale)          # [종목 × 1 × 신호] 기준 항목의 기간 말(일수 · 없으면 −1)
        Pd = Pd[:, 0, :]
        Q = np.where(Pd >= 0, qnum(np.where(Pd >= 0, Pd, 0)), -1)
        nQ = int(max(Q.max(), 0)) + 1
        A = np.full((nT, len(items), nQ), np.nan, F32)
        FD = np.full((nT, len(items), nQ), np.iinfo(np.int32).max, np.int32)
        L = L[L["Item"].isin(items)]                                                         # 아래는 같은 기간 맞춤으로 읽는 항목만
        if len(L):
            ti = pd.Categorical(L["Ticker"], categories=part).codes.astype(np.int64)
            ii = pd.Categorical(L["Item"], categories=items).codes.astype(np.int64)
            qq, v, fd = qnum(L["pd"].to_numpy()), L["v"].to_numpy(), L["fd"].to_numpy()
            ok = (ti >= 0) & (ii >= 0) & (qq >= 0) & (qq < nQ) & np.isfinite(v)
            A[ti[ok], ii[ok], qq[ok]] = v[ok].astype(F32)
            FD[ti[ok], ii[ok], qq[ok]] = fd[ok].astype(np.int32)
        for (it, lg), dst in out.items():
            if it in FUND_ASOF:
                continue
            k = items.index(it)
            ql = np.clip(Q - lg, 0, nQ - 1)
            good = (Q >= 0) & (Q - lg >= 0) & (np.take_along_axis(FD[:, k, :], ql, axis=1) <= me[None, :])
            dst[:, i:i + nT] = np.where(good, np.take_along_axis(A[:, k, :], ql, axis=1), np.nan).T
        if progress:
            progress(min(i + chunk, len(tk)), len(tk))
    return out


def cons_asof(D, name):
    """컨센서스 항목의 신호일 전날까지의 마지막 값 [덮는 신호 × 종목](MAX_AGE_CONS 거래일보다 오래되면 버림 — 1단계 컨센서스 묶음과 같은 규칙)."""
    q = ad.DailyGrid(D.f, ac.root() + "/.cache/consensus/%s.parquet" % name, [name], cut=D.cut, base_dates=D.g.dates)
    return np.asarray(last_valid(q.panel(name), ad.lag_rows(D.sig_rows, 1), max_age=MAX_AGE_CONS), dtype=np.float64)


def desc_fund(D, FP, eps1, bps1):
    cap = np.exp(D.ls[D.sig_rows].astype(np.float64))                                        # 신호일 시가총액(원 — 재무 원계정과 같은 단위)

    def g(it, lg=0):
        return FP[(it, lg)].astype(np.float64)

    def z0(x):
        return np.where(np.isfinite(x), x, 0.0)

    ta = g(ANCHOR)
    has = np.isfinite(ta)
    pe = z0(g("PreferredCapital"))                                                           # 우선주(자본금 — 장부 기준)
    be = g("EquityParent") - pe                                                              # 보통주 자본
    ibd = g("InterestBearingDebt")
    ld = np.where(np.isfinite(ibd), np.maximum(ibd - z0(g("CurrentBorr")) - z0(g("CurrentBonds")), 0.0),      # 장기부채 = 이자부부채 − 단기차입금 − 유동성 사채
                  z0(g("LongTermBorr")) + z0(g("Bonds")) + z0(g("ConvBonds")) + z0(g("ExchBonds")) + z0(g("BondsWithWarrants")))   # 이자부부채가 없으면 장기차입금 + 사채류
    k = (np.arange(len(GROWTH_LAGS)) - (len(GROWTH_LAGS) - 1) / 2.0)[:, None, None]

    def growth(y):                                                                           # 연간 다섯 점을 시간에 회귀한 기울기 ÷ 절댓값 평균(다섯 점이 다 있어야 한다)
        with np.errstate(all="ignore"):
            den = np.abs(y).mean(0)
            return np.where(den > 0, (k * y).sum(0) / (k ** 2).sum() / den, np.nan)

    with np.errstate(all="ignore"):
        sh = np.stack([g("SharesCommonAvgAdj", lg) for lg in GROWTH_LAGS])
        btop = np.where(has & (cap > 0), be / cap, np.nan)
        out = {"ETOP": g("NetIncomeParent") / cap, "CETOP": g("CashEarnings") / cap,
               "YILD": g("CashDivTotal") / cap,                                              # 최근 12개월 현금배당 ÷ 시총(무배당 = 0 행 · 행이 없으면 결측)
               "BTOP": btop,
               "EPFWD": np.where((bps1 > 0) & (be > 0), eps1 / bps1 * btop, np.nan),         # 예상 ROE × 장부가/시가
               "MLEV": np.where(has, (cap + pe + ld) / cap, np.nan),
               "DTOA": np.where(ta > 0, (ld + g("CurrentLiab")) / ta, np.nan),
               "BLEV": np.where(be > 0, (be + pe + ld) / be, np.nan),
               "EGRO": growth(np.stack([g("EPSParentAdj", lg) for lg in GROWTH_LAGS])),
               "SGRO": growth(np.stack([g("Revenue", lg) for lg in GROWTH_LAGS]) / np.where(sh > 0, sh, np.nan))}
    return {k_: np.where(np.isfinite(v), v, np.nan).astype(F32) for k_, v in out.items()}


def build_desc(f, cut=None, sel=None, unit=None):
    """지표 전부 dict[name] = [덮는 신호 × 종목] + 일별 패널 · 추정 유니버스 수익. sel = 계산할 신호 번호(자가 시험)."""
    t0 = time.perf_counter()
    D = Daily(f, cut)
    mkt = estu_return(D)
    ac.log("일별 패널 %d일 × %d종목 · 추정 유니버스 수익 — %.0f초", D.T, D.N, time.perf_counter() - t0)
    desc = desc_price(D, mkt, sel, (lambda a, b: unit(0, a, b)) if unit else None)
    ac.log("가격 · 거래 지표 — %.0f초", time.perf_counter() - t0)
    FP = fund_panel(f, D.sig_sel, cut, progress=(lambda a, b: unit(1, a, b)) if unit else None)
    desc.update(desc_fund(D, FP, cons_asof(D, "eps_1y"), cons_asof(D, "bps_1y")))
    ac.log("재무 · 컨센서스 지표 — %.0f초", time.perf_counter() - t0)
    return D, mkt, desc


# ── 노출 ─────────────────────────────────────────────────────────────────────────────────────────────
def standardize(x, est, cap):
    """평균 = 추정 유니버스의 시총 가중 · 표준편차 = 추정 유니버스의 동일가중. 종목이 모자라면 전부 결측."""
    ok = est & np.isfinite(x)
    if ok.sum() < MIN_EST:
        return np.full(x.shape, np.nan)
    sd = x[ok].std(ddof=1)
    if not sd > 0:
        return np.full(x.shape, np.nan)
    return (x - np.dot(cap[ok], x[ok]) / cap[ok].sum()) / sd


def clean_z(x, est, cap):
    """지표 표준화: 자료 오류(OUT_SD 밖) 버림 → 3 표준편차로 절단 → 다시 표준화."""
    z = standardize(x, est, cap)
    z[np.abs(z) > OUT_SD] = np.nan
    return standardize(np.clip(standardize(z, est, cap), -CLIP_SD, CLIP_SD), est, cap)


def wls(y, X, v, fit):
    """가중 v 의 최소제곱(fit 종목으로 추정). 종목이 없는 업종의 열은 최소 노름 해가 0 을 준다."""
    sv = np.sqrt(v[fit])
    return np.linalg.lstsq(X[fit] * sv[:, None], y[fit] * sv, rcond=None)[0]


def build_expo(desc, sector, mem, n_sec, sel=None, unit=None):
    """스타일 노출 [신호 × 종목 × 스타일] · 추정 유니버스 [신호 × 종목] · 채운 종목 수 [신호 × 스타일](추정 유니버스 안).
    그 달에 값이 있는 추정 유니버스 종목이 MIN_EST 에 못 미치는 스타일은 그 달 전부 결측으로 둔다(재무 자료가 시작되기 전 · 배당 자료가 빈 달) — 회귀에서 그 달만 빠진다."""
    S, N = mem.shape
    X = np.full((S, N, len(STYLES)), np.nan, F32)
    EST = np.zeros((S, N), bool)
    filled = np.zeros((S, len(STYLES)), np.int32)
    one = np.ones(N)
    for i in range(S):
        if sel is not None and i not in sel:
            continue
        lncap = desc["LNCAP"][i].astype(np.float64)
        sec = sector[i]
        cover = np.isfinite(lncap) & (sec >= 0)                                              # 노출을 매기는 종목(그날 행과 업종이 있다)
        est = mem[i] & cover
        if est.sum() < MIN_EST:
            continue
        EST[i] = est
        cap = np.where(np.isfinite(lncap), np.exp(lncap), 0.0)
        v = np.sqrt(cap)                                                                     # 회귀 가중 = 시총의 제곱근
        fac = {}
        for name, parts in STYLE_DEF.items():                                                # 지표 표준화 → 있는 지표끼리 가중 평균 → 다시 표준화
            zs = np.stack([clean_z(desc[d][i].astype(np.float64), est, cap) for d, _ in parts])
            ws = np.array([w for _, w in parts])[:, None] * np.isfinite(zs)
            den = ws.sum(0)
            with np.errstate(all="ignore"):
                fac[name] = standardize(np.where(den > 0, (np.nan_to_num(zs) * ws).sum(0) / den, np.nan), est, cap)
        Dm = np.zeros((N, n_sec))
        ci = np.nonzero(cover)[0]
        Dm[ci, sec[ci].astype(np.int64)] = 1.0
        Z = np.column_stack([Dm, np.nan_to_num(fac["SIZE"])])
        for j, name in enumerate(STYLE_DEF):                                                 # 결측 채우기: 업종 더미 + 규모에 회귀(추정 유니버스의 값 있는 종목 · √시총 가중)
            x = fac[name]
            miss = cover & ~np.isfinite(x)
            fit = est & np.isfinite(x)
            if fit.sum() < MIN_EST:                                                          # 그 달에 이 스타일이 없다
                fac[name] = np.full(N, np.nan)
                continue
            if name != "SIZE" and miss.any():
                x = x.copy()
                x[miss] = Z[miss] @ wls(x, Z, v, fit)
                filled[i, j] = int((miss & est).sum())
                fac[name] = standardize(x, est, cap)
        for name, base in ORTH.items():                                                      # 직교화: 절편 + 기준 노출에 회귀한 잔차
            if not (np.isfinite(fac[name][est]).any() and np.isfinite(fac[base][est]).any()):
                fac[name] = np.full(N, np.nan)
                continue
            Xb = np.column_stack([one, np.nan_to_num(fac[base])])
            fac[name] = standardize(fac[name] - Xb @ wls(np.nan_to_num(fac[name]), Xb, v, est), est, cap)
        for name, base in CUBE.items():                                                      # 비선형: 세제곱 → 원래 노출에 직교화 → 절단 → 표준화
            if not np.isfinite(fac[base][est]).any():
                fac[name] = np.full(N, np.nan)
                continue
            Xb = np.column_stack([one, np.nan_to_num(fac[base])])
            y = fac[base] ** 3
            r_ = standardize(y - Xb @ wls(np.nan_to_num(y), Xb, v, est), est, cap)
            fac[name] = standardize(np.clip(r_, -CLIP_SD, CLIP_SD), est, cap)
        for j, name in enumerate(STYLES):
            X[i, :, j] = np.where(cover, fac[name], np.nan)
        if unit:
            unit(2, i + 1, S)
    return X, EST, filled


# ── 횡단면 회귀 ──────────────────────────────────────────────────────────────────────────────────────
def design(Xi, sec_i, est_i, cap_i, n_sec):
    """한 달의 설계 — 추정 유니버스 종목의 [시장 | 업종 더미(종목이 있는 업종만) | 스타일] 과 제약 변환 R.
    제약: 업종 팩터 수익의 시총 가중 합 = 0 → 마지막 업종의 수익을 나머지로 푼다(f_J = −Σ (w_i ÷ w_J) f_i). 전체 팩터 = R × 줄인 팩터."""
    ks = np.nonzero(np.isfinite(Xi[est_i]).any(0))[0]                                         # 그 달에 값이 있는 스타일
    idx = np.nonzero(est_i & np.isfinite(Xi[:, ks]).all(1))[0]
    sec = sec_i[idx].astype(np.int64)
    present = np.unique(sec)
    K, J = len(ks), len(present)
    A = np.column_stack([np.ones(len(idx)), (sec[:, None] == present[None, :]).astype(np.float64), Xi[idx][:, ks].astype(np.float64)])
    cols = np.r_[0, 1 + present, 1 + n_sec + ks]                                              # 전체 팩터 순서(시장 · 업종 26 · 스타일) 안의 열 번호
    wi = np.array([cap_i[idx][sec == s].sum() for s in present])
    wi = wi / wi.sum()
    R = np.zeros((1 + J + K, J + K))
    R[0, 0] = 1.0
    for a in range(J - 1):
        R[1 + a, 1 + a] = 1.0
        R[J, 1 + a] = -wi[a] / wi[J - 1]
    R[1 + J + np.arange(K), J + np.arange(K)] = 1.0
    return idx, A, cols, R, wi, ks


def creg(y, A, R, v, want_t=True):
    """제약 가중 최소제곱. 돌려주는 것: 팩터 수익(전체) · 잔차 · t 값 · R²(USE4 의 정의 = 1 − Σ v u² ÷ Σ v r²)."""
    sv = np.sqrt(v)
    Ar = (A @ R) * sv[:, None]
    G = Ar.T @ Ar
    try:
        gam = np.linalg.solve(G, Ar.T @ (y * sv))
        Gi = np.linalg.inv(G) if want_t else None
    except np.linalg.LinAlgError:                                                            # 그날 수익이 있는 종목이 없는 업종 등 — 최소 노름 해
        gam = np.linalg.lstsq(Ar, y * sv, rcond=None)[0]
        Gi = np.linalg.pinv(G) if want_t else None
    fr = R @ gam
    u = y - A @ fr
    sse = float((v * u * u).sum())
    t = None
    if want_t:
        s2 = sse / max(len(y) - Ar.shape[1], 1)                                              # 고유수익 분산이 1 ÷ v 에 비례한다는 가정(회귀 가중의 근거)
        with np.errstate(all="ignore"):
            t = fr / np.sqrt(np.maximum(np.einsum("ij,jk,ik->i", R, Gi, R) * s2, 0.0))
    return fr, u, t, 1.0 - sse / float((v * y * y).sum())


def run_reg(f, D, X, EST, sector, n_sec, sel=None, unit=None):
    """월간 · 일간 횡단면 회귀. 노출과 추정 유니버스는 신호일 i 의 것을 그 보유월(틀의 hold_a ~ hold_b) 내내 쓴다."""
    S, N, K = X.shape
    P = 1 + n_sec + K
    fwd = np.asarray(f.fwd(1))
    rf = D.rf[D.offset:]                                                                     # 공통 틀 날짜의 일별 무위험 수익
    nd = len(rf)
    FM = np.full((S, P), np.nan); TM = np.full((S, P), np.nan); R2M = np.full(S, np.nan); NM = np.zeros(S, np.int32)
    FDY = np.full((nd, P), np.nan); R2D = np.full(nd, np.nan); NDY = np.zeros(nd, np.int32)
    SPEC = np.full((nd, N), np.nan, F32)
    WIND = np.full((S, n_sec), np.nan)                                                       # 업종의 시총 비중(제약 점검용)
    for i in range(S):
        s = int(D.sig_sel[i])
        if (sel is not None and i not in sel) or not EST[i].any():
            continue
        cap = np.exp(D.ls[D.sig_rows[i]].astype(np.float64))
        idx, A, cols, R, wi, _ = design(X[i], sector[i], EST[i], cap, n_sec)
        if len(idx) < MIN_EST:
            continue
        v = np.sqrt(cap[idx])
        WIND[i, cols[1:1 + len(wi)] - 1] = wi
        a, b = int(f.hold_a[s]), min(int(f.hold_b[s]), nd - 1)
        if f.hold_ok[s]:                                                                     # 월간: 보유월 수익 − 그 달의 무위험 수익
            y = fwd[s, idx].astype(np.float64) - np.expm1(D.lrf[a + D.offset:b + 1 + D.offset].sum())   # 그 달의 무위험 수익(회귀의 종속변수에서 빼는 값 — 성과 수익의 합성이 아니다)
            ok = np.isfinite(y)
            if ok.sum() >= MIN_EST:
                fr, _, t, r2 = creg(y[ok], A[ok], R, v[ok])
                FM[i, cols], TM[i, cols], R2M[i], NM[i] = fr, t, r2, int(ok.sum())
        for d in range(a, b + 1):                                                            # 일간: 그날 행이 있는 종목만
            y = np.expm1(D.lr[d + D.offset, idx].astype(np.float64)) - rf[d]
            ok = np.isfinite(y)
            if ok.sum() >= MIN_EST:
                fr, u, _, r2 = creg(y[ok], A[ok], R, v[ok], want_t=False)
                FDY[d, cols], R2D[d], NDY[d] = fr, r2, int(ok.sum())
                SPEC[d, idx[ok]] = u.astype(F32)
        if unit:
            unit(3, i + 1, S)
    return {"fm": FM, "tm": TM, "r2m": R2M, "nm": NM, "fd": FDY, "r2d": R2D, "ndy": NDY, "wind": WIND}, SPEC


# ── 팩터 통계표 ──────────────────────────────────────────────────────────────────────────────────────
def wcorr(x, y, v):
    v = v / v.sum()
    mx, my = np.dot(v, x), np.dot(v, y)
    return np.dot(v, (x - mx) * (y - my)) / np.sqrt(np.dot(v, (x - mx) ** 2) * np.dot(v, (y - my) ** 2))


def expo_stats(D, X, EST, sector, n_sec, months):
    """노출 안정 계수(이번 달과 다음 달 노출의 √시총 가중 횡단면 상관) · 분산팽창계수(다른 팩터 전부에 회귀) — months 의 평균."""
    S, K = X.shape[0], X.shape[2]
    stab = np.full((len(months), K), np.nan)
    vif = np.full((len(months), K), np.nan)
    for a, i in enumerate(months):
        cap = np.exp(D.ls[D.sig_rows[i]].astype(np.float64))
        if i + 1 < S and EST[i + 1].any():
            for j in range(K):
                both = EST[i] & EST[i + 1] & np.isfinite(X[i, :, j]) & np.isfinite(X[i + 1, :, j])
                if both.sum() >= MIN_EST:
                    stab[a, j] = wcorr(X[i, both, j].astype(np.float64), X[i + 1, both, j].astype(np.float64), np.sqrt(cap[both]))
        idx, A, _, _, _, ks = design(X[i], sector[i], EST[i], cap, n_sec)
        if len(idx) >= MIN_EST:
            v = np.sqrt(cap[idx]); sv = np.sqrt(v)
            for c, j in enumerate(ks):
                col = A.shape[1] - len(ks) + c
                Z = np.delete(A[:, 1:], col - 1, axis=1)                                     # 시장 열은 업종 더미의 합이라 뺀다
                y = A[:, col]
                e = y - Z @ np.linalg.lstsq(Z * sv[:, None], y * sv, rcond=None)[0]
                vif[a, j] = 1.0 / max(np.dot(v, e * e) / np.dot(v, (y - np.dot(v, y) / v.sum()) ** 2), 1e-12)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        return np.nanmean(stab, axis=0), np.nanmean(vif, axis=0)


def factor_table(f, D, mkt, reg, X, EST, sector, sec_names, is_end):
    """표본 안(보유월이 is_end 안에서 끝난 달 · 그날까지의 일별 값)의 팩터 통계 — 행 = 시장 · 업종 평균 · 스타일 12."""
    n_sec, K = len(sec_names), X.shape[2]
    sg = D.sig_sel
    ok_m = np.isfinite(reg["r2m"]) & (f.dates[np.minimum(f.hold_b[sg], f.nd - 1)] <= is_end)
    ok_d = np.isfinite(reg["r2d"]) & (f.dates <= is_end)
    months = np.nonzero(ok_m)[0]
    stab, vif = expo_stats(D, X, EST, sector, n_sec, months)
    me = mkt[D.offset:][ok_d]
    names = ["시장"] + list(sec_names) + [STYLE_KO[s] for s in STYLES]
    rows = []
    for p, nm in enumerate(names):
        t = reg["tm"][ok_m, p]; t = t[np.isfinite(t)]
        fd = reg["fd"][ok_d, p]; g = np.isfinite(fd)
        if not len(t) or g.sum() < 60:
            continue
        ret, vol = fd[g].mean() * 252.0, fd[g].std(ddof=1) * np.sqrt(252.0)
        j = p - 1 - n_sec
        rows.append({"factor": nm, "kind": "시장" if p == 0 else ("업종" if p <= n_sec else "스타일"), "months": len(t),
                     "abs_t_mean": float(np.abs(t).mean()), "abs_t_gt2": float((np.abs(t) > 2).mean()), "ann_ret": float(ret), "ann_vol": float(vol),
                     "sharpe": float(ret / vol) if vol > 0 else np.nan, "corr_estu": float(np.corrcoef(fd[g], me[g])[0, 1]),
                     "stability": float(stab[j]) if j >= 0 else np.nan, "vif": float(vif[j]) if j >= 0 else np.nan})
    return rows, {"months": int(ok_m.sum()), "days": int(ok_d.sum()), "r2_month_mean": float(np.nanmean(reg["r2m"][ok_m])), "r2_day_mean": float(np.nanmean(reg["r2d"][ok_d])),
                  "n_month_mean": float(reg["nm"][ok_m].mean())}


# ── 점검 ─────────────────────────────────────────────────────────────────────────────────────────────
def checks(f, D, mkt, reg, X, EST):
    """구현 점검(전 기간 — 성과가 아니라 식의 성질): 표준화 · 직교 · 시장 팩터와 추정 유니버스 수익 · 업종 제약."""
    S, N, K = X.shape
    mean_dev = sd_dev = 0.0
    orth = {k: 0.0 for k in list(ORTH) + list(CUBE)}
    for i in range(S):
        est = EST[i]
        if not est.any():
            continue
        cap = np.exp(D.ls[D.sig_rows[i]].astype(np.float64))
        v = np.sqrt(cap[est])
        x = X[i, est].astype(np.float64)
        for j, nm in enumerate(STYLES):
            ok = np.isfinite(x[:, j])
            if ok.sum() < MIN_EST:
                continue
            w = cap[est][ok] / cap[est][ok].sum()
            mean_dev = max(mean_dev, abs(float(w @ x[ok, j])))
            sd_dev = max(sd_dev, abs(float(x[ok, j].std(ddof=1) - 1.0)))
            base = {**ORTH, **CUBE}.get(nm)
            if base and np.isfinite(x[:, STYLES.index(base)]).all():
                orth[nm] = max(orth[nm], abs(float(wcorr(x[ok, j], x[ok, STYLES.index(base)], v[ok]))))
    fd0 = reg["fd"][:, 0]; me = mkt[D.offset:]
    g = np.isfinite(fd0) & np.isfinite(me)
    n_sec = reg["wind"].shape[1]
    worst = 0.0
    for i in range(S):
        if np.isfinite(reg["wind"][i]).any() and np.isfinite(reg["fm"][i, 0]):
            worst = max(worst, abs(float(np.nansum(reg["wind"][i] * reg["fm"][i, 1:1 + n_sec]))))
    return {"standardize_capw_mean_max_abs": mean_dev, "standardize_eq_sd_max_dev": sd_dev, "orth_max_abs_corr": orth,
            "market_vs_estu_corr_daily": float(np.corrcoef(fd0[g], me[g])[0, 1]), "market_minus_estu_daily_sd": float((fd0[g] - me[g]).std()),
            "industry_constraint_max_abs_monthly": worst, "days": int(g.sum())}


def truncation_check(f, desc, X, sector, n_sec, at):
    """자료를 신호일에서 자르고 다시 만든 지표 · 노출이 온 자료로 만든 것과 같은가(신호 번호 at 들에서)."""
    res = []
    for i in at:
        cut = str(f.sig_dates[i])
        D2, _, d2 = build_desc(f, cut=cut, sel={i})
        dd = max(float(np.nanmax(np.abs(d2[k][i].astype(np.float64) - desc[k][i].astype(np.float64)))) if np.isfinite(d2[k][i]).any() else 0.0 for k in DESC_NAMES)
        nan_same = all(np.array_equal(np.isfinite(d2[k][i]), np.isfinite(desc[k][i])) for k in DESC_NAMES)
        X2, _, _ = build_expo(d2, sector[D2.sig_sel], D2.mem, n_sec, sel={i})
        xd = float(np.nanmax(np.abs(X2[i].astype(np.float64) - X[i].astype(np.float64))))
        res.append({"signal": cut, "desc_max_abs_diff": dd, "desc_missing_same": bool(nan_same), "expo_max_abs_diff": xd,
                    "expo_missing_same": bool(np.array_equal(np.isfinite(X2[i]), np.isfinite(X[i])))})
        ac.log("자르기 시험 %s — 지표 차이 %.3g · 노출 차이 %.3g · 결측 자리 같음 %s", cut, dd, xd, nan_same)
        del D2
    return res


# ── 실행 ─────────────────────────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--check", action="store_true", help="자르기 시험(세 신호일)을 함께 돌린다")
    ap.add_argument("--smoke", action="store_true", help="신호 24개(2015~2016)만 · 상태 파일을 건드리지 않고 risk_smoke 폴더에 쓴다")
    a = ap.parse_args()
    ac.SMOKE["on"] = a.smoke
    if not a.smoke and ac.track() != "followup":                                             # 2단계 줄이 아니면 1단계의 상태 파일에 이 단계를 적게 된다
        raise RuntimeError("[aif] 2단계 줄로만 띄운다 — ops/aif_run.py --track followup 또는 AIF_TRACK=followup")
    ac.low_priority()
    f = ac.Frame()
    meta_p = RK("meta.json")
    tag = {"version": VERSION, "rawdata_tag": f.meta.get("rawdata_tag"), "n_signals": f.ns}
    if not a.force and not a.check and (ac.read_json(meta_p) or {}).get("tag") == tag:
        ac.log("위험 모형 1부 — 저장분이 같은 판이다(건너뜀 · 다시 만들려면 --force)")
        return 0
    os.makedirs(RK(), exist_ok=True)
    sector = np.load(f.path + "/sector.npy")
    sec_names = ac.read_json(f.path + "/sector.json")["names"]
    n_sec = len(sec_names)
    sel = set(range(180, 204)) if a.smoke else None
    parts = [("가격 · 거래 지표", 0.00, 0.25), ("재무 · 컨센서스 지표", 0.25, 0.40), ("노출", 0.40, 0.60), ("횡단면 회귀", 0.60, 0.95)]

    def unit(k, done, total):                                                                # 부분 k 의 진행을 단계 진행률로 옮긴다
        if done == total or done % 20 == 0:
            nm, lo, hi = parts[k]
            ac.stage_unit(int(round(100 * (lo + (hi - lo) * done / total))), "%s %d / %d" % (nm, done, total))

    ac.stage_begin(STAGE, 100, "진행(%)", 0.0, PART_TO)
    t0 = time.perf_counter()
    D, mkt, desc = build_desc(f, sel=sel, unit=unit)
    X, EST, filled = build_expo(desc, sector[D.sig_sel], D.mem, n_sec, sel=sel, unit=unit)
    ac.log("노출 — %.0f초 · 추정 유니버스 평균 %.0f종목", time.perf_counter() - t0, EST[EST.any(1)].sum(1).mean())
    reg, SPEC = run_reg(f, D, X, EST, sector[D.sig_sel], n_sec, sel=sel, unit=unit)
    ac.log("횡단면 회귀 — %.0f초 · 월간 %d달 · 일간 %d일", time.perf_counter() - t0, int(np.isfinite(reg["r2m"]).sum()), int(np.isfinite(reg["r2d"]).sum()))
    _save_npz(RK("desc.npz"), names=np.array(DESC_NAMES), D=np.stack([desc[k] for k in DESC_NAMES], axis=2))
    _save_npz(RK("expo.npz"), styles=np.array(STYLES), X=X, EST=EST, filled=filled)
    _save_npz(RK("reg.npz"), factors=np.array(["MARKET"] + ["IND_%02d" % k for k in range(n_sec)] + STYLES), estu_excess=mkt[D.offset:], **reg)
    _save_npy(RK("spec_daily.npy"), SPEC)
    is_end = np.datetime64(ac.cfg()["measure"]["is_end"], "D")
    rows, ov = factor_table(f, D, mkt, reg, X, EST, sector[D.sig_sel], sec_names, is_end)
    chk = checks(f, D, mkt, reg, X, EST)
    cover = {d: float(np.mean([np.isfinite(desc[d][i][EST[i]]).mean() for i in range(len(EST)) if EST[i].any()])) for d in DESC_NAMES}
    fill = {s: float(np.mean([filled[i, j] / max(EST[i].sum(), 1) for i in range(len(EST)) if EST[i].any()])) for j, s in enumerate(STYLES)}
    if a.check:
        chk["truncation"] = truncation_check(f, desc, X, sector, n_sec, sorted(sel)[::10] if sel else [60, 180, 300])
    rdir = ac.results("followup", ac.smoke_name("risk"))
    os.makedirs(rdir, exist_ok=True)

    def wcsv(p):
        with open(p, "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
    ac.write_atomic(rdir + "/factor_stats_is.csv", wcsv)
    ac.write_json({"at": ac._now(), "is_end": str(is_end), "overall_is": ov, "checks": chk, "descriptor_cover_in_estu": cover, "filled_share_in_estu": fill}, rdir + "/checks.json")
    st = [r for r in rows if r["kind"] == "스타일"]
    mk_ = rows[0]
    lines = ["지표 19개 → 스타일 노출 12개 → 월간 %d달 · 일간 %s일의 횡단면 회귀를 돌렸습니다(추정 유니버스 달 평균 %.0f종목 · 표본 안 통계)" % (ov["months"], format(ov["days"], ","), ov["n_month_mean"]),
             "월간 회귀의 설명력(R²) 평균 %.1f%% · 시장 팩터의 평균 |t| %.1f · 시장 팩터와 추정 유니버스 수익의 일간 상관 %.4f" % (100 * ov["r2_month_mean"], mk_["abs_t_mean"], chk["market_vs_estu_corr_daily"]),
             "스타일 12개 — 평균 |t| %.2f · |t|>2 인 달 %.0f%% · 노출 안정 계수 %.2f · 분산팽창계수 %.1f" % (np.mean([r["abs_t_mean"] for r in st]), 100 * np.mean([r["abs_t_gt2"] for r in st]),
                                                                              np.mean([r["stability"] for r in st]), np.mean([r["vif"] for r in st])),
             "평균 |t| 가 큰 스타일 — " + " · ".join("%s %.1f" % (r["factor"], r["abs_t_mean"]) for r in sorted(st, key=lambda r: -r["abs_t_mean"])[:4]),
             "평균 |t| 가 작은 스타일 — " + " · ".join("%s %.1f" % (r["factor"], r["abs_t_mean"]) for r in sorted(st, key=lambda r: r["abs_t_mean"])[:3]),
             "구현 점검 — 표준화 어긋남 %.1e · 업종 제약 어긋남 %.1e%s" % (max(chk["standardize_capw_mean_max_abs"], chk["standardize_eq_sd_max_dev"]), chk["industry_constraint_max_abs_monthly"],
                                                          (" · 자르기 시험 차이 %.1e" % max(max(t["desc_max_abs_diff"], t["expo_max_abs_diff"]) for t in chk["truncation"])) if a.check else "")]
    ac.write_json({"at": ac._now(), "title": "위험 평가 모형 1부 — 지표 · 노출 · 횡단면 회귀", "lines": lines, "charts": [], "chart_names": []}, ac.out("followup", ac.smoke_name("stage_summary_nl_risk") + ".json"))
    ac.write_json({"tag": tag, "at": ac._now(), "styles": STYLES, "descriptors": DESC_NAMES, "seconds": round(time.perf_counter() - t0, 1)}, meta_p)
    for ln in lines:
        ac.log("%s", ln)
    ac.stage_unit(100, "1부 끝")
    if not a.smoke:                                                                          # 이 줄에 도는 작업이 없음을 알린다 — '실행 중'으로 남으면 1단계의 주기 통이 2단계 통을 기다리며 쉰다
        ac.status_set(stage_state="done", detail="1부 끝 — 다음 작업 대기")
    return 0


if __name__ == "__main__":
    sys.exit(main())
