"""gp_fitness.py — GP 탐색 적합도(탐색 목적함수 · metric_type = proxy) (gpa_v1 · 2026-11-16)

★이 값은 탐색 안의 목적함수다 — 측정 · 등급이 아니다. 권위 측정 = 시스템 표준 계약(run_paper_replication → essence · R 경유).
  python-policy §4 는 '보고하는 포트 수익'을 R 경유로 하라는 규칙이다. 여기 포트 수익은 수식 순위 매기기용 내부 계산이며
  보고 · 판정 · 등록에 쓰지 않는다(README §적합도 · 한계).

포트 = 월말 m 위생 멤버 중 신호 상위 25종 동일가중 롱온리 · 다음 달 보유 · 편도 15bps × 매매 비중(|Δw| 합).
주 적합도 = CAPM α 정보 비율: (r_p − rf) = α + β (r_KOSPI200 − rf) + ε 를 그 평가 창 안에서 추정 → α_t = (r_p − rf) − β̂ (r_b − rf) 의 평균/표준편차 × √12.
보조(선택에 안 씀): 단순 초과 IR · β · 단면 순위 IC 평균 · t · 회전율 · 최대 단일 종목 기여 비율 · 커버리지.
"""
from __future__ import annotations

import hashlib

import bottleneck as bn
import numpy as np


def month_sets(panel, fitness_start, win_start, val_months: int, embargo: int):
    """창 안 신호 월(표적이 창 안에서 완결) → (학습 색인, 검증 색인). 검증 = 마지막 val_months 개 · 그 앞 embargo 개 제외."""
    md = panel.me_dates
    ok = panel.fwd_valid & (md >= np.datetime64(fitness_start, "D")) & (md >= np.datetime64(win_start, "D"))
    idx = np.nonzero(ok)[0]
    if len(idx) < val_months + embargo + 12:
        raise ValueError(f"창이 너무 짧다: {len(idx)}개월")
    val = idx[-val_months:]
    train = idx[: len(idx) - val_months - embargo]
    return train, val


def _rank_rows(x):
    r = bn.nanrankdata(x, axis=1)
    return r


def spearman_rows(a, b):
    """행(월)별 단면 스피어먼 — 두 값이 모두 유한한 종목만."""
    m = np.isfinite(a) & np.isfinite(b)
    a = np.where(m, a, np.nan); b = np.where(m, b, np.nan)
    ra = _rank_rows(a); rb = _rank_rows(b)
    ra = ra - bn.nanmean(ra, axis=1)[:, None]; rb = rb - bn.nanmean(rb, axis=1)[:, None]
    num = bn.nansum(ra * rb, axis=1)
    den = np.sqrt(bn.nansum(ra * ra, axis=1) * bn.nansum(rb * rb, axis=1))
    with np.errstate(invalid="ignore", divide="ignore"):
        out = num / den
    out[np.sum(m, axis=1) < 10] = np.nan
    return out


def portfolio(panel, S, months, cfg_p):
    """S = (M,N) 월말 신호(전 월말 행). months = 쓸 월 색인(오름차순). 반환 = dict(월별 배열 + 보유 집합 지문)."""
    top = cfg_p["top_n"]; cost = cfg_p["cost_one_way"]; mn = cfg_p["min_names"]
    N = S.shape[1]
    gross = np.full(len(months), np.nan); net = gross.copy(); turn = gross.copy(); mcon = gross.copy(); cov = gross.copy()
    w_prev = np.zeros(N)
    hset = hashlib.sha1()
    prev_m = None
    for i, m in enumerate(months):
        el = panel.elig[panel.me_idx[m]]
        s = S[m]
        ne = el.sum()
        cand = el & np.isfinite(s)
        cov[i] = cand.sum() / ne if ne else np.nan
        if cand.sum() < mn:
            hset.update(b"-")
            prev_m = None; w_prev[:] = 0
            continue
        ci = np.nonzero(cand)[0]
        order = ci[np.lexsort((ci, -s[ci]))][:top]          # 동률 = 종목 순서(결정적)
        w = np.zeros(N); w[order] = 1.0 / len(order)
        r = panel.fwd_ret[m, order].astype(np.float64)
        r = np.where(np.isfinite(r), r, 0.0)                  # 다음 달 행 없음(상장폐지 등) = 0(현금) — 기록된 근사
        if prev_m is None or months[i - 1] != m - 1:
            w_prev[:] = 0
        tv = np.abs(w - w_prev).sum()
        g = r.mean()
        gross[i] = g; turn[i] = tv; net[i] = g - cost * tv
        c = np.abs(r / len(order))
        mcon[i] = c.max() / c.sum() if c.sum() > 0 else np.nan
        w_prev = w; prev_m = m
        hset.update(np.sort(order).astype(np.int32).tobytes())
    return {"gross": gross, "net": net, "turn": turn, "maxcon": mcon, "cov": cov, "hold_hash": hset.hexdigest()[:16]}


def metrics(panel, S, months, cfg_p):
    pf = portfolio(panel, S, months, cfg_p)
    rb = panel.bm_fwd[months]; rf = panel.rf_fwd[months]
    net = pf["net"]
    ok = np.isfinite(net) & np.isfinite(rb)
    out = {"n_months": int(ok.sum()), "hold_hash": pf["hold_hash"],
           "coverage": float(np.nanmean(pf["cov"])) if np.isfinite(pf["cov"]).any() else 0.0,
           "turnover": float(np.nanmean(pf["turn"])) if ok.any() else np.nan,
           "max_single_contrib_mean": float(np.nanmean(pf["maxcon"])) if ok.any() else np.nan,
           "max_single_contrib_max": float(np.nanmax(pf["maxcon"])) if ok.any() else np.nan}
    if ok.sum() < 12:
        out.update(excess_ir=np.nan, beta=np.nan, alpha_ir=np.nan, alpha_ann=np.nan)
    else:
        ex = net[ok] - rb[ok]
        sd = ex.std(ddof=1)
        out["excess_ir"] = float(ex.mean() / sd * np.sqrt(12)) if sd > 0 else np.nan
        okr = ok & np.isfinite(rf)
        if okr.sum() >= 12:
            y = net[okr] - rf[okr]; x = rb[okr] - rf[okr]
            vx = x.var(ddof=1)
            beta = float(np.cov(x, y, ddof=1)[0, 1] / vx) if vx > 0 else np.nan
            a = y - beta * x
            sa = a.std(ddof=1)
            out["beta"] = beta
            out["alpha_ir"] = float(a.mean() / sa * np.sqrt(12)) if sa > 0 else np.nan
            out["alpha_ann"] = float(a.mean() * 12)
        else:
            out.update(beta=np.nan, alpha_ir=np.nan, alpha_ann=np.nan)
    # 순위 IC(진단) — 위생 멤버 · 다음 달 수익
    el = panel.elig[panel.me_idx[months]]
    ic = spearman_rows(np.where(el, S[months], np.nan), np.where(el, panel.fwd_ret[months], np.nan))
    icf = ic[np.isfinite(ic)]
    out["rank_ic_mean"] = float(icf.mean()) if len(icf) else np.nan
    out["rank_ic_t"] = float(icf.mean() / icf.std(ddof=1) * np.sqrt(len(icf))) if len(icf) > 2 and icf.std() > 0 else np.nan
    return out


def std_corr(panel, S, months):
    """표준 팩터(MOM12_1 · STREV · SIZE · LOWVOL)와 월별 단면 스피어먼 평균 — 절댓값 최대와 각각."""
    el = panel.elig[panel.me_idx[months]]
    s = np.where(el, S[months], np.nan)
    res = {}
    for k, F in panel.std_factors.items():
        c = spearman_rows(s, np.where(el, F[months], np.nan))
        res[k] = float(np.nanmean(c)) if np.isfinite(c).any() else np.nan
    mx = max([abs(v) for v in res.values() if np.isfinite(v)] or [0.0])
    return mx, res
