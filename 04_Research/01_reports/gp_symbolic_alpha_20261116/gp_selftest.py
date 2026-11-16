"""gp_selftest.py — PIT · 극단치 자가 시험 (gpa_v1 · 2026-11-16)

T1 연산자 단정: 미래 행(t > τ)을 무작위로 바꿔도 t ≤ τ 값이 비트 단위로 같다(모든 연산자) · 단면 · 원소별 연산자는 다른 날짜 행을 다 바꿔도 그날 값이 같다.
   + 돌연변이(양성 대조): 미래를 보는 가짜 연산자(shift −1 · 중심 창)를 넣으면 T1 이 잡아야 한다.
T2 무작위 수식 200개(문법 생성기)를 실제 스모크 패널에서: 미래 행 교란 전후 t ≤ τ 값 동일.
T3 적재기 잘림: build_panel(end = Y-12-31) 새로 적재 vs 긴 패널.slice_to(Y-12-31) — 필드 · 위생 · 표적 · 벤치 · 표준 팩터 동일.
T4 걸어가는 재진화 잘림: 해 Y 진화(작은 예산)를 (a) Y 말까지만 적재한 패널 (b) 긴 패널 자름 으로 돌려 원장 해시 · 적합도 · 선정 동일 ·
   적용 해 Y+1 의 월말 m 신호를 (m 까지 자른 패널) vs (Y+1 말까지 자른 패널)로 계산해 동일.
T5 표적 방향: 표적 = 다음 달 수익(신호 = 표적 자신이면 IC ≈ 1 · 신호 = 지난달 수익이면 그렇지 않다).
T6 극단치 주입: 한 종목 원자료(가격 · 거래량 · 시총 · 재무) × 1e6 → 다른 종목들의 월말 신호 순위 상관(중앙값) ≈ 1.
결과 = <run_dir>/selftest.json
"""
from __future__ import annotations

import json
import os
import random
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gp_ops as O                                                  # noqa: E402
from gp_data import build_panel, load_cfg                           # noqa: E402
from gp_engine import Evolution, build_pset, gen_half, to_tuple, clean, _setup_creator  # noqa: E402
from gp_fitness import month_sets, spearman_rows                    # noqa: E402
import gp_run as R                                                  # noqa: E402


def eqnan(a, b):
    return bool(np.array_equal(a, b, equal_nan=True))


def t1_ops(seed=1):
    rng = np.random.default_rng(seed)
    T, N, tau = 400, 40, 260
    X = rng.normal(size=(T, N)).astype(np.float32) * 10
    X[rng.random((T, N)) < 0.05] = np.nan
    Y = rng.normal(size=(T, N)).astype(np.float32)
    X2, Y2 = X.copy(), Y.copy()
    X2[tau + 1:] = rng.normal(size=(T - tau - 1, N)) * 1e3
    Y2[tau + 1:] = rng.normal(size=(T - tau - 1, N)) * 1e3
    res = {}
    for op, f in O.OPS.items():
        a = O.ARITY[op]
        for d in ([5, 20, 250] if op in O.TS_UNARY + O.TS_BINARY else [None]):
            if op in O.TS_BINARY:
                r1, r2 = f(X, Y, d), f(X2, Y2, d)
            elif op in O.TS_UNARY:
                r1, r2 = f(X, d), f(X2, d)
            elif a == 2:
                r1, r2 = f(X, Y), f(X2, Y2)
            else:
                r1, r2 = f(X), f(X2)
            res[f"{op}" + (f"_{d}" if d else "")] = eqnan(r1[: tau + 1], r2[: tau + 1])
    # 단면 · 원소별: 다른 날짜 행 전부 교란해도 그날 행 같음
    X3 = X.copy(); X3[:tau] = rng.normal(size=(tau, N)); X3[tau + 1:] = rng.normal(size=(T - tau - 1, N))
    for op in O.UNARY:
        res[f"{op}_rowonly"] = eqnan(O.OPS[op](X)[tau], O.OPS[op](X3)[tau])
    # 돌연변이(양성 대조) — 미래를 보는 연산자는 잡혀야 한다
    def leak_shift(x, d):  # x[t+1]
        out = np.full_like(x, np.nan); out[:-1] = x[1:]; return out

    def leak_center(x, d):  # 중심 창 평균(앞뒤 d/2)
        import bottleneck as bn
        m = bn.move_mean(x, d, min_count=1, axis=0)
        out = np.full_like(x, np.nan); k = d // 2; out[:-k] = m[k:]; return out
    mut = {"leak_shift_caught": not eqnan(leak_shift(X, 1)[: tau + 1], leak_shift(X2, 1)[: tau + 1]),
           "leak_center_caught": not eqnan(leak_center(X, 20)[: tau + 1], leak_center(X2, 20)[: tau + 1])}
    return {"pass": all(res.values()) and all(mut.values()), "ops": res, "mutation": mut}


def random_exprs(cfg, n, seed=7):
    _setup_creator()
    from deap import creator
    ps = build_pset(cfg)
    random.seed(seed)
    out, seen = [], set()
    while len(out) < n:
        ind = creator.Individual(gen_half(ps, 1, 4))
        e = to_tuple(ind)
        try:
            c = O.canon(e)
        except O.Degenerate:
            continue
        if not isinstance(c, tuple) or O.nodes(c) > cfg["grammar"]["max_nodes"] or O.to_str(c) in seen:
            continue
        seen.add(O.to_str(c)); out.append(c)
    return out


def t2_random(cfg, panel, n=200, tau_date="2008-06-30"):
    tau = int(np.searchsorted(panel.dates, np.datetime64(tau_date, "D"), side="right")) - 1
    rng = np.random.default_rng(3)
    f2 = {}
    for k, v in panel.fields.items():
        w = v.copy()
        w[tau + 1:] = w[tau + 1:] * rng.lognormal(0, 1, size=w[tau + 1:].shape).astype(np.float32)
        f2[k] = w
    e1, e2 = O.Evaluator(panel.fields, 300), O.Evaluator(f2, 300)
    bad = []
    exprs = random_exprs(cfg, n)
    for e in exprs:
        if not eqnan(e1.eval(e)[: tau + 1], e2.eval(e)[: tau + 1]):
            bad.append(O.to_str(e))
    return {"pass": not bad, "n": len(exprs), "violations": bad[:10]}


def _cmp_panels(a, b):
    out = {}
    for k in a.fields:
        out["field_" + k] = eqnan(a.fields[k], b.fields[k])
    out["elig"] = bool(np.array_equal(a.elig, b.elig))
    out["me_dates"] = bool(np.array_equal(a.me_dates, b.me_dates))
    out["fwd_ret"] = eqnan(a.fwd_ret, b.fwd_ret)
    out["fwd_valid"] = bool(np.array_equal(a.fwd_valid, b.fwd_valid))
    out["bm_fwd"] = eqnan(a.bm_fwd, b.bm_fwd)
    out["rf_fwd"] = eqnan(a.rf_fwd, b.rf_fwd)
    for k in a.std_factors:
        out["std_" + k] = eqnan(a.std_factors[k], b.std_factors[k])
    return out


def t3_loader(cfg, full, tick, Y, start):
    fresh = build_panel(cfg, start, f"{Y}-12-31", tickers=tick, verbose=False)
    cut = full.slice_to(f"{Y}-12-31")
    if not np.array_equal(fresh.tickers, cut.tickers):  # 짧은 적재에 아직 상장 안 한 종목이 없을 수 있다 → 열 맞춤
        return {"pass": False, "reason": "ticker set differs"}
    r = _cmp_panels(fresh, cut)
    return {"pass": all(r.values()), "checks": r}, fresh


def t4_walkforward(cfg, full, fresh, Y, wf, evo_cfg, run_dir):
    def one(panel, name):
        tm, vm = month_sets(panel, wf["fitness_start"], wf["fitness_start"], wf["val_months"], wf["embargo_months"])
        path = os.path.join(run_dir, f"selftest_ledger_{name}.jsonl")
        with open(path, "w", encoding="utf-8") as led:
            evo = Evolution(cfg, panel, tm, vm, led, {"variant": "ST", "evo_year_end": Y}, evo_cfg, evo_cfg["seed"] + Y, 300)
            evo.run([])
            ch, _ = R.select(evo, cfg)
        recs = [json.loads(l) for l in open(path, encoding="utf-8") if '"trial"' in l]
        return [(r["hash"], r["fitness"]) for r in recs], [c["hash"] for c in ch], [c["expr"] for c in ch]
    la, ca, xa = one(fresh, "fresh")
    lb, cb, xb = one(full.slice_to(f"{Y}-12-31"), "cut")
    same_ledger = la == lb
    same_sel = ca == cb
    # 적용 해 신호: 월말 m 까지 자른 패널 vs 그해 말까지 자른 패널
    sig_ok = []
    pY = full.slice_to(f"{Y+1}-12-31")
    ym = pY.me_dates.astype("datetime64[Y]").astype(int) + 1970
    rows = np.nonzero(ym == Y + 1)[0]
    for m in rows[[0, len(rows) // 2, -1]]:
        pm = full.slice_to(str(pY.me_dates[m]))
        for x in xa:
            e = R.parse(x)
            v1 = O.Evaluator(pY.fields, 100).eval(e)[pY.me_idx[m]]
            v2 = O.Evaluator(pm.fields, 100).eval(e)[pm.me_idx[-1] if pm.me_idx[-1] == len(pm.dates) - 1 else len(pm.dates) - 1]
            sig_ok.append(eqnan(v1, v2))
    return {"pass": same_ledger and same_sel and all(sig_ok), "same_ledger": same_ledger, "n_trials": len(la),
            "same_selection": same_sel, "selected": xa, "apply_signal_equal": sig_ok}


def t5_label(panel):
    months = np.nonzero(panel.fwd_valid)[0]
    el = panel.elig[panel.me_idx[months]]
    S_cheat = panel.fwd_ret
    ic_cheat = np.nanmean(spearman_rows(np.where(el, S_cheat[months], np.nan), np.where(el, panel.fwd_ret[months], np.nan)))
    # 지난달 수익(과거) — 월말 m 까지의 21일 수익
    c = panel.fields["close"]
    past = np.full_like(c, np.nan); past[21:] = c[21:] / c[:-21] - 1
    S_past = past[panel.me_idx]
    ic_past = np.nanmean(spearman_rows(np.where(el, S_past[months], np.nan), np.where(el, panel.fwd_ret[months], np.nan)))
    # 손 대조 1건: 한 종목 · 한 달의 표적 = 다음 달 일별 Ret 복리
    m = months[len(months) // 2]; j = int(np.nonzero(el[len(months) // 2])[0][0])
    a, b = panel.me_idx[m] + 1, panel.me_idx[m + 1] + 1
    hand = float(np.prod(1 + np.nan_to_num(panel.fields["ret_raw"][a:b, j].astype(np.float64))) - 1)
    return {"pass": bool(ic_cheat > 0.99 and abs(ic_past) < 0.5 and abs(hand - float(panel.fwd_ret[m, j])) < 1e-5),
            "ic_target_itself": float(ic_cheat), "ic_past_month_return": float(ic_past),
            "hand_check": {"month": str(panel.me_dates[m]), "ticker": str(panel.tickers[j]), "hand": hand, "panel": float(panel.fwd_ret[m, j])}}


def t6_extreme(cfg, panel, n=40):
    exprs = random_exprs(cfg, n, seed=11)
    el_any = panel.elig.any(axis=0)
    j = int(np.nonzero(el_any)[0][0])
    f2 = {}
    for k, v in panel.fields.items():
        w = v.copy()
        if k not in ("ret", "ret_raw"):
            w[:, j] = w[:, j] * 1e6
        f2[k] = w
    # 원자료 1e6 배를 넣은 뒤 재무 · ret 윈저는 적재기가 이미 했으므로 여기서 재무 열 윈저를 다시 건다(주입이 원자료 단계임을 흉내)
    from gp_data import cs_winsor
    for k in f2:
        if k.startswith("fund_"):
            f2[k] = cs_winsor(f2[k], tuple(cfg["grammar"]["winsor_q"]))
    e1, e2 = O.Evaluator(panel.fields, 300), O.Evaluator(f2, 300)
    others = np.ones(panel.fields["close"].shape[1], bool); others[j] = False
    cors = []
    for e in exprs:
        a = e1.eval(e)[panel.me_idx][:, others]; b = e2.eval(e)[panel.me_idx][:, others]
        c = spearman_rows(a, b)
        if np.isfinite(c).any():
            cors.append(float(np.nanmedian(c)))
    cors = np.array(cors)
    return {"pass": bool(np.median(cors) > 0.99), "injected_ticker": str(panel.tickers[j]), "n_exprs": len(cors),
            "median_of_median_rank_corr": float(np.median(cors)), "p10": float(np.quantile(cors, 0.1)),
            "min": float(cors.min()), "share_ge_0.99": float((cors >= 0.99).mean())}


def main(run_dir):
    cfg = load_cfg(); O.configure(cfg["grammar"])
    S = cfg["smoke"]
    out = {}
    t0 = time.perf_counter()
    out["T1_ops"] = t1_ops(); print("T1", out["T1_ops"]["pass"], out["T1_ops"]["mutation"], flush=True)
    tick, _ = R.pick_smoke_tickers(cfg)
    full = build_panel(cfg, S["history_buffer_start"], S["data_end"], tickers=tick, verbose=False)
    out["T2_random_exprs"] = t2_random(cfg, full); print("T2", out["T2_random_exprs"]["pass"], flush=True)
    Y = 2009
    r3, fresh = t3_loader(cfg, full, tick, Y, S["history_buffer_start"]); out["T3_loader_truncation"] = r3
    print("T3", r3["pass"], flush=True)
    evo_cfg = dict(cfg["evolution"]); evo_cfg.update(population=30, generations=2, hall_of_fame=8)
    wf = {"fitness_start": S["fitness_start"], "val_months": S["val_months"], "embargo_months": cfg["walkforward"]["embargo_months"]}
    out["T4_walkforward_truncation"] = t4_walkforward(cfg, full, fresh, Y, wf, evo_cfg, run_dir)
    print("T4", out["T4_walkforward_truncation"]["pass"], flush=True)
    out["T5_label_direction"] = t5_label(full); print("T5", out["T5_label_direction"]["pass"], flush=True)
    out["T6_extreme_injection"] = t6_extreme(cfg, full); print("T6", out["T6_extreme_injection"]["pass"], flush=True)
    out["all_pass"] = all(v["pass"] for v in out.values() if isinstance(v, dict) and "pass" in v)
    out["seconds"] = round(time.perf_counter() - t0, 1)
    with open(os.path.join(run_dir, "selftest.json"), "w", encoding="utf-8") as f:
        json.dump(clean(out), f, ensure_ascii=False, indent=1)
    print("ALL", out["all_pass"], out["seconds"])


if __name__ == "__main__":
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    main(d)
