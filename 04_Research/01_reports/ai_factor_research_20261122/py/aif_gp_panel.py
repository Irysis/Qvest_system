"""aif_gp_panel.py — 수식 탐색 3판이 쓸 일별 단말 패널을 만든다(공용 venv 에서 실행 · 결과는 .npy memmap).

수식 탐색은 일별 [날짜 × 종목] 패널 위에서 시계열 연산(창 평균 · 상관 등)을 하므로, 월말 값만 있는 특성 저장소와 별도로 일별 단말이 필요하다.
단말(30개) — 모든 값은 '그날 종가에 알 수 있는 값'이다:
  가격 · 거래 8   LogRet · LogBMRet(모든 종목 같은 값) · LogSize · LogFloatCap(원자료에서 직접) · LogAmount · LogHL · LogCO · LogGap
  재무 비율 13    2판과 같은 정의(gp_config.json::data.fund_ratios) — Factor_Date <= 그날 인 마지막 값 ÷ 그날 시총 또는 총자산 · 15개월보다 오래면 버림
  수급 3          외국인 · 기관 · 개인 순매수 ÷ 시가총액 — 하루 늦춰 넣는다(전날 값 · 수급은 장 마감 뒤 확정)
  거시 6          환율 · 국고 3년 · VIX · 미 10년 · 유가 · 달러지수의 '그날 알 수 있던 값'의 일별 변화(모든 종목 같은 값 — 시계열 상관 · 공분산의 짝으로만 뜻이 있다)
컨센서스는 멤버의 3분의 1에만 값이 있어 선별 기준(채움 60%)을 넘지 못하므로 단말에서 뺐다.
함께 저장: 달력 · 종목 · 월말 신호 위치 · 멤버 표(월말 행만) · 다음 달 수익(공통 틀의 값) · 일별 업종 코드(업종 중립 연산자용).
실행: python py/aif_gp_panel.py [--force]
"""
import argparse
import json
import os
import sys

import numpy as np

import aif_blocks as ab
import aif_common as ac
import aif_daily as ad

F32 = np.float32
VERSION = 1
MACRO_TERMS = {"mc_fx": "m_fx_krw", "mc_kr3y": "m_kr3y", "mc_vix": "m_vix", "mc_us10y": "m_us10y", "mc_wti": "m_wti", "mc_dxy": "m_dxy"}
FLOW_FILES = {"fl_for": "investor_foreign", "fl_ins": "investor_institutional", "fl_ind": "investor_individual"}
WINSOR_Q = (0.01, 0.99)          # 2판과 같은 값(gp_config.json::grammar.winsor_q) — 날짜별 단면 1%/99%


def cs_winsor(x, q=WINSOR_Q):
    """날짜(행)별 단면 윈저 — 그 행의 유한값 분위만 쓴다(다른 날짜 무접촉)."""
    o = np.array(x, dtype=F32, copy=True)
    o[~np.isfinite(o)] = np.nan
    for i in range(o.shape[0]):
        k = np.isfinite(o[i])
        if k.sum() >= 5:
            lo, hi = np.quantile(o[i, k], q)
            o[i, k] = np.clip(o[i, k], lo, hi)
    return o


def gp_cfg():
    with open(ac.root() + "/04_Research/01_reports/gp_symbolic_alpha_20261116/gp_config.json", encoding="utf-8") as fh:
        return json.load(fh)


def asof_daily(ctx, g, items, max_age_m):
    """재무 항목의 일별 as-of 패널 dict[item] = [T × N]: Factor_Date <= 그날 인 마지막 행의 값 · 기간 말이 max_age_m 개월보다 오래면 NaN."""
    import pandas as pd
    nd = ab._nlff()
    cfg = nd.load_cfg()
    f = ctx.f
    T, N = g.T, g.N
    dd = g.dates.astype(np.int64)
    trunc = None if ctx.cut is None else int(np.datetime64(ctx.cut, "D").astype(np.int64))
    out = {it: np.full((T, N), np.nan, dtype=F32) for it in items}
    per = {it: np.full((T, N), -1, dtype=np.int32) for it in items}
    tk = f.tickers
    for i in range(0, len(tk), 500):
        part = tk[i:i + 500]
        L = nd._read_long(nd.p(cfg["paths"]["fund_q"]), part[0], part[-1], list(items), trunc)
        L = L[L["Ticker"].isin(part) & np.isfinite(L["v"])]
        if not len(L):
            continue
        tj = f.ticker_index(L["Ticker"].to_list())
        r = np.searchsorted(dd, L["fd"].to_numpy(), side="left")              # 그 행을 처음 쓸 수 있는 거래일(날짜 >= Factor_Date)
        ok = (r < T) & (tj >= 0)
        L, tj, r = L[ok], tj[ok], r[ok]
        for it in items:
            m = (L["Item"] == it).to_numpy()
            if not m.any():
                continue
            o = np.lexsort((L["pd"].to_numpy()[m], r[m], tj[m]))              # 같은 칸에 여럿이면 기간이 가장 늦은 것이 마지막에 쓰인다
            out[it][r[m][o], tj[m][o]] = L["v"].to_numpy()[m][o].astype(F32)
            per[it][r[m][o], tj[m][o]] = L["pd"].to_numpy()[m][o].astype(np.int32)
    min_pd = (pd.DatetimeIndex(g.dates) - pd.DateOffset(months=max_age_m)).to_numpy().astype("datetime64[D]").astype(np.int64)
    for it in items:                                                          # 앞으로 채우기 → 묵은 값 거르기
        has = per[it] >= 0
        idx = np.where(has, np.arange(T, dtype=np.int32)[:, None], -1)
        np.maximum.accumulate(idx, axis=0, out=idx)
        got = idx >= 0
        cols = np.arange(N)[None, :]
        v = np.where(got, out[it][np.maximum(idx, 0), cols], np.nan)
        p = np.where(got, per[it][np.maximum(idx, 0), cols], -1)
        v[p < min_pd[:, None]] = np.nan
        out[it] = v.astype(F32)
    return out


class Sink:
    """단말을 만드는 대로 받아 처리하고 버린다 — 30개를 한꺼번에 들고 있지 않게(메모리 정점). put(이름, [T × N]) · names = 받은 이름."""

    def __init__(self, fn):
        self.fn, self.names = fn, []

    def __setitem__(self, name, arr):
        self.fn(name, arr)
        self.names.append(name)


def build(ctx, F, log=ac.log):
    """단말 패널을 하나씩 만들어 F(Sink)에 넘긴다. 격자를 돌려준다."""
    g, P = ctx.price()
    T, N = g.T, g.N
    for c in ("LogRet", "LogHL", "LogCO", "LogGap"):                           # 수익률형은 날짜별 윈저(2판과 같다)
        F[c] = cs_winsor(P[c])
    for c in ("LogSize", "LogFloatCap", "LogAmount"):
        F[c] = np.asarray(P[c], dtype=F32)
    F["LogBMRet"] = np.broadcast_to(P["mkt"].astype(F32)[:, None], (T, N)).copy()
    log("가격 · 거래 단말 8개")
    cfg = gp_cfg()
    R = cfg["data"]["fund_ratios"]
    items = sorted({i for r in R.values() for i in r["num"] + ([r["den"]] if r["den"] not in ("cap", "none") else [])})
    A = asof_daily(ctx, g, items, int(cfg["data"]["fund_max_age_months"]))
    cap = np.exp(P["LogSize"].astype(np.float64))
    with np.errstate(invalid="ignore", divide="ignore"):
        for name, r in R.items():
            num = A[r["num"][0]].astype(np.float64)
            if len(r["num"]) == 2:
                num = num - A[r["num"][1]]
            if r["den"] == "none":
                v = num
            else:
                den = cap if r["den"] == "cap" else A[r["den"]].astype(np.float64)
                v = np.where(den > 0, num / den, np.nan)
            F["fr_" + name] = cs_winsor(np.where(np.isfinite(v), v, np.nan))
    del A
    log("재무 비율 단말 %d개", len(R))
    traded = np.isfinite(P["LogRet"])
    start_row = int(np.searchsorted(g.dates, np.datetime64("2000-01-04")))
    for name, fn in FLOW_FILES.items():
        q = ad.DailyGrid(ctx.f, ctx.path(".cache/investor_stock/%s.parquet" % fn), ["NetBuy"], cut=ctx.cut, base_dates=g.dates)
        nb = q.panel("NetBuy", dtype=np.float64)
        del q
        nb = np.where(np.isfinite(nb), nb, np.where(traded, 0.0, np.nan))
        nb[:start_row] = np.nan
        with np.errstate(invalid="ignore", divide="ignore"):
            v = nb / cap
        lagged = np.full((T, N), np.nan, dtype=F32)
        lagged[1:] = v[:-1]                                                    # 하루 늦춘다 — 그날 행에는 전날 수급이 들어간다
        F[name] = cs_winsor(lagged)
        del nb, v, lagged
    del cap
    log("수급 단말 %d개", len(FLOW_FILES))
    S, _ = ab.macro_series(ctx, g.dates)
    Fm = ab.macro_factors(S)
    for name, src in MACRO_TERMS.items():
        F[name] = np.broadcast_to(Fm[src].astype(F32)[:, None], (T, N)).copy()
    log("거시 단말 %d개", len(MACRO_TERMS))
    return g


def sector_daily(ctx, g):
    """일별 업종 코드 [T × N] int16(없으면 −1) — 업종 중립 연산자용(그날 값)."""
    import pyarrow.dataset as ds
    raw = ds.dataset(ctx.path(".cache/RAWDATA.parquet"), format="parquet")
    hi = g.dates[-1]
    t = raw.to_table(columns=["Date", "Ticker", "Sector"], filter=ad.date_filter(raw, "Date", g.dates[0], hi))
    d = ad.to_days(t.column("Date"))
    tk = t.column("Ticker").combine_chunks().dictionary_encode()
    ti = ctx.f.ticker_index(tk.dictionary.to_pylist())[tk.indices.to_numpy(zero_copy_only=False)]
    sec = t.column("Sector").combine_chunks().dictionary_encode()
    names = sec.dictionary.to_pylist()
    order = np.argsort(names)                                                  # 코드 = 이름순(자른 원천에서도 같은 코드가 되게)
    remap = np.empty(len(names), dtype=np.int16)
    remap[order] = np.arange(len(names), dtype=np.int16)
    si = sec.indices.to_numpy(zero_copy_only=False)
    code = np.where(np.isfinite(si.astype(np.float64)), remap[np.nan_to_num(si.astype(np.float64), nan=0).astype(np.int64)], -1).astype(np.int16)
    di = np.clip(np.searchsorted(g.dates, d), 0, g.T - 1)
    ok = (g.dates[di] == d) & (ti >= 0)
    out = np.full((g.T, g.N), -1, dtype=np.int16)
    out[di[ok], ti[ok]] = code[ok]
    return out, [names[i] for i in order]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="이미 만든 패널이 있어도 다시 만든다")
    a = ap.parse_args()
    ac.low_priority()
    f = ac.Frame()
    d = ac.out("_scratch", "gp_panel")
    os.makedirs(d, exist_ok=True)
    fp = "%s|v%d" % (f.meta.get("rawdata_tag"), VERSION)
    meta = ac.read_json(d + "/panel_meta.json")
    if meta and meta.get("fp") == fp and not a.force:
        ac.log("일별 단말 패널 — 이미 만듦(건너뜀)")
        return 0
    ac.stage_begin("gp_v3", 3, "준비", 0.0, 0.03)
    ctx = ab.Ctx(f)
    picks = [f.ns // 3, (2 * f.ns) // 3]                                       # 잘라내기 자가 시험에 쓸 신호(그날 행만 남겨 둔다)
    g0 = ctx.price()[0]
    test_rows = {s: int(g0.sig_rows[s]) for s in picks}
    keep = {s: {} for s in picks}

    def put_full(name, arr):
        np.save(d + "/%s.npy" % name, np.asarray(arr, dtype=F32))
        for s, r in test_rows.items():
            keep[s][name] = np.array(arr[r], dtype=F32, copy=True)

    F = Sink(put_full)
    g = build(ctx, F)
    sec, sec_names = sector_daily(ctx, g)
    np.save(d + "/sector.npy", sec)
    elig = np.zeros((g.T, g.N), dtype=bool)
    elig[g.sig_rows] = f.mem
    np.save(d + "/elig.npy", elig)
    np.save(d + "/dates.npy", g.dates)
    np.save(d + "/tickers.npy", np.array(f.tickers).astype("U12"))
    np.save(d + "/me_idx.npy", g.sig_rows)
    np.save(d + "/fwd_ret.npy", np.asarray(f.fwd(1), dtype=F32))
    np.save(d + "/hold_end.npy", (f.hold_b + g.offset).astype(np.int64))       # 신호의 보유월이 끝나는 행(이 달력 안)
    np.save(d + "/hold_ok.npy", f.hold_ok)
    ac.stage_unit(1, "단말 %d개 저장" % len(F.names))
    # 미래 행 잘라내기 — 자른 원천으로 만든 그날 행이 전체로 만든 값과 같아야 한다(패널을 만들 때마다 돌린다)
    res = {"dates": [], "fields_differ": {}, "pass": True}
    for s in picks:
        cut = f.sig_dates[s]
        c2 = ab.Ctx(f, cut=cut)
        last = {}
        g2 = build(c2, Sink(lambda name, arr: last.__setitem__(name, np.array(arr[-1], dtype=F32, copy=True))), log=lambda *x: None)
        sec2, _ = sector_daily(c2, g2)
        row = g2.T - 1
        if g2.dates[row] != cut or g.dates[row] != cut or row != test_rows[s]:
            raise RuntimeError("[aif] 자른 달력의 끝이 기대와 다르다")
        res["dates"].append(str(cut))
        for k in F.names:
            if not np.array_equal(last[k], keep[s][k], equal_nan=True):
                res["fields_differ"][k] = res["fields_differ"].get(k, 0) + 1
                res["pass"] = False
        if not np.array_equal(sec2[row], sec[row]):
            res["fields_differ"]["sector"] = res["fields_differ"].get("sector", 0) + 1
            res["pass"] = False
        del c2, g2, last
        ac.log("자가 시험 %s — %s", str(cut), "통과" if res["pass"] else "실패 %s" % list(res["fields_differ"]))
    ac.write_json(res, ac.results("selftest_gp_panel.json"))
    ac.stage_unit(2, "잘라내기 자가 시험")
    ac.write_json({"fp": fp, "fields": sorted(F.names), "T": int(g.T), "N": int(g.N), "offset": int(g.offset), "sector_names": sec_names,
                   "row_constant": ["LogBMRet"] + sorted(MACRO_TERMS), "selftest": res, "built_at": ac._now()}, d + "/panel_meta.json")
    ac.stage_unit(3, "일별 단말 패널 끝")
    ac.stage_end(done=False)
    if res["pass"] is False:
        ac.status_set(stage_state="error", error="일별 단말 패널의 잘라내기 자가 시험 실패 — results/selftest_gp_panel.json")
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
