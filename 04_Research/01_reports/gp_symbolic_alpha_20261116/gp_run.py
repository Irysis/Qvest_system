"""gp_run.py — 걸어가는 재진화(walk-forward) 실행기 (gpa_v1 · 2026-11-16)

해마다 말 Y 에(Y = first_evolution_year_end … last_evolution_year_end):
  1. 패널을 Y-12-31 에서 자른다(그 뒤 행은 메모리에도 없다).
  2. 창(EXP = fitness_start~ · ROLL = 마지막 n 년) 안 신호 월을 학습 / 엠바고 / 검증(마지막 val_months)으로 나눈다.
  3. 진화(초기 개체 = 직전 해 생존 수식 inherit_frac + 무작위) — 적합도 = 학습 α IR − 복잡도 − 표준 팩터 중복.
  4. 기계적 선택: 학습 α IR > 0 ∧ 검증 α IR > 0 ∧ 커버리지 ≥ 하한 ∧ 표준 팩터 |ρ| < 0.7 → 검증 α IR 내림차순 →
     보유 지문 중복 제거 → 이미 고른 것과 |ρ| < 0.7 인 것만 → k 개.
  5. Y+1 의 월말 신호를 Y+1-12-31 까지 자른 패널로 계산(수식은 고정) → 팩터 파일.
사용: python gp_run.py --smoke [--variants EXP,ROLL3] [--tag <run>]  ·  python gp_run.py --full (금지 — 설계 단계)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import numpy as np
import pandas as pd
import psutil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gp_ops as O                                     # noqa: E402
from gp_data import ROOT, build_panel, load_cfg         # noqa: E402
from gp_engine import Evolution, clean                  # noqa: E402
from gp_fitness import month_sets, spearman_rows        # noqa: E402

OUT_CACHE = os.path.join(ROOT, ".cache", "gp_alpha_factors")


def rss_gb():
    return psutil.Process().memory_info().rss / 2**30


def pick_smoke_tickers(cfg):
    """스모크 종목 = 2004-12-30 위생 멤버 중 무작위 n(그날까지 정보로만 고른다 — 이후 상장 종목은 스모크에서 빠짐 · 기록)."""
    S = cfg["smoke"]
    p0 = build_panel(cfg, "2004-10-01", "2004-12-31", fund=False, verbose=False)
    t = np.datetime64("2004-12-30", "D")
    i = int(np.searchsorted(p0.dates, t, side="right")) - 1
    el = p0.tickers[p0.elig[i]]
    rng = np.random.default_rng(cfg["evolution"]["seed"])
    return sorted(rng.choice(el, size=min(S["n_tickers"], len(el)), replace=False).tolist()), str(p0.dates[i])


def select(evo: Evolution, cfg):
    """기계적 선택 규칙(사전 고정 · gp_config.selection)."""
    Sx = cfg["selection"]
    F = cfg["fitness"]
    rows = [r for (_, r) in evo.memo.values() if r and r.get("status") == "ok"]
    cand = []
    for r in rows:
        tr, va = r["train"], r["val"]
        if Sx["require_train_alpha_ir_pos"] and not (tr.get("alpha_ir") or -1) > 0:
            continue
        if Sx["require_val_alpha_ir_pos"] and not (va.get("alpha_ir") or -1) > 0:
            continue
        if tr["coverage"] < F["coverage_min"] or r["std_corr_max"] >= Sx["corr_max_vs_std"]:
            continue
        cand.append(r)
    cand.sort(key=lambda r: (-r["val"]["alpha_ir"], r["nodes"], r["hash"]))   # 동률 = 짧은 식 · 해시(결정적)
    chosen, seen_hold = [], set()
    months = np.r_[evo.tm, evo.vm]
    _sc = {}

    def sig(r):   # 월말 신호는 저장하지 않고 필요할 때 다시 계산(메모리 — 부분식 캐시가 대부분 맞힌다)
        if r["hash"] not in _sc:
            _sc[r["hash"]] = evo.ev.eval(parse(r["expr"]))[evo.p.me_idx]
        return _sc[r["hash"]]
    for r in cand:
        if len(chosen) >= Sx["k"]:
            break
        hk = r["train"]["hold_hash"] + r["val"]["hold_hash"]
        if hk in seen_hold:
            continue
        S = sig(r)
        ok = True
        for c in chosen:
            rho = np.nanmean(spearman_rows(S[months], sig(c)[months]))
            if abs(rho) >= Sx["corr_max_vs_selected"]:
                ok = False
                break
        if ok:
            chosen.append(r); seen_hold.add(hk)
    return chosen, len(cand)


def describe(e) -> str:
    """구조 설명 1줄(기계 생성 — 사람 해석은 전체 실행 뒤 README 에 덧붙인다)."""
    W = {"ts_mean": "평균", "ts_std": "변동성", "ts_rank": "시계열 순위", "ts_min": "최저", "ts_max": "최고",
         "ts_delta": "변화", "ts_delay": "지연", "ts_decay_linear": "선형 감쇠 평균", "ts_corr": "상관", "ts_cov": "공분산"}
    U = {"neg": "−", "abs": "|·|", "slog": "로그", "ssqrt": "제곱근", "cs_rank": "단면 순위", "cs_zscore": "단면 z"}
    B = {"add": "+", "sub": "−", "mul": "×", "div": "÷"}

    def r(x):
        if isinstance(x, tuple):
            op = x[0]
            if op in W:
                ser = ", ".join(r(c) for c in x[1:-1])
                return f"{x[-1]}일 {W[op]}[{ser}]"
            if op in U:
                return f"{U[op]}({r(x[1])})"
            return f"({r(x[1])} {B[op]} {r(x[2])})"
        return str(x).replace("fund_", "재무:")
    return r(e)


def parse(s: str):
    """to_str 의 역 — 'op(a,b,20)' → 튜플."""
    s = s.strip()
    if "(" not in s:
        return int(s) if s.isdigit() else s
    op, rest = s.split("(", 1)
    rest = rest[:-1]
    args, depth, cur = [], 0, ""
    for ch in rest:
        if ch == "," and depth == 0:
            args.append(cur); cur = ""
            continue
        depth += ch == "("
        depth -= ch == ")"
        cur += ch
    args.append(cur)
    return (op, *[parse(a) for a in args])


def apply_year(cfg, full, chosen_exprs, year, out_dir, variant):
    """Y+1 월말 신호 — 패널을 그해 말까지 잘라 계산(수식 고정). 반환 = 롱 표 · 합성."""
    pY = full.slice_to(f"{year}-12-31")
    ev = O.Evaluator(pY.fields, cfg["resources"]["subtree_cache_mb"] / 3)
    ym = pY.me_dates.astype("datetime64[Y]").astype(int) + 1970
    rows_m = np.nonzero(ym == year)[0]
    if not len(rows_m):
        return None
    tab, ranks = [], []
    for j, (hh, e) in enumerate(chosen_exprs):
        X = ev.eval(e)[pY.me_idx[rows_m]]
        rk = O.op_cs_rank(np.where(np.isfinite(X), X, np.nan).astype(np.float32))
        ranks.append(rk)
        for i, m in enumerate(rows_m):
            fin = np.isfinite(X[i])
            tab.append(pd.DataFrame({"Date": pY.me_dates[m], "Ticker": pY.tickers[fin],
                                     "Factor_Name": f"GPA_{variant}_{year}_{j+1}_{hh}", "Raw_Value": X[i][fin]}))
    comp = np.nanmean(np.stack(ranks), axis=0) if ranks else None
    cnt = np.sum(np.isfinite(np.stack(ranks)), axis=0) if ranks else None
    if comp is not None:
        comp[cnt < max(1, int(np.ceil(len(ranks) / 2)))] = np.nan
        for i, m in enumerate(rows_m):
            fin = np.isfinite(comp[i])
            tab.append(pd.DataFrame({"Date": pY.me_dates[m], "Ticker": pY.tickers[fin],
                                     "Factor_Name": f"GPA_{variant}", "Raw_Value": comp[i][fin]}))
    return pd.concat(tab, ignore_index=True) if tab else None


def walk_forward(cfg, full, variant: str, vcfg: dict, evo_cfg: dict, wf: dict, run_dir: str, years, log):
    led_path = os.path.join(run_dir, f"trial_ledger_{variant}.jsonl")
    sel_path = os.path.join(run_dir, f"selected_{variant}.jsonl")
    out_tabs = []
    inherited = []
    with open(led_path, "w", encoding="utf-8") as led, open(sel_path, "w", encoding="utf-8") as sf:
        for Y in years:
            t0 = time.perf_counter()
            pw = full.slice_to(f"{Y}-12-31")
            if vcfg["window"] == "expanding":
                ws = wf["fitness_start"]
            else:
                ws = f"{Y - vcfg['years'] + 1}-01-01"
            ws = max(ws, wf["fitness_start"])
            tm, vm = month_sets(pw, wf["fitness_start"], ws, wf["val_months"], wf["embargo_months"])
            tag = {"variant": variant, "evo_year_end": Y, "post_tauD": bool(Y > 2022),
                   "train_from": str(pw.me_dates[tm[0]]), "train_to": str(pw.me_dates[tm[-1]]),
                   "val_from": str(pw.me_dates[vm[0]]), "val_to": str(pw.me_dates[vm[-1]])}
            evo = Evolution(cfg, pw, tm, vm, led, tag, evo_cfg, seed=evo_cfg["seed"] + Y,
                            cache_mb=cfg["resources"]["subtree_cache_mb"])
            hof = evo.run(inherited)
            chosen, n_cand = select(evo, cfg)
            t_evo = time.perf_counter() - t0
            srec = {"type": "selection", **tag, "n_unique": len(evo.memo), "n_seen": evo.n_seen,
                    "n_ok": sum(1 for (_, r) in evo.memo.values() if r and r.get("status") == "ok"),
                    "n_hold_unique": len({r["train"]["hold_hash"] + r["val"]["hold_hash"] for (_, r) in evo.memo.values()
                                          if r and r.get("status") == "ok"}),
                    "n_candidates": n_cand, "evo_seconds": round(t_evo, 1), "rss_gb": round(rss_gb(), 2),
                    "cache_hits": evo.ev.hits, "cache_miss": evo.ev.miss,
                    "chosen": [{"hash": r["hash"], "expr": r["expr"], "skeleton": r["skeleton"], "nodes": r["nodes"],
                                "describe": describe(parse(r["expr"])), "std_corr_max": r["std_corr_max"]} for r in chosen]}
            sf.write(json.dumps(clean(srec), ensure_ascii=False) + "\n"); sf.flush()
            log(f"[{variant} Y={Y}] 고유 {len(evo.memo)} · 본 개체 {evo.n_seen} · 후보 {n_cand} · 선정 {len(chosen)} · "
                f"{t_evo:.0f}s · RSS {rss_gb():.2f}GB")
            # 다음 해 초기 개체(이어 받기) = 선정 수식 + 명예의 전당(과거 선택물 — PIT 안전)
            inherited = [parse(r["expr"]) for r in chosen] + [_t(h_) for h_ in hof]
            inherited = [e for e in inherited if isinstance(e, tuple)]
            # 적용(Y+1)
            if Y + 1 <= int(str(full.dates[-1])[:4]):
                tab = apply_year(cfg, full, [(r["hash"], parse(r["expr"])) for r in chosen], Y + 1, run_dir, variant)
                if tab is not None:
                    out_tabs.append(tab)
            del evo, pw
    return out_tabs


def _t(ind):
    from gp_engine import to_tuple
    return to_tuple(ind)


def stability(run_dir, variant):
    rows = [json.loads(l) for l in open(os.path.join(run_dir, f"selected_{variant}.jsonl"), encoding="utf-8")]
    out = []
    for a, b in zip(rows[:-1], rows[1:]):
        ha = {c["hash"] for c in a["chosen"]}; hb = {c["hash"] for c in b["chosen"]}
        sa = {c["skeleton"] for c in a["chosen"]}; sb = {c["skeleton"] for c in b["chosen"]}
        out.append({"from": a["evo_year_end"], "to": b["evo_year_end"],
                    "same_formula_retention": len(ha & hb) / len(ha) if ha else None,
                    "same_skeleton_retention": len(sa & sb) / len(sa) if sa else None})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--tag", default=None)
    a = ap.parse_args()
    cfg = load_cfg()
    O.configure(cfg["grammar"])
    if a.full:
        sys.exit("[gp_run] 전체 실행은 이 설계 단계에서 금지(도훈 11-16 '설계와 짧은 구간 시험까지') — --smoke 만.")
    if not a.smoke:
        sys.exit("사용: --smoke")
    S = cfg["smoke"]
    run = a.tag or ("smoke_" + time.strftime("%Y%m%d_%H%M%S"))
    run_dir = os.path.join(OUT_CACHE, run)
    os.makedirs(run_dir, exist_ok=True)
    logf = open(os.path.join(run_dir, "run.log"), "w", encoding="utf-8")

    def log(m):
        print(m, flush=True); logf.write(m + "\n"); logf.flush()
    t0 = time.perf_counter()
    tick, pick_day = pick_smoke_tickers(cfg)
    log(f"[smoke] 종목 {len(tick)} (pick {pick_day} 위생 멤버 무작위) · RSS {rss_gb():.2f}GB")
    full = build_panel(cfg, S["history_buffer_start"], S["data_end"], tickers=tick)
    log(f"[smoke] 패널 적재 {time.perf_counter()-t0:.0f}s · RSS {rss_gb():.2f}GB")
    evo_cfg = dict(cfg["evolution"]); evo_cfg.update(population=S["population"], generations=S["generations"],
                                                    hall_of_fame=S["hall_of_fame"])
    wf = {"fitness_start": S["fitness_start"], "val_months": S["val_months"], "embargo_months": cfg["walkforward"]["embargo_months"]}
    years = list(range(S["first_evolution_year_end"], S["last_evolution_year_end"] + 1))
    variants = {"EXP": {"window": "expanding"}, f"ROLL{S['rolling_years']}": {"window": "rolling", "years": S["rolling_years"]}}
    summary = {"run": run, "mode": "smoke", "tickers": len(tick), "pick_day": pick_day, "years": years, "variants": {}}
    for v, vc in variants.items():
        tv = time.perf_counter()
        tabs = walk_forward(cfg, full, v, vc, evo_cfg, wf, run_dir, years, log)
        if tabs:
            df = pd.concat(tabs, ignore_index=True)
            for fn, g in df.groupby("Factor_Name"):
                g.to_parquet(os.path.join(run_dir, f"{fn}.parquet"), index=False)
        summary["variants"][v] = {"seconds": round(time.perf_counter() - tv, 1), "stability": stability(run_dir, v),
                                  "factor_files": sorted({f for f in os.listdir(run_dir) if f.startswith(f"GPA_{v}")})}
    summary["total_seconds"] = round(time.perf_counter() - t0, 1)
    summary["peak_rss_gb"] = round(psutil.Process().memory_info().peak_wset / 2**30, 2) if hasattr(psutil.Process().memory_info(), "peak_wset") else None
    with open(os.path.join(run_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(clean(summary), f, ensure_ascii=False, indent=1)
    log(json.dumps(clean(summary), ensure_ascii=False))


if __name__ == "__main__":
    main()
