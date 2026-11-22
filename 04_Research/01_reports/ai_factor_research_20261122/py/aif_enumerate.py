"""aif_enumerate.py — 단계 3 생성기 ①: 체계적 열거(재무 항목 × 정해진 형태) → 해마다 고르기 → 합성 팩터.

방법(Yan & Zheng 2017 RFS https://doi.org/10.1093/rfs/hhx001 의 구성 · Chen & Dim https://arxiv.org/abs/2311.10685 의 경험적 베이즈 축소):
  후보 = 분자 X(재무 원계정 · 단일 분기 값) × 분모 Y(15개) × 형태 5가지 + X 의 성장률
      ① X/Y  ② Δ(X/Y)  ③ %Δ(X/Y)  ④ ΔX / 1년 전 Y  ⑤ %ΔX − %ΔY  ⑥ %ΔX      (Δ = 4분기 전 같은 기간 대비 · 형태 수 76 = 15 × 5 + 1)
  값은 신호일 t 에 Factor_Date <= t 인 마지막 기간의 값(같은 항목의 4분기 전 기간 값과 짝) · 분자와 분모의 기간이 다르면 결측.
  1단계: 후보마다 월별 순위 IC(그 달 멤버 · 다음 1개월 수익) 계열을 만든다(분자 항목 하나 = 체크포인트 하나).
  2단계: 해마다 12월 신호일에, 그때까지 실현된 IC 만으로 t 값을 내고 (형태 × 분모) 묶음 안에서 경험적 베이즈로 줄인다.
         줄인 t 의 절댓값 상위부터, 채움 60% 이상 · 이미 뽑힌 것과의 순위 상관 0.7 미만인 것을 K 개 뽑아 다음 12달에만 쓴다.
산출: factors/ENUM_EB20.parquet(뽑힌 K 개의 부호 맞춘 순위 평균) · ENUM_TOP1~5.parquet(해마다 k 번째로 뽑힌 식) · 뽑힌 식 목록 csv.
실행: python py/aif_enumerate.py [--force]
"""
import argparse
import os
import sys
import time

import numpy as np
from scipy.stats import rankdata

import aif_blocks as ab
import aif_common as ac
from aif_features import FeatureStore

VERSION = 1
Y_ITEMS = ["TotalAssets", "CurrentAssets", "Inventory", "PPE", "TotalLiab", "CurrentLiab", "InterestBearingDebt", "EquityParent", "TotalEquity",
           "InvestedCapital", "Revenue", "COGS", "SGAExpense", "Employees"]                # + 시가총액(MKTCAP) = 15개(Yan & Zheng 의 분모 15개에 대응)
X_EXCLUDE = ("AdjDPS", "EPS", "Shares", "BuybackShares", "TreasuryShares")    # 이 말로 시작하는 항목 = 주당 값 · 주식 수(수정 계수가 섞인다) → 분자에서 뺀다
FORMS = ["ratio", "d_ratio", "pd_ratio", "dx_over_lagy", "pdx_minus_pdy"]
K_SELECT, N_TOP, MIN_IC_MONTHS, MIN_COVER, MAX_CORR, BURN_YEARS, COVER_WINDOW, CORR_WINDOW = 20, 5, 36, 0.60, 0.70, 5, 36, 12
PARAM_SRC = {"K_SELECT": "합성에 넣는 식 수 20 — 식 하나의 잡음을 1/sqrt(20) 로 줄이는 크기(DeMiguel, Garlappi & Uppal 2009 의 동일가중 논거 · https://doi.org/10.1093/rfs/hhm075)",
             "MIN_IC_MONTHS": "t 값을 내는 최소 달 수 36(3년)", "MIN_COVER": "승인 계획의 선별 기준 — 커버리지 60% 이상", "MAX_CORR": "승인 계획의 선별 기준 — 후보끼리 상관 0.7 미만",
             "BURN_YEARS": "첫 선택까지의 예열 5년(2000~2004) → 2005-01 부터 팩터 값"}


def _safe_div(a, b, pos=False):
    with np.errstate(invalid="ignore", divide="ignore"):
        o = a / b
    ok = np.isfinite(o) & ((b > 0) if pos else (b != 0))
    return np.where(ok, o, np.nan)


class Compact:
    """멤버 칸만 모은 납작한 배열(달 순서 · 달 안에서는 종목 순서). seg[s]:seg[s+1] = 신호 s 의 멤버들."""

    def __init__(self, frame):
        self.f = frame
        S, J = np.nonzero(frame.mem)
        self.S, self.J = S.astype(np.int32), J.astype(np.int32)
        self.seg = np.searchsorted(S, np.arange(frame.ns + 1)).astype(np.int64)
        self.n = len(S)
        self.pos = np.full((frame.ns, frame.nt), -1, dtype=np.int32)
        self.pos[S, J] = np.arange(self.n, dtype=np.int32)
        fwd = np.asarray(frame.fwd(1))[S, J].astype(np.float64)
        self.fwd_ok = np.isfinite(fwd)
        self.fwd_rank = np.full(self.n, np.nan)
        for s in range(frame.ns):                                     # 다음 달 수익의 그 달 멤버 안 순위(한 번만)
            a, b = self.seg[s], self.seg[s + 1]
            k = self.fwd_ok[a:b]
            if k.sum() >= 30:
                r = np.full(b - a, np.nan)
                r[k] = rankdata(fwd[a:b][k])
                self.fwd_rank[a:b] = r

    def ic(self, v, min_n=30):
        """납작한 신호 값 → 달별 순위 IC · 채움 비율."""
        ns = self.f.ns
        ic, cov = np.full(ns, np.nan, dtype=np.float32), np.zeros(ns, dtype=np.float32)
        fin = np.isfinite(v)
        for s in range(ns):
            a, b = self.seg[s], self.seg[s + 1]
            if b <= a:
                continue
            k = fin[a:b]
            cov[s] = k.mean()
            k = k & self.fwd_ok[a:b]
            n = int(k.sum())
            if n < min_n:
                continue
            x = rankdata(v[a:b][k])
            y = self.fwd_rank[a:b][k]
            x = x - x.mean()
            y = y - y.mean()
            den = np.sqrt((x * x).sum() * (y * y).sum())
            if den > 0:
                ic[s] = (x * y).sum() / den
        return ic, cov

    def rank_pm1(self, v):
        """납작한 값 → 달별 멤버 안 순위 (−1, 1)(결측 유지)."""
        o = np.full(self.n, np.nan, dtype=np.float32)
        for s in range(self.f.ns):
            a, b = self.seg[s], self.seg[s + 1]
            k = np.isfinite(v[a:b])
            n = int(k.sum())
            if n >= 2:
                r = np.full(b - a, np.nan, dtype=np.float32)
                r[k] = 2.0 * (rankdata(v[a:b][k]) - 1.0) / (n - 1.0) - 1.0
                o[a:b] = r
        return o


def load_fund(cp, items, cut=None, chunk=250, log=ac.log):   # 묶음 250종목 — 항목이 많아 긴 표가 커진다(메모리 정점을 낮춘다)
    """항목별 as-of 값(cur) · 그 기간의 분기 번호(qtr) · 4분기 전 같은 항목 값(lag) — 멤버 칸만. [항목 × 멤버 칸]."""
    nd = ab._nlff()
    cfg = nd.load_cfg()
    f = cp.f
    me = f.sig_dates.astype(np.int64)
    trunc = None if cut is None else int(np.datetime64(cut, "D").astype(np.int64))
    nI = len(items)
    cur = np.full((nI, cp.n), np.nan, dtype=np.float32)
    lag = np.full((nI, cp.n), np.nan, dtype=np.float32)
    qtr = np.full((nI, cp.n), -1, dtype=np.int16)
    path, stale = nd.p(cfg["paths"]["fund_q"]), int(cfg["staleness_months"]["q"])
    q0 = 1998 * 4
    tk = f.tickers
    for i in range(0, len(tk), chunk):
        part = tk[i:i + chunk]
        L = nd._read_long(path, part[0], part[-1], list(items), trunc)
        L = L[L["Ticker"].isin(part)]
        V, Pd, _ = nd.asof_dense(L, part, list(items), me, stale)              # [종목 × 항목 × 월] — 값 · 기간 말(일수)
        nT = len(part)
        pdt = np.where(Pd >= 0, Pd, 0).astype("datetime64[D]")
        yy = pdt.astype("datetime64[Y]").astype(np.int64) + 1970
        mm = pdt.astype("datetime64[M]").astype(np.int64) % 12
        Q = np.where(Pd >= 0, yy * 4 + mm // 3 - q0, -1).astype(np.int64)      # 분기 번호(1998Q1 = 0)
        nQ = int(max(Q.max(), 0)) + 1
        A = np.full((nT, nI, nQ), np.nan, dtype=np.float32)                    # 기간별 값(4분기 전 값 찾기용)
        if len(L):
            import pandas as pd
            ti = pd.Categorical(L["Ticker"], categories=part).codes.astype(np.int64)
            ii = pd.Categorical(L["Item"], categories=list(items)).codes.astype(np.int64)
            pp = L["pd"].to_numpy().astype("datetime64[D]")
            qq = (pp.astype("datetime64[Y]").astype(np.int64) + 1970) * 4 + (pp.astype("datetime64[M]").astype(np.int64) % 12) // 3 - q0
            ok = (ti >= 0) & (ii >= 0) & (qq >= 0) & (qq < nQ) & np.isfinite(L["v"].to_numpy())
            A[ti[ok], ii[ok], qq[ok]] = L["v"].to_numpy()[ok].astype(np.float32)
        ql = Q - 4
        Lg = np.take_along_axis(A, np.clip(ql, 0, nQ - 1), axis=2)
        Lg = np.where((Q >= 0) & (ql >= 0), Lg, np.nan)
        sub = cp.pos[:, i:i + nT]                                               # [월 × 종목] 의 멤버 칸 위치
        m_i, t_i = np.nonzero(sub >= 0)
        dst = sub[m_i, t_i]
        for k in range(nI):
            cur[k, dst] = V[t_i, k, m_i]
            lag[k, dst] = Lg[t_i, k, m_i]
            qtr[k, dst] = Q[t_i, k, m_i]
        log("재무 as-of — 종목 %d / %d", min(i + chunk, len(tk)), len(tk))
    return cur, lag, qtr


def signals_for(x, Y, form_list):
    """분자 x = (cur, lag, qtr) 와 분모들 Y[name] = (cur, lag, qtr 또는 None) → [(형태, 분모 이름, 값)] 생성기."""
    cx, lx, qx = x
    cx64, lx64 = cx.astype(np.float64), lx.astype(np.float64)
    dx = cx64 - lx64
    pdx = _safe_div(dx, np.abs(lx64))
    yield "pd_x", "", pdx
    for yn, (cy, ly, qy) in Y.items():
        same = np.ones(len(cx), bool) if qy is None else (qx == qy)             # 분자와 분모가 같은 기간일 때만
        cy64, ly64 = np.where(same, cy, np.nan).astype(np.float64), np.where(same, ly, np.nan).astype(np.float64)
        r, rl = _safe_div(cx64, cy64, pos=True), _safe_div(lx64, ly64, pos=True)
        for fm in form_list:
            if fm == "ratio":
                v = r
            elif fm == "d_ratio":
                v = r - rl
            elif fm == "pd_ratio":
                v = _safe_div(r - rl, np.abs(rl))
            elif fm == "dx_over_lagy":
                v = _safe_div(dx, ly64, pos=True)
            else:
                v = pdx - _safe_div(cy64 - ly64, np.abs(ly64))
            yield fm, yn, v


def formula_text(fm, x, y):
    return {"pd_x": "%%Δ %s" % x, "ratio": "%s / %s" % (x, y), "d_ratio": "Δ(%s / %s)" % (x, y), "pd_ratio": "%%Δ(%s / %s)" % (x, y),
            "dx_over_lagy": "Δ%s / 1년 전 %s" % (x, y), "pdx_minus_pdy": "%%Δ%s − %%Δ%s" % (x, y)}[fm]


def eb_shrink(t, fam):
    """(형태 × 분모) 묶음 안에서 t 값을 묶음 평균 쪽으로 줄인다: t~ = mu + max(0, 1 − 1/Var(t)) × (t − mu)."""
    out = np.full(len(t), np.nan)
    for g in np.unique(fam):
        k = (fam == g) & np.isfinite(t)
        if k.sum() < 10:
            continue
        mu, var = t[k].mean(), t[k].var(ddof=1)
        out[k] = mu + max(0.0, 1.0 - 1.0 / var) * (t[k] - mu) if var > 0 else mu
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    ac.low_priority()
    f = ac.Frame()
    store = FeatureStore(f)
    cp = Compact(f)
    out_dir = ac.out("enumerate")
    os.makedirs(out_dir, exist_ok=True)
    rep = ac.read_json(ac.root() + "/.cache/fundamental_caches_report.json") or {}
    stocks, flows = list(rep.get("stocks") or []), list(rep.get("flows") or [])
    if not stocks or not flows:
        raise RuntimeError("[aif] 재무 캐시 보고서에서 원계정 목록을 읽지 못했다(fundamental_caches_report.json 의 stocks · flows)")
    raw_items = stocks + flows + [x + "_Q" for x in flows]                    # 잔액 · 최근 4분기 합 · 단일 분기 값
    x_items = [x for x in raw_items if not x.startswith(X_EXCLUDE)]
    items = sorted(set(x_items) | set(Y_ITEMS))
    fp = "%s|v%d|%d" % (f.meta.get("rawdata_tag"), VERSION, len(items))
    ac.stage_begin("enumerate", 1, "준비", 0.0, 0.02)
    ac.status_set(detail="재무 항목 %d개의 as-of 값 준비" % len(items))
    cur, lag, qtr = load_fund(cp, items)
    ix = {k: i for i, k in enumerate(items)}
    raw, pn = store.open("price", "raw")
    cap = np.exp(np.asarray(raw[:, :, pn.index("p_size")], dtype=np.float64))              # 신호일 시가총액
    s12 = cp.S - 12                                                                        # 12달 전 신호일의 시가총액(같은 종목)
    Y = {y: (cur[ix[y]], lag[ix[y]], qtr[ix[y]]) for y in Y_ITEMS}
    Y["MKTCAP"] = (cap[cp.S, cp.J].astype(np.float32), np.where(s12 >= 0, cap[np.maximum(s12, 0), cp.J], np.nan).astype(np.float32), None)
    del cap, raw

    # ── 1단계: 후보마다 월별 순위 IC ──
    icp, metap = out_dir + "/ic.npy", out_dir + "/signals.json"
    meta = ac.read_json(metap)
    if meta and meta.get("fp") == fp and os.path.exists(icp) and not a.force:
        ac.log("1단계 — 이미 끝남(건너뜀) · 후보 %d개", len(meta["signals"]))
        ac.stage_begin("enumerate", 1, "단계", 0.0, 0.6)
        ac.stage_unit(1, "후보 IC 계열 재사용")
    else:
        ac.stage_begin("enumerate", len(x_items) + 2, "분자 항목", 0.0, 0.6)
        t0 = time.time()
        ac.stage_unit(1, "재무 as-of 값 준비 끝")
        sig, ICs, COV = [], [], []
        for n, x in enumerate(x_items):
            xs = (cur[ix[x]], lag[ix[x]], qtr[ix[x]])
            for fm, yn, v in signals_for(xs, Y, FORMS):
                if yn == x:
                    continue                                                               # 자기 자신으로 나눈 것은 뺀다
                ic, cov = cp.ic(v)
                if np.isfinite(ic).sum() < MIN_IC_MONTHS:
                    continue
                sig.append({"x": x, "form": fm, "y": yn})
                ICs.append(ic)
                COV.append((cov * 100).astype(np.uint8))
            if (n + 1) % 5 == 0 or n + 1 == len(x_items):
                ac.stage_unit(1 + n + 1, "%s 까지 · 후보 %d개" % (x, len(sig)))
        np.save(icp, np.stack(ICs))
        np.save(out_dir + "/cov.npy", np.stack(COV))
        meta = {"fp": fp, "signals": sig, "x_items": x_items, "y_items": Y_ITEMS + ["MKTCAP"], "seconds": round(time.time() - t0, 1)}
        ac.write_json(meta, metap)
        ac.log("1단계 끝 — 후보 %d개 · %.0f초", len(sig), time.time() - t0)

    # ── 2단계: 해마다 고르기 → 다음 12달 팩터 ──
    IC, COV, sig = np.load(icp), np.load(out_dir + "/cov.npy"), meta["signals"]
    fam = np.array(["%s|%s" % (s["form"], s["y"]) for s in sig])
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    ac.stage_begin("enumerate", len(sel_years), "해", 0.6, 0.9)

    def value_of(s):
        for fm, yn, v in signals_for((cur[ix[s["x"]]], lag[ix[s["x"]]], qtr[ix[s["x"]]]), {s["y"]: Y[s["y"]]} if s["y"] else {}, [s["form"]] if s["y"] else []):
            if fm == s["form"] and yn == s["y"]:
                return v
        raise RuntimeError("식 값을 다시 만들지 못했다: %s" % s)

    comp = np.full(cp.n, np.nan, dtype=np.float32)
    tops = [np.full(cp.n, np.nan, dtype=np.float32) for _ in range(N_TOP)]
    rows = []
    for n, y in enumerate(sel_years):
        sY = dec[y]
        use = slice(0, sY)                                                     # 신호 0 … sY−1: 다음 달 수익이 sY 의 날짜까지 실현된 것만
        ic = IC[:, use]
        cnt = np.isfinite(ic).sum(1)
        with np.errstate(invalid="ignore", divide="ignore"):
            mu, sd = np.nanmean(ic, 1), np.nanstd(ic, 1, ddof=1)
            t = np.where(cnt >= MIN_IC_MONTHS, mu / (sd / np.sqrt(cnt)), np.nan)
        cover = COV[:, max(0, sY - COVER_WINDOW):sY].mean(1) / 100.0
        t = np.where(cover >= MIN_COVER, t, np.nan)
        ts = eb_shrink(t, fam)
        order = np.argsort(-np.abs(np.where(np.isfinite(ts), ts, 0.0)))
        a0, b0 = cp.seg[max(0, sY - CORR_WINDOW + 1)], cp.seg[sY + 1]          # 상관을 재는 구간(선택 시점까지의 최근 12달 신호)
        nxt = [s for s in range(sY, min(sY + 12, f.ns))]                       # 이 선택을 쓰는 신호(12월 말 ~ 다음 해 11월 말)
        a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
        picked, pr = [], []
        for i in order:
            if not np.isfinite(ts[i]) or len(picked) >= K_SELECT:
                break
            r = cp.rank_pm1(value_of(sig[i])) * np.sign(ts[i])                 # 방향 = 그때까지의 IC 부호(줄인 t 의 부호)
            ra = r[a0:b0]
            ok = True
            for q in pr:
                k = np.isfinite(ra) & np.isfinite(q[a0:b0])
                if k.sum() > 100 and abs(np.corrcoef(ra[k], q[a0:b0][k])[0, 1]) >= MAX_CORR:
                    ok = False
                    break
            if ok:
                picked.append(i)
                pr.append(r)
                rows.append({"year_selected": y, "used_from": str(f.sig_dates[nxt[0]]), "used_to": str(f.sig_dates[nxt[-1]]), "pick": len(picked),
                             "formula": formula_text(sig[i]["form"], sig[i]["x"], sig[i]["y"]), "direction": int(np.sign(ts[i])), "t_asof": round(float(t[i]), 2),
                             "t_shrunk": round(float(ts[i]), 2), "ic_mean_asof": round(float(mu[i]), 4), "months": int(cnt[i]), "coverage": round(float(cover[i]), 2)})
        if picked:
            M = np.stack([q[a1:b1] for q in pr])                               # [뽑힌 식 × 칸]
            have = np.isfinite(M).mean(0)
            comp[a1:b1] = np.where(have >= 0.5, np.nanmean(np.where(np.isfinite(M), M, 0.0), 0), np.nan)   # 빠진 식은 0(중앙)으로 두고 평균 · 절반 이상 있어야 값
            for k in range(min(N_TOP, len(pr))):
                tops[k][a1:b1] = pr[k][a1:b1]
        ac.stage_unit(n + 1, "%d년 말 선택 — %d개" % (y, len(picked)))
    import csv
    os.makedirs(ac.results("stage3_enumerate"), exist_ok=True)
    with open(ac.results("stage3_enumerate", "selected_formulas.csv"), "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    fac_dir = ac.out("factors")
    os.makedirs(fac_dir, exist_ok=True)
    manifest = []

    def save(name, vec, desc):
        S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
        S[cp.S, cp.J] = vec
        p = fac_dir + "/%s.parquet" % name
        ac.save_factor_panel(p, name, S, f)
        manifest.append({"id": name, "path": p, "direction": 1, "method": "체계적 열거", "desc": desc})

    save("ENUM_EB20", comp, "해마다 뽑은 재무 식 %d개의 순위 평균(경험적 베이즈 축소 t 상위)" % K_SELECT)
    for k in range(N_TOP):
        save("ENUM_TOP%d" % (k + 1), tops[k], "해마다 %d번째로 뽑힌 재무 식(식은 해마다 바뀐다)" % (k + 1))
    ac.write_json({"at": ac._now(), "stage": "enumerate", "factors": manifest, "params": {"K_SELECT": K_SELECT, "N_TOP": N_TOP, "MIN_IC_MONTHS": MIN_IC_MONTHS,
                   "MIN_COVER": MIN_COVER, "MAX_CORR": MAX_CORR, "BURN_YEARS": BURN_YEARS, "_source": PARAM_SRC}, "n_candidates": len(sig),
                   "selected_csv": ac.results("stage3_enumerate", "selected_formulas.csv")}, ac.out("manifest_enumerate.json"))
    ac.log("2단계 끝 — 선택 %d해 · 팩터 %d개 저장", len(sel_years), len(manifest))
    ac.stage_end(done=False)                                                   # 성과 측정(R)까지 끝나야 단계가 끝난다
    return 0


if __name__ == "__main__":
    sys.exit(main())
