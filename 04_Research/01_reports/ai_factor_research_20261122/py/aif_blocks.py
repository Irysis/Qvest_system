"""aif_blocks.py — 단말 묶음별 적재기. 원자료를 '월말 신호일 t 에 알 수 있는 종목별 값'으로 바꾼다.

가용 규칙(신호일 t = 월말 거래일 · t 종가에 매매한다고 본다):
  price  가격 · 거래   t 종가까지(로그 캐시 — 수정주가 수준 · 수정 거래량 수준은 쓰지 않는다)
  flow   투자자 수급   t−1 까지(수급은 장 마감 뒤에 확정된다)
  macro  거시 민감도   해외 · 금리 · 환율 = 인프라 가용 시점 규칙(fred_availability)으로 't 종가에 알 수 있는 값'만 · 국내 지수 = t 종가
  fund   재무          Factor_Date <= t 인 마지막 행(같은 연구 줄기의 nlff_data.build_chunk 를 그대로 쓴다 · 묵은 값 15/24개월)
  val    가치 비율     재무(위 규칙) ÷ t 의 시가총액 · 기업가치
  cons   컨센서스      t−1 까지의 마지막 값(20거래일보다 오래되면 버림) · 주당 추정치는 서로의 비율로만 쓴다(주가 수준과 섞지 않는다)
  cat    범주          t 의 시장 구분 · 지수 편입 · 업종(업종은 그룹 연산의 열쇠로 따로 저장)
모든 묶음 함수는 (이름 목록, 값 [덮는 신호 × 종목 × 특성], 메타)를 돌려준다. cut 을 준 문맥은 그 날짜 뒤의 원천 행을 읽지 않는다.
"""
import os
import sys

import numpy as np

import aif_common as ac
import aif_daily as ad
from aif_roll import Cum, cross, window_max, last_valid

F32 = np.float32
EXT_START = "1996-01-01"          # 예열 구간 시작 — 가장 긴 창(750거래일)이 2000-01 신호에서 찰 만큼 앞에서 읽는다


def _mo(w, frac=0.8):
    return int(np.ceil(frac * w))


def _div(a, b):
    with np.errstate(invalid="ignore", divide="ignore"):
        o = np.asarray(a, dtype=np.float64) / np.asarray(b, dtype=np.float64)
    return np.where(np.isfinite(o), o, np.nan).astype(F32)


def _pos(x):
    return np.where(np.asarray(x) > 0, x, np.nan)


class Ctx:
    """묶음들이 함께 쓰는 문맥 — 공통 틀 · 자르는 날짜 · 가격 패널(한 번 읽어 재사용)."""

    def __init__(self, frame, cut=None):
        self.f, self.cut, self.root = frame, cut, ac.root()
        self._price = None
        self._fund_cache = {}

    def path(self, rel):
        return self.root + "/" + rel

    def price(self):
        if self._price is None:
            import warnings
            cols = ["LogRet", "LogBMRet", "LogSize", "LogAmount", "LogHL", "LogCO", "LogGap"]
            g = ad.DailyGrid(self.f, self.path(".cache/rawdata_log.parquet"), cols, ext_start=EXT_START, cut=self.cut)
            P = {c: g.panel(c) for c in cols}
            with np.errstate(all="ignore"), warnings.catch_warnings():
                warnings.simplefilter("ignore", RuntimeWarning)
                P["mkt"] = np.nanmax(P["LogBMRet"], axis=1).astype(np.float64)          # 그날 KOSPI200 로그 수익(모든 종목에 같은 값)
            del P["LogBMRet"]
            # 유동시총은 원자료에서 직접 만든다 — 로그 캐시의 LogFloatCap 은 2026-03-30 이후 행이 전부 비어 있다(원자료 Float 은 있음 · 11-23 확인)
            gf = ad.DailyGrid(self.f, self.path(".cache/RAWDATA.parquet"), ["Float"], cut=self.cut, base_dates=g.dates)
            fl = gf.panel("Float", dtype=np.float64)
            del gf
            with np.errstate(all="ignore"):
                P["LogFloatCap"] = (P["LogSize"].astype(np.float64) + np.log(np.where(fl > 0, fl, np.nan) / 100.0)).astype(F32)   # log(시총 × 유동비율 % ÷ 100)
            del fl
            self._price = (g, P)
        return self._price

    def cap_at_signal(self):
        """신호일의 시가총액(원) [덮는 신호 × 종목] — 그날 값이라 t 에 알 수 있다."""
        g, P = self.price()
        return np.exp(P["LogSize"][g.sig_rows].astype(np.float64))

    def fund_asof(self, items, annual=False):
        """재무 항목의 신호일 as-of 값 dict[item] = [덮는 신호 × 종목](Factor_Date <= t · 묵은 값 버림). nlff_data 의 규칙 그대로."""
        nd = _nlff()
        cfg = nd.load_cfg()
        g, _ = self.price()
        me = self.f.sig_dates[g.sig_sel]
        key = (tuple(items), annual)
        if key in self._fund_cache:
            return self._fund_cache[key]
        out = {it: np.full((len(me), self.f.nt), np.nan, dtype=F32) for it in items}
        path = nd.p(cfg["paths"]["fund_a" if annual else "fund_q"])
        stale = int(cfg["staleness_months"]["a" if annual else "q"])
        trunc = None if self.cut is None else int(np.datetime64(self.cut, "D").astype(np.int64))
        tk = self.f.tickers
        for i in range(0, len(tk), 500):
            part = tk[i:i + 500]
            L = nd._read_long(path, part[0], part[-1], list(items), trunc)
            L = L[L["Ticker"].isin(part)]
            V, _, _ = nd.asof_dense(L, part, list(items), me.astype(np.int64), stale)       # [종목 × 항목 × 월]
            for k, it in enumerate(items):
                out[it][:, i:i + len(part)] = V[:, k, :].T
        self._fund_cache[key] = out
        return out


def _nlff():
    p = ac.root() + "/04_Research/01_reports/nonlinear_fundamental_factors_20261116"
    if p not in sys.path:
        sys.path.insert(0, p)
    import nlff_data
    return nlff_data


# ── 가격 · 거래 ──────────────────────────────────────────────────────────────
def build_price(ctx):
    g, P = ctx.price()
    rows = g.sig_rows
    lr, m = P["LogRet"], P["mkt"]
    F = {}
    C = Cum(lr, power=3)
    for w in (5, 20, 60, 120, 250):
        F["p_mom_%d" % w] = C.sum(rows, w, _mo(w))
    F["p_mom_12_1"] = F["p_mom_250"] - F["p_mom_20"]
    F["p_mom_6_1"] = F["p_mom_120"] - F["p_mom_20"]
    F["p_rev_36_12"] = C.sum(rows, 750, _mo(750)) - F["p_mom_250"]
    F["p_seas_12"] = C.sum(ad.lag_rows(rows, 230), 20, 16)              # 1년 전 같은 달 무렵의 수익
    for w in (20, 60, 120, 250):
        F["p_vol_%d" % w] = C.std(rows, w, _mo(w))
    F["p_skew_60"], F["p_skew_250"] = C.skew(rows, 60, 48), C.skew(rows, 250, 200)
    F["p_sharpe_60"], F["p_sharpe_250"] = _div(F["p_mom_60"], _pos(F["p_vol_60"])), _div(F["p_mom_250"], _pos(F["p_vol_250"]))
    del C
    fin = np.isfinite(lr)
    neg = np.where(fin, np.minimum(lr, 0.0), np.nan)
    Cn = Cum(neg * neg, power=1)
    F["p_dvol_60"], F["p_dvol_250"] = np.sqrt(Cn.mean(rows, 60, 48)), np.sqrt(Cn.mean(rows, 250, 200))
    del Cn, neg
    Cu = Cum(np.where(fin, (lr > 0).astype(np.float64), np.nan), power=1)
    F["p_up_60"], F["p_up_250"] = Cu.mean(rows, 60, 48), Cu.mean(rows, 250, 200)
    Cz = Cum(np.where(fin, (lr == 0).astype(np.float64), np.nan), power=1)
    F["p_zero_60"], F["p_zero_250"] = Cz.mean(rows, 60, 48), Cz.mean(rows, 250, 200)
    del Cu, Cz
    F["p_max_20"], F["p_min_20"] = window_max(lr, rows, 20, 16, np.nanmax), window_max(lr, rows, 20, 16, np.nanmin)
    for w in (60, 250):
        b, iv, cr = cross(lr, m, rows, w, _mo(w))
        F["p_beta_%d" % w], F["p_ivol_%d" % w], F["p_corr_%d" % w] = b, iv, cr
    ls, lf, la = P["LogSize"], P["LogFloatCap"], P["LogAmount"]
    F["p_size"], F["p_floatcap"] = ls[rows], lf[rows]
    F["p_float_ratio"] = (lf[rows].astype(np.float64) - ls[rows]).astype(F32)
    la_pos = np.where(la > 0, la, np.nan)                               # 거래대금 0(거래 없음)은 로그 평균에서 뺀다
    Ct = Cum(la_pos - ls, power=1)                                      # 회전율 = 거래대금 ÷ 시가총액(유동비율 자료는 2003-04 부터라 분모를 시총으로 둔다)
    for w in (20, 60, 250):
        F["p_turn_%d" % w] = Ct.mean(rows, w, _mo(w, 0.6))
    F["p_turn_chg"] = F["p_turn_20"] - F["p_turn_250"]
    del Ct
    Ca = Cum(la_pos, power=2)
    F["p_amt_20"], F["p_amt_250"], F["p_amt_vol_60"] = Ca.mean(rows, 20, 12), Ca.mean(rows, 250, 150), Ca.std(rows, 60, 36)
    del Ca
    Ci = Cum(np.abs(lr) * np.exp(-la_pos.astype(np.float64)), power=1)   # |수익| ÷ 거래대금(Amihud 2002)
    with np.errstate(invalid="ignore", divide="ignore"):
        F["p_amihud_20"], F["p_amihud_250"] = np.log(_pos(Ci.mean(rows, 20, 12))), np.log(_pos(Ci.mean(rows, 250, 150)))
    del Ci
    Cq = Cum(np.where(np.isfinite(la), (la <= 0).astype(np.float64), np.nan), power=1)
    F["p_notrade_250"] = Cq.mean(rows, 250, 150)
    del Cq, la_pos
    Ch = Cum(P["LogHL"], power=1)
    F["p_hl_20"], F["p_hl_60"], F["p_hl_250"] = Ch.mean(rows, 20, 16), Ch.mean(rows, 60, 48), Ch.mean(rows, 250, 200)
    del Ch
    Co, Cg = Cum(P["LogCO"], power=1), Cum(P["LogGap"], power=1)
    F["p_co_20"], F["p_co_250"] = Co.sum(rows, 20, 16), Co.sum(rows, 250, 200)
    F["p_gap_20"], F["p_gap_250"] = Cg.sum(rows, 20, 16), Cg.sum(rows, 250, 200)
    F["p_gap_minus_co_250"] = F["p_gap_250"] - F["p_co_250"]
    del Co, Cg
    c = ad.log_path(lr)
    F["p_high_250"] = (c[rows] - window_max(c, rows, 250, 200, np.nanmax)).astype(F32)
    F["p_low_250"] = (c[rows] - window_max(c, rows, 250, 200, np.nanmin)).astype(F32)
    del c
    names = list(F)
    X = np.stack([np.asarray(F[k], dtype=F32) for k in names], axis=2)
    return names, X, {"source": ".cache/rawdata_log.parquet(로그 수익 · 로그 시총 · 로그 유동시총 · 로그 거래대금 · 고저 · 시종 · 갭)",
                      "asof": "신호일 종가까지 · 창 = 거래일 수(5 · 20 · 60 · 120 · 250 · 750) · 창의 80% 이상 유효해야 값이 있다",
                      "note": "수정주가 수준은 쓰지 않는다 — 고점 · 저점 대비 위치는 로그 수익의 누적 경로로 계산"}


# ── 투자자 수급 ──────────────────────────────────────────────────────────────
def build_flow(ctx):
    g, P = ctx.price()
    rows1 = ad.lag_rows(g.sig_rows, 1)                                   # 전날까지
    traded = np.isfinite(P["LogRet"])
    amount = np.where(np.isfinite(P["LogAmount"]), np.expm1(P["LogAmount"].astype(np.float64)), 0.0)
    mcap = np.exp(P["LogSize"][rows1].astype(np.float64))                # 전날 시가총액(원) — 유동비율 자료가 2003-04 부터라 분모를 시총으로 둔다
    amt = {w: ad.wsum(amount, rows1, w) for w in (20, 60)}
    del amount
    first = np.datetime64("2000-01-04")                                  # 수급 자료 시작일(그 전 창은 값이 없다)
    start_row = int(np.searchsorted(g.dates, first))
    F = {}
    for tag, fn in (("for", "investor_foreign"), ("ins", "investor_institutional"), ("ind", "investor_individual")):
        q = ad.DailyGrid(ctx.f, ctx.path(".cache/investor_stock/%s.parquet" % fn), ["NetBuy"], cut=ctx.cut, base_dates=g.dates)
        nb = q.panel("NetBuy", dtype=np.float64)
        del q
        nb = np.where(np.isfinite(nb), nb, np.where(traded, 0.0, np.nan))  # 행이 없는 거래일 = 그 투자자의 순매수 0
        nb[:start_row] = np.nan
        C = Cum(nb, power=2)
        for w in (5, 20, 60, 120):
            F["f_%s_mc_%d" % (tag, w)] = _div(C.sum(rows1, w, _mo(w)), mcap)
        for w in (20, 60):
            F["f_%s_amt_%d" % (tag, w)] = _div(C.sum(rows1, w, _mo(w)), _pos(amt[w]))
        F["f_%s_z_20" % tag] = _div(C.sum(rows1, 20, 16), _pos(C.std(rows1, 250, 200)) * np.sqrt(20.0))
        del C
        Cp = Cum(np.where(np.isfinite(nb), (nb > 0).astype(np.float64), np.nan), power=1)
        F["f_%s_pos_20" % tag], F["f_%s_pos_60" % tag] = Cp.mean(rows1, 20, 16), Cp.mean(rows1, 60, 48)
        del Cp, nb
    names = list(F)
    X = np.stack([np.asarray(F[k], dtype=F32) for k in names], axis=2)
    return names, X, {"source": ".cache/investor_stock/investor_{foreign,institutional,individual}.parquet(순매수 금액 · 원)",
                      "asof": "신호일 전날까지(수급은 장 마감 뒤 확정) · 행이 없는 거래일은 순매수 0",
                      "note": "기타법인은 단위가 주식 수이고 2009-03 부터라 뺐다 · 시가총액 · 거래대금 대비 강도로만 쓴다(유동비율 자료는 2003-04 부터라 분모를 시총으로 뒀다)"}


# ── 거시 민감도 ──────────────────────────────────────────────────────────────
MACRO = [   # (특성 이름, 계열 id, 원천, 변환) — id 는 인프라 가용 시점 규칙(06_Registry/fred_availability_rules.json)에 등록된 것만
    ("m_fx_krw", "ECOS_KRW_USD", ("wide", ".cache/ecos_krw_usd.parquet", "KRW_USD"), "dlog"),
    ("m_kr3y", "KR_Gov3Y", ("long", ".cache/ecos_bond_rates.parquet", "Series", "KR_Gov3Y"), "diff"),
    ("m_kr10y", "KR_Gov10Y", ("long", ".cache/ecos_bond_rates.parquet", "Series", "KR_Gov10Y"), "diff"),
    ("m_krbbb", "KR_CorpBBB", ("long", ".cache/ecos_bond_rates.parquet", "Series", "KR_CorpBBB"), "diff"),
    ("m_vix", "VIXCLS", ("wide", ".cache/fred_macro_wide.parquet", "VIX"), "dlog"),
    ("m_us10y", "DGS10", ("wide", ".cache/fred_macro_wide.parquet", "US_10Y_Yield"), "diff"),
    ("m_us2y", "DGS2", ("wide", ".cache/fred_macro_wide.parquet", "US_2Y_Yield"), "diff"),
    ("m_dxy", "ECOS_DXY_PROXY", ("long", ".cache/ecos_fx_majors.parquet", "Series", "ECOS_DXY_PROXY"), "dlog"),
    ("m_jpy", "ECOS_JPY_PER_USD", ("long", ".cache/ecos_fx_majors.parquet", "Series", "ECOS_JPY_PER_USD"), "dlog"),
    ("m_wti", "QW_WTI_NYMEX", ("long", ".cache/qw_global_macro.parquet", "Series_ID", "QW_WTI_NYMEX"), "dlog"),
    ("m_krcpi", "KR_CPI", ("long", ".cache/ecos_bond_rates.parquet", "Series", "KR_CPI"), "level"),
]
INDEX_COLS = ["kospi", "kosdaq", "kospi_large", "kospi_small", "kospi200_vol"]


def macro_series(ctx, dates):
    """등록 계열의 '그 한국 거래일 종가에 알 수 있던 값' 일별 계열 dict[이름] = [T]. 가용 시점은 인프라 규칙으로 정한다."""
    import pandas as pd
    import pyarrow.parquet as pq
    p = ctx.root + "/02_Infrastructure/data"
    if p not in sys.path:
        sys.path.insert(0, p)
    import fred_availability as fa
    kr = [pd.Timestamp(d).date() for d in dates]
    hi = pd.Timestamp(dates[-1]).date()
    out, meta = {}, {}
    for name, sid, src, _ in MACRO:
        t = pq.read_table(ctx.path(src[1])).to_pandas()
        if src[0] == "long":
            t = t[t[src[2]] == src[3]]
            s = pd.DataFrame({"Date": pd.to_datetime(t["Date"]).dt.date, "Value": t["Value"].astype(float)})
        else:
            s = pd.DataFrame({"Date": pd.to_datetime(t["Date"]).dt.date, "Value": t[src[2]].astype(float)})
        s = s[s["Value"].notna() & (s["Date"] <= hi)].drop_duplicates("Date").sort_values("Date")   # cut 뒤의 관측은 읽지 않는다
        j = fa.fred_asof_join(kr, s, sid, mode="decision_close")
        out[name] = pd.to_numeric(j["value"], errors="coerce").to_numpy(dtype=np.float64)
        meta[name] = {"series_id": sid, "rules_version": j.attrs.get("rules_version"), "first": str(j.loc[j["value"].notna(), "kr_date"].min())}
    ix = pq.read_table(ctx.path(".cache/indices.parquet"), columns=["Date"] + INDEX_COLS).to_pandas()
    ix["Date"] = pd.to_datetime(ix["Date"]).to_numpy().astype("datetime64[D]")
    ix = ix[ix["Date"] <= dates[-1]].drop_duplicates("Date").set_index("Date").reindex(dates)       # 국내 지수 = 그날 종가(가격과 같은 규칙)
    for c in INDEX_COLS:
        out["ix_" + c] = ix[c].to_numpy(dtype=np.float64)
    return out, meta


def _chg(x, how):
    with np.errstate(invalid="ignore", divide="ignore"):
        if how == "dlog":
            d = np.diff(np.log(np.where(x > 0, x, np.nan)), prepend=np.nan)
        else:
            d = np.diff(x, prepend=np.nan)
    return d


def macro_factors(S):
    """민감도를 잴 일별 요인 변화 dict[이름] = [T]."""
    Fm = {}
    for name, _, _, how in MACRO:
        if how != "level":
            Fm[name] = _chg(S[name], how)
    Fm["m_kr_term"] = _chg(S["m_kr10y"] - S["m_kr3y"], "diff")
    Fm["m_kr_credit"] = _chg(S["m_krbbb"] - S["m_kr3y"], "diff")
    Fm["m_us_term"] = _chg(S["m_us10y"] - S["m_us2y"], "diff")
    Fm["m_kq_ks"] = _chg(S["ix_kosdaq"], "dlog") - _chg(S["ix_kospi"], "dlog")
    Fm["m_small_large"] = _chg(S["ix_kospi_small"], "dlog") - _chg(S["ix_kospi_large"], "dlog")
    Fm["m_vkospi"] = _chg(S["ix_kospi200_vol"], "dlog")
    for k in ("m_kr10y", "m_krbbb", "m_us2y"):                           # 스프레드의 재료로만 쓴 계열은 민감도에서 뺀다
        Fm.pop(k, None)
    return Fm


def build_macro(ctx, window=250):
    """종목 로그 수익을 [시장, 요인 변화]에 회귀한 요인 쪽 기울기(시장을 통제한 민감도). 창 = 250거래일."""
    g, P = ctx.price()
    rows, y, m = g.sig_rows, P["LogRet"], P["mkt"]
    S, meta = macro_series(ctx, g.dates)
    Fm = macro_factors(S)
    names, cols = [], []
    yfin = np.isfinite(y) & np.isfinite(m)[:, None]
    for name, f in Fm.items():
        ok = yfin & np.isfinite(f)[:, None]
        z = lambda a: np.where(ok, a, 0.0)                               # noqa: E731
        mm, ff = np.broadcast_to(m[:, None], y.shape), np.broadcast_to(f[:, None], y.shape)
        W = lambda a: ad.wsum(z(a), rows, window)                        # noqa: E731
        n = ad.wsum(ok.astype(np.float64), rows, window)
        sy, sm, sf = W(y), W(mm), W(ff)
        with np.errstate(invalid="ignore", divide="ignore"):
            cmm = W(mm * mm) - sm * sm / n
            cff = W(ff * ff) - sf * sf / n
            cmf = W(mm * ff) - sm * sf / n
            cym = W(y * mm) - sy * sm / n
            cyf = W(y * ff) - sy * sf / n
            den = cmm * cff - cmf * cmf
            b = (cyf * cmm - cym * cmf) / den
        b = np.where((n >= _mo(window, 0.6)) & (den > 1e-24), b, np.nan)
        names.append(name.replace("m_", "m_b_", 1))
        cols.append(b.astype(F32))
    X = np.stack(cols, axis=2)
    return names, X, {"source": "ecos_krw_usd · ecos_bond_rates · ecos_fx_majors · fred_macro_wide · qw_global_macro · indices",
                      "asof": "해외 · 금리 · 환율 계열은 fred_availability.fred_asof_join(decision_close)로 '그날 종가에 알 수 있던 값'의 일별 변화 · 국내 지수는 그날 종가",
                      "note": "기울기 = 종목 로그 수익 ~ 시장(KOSPI200) + 요인 변화 의 요인 쪽 계수 · 창 250거래일(60% 이상 유효)", "series": meta}


def macro_state(ctx):
    """월말 시점의 시장 · 거시 상태 변수(모든 종목에 같은 값) [덮는 신호 × k] — 예측 모형이 종목 특성과의 상호작용으로 쓴다."""
    g, P = ctx.price()
    rows, m = g.sig_rows, P["mkt"]
    S, _ = macro_series(ctx, g.dates)
    cm = np.cumsum(np.where(np.isfinite(m), m, 0.0))
    back = lambda x, k: x[rows] - x[np.maximum(rows - k, 0)]             # noqa: E731
    lvl = lambda x: x[rows]                                              # noqa: E731
    lg = lambda x: np.log(np.where(x > 0, x, np.nan))                    # noqa: E731
    Z = {"s_mkt_1m": back(cm, 20), "s_mkt_3m": back(cm, 60), "s_mkt_12m": back(cm, 250)}
    Z["s_mkt_vol_60"] = np.array([np.nanstd(m[max(0, t - 59): t + 1]) for t in rows])
    Z["s_mkt_dd_250"] = np.array([cm[t] - np.max(cm[max(0, t - 249): t + 1]) for t in rows])
    Z["s_kq_ks_3m"] = back(lg(S["ix_kosdaq"]), 60) - back(lg(S["ix_kospi"]), 60)
    Z["s_small_large_3m"] = back(lg(S["ix_kospi_small"]), 60) - back(lg(S["ix_kospi_large"]), 60)
    Z["s_vkospi"] = lvl(S["ix_kospi200_vol"])
    Z["s_kr3y"], Z["s_kr3y_3m"] = lvl(S["m_kr3y"]), back(S["m_kr3y"], 60)
    Z["s_kr_term"] = lvl(S["m_kr10y"] - S["m_kr3y"])
    Z["s_kr_credit"], Z["s_kr_credit_3m"] = lvl(S["m_krbbb"] - S["m_kr3y"]), back(S["m_krbbb"] - S["m_kr3y"], 60)
    Z["s_fx_krw_3m"], Z["s_dxy_3m"], Z["s_jpy_3m"] = back(lg(S["m_fx_krw"]), 60), back(lg(S["m_dxy"]), 60), back(lg(S["m_jpy"]), 60)
    Z["s_vix"], Z["s_us10y_3m"] = lvl(S["m_vix"]), back(S["m_us10y"], 60)
    Z["s_us_term"] = lvl(S["m_us10y"] - S["m_us2y"])
    Z["s_wti_3m"] = back(lg(S["m_wti"]), 60)
    Z["s_krcpi_yoy"] = back(lg(S["m_krcpi"]), 250)
    mem = ctx.f.mem[g.sig_sel]
    r1, r3 = wsum_rows(P["LogRet"], rows, 20), wsum_rows(P["LogRet"], rows, 60)
    Z["s_cs_disp_1m"] = np.array([np.nanstd(r1[i, mem[i]]) for i in range(len(rows))])   # 멤버 수익의 횡단면 흩어짐
    Z["s_breadth_3m"] = np.array([np.nanmean(r3[i, mem[i]] > 0) for i in range(len(rows))])
    names = list(Z)
    return names, np.stack([np.asarray(Z[k], dtype=np.float64) for k in names], axis=1).astype(F32)


def wsum_rows(x, rows, w):
    return ad.wsum(np.where(np.isfinite(x), x, 0.0), rows, w)


# ── 재무(같은 연구 줄기의 재무 입력 204개) ──────────────────────────────────
def build_fund(ctx, chunk=400, progress=None):
    nd = _nlff()
    cfg = nd.load_cfg()
    spec = nd.feature_spec(cfg)
    g, _ = ctx.price()
    sel = g.sig_sel
    me = ctx.f.sig_dates[sel]
    trunc = None if ctx.cut is None else int(np.datetime64(ctx.cut, "D").astype(np.int64))
    feats = list(spec["features"])
    X = np.full((len(sel), ctx.f.nt, len(feats)), np.nan, dtype=F32)
    days = me.astype(np.int64)
    tk = ctx.f.tickers
    for i in range(0, len(tk), chunk):
        part = tk[i:i + chunk]
        df = nd.build_chunk(cfg, spec, part, me, truncate_day=trunc)
        if len(df):
            si = np.searchsorted(days, df["Date"].to_numpy().astype("datetime64[D]").astype(np.int64))
            ti = ctx.f.ticker_index(df["Ticker"].to_list())
            have = [c for c in feats if c in df.columns]
            X[si[:, None], ti[:, None], np.array([feats.index(c) for c in have])[None, :]] = df[have].to_numpy(dtype=F32)
        if progress:
            progress(min(i + chunk, len(tk)), len(tk))
    return ["q_" + c for c in feats], X, {"source": ".cache/fundamental_quarterly.parquet · fundamental_annual.parquet(nlff_data.build_chunk · 규모 없는 파생 항목 + 변화량 ÷ 1년 전 총자산 + 부호 보존 로그)",
                                          "asof": "Factor_Date <= 신호일 인 마지막 행 · 기간 말이 15개월(분기) · 24개월(연간)보다 오래면 버림",
                                          "note": "가격 · 수익 입력 없음(순수 재무)"}


# ── 가치 비율 ────────────────────────────────────────────────────────────────
VAL_ITEMS = ["NetIncomeParent", "OperatingProfit", "EBITDA", "OperatingCF", "FCF1", "Revenue", "GrossProfit", "EquityParent", "TotalAssets", "TotalLiab",
             "NetDebt", "CashDivTotal", "CashAndEquiv", "RandD", "Capex", "RetainedEarnings", "Intangibles"]


def build_val(ctx):
    A = ctx.fund_asof(VAL_ITEMS)
    cap = ctx.cap_at_signal()
    nd_ = np.where(np.isfinite(A["NetDebt"]), A["NetDebt"], 0.0)
    ev = _pos(cap + nd_)                                                 # 기업가치(시총 + 순차입금) — 0 이하면 결측
    F = {"v_ep": _div(A["NetIncomeParent"], cap), "v_opp": _div(A["OperatingProfit"], cap), "v_ebitdap": _div(A["EBITDA"], cap),
         "v_cfp": _div(A["OperatingCF"], cap), "v_fcfp": _div(A["FCF1"], cap), "v_sp": _div(A["Revenue"], cap), "v_gpp": _div(A["GrossProfit"], cap),
         "v_bp": _div(A["EquityParent"], cap), "v_tbp": _div(A["EquityParent"].astype(np.float64) - np.where(np.isfinite(A["Intangibles"]), A["Intangibles"], 0.0), cap),
         "v_ap": _div(A["TotalAssets"], cap), "v_lp": _div(A["TotalLiab"], cap), "v_ndp": _div(A["NetDebt"], cap), "v_dp": _div(A["CashDivTotal"], cap),
         "v_cashp": _div(A["CashAndEquiv"], cap), "v_rdp": _div(A["RandD"], cap), "v_capexp": _div(A["Capex"], cap), "v_rep": _div(A["RetainedEarnings"], cap),
         "v_ebitda_ev": _div(A["EBITDA"], ev), "v_op_ev": _div(A["OperatingProfit"], ev), "v_s_ev": _div(A["Revenue"], ev), "v_fcf_ev": _div(A["FCF1"], ev)}
    names = list(F)
    return names, np.stack([F[k] for k in names], axis=2), {"source": "fundamental_quarterly(원계정 · 흐름은 최근 4분기 합) ÷ 신호일 시가총액(로그 캐시)",
                                                            "asof": "재무 = Factor_Date <= 신호일 · 시총 = 신호일 값", "note": "기업가치 = 시총 + 순차입금(0 이하면 결측)"}


# ── 컨센서스 ─────────────────────────────────────────────────────────────────
CONS = ["eps_1y", "bps_1y", "dps_1y", "eps_chg_1m", "eps_chg_3m", "sue", "revenue_fy1", "op_profit_fy1", "escr", "esbr", "coverage"]


def build_cons(ctx, max_age=20):
    g, _ = ctx.price()
    rows1 = ad.lag_rows(g.sig_rows, 1)                                   # 전날까지의 마지막 값
    A = {}
    for mname in CONS:
        q = ad.DailyGrid(ctx.f, ctx.path(".cache/consensus/%s.parquet" % mname), [mname], cut=ctx.cut, base_dates=g.dates)
        A[mname] = last_valid(q.panel(mname), rows1, max_age=max_age)
        del q
    cap = ctx.cap_at_signal()
    Fd = ctx.fund_asof(["Revenue", "OperatingProfit", "TotalAssets"])
    F = {"c_eps_chg_1m": A["eps_chg_1m"], "c_eps_chg_3m": A["eps_chg_3m"], "c_sue": A["sue"], "c_escr": A["escr"], "c_esbr": A["esbr"],
         "c_coverage": np.log1p(np.where(A["coverage"] >= 0, A["coverage"], np.nan)).astype(F32),
         "c_fwd_sp": _div(A["revenue_fy1"], cap), "c_fwd_opp": _div(A["op_profit_fy1"], cap),
         "c_fwd_opm": _div(A["op_profit_fy1"], _pos(A["revenue_fy1"])),
         "c_fwd_roe": _div(A["eps_1y"], _pos(A["bps_1y"])), "c_fwd_payout": _div(A["dps_1y"], _pos(A["eps_1y"])), "c_fwd_dy_b": _div(A["dps_1y"], _pos(A["bps_1y"])),
         "c_fwd_rev_g": (_div(A["revenue_fy1"], _pos(Fd["Revenue"])) - 1.0).astype(F32),
         "c_fwd_op_g": _div(A["op_profit_fy1"].astype(np.float64) - Fd["OperatingProfit"], _pos(Fd["TotalAssets"]))}
    names = list(F)
    return names, np.stack([np.asarray(F[k], dtype=F32) for k in names], axis=2), {
        "source": ".cache/consensus/<항목>.parquet", "asof": "신호일 전날까지의 마지막 값 · %d거래일보다 오래되면 버림" % max_age,
        "note": "주당 추정치(EPS · BPS · DPS)는 서로의 비율로만 쓴다(수정주가 수준과 나누지 않는다) · 총액 추정치(매출 · 영업이익)는 시총 · 실적 대비"}


# ── 범주(시장 · 지수 편입 · 업종) ────────────────────────────────────────────
def build_cat(ctx):
    import pyarrow.dataset as ds
    g, _ = ctx.price()
    sel = g.sig_sel
    sd = ctx.f.sig_dates[sel]
    raw = ds.dataset(ctx.path(".cache/RAWDATA.parquet"), format="parquet")
    t = raw.to_table(columns=["Date", "Ticker", "K200", "KQ150", "Sector"], filter=ad.date_filter(raw, "Date", isin=sd))
    si = np.searchsorted(sd, ad.to_days(t.column("Date")))
    ti = ctx.f.ticker_index(t.column("Ticker").to_pylist())
    ok = ti >= 0
    X = np.full((len(sel), ctx.f.nt, 3), np.nan, dtype=F32)
    for k, c in enumerate(["K200", "KQ150"]):
        v = np.asarray(t.column(c).to_numpy(zero_copy_only=False), dtype=np.float64)
        X[si[ok], ti[ok], k] = np.where(np.isfinite(v[ok]), v[ok], 0.0)   # 표식 결측 = 편입 아님
    sec = t.column("Sector").combine_chunks().dictionary_encode()
    sec_names = sec.dictionary.to_pylist()
    code = np.full((len(sel), ctx.f.nt), -1, dtype=np.int16)
    sc = np.asarray(sec.indices.to_numpy(zero_copy_only=False), dtype=np.float64)
    code[si[ok], ti[ok]] = np.where(np.isfinite(sc[ok]), sc[ok], -1).astype(np.int16)
    mt = ds.dataset(ctx.path(".cache/qw_ext/listing_market/market_type.parquet"), format="parquet")
    u = mt.to_table(columns=["Date", "Ticker", "Value"], filter=ad.date_filter(mt, "Date", isin=sd))
    s2 = np.searchsorted(sd, ad.to_days(u.column("Date")))
    t2 = ctx.f.ticker_index(u.column("Ticker").to_pylist())
    val = np.asarray(u.column("Value").to_pylist(), dtype=object)
    o2 = (t2 >= 0) & np.isin(val, ["KS", "KQ"])
    X[s2[o2], t2[o2], 2] = (val[o2] == "KQ").astype(F32)
    return ["cat_k200", "cat_kq150", "cat_kosdaq"], X, {"source": "RAWDATA(K200 · KQ150 · Sector) · qw_ext/listing_market(시장 구분)", "asof": "신호일 값",
                                                        "note": "업종 코드는 그룹 연산의 열쇠로 따로 저장(sector.npy) · 업종 이력의 시점 정합성은 확인되지 않았다",
                                                        "_sector": (code, sec_names)}


BLOCKS = {"price": build_price, "flow": build_flow, "macro": build_macro, "val": build_val, "cons": build_cons, "cat": build_cat, "fund": build_fund}
ORDER = ["price", "flow", "macro", "cat", "val", "cons", "fund"]
