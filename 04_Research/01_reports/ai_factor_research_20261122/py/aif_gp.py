"""aif_gp.py — 단계 3 생성기 ③: 수식 탐색 3판(유전 프로그래밍).

2판(04_Research/01_reports/gp_symbolic_alpha_20261116)의 엔진 · 연산자 · 정규화 · 선택 규칙 · 진화 설정을 그대로 불러 쓰고 세 가지만 바꾼다:
  ① 단말 = 전 자료(가격 · 거래 8 + 재무 비율 13 + 수급 3 + 거시 6 = 30개) — aif_gp_panel.py 가 만든 일별 패널
  ② 연산자에 업종 중립(cs_sec_demean = 그날 같은 업종 평균을 뺀 값)을 더한다
  ③ 수식을 고르는 점수 = 전 종목 순위 IC 의 안정성(월별 순위 IC 평균 ÷ 표준편차 × √12) — 2판은 상위 25종 롱온리의 알파 IR 이었다(도훈 11-22 결정 D2)
걸어가는 절차(2판과 같다): 해 Y 말에 그때까지의 패널만으로 진화 → 기계적 선택(학습 · 검증 점수 > 0 · 채움 60% 이상 · 표준 팩터와 상관 0.7 미만 ·
  이미 고른 식과 상관 0.7 미만 · 5개) → Y+1 년 월말 신호에만 쓴다. 변형 = 확장 창(EXP) · 고정 8년 창(ROLL8).
산출: factors/GP3_EXP.parquet · GP3_ROLL8.parquet(해마다 고른 식의 순위 평균) · GP3_EXP_TOP1~5.parquet(해마다 k 번째로 고른 식) · 고른 식 목록.
실행(전용 환경 .venv_gp_alpha — deap · bottleneck): python py/aif_gp.py [--smoke]   ((변형, 해) 하나 = 체크포인트 하나)
"""
import argparse
import hashlib
import os
import sys
import time

import numpy as np
import pandas as pd

import aif_common as ac

GP2 = ac.root() + "/04_Research/01_reports/gp_symbolic_alpha_20261116"
sys.path.insert(0, GP2)
import gp_data as GD          # noqa: E402
import gp_engine as GE        # noqa: E402
import gp_fitness as GF       # noqa: E402
import gp_ops as O            # noqa: E402
import gp_run as GR           # noqa: E402

F32 = np.float32
VERSION = 1
SEC = {"code": None, "n": 0}


def op_cs_sec_demean(x):
    """업종 중립 — 그날 같은 업종(유한값이 5개 이상인 날만)의 평균을 뺀다. 그 날짜 행만 본다."""
    sec = SEC["code"][: x.shape[0]]
    out = np.full(x.shape, np.nan, dtype=F32)
    ns = SEC["n"]
    for i in range(x.shape[0]):
        xi = x[i]
        k = np.isfinite(xi) & (sec[i] >= 0)
        if k.sum() < 5:
            continue
        c = sec[i][k]
        s, n = np.bincount(c, weights=xi[k].astype(np.float64), minlength=ns), np.bincount(c, minlength=ns)
        out[i, k] = (xi[k] - (s / np.maximum(n, 1))[c]).astype(F32)
    return out


def metrics_ic(panel, S, months, cfg_p):
    """탐색 점수 — 전 종목(그 달 멤버) 순위 IC 의 평균 ÷ 표준편차 × √12. 엔진이 읽는 이름(alpha_ir)에 싣는다."""
    el = panel.elig[panel.me_idx[months]]
    s = np.where(el, S[months], np.nan)
    r = np.where(el, panel.fwd_ret[months], np.nan)
    ic = GF.spearman_rows(s, r)
    ne = el.sum(1)
    cov = np.where(ne > 0, np.isfinite(s).sum(1) / np.maximum(ne, 1), np.nan)
    icf = ic[np.isfinite(ic)]
    out = {"n_months": int(len(icf)), "coverage": float(np.nanmean(cov)) if np.isfinite(cov).any() else 0.0,
           "hold_hash": hashlib.sha1(np.round(np.nan_to_num(ic, nan=9.0), 4).astype(np.float32).tobytes()).hexdigest()[:16]}
    if len(icf) >= 12 and icf.std(ddof=1) > 0:
        out.update(rank_ic_mean=float(icf.mean()), rank_ic_t=float(icf.mean() / icf.std(ddof=1) * np.sqrt(len(icf))),
                   alpha_ir=float(icf.mean() / icf.std(ddof=1) * np.sqrt(12.0)))
    else:
        out.update(rank_ic_mean=np.nan, rank_ic_t=np.nan, alpha_ir=np.nan)
    return out


class Panel3(GD.Panel):
    """2판 패널과 같은 모양. 표적(다음 달 수익)은 공통 틀의 값을 쓰고, 자를 때는 보유월이 자른 끝 안에서 끝난 달만 남긴다."""

    def slice_to(self, end_date):
        end = np.datetime64(pd.Timestamp(end_date).date(), "D")
        t = int(np.searchsorted(self.dates, end, side="right"))
        keep = self.me_idx < t
        p = Panel3(self.dates[:t], self.tickers, {k: v[:t] for k, v in self.fields.items()}, self.elig[:t], self.me_idx[keep], self.me_dates[keep],
                   None, None, None, None, {k: v[keep] for k, v in self.std_factors.items()}, dict(self.meta))
        attach(p, t)
        return p


def attach(p, t):
    m = len(p.me_idx)
    ok = p.meta["_hold_ok"][:m] & (p.meta["_hold_end"][:m] < t)
    p.fwd_ret = np.where(ok[:, None], p.meta["_fwd"][:m], np.nan).astype(F32)
    p.fwd_valid = ok
    p.bm_fwd, p.rf_fwd = np.zeros(m), np.zeros(m)


def load_panel():
    d = ac.out("_scratch", "gp_panel")
    meta = ac.read_json(d + "/panel_meta.json")
    if not meta:
        raise RuntimeError("[aif] 일별 단말 패널이 없다 — py/aif_gp_panel.py 를 먼저 돌린다")
    L = lambda n, mm=True: np.load(d + "/%s.npy" % n, mmap_mode="r" if mm else None)   # noqa: E731
    dates, tick, me_idx = L("dates", False), L("tickers", False).astype(str), L("me_idx", False)
    fields = {k: L(k) for k in meta["fields"]}
    p = Panel3(dates, tick, fields, L("elig"), me_idx, dates[me_idx], None, None, None, None, {},
               {"_fwd": L("fwd_ret", False), "_hold_end": L("hold_end", False), "_hold_ok": L("hold_ok", False), "store_dir": d})
    attach(p, len(dates))
    p.std_factors = GD.std_factors(p)
    SEC["code"], SEC["n"] = L("sector"), len(meta["sector_names"])
    return p, meta


def make_cfg(meta, smoke):
    cfg = GD.load_cfg()
    G = cfg["grammar"]
    fr = ["fr_" + k for k in cfg["data"]["fund_ratios"]]
    miss = [k for k in fr if k not in meta["fields"]]
    if miss:
        raise RuntimeError("[aif] 패널에 없는 재무 비율 단말: %s" % miss)
    G["terminals_log"] = [k for k in meta["fields"] if not k.startswith("fr_")]
    G["unary"] = list(G["unary"]) + ["cs_sec_demean"]
    G["degenerate"]["row_constant_terminal"] = list(meta["row_constant"])
    O.OPS["cs_sec_demean"], O.ARITY["cs_sec_demean"] = op_cs_sec_demean, 1
    O.configure(G)
    GE.metrics = metrics_ic                                     # 탐색 점수 교체(2판 = 상위 25종 알파 IR)
    cfg["fitness"]["objective"] = "rank_ic_ir(전 종목 순위 IC 평균 ÷ 표준편차 × √12)"
    if smoke:
        cfg["evolution"].update(population=40, generations=2, hall_of_fame=10)
        cfg["walkforward"].update(first_evolution_year_end=2008, last_evolution_year_end=2009)
    return cfg


def describe(e):
    W = {"ts_mean": "평균", "ts_std": "변동성", "ts_rank": "시계열 순위", "ts_min": "최저", "ts_max": "최고", "ts_delta": "변화", "ts_delay": "지연",
         "ts_decay_linear": "선형 감쇠 평균", "ts_corr": "상관", "ts_cov": "공분산"}
    U = {"neg": "−", "abs": "|·|", "slog": "로그", "ssqrt": "제곱근", "cs_rank": "단면 순위", "cs_zscore": "단면 z", "cs_sec_demean": "업종 평균 차감"}
    B = {"add": "+", "sub": "−", "mul": "×", "div": "÷"}

    def r(x):
        if isinstance(x, tuple):
            op = x[0]
            if op in W:
                return "%s일 %s[%s]" % (x[-1], W[op], ", ".join(r(c) for c in x[1:-1]))
            if op in U:
                return "%s(%s)" % (U[op], r(x[1]))
            return "(%s %s %s)" % (r(x[1]), B[op], r(x[2]))
        return str(x).replace("fr_", "재무비율:").replace("fl_", "수급:").replace("mc_", "거시:")
    return r(e)


def run_variant(cfg, full, variant, vcfg, run_dir, years, unit0):
    wf = cfg["walkforward"]
    fs = cfg["data"]["fitness_start"]
    inherited, tabs, sel_rows = [], [], []
    with open(run_dir + "/trial_ledger_%s.jsonl" % variant, "a", encoding="utf-8") as led:
        for n, Y in enumerate(years):
            ck = "%s/%s_%d.json" % (run_dir, variant, Y)
            tabp = "%s/%s_%d_tab.parquet" % (run_dir, variant, Y + 1)
            z = ac.read_json(ck)
            if z and z.get("version") == VERSION:
                inherited = [GR.parse(s) for s in z["inherited"]]
                sel_rows += z["rows"]
                if os.path.exists(tabp):
                    tabs.append(pd.read_parquet(tabp))
                ac.stage_unit(unit0 + n + 1, "%s %d년 진화 — 저장분 사용" % (variant, Y))
                continue
            t0 = time.perf_counter()
            pw = full.slice_to("%d-12-31" % Y)
            ws = fs if vcfg["window"] == "expanding" else max("%d-01-01" % (Y - vcfg["years"] + 1), fs)
            tm, vm = GF.month_sets(pw, fs, ws, wf["val_months"], wf["embargo_months"])
            tag = {"variant": variant, "evo_year_end": Y, "train_from": str(pw.me_dates[tm[0]]), "train_to": str(pw.me_dates[tm[-1]]),
                   "val_from": str(pw.me_dates[vm[0]]), "val_to": str(pw.me_dates[vm[-1]])}
            evo = GE.Evolution(cfg, pw, tm, vm, led, tag, dict(cfg["evolution"]), seed=cfg["evolution"]["seed"] + Y, cache_mb=cfg["resources"]["subtree_cache_mb"])
            hof = evo.run(inherited)
            chosen, n_cand = GR.select(evo, cfg)
            rows = [{"variant": variant, "year_selected": Y, "used_year": Y + 1, "pick": j + 1, "formula": r["expr"], "describe": describe(GR.parse(r["expr"])),
                     "nodes": r["nodes"], "train_ic_ir": round(r["train"]["alpha_ir"], 3), "val_ic_ir": round(r["val"]["alpha_ir"], 3),
                     "train_ic_mean": round(r["train"]["rank_ic_mean"], 4), "std_corr_max": round(r["std_corr_max"], 3), "hash": r["hash"]}
                    for j, r in enumerate(chosen)]
            inherited = [GR.parse(r["expr"]) for r in chosen] + [GE.to_tuple(h_) for h_ in hof]
            inherited = [e for e in inherited if isinstance(e, tuple)]
            if Y + 1 <= int(str(full.dates[-1])[:4]):
                tab = GR.apply_year(cfg, full, [(r["hash"], GR.parse(r["expr"])) for r in chosen], Y + 1, run_dir, variant)
                if tab is not None:
                    ac.write_atomic(tabp, lambda p, tab=tab: tab.to_parquet(p, index=False))
                    tabs.append(tab)
            ac.write_json({"version": VERSION, "variant": variant, "year": Y, "rows": rows, "inherited": [O.to_str(e) for e in inherited],
                           "n_unique": len(evo.memo), "n_seen": evo.n_seen, "n_candidates": n_cand, "seconds": round(time.perf_counter() - t0, 1)}, ck)
            sel_rows += rows
            ac.log("%s %d년 진화 — 고유 수식 %d · 후보 %d · 고름 %d · %.0f초", variant, Y, len(evo.memo), n_cand, len(chosen), time.perf_counter() - t0)
            ac.stage_unit(unit0 + n + 1, "%s %d년 진화 끝" % (variant, Y))
            del evo, pw
    return tabs, sel_rows


def export(f, tabs, variant, n_top):
    """2판 형식의 긴 표 → 이 연구의 팩터 파일(합성 + 해마다 k 번째로 고른 식을 이어 붙인 것)."""
    df = pd.concat(tabs, ignore_index=True)
    out = []
    fac_dir = ac.out(ac.smoke_name("factors"))
    os.makedirs(fac_dir, exist_ok=True)

    def save(name, g, desc):
        S = np.full((f.ns, f.nt), np.nan, dtype=F32)
        si = np.searchsorted(f.sig_dates, g["Date"].to_numpy().astype("datetime64[D]"))
        ti = f.ticker_index(g["Ticker"].astype(str).to_list())
        ok = (si < f.ns) & (ti >= 0)
        ok[ok] &= f.sig_dates[si[ok]] == g["Date"].to_numpy().astype("datetime64[D]")[ok]
        S[si[ok], ti[ok]] = g["Raw_Value"].to_numpy(dtype=F32)[ok]
        p = fac_dir + "/%s.parquet" % name
        ac.save_factor_panel(p, name, S, f)
        out.append({"id": name, "path": p, "direction": 1, "method": "수식 탐색 3판", "desc": desc})

    comp = df[df["Factor_Name"] == "GPA_%s" % variant]
    save("GP3_%s" % variant, comp, "해마다 고른 수식 5개의 순위 평균(%s)" % ("확장 창" if variant == "EXP" else "고정 8년 창"))
    ind = df[df["Factor_Name"] != "GPA_%s" % variant].copy()
    ind["pick"] = ind["Factor_Name"].str.split("_").str[3].astype(int)       # GPA_<변형>_<해>_<순번>_<해시>
    for k in range(1, n_top + 1):
        g = ind[ind["pick"] == k]
        if len(g):
            save("GP3_%s_TOP%d" % (variant, k), g, "해마다 %d번째로 고른 수식(식은 해마다 바뀐다 · %s)" % (k, variant))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--smoke", action="store_true")
    a = ap.parse_args()
    ac.SMOKE["on"] = a.smoke
    ac.low_priority()
    f = ac.Frame()
    full, meta = load_panel()
    cfg = make_cfg(meta, a.smoke)
    run_dir = ac.out(ac.smoke_name("gp3"))
    os.makedirs(run_dir, exist_ok=True)
    wf = cfg["walkforward"]
    years = list(range(wf["first_evolution_year_end"], wf["last_evolution_year_end"] + 1))
    variants = {"EXP": wf["variants"]["EXP"]} if a.smoke else dict(wf["variants"])
    ac.stage_begin("gp_v3", len(years) * len(variants), "진화", 0.03, 0.9)
    ac.log("패널 — 날짜 %d · 종목 %d · 단말 %d개 · 월말 %d · 변형 %s · 해 %d~%d · 개체 %d × 세대 %d", len(full.dates), len(full.tickers), len(meta["fields"]),
           len(full.me_idx), "/".join(variants), years[0], years[-1], cfg["evolution"]["population"], cfg["evolution"]["generations"])
    manifest, all_rows, u0 = [], [], 0
    for v, vc in variants.items():
        tabs, rows = run_variant(cfg, full, v, vc, run_dir, years, u0)
        u0 += len(years)
        all_rows += rows
        if tabs:
            manifest += export(f, tabs, v, 5 if v == "EXP" else 0)
    res_dir = ac.results(ac.smoke_name("stage3_gp"))
    os.makedirs(res_dir, exist_ok=True)
    if all_rows:
        pd.DataFrame(all_rows).to_csv(res_dir + "/selected_formulas.csv", index=False, encoding="utf-8-sig")
    ac.write_json({"at": ac._now(), "stage": "gp_v3", "factors": manifest, "terminals": meta["fields"],
                   "params": {"evolution": cfg["evolution"], "walkforward": {k: v for k, v in wf.items() if not k.startswith("_")}, "selection": cfg["selection"],
                              "fitness": cfg["fitness"], "_source": "2판 설정(gp_config.json)을 그대로 쓰고 단말 · 업종 중립 연산자 · 탐색 점수만 바꿨다"}},
                  ac.out(ac.smoke_name("manifest_gp") + ".json"))
    ac.log("끝 — 팩터 %d개 · 고른 식 %d줄", len(manifest), len(all_rows))
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
