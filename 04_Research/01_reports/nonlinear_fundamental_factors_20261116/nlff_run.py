"""nlff_run.py — 비선형 재무 팩터(NLFF) 걸어가는 AutoML 학습 · 월말 팩터 산출.

  .venv_qvest_ml/Scripts/python.exe nlff_run.py --smoke                       # 짧은 스모크(설정 smoke 절)
  .venv_qvest_ml/Scripts/python.exe nlff_run.py --start 2003-01 --end 2026-10 --workers 4 --budget 60

출력 = .cache/nl_fundamental_factors/[smoke/]NLFF_<T>.parquet (Date · Ticker · Factor_Name · Raw_Value) + 실행 기록 json.
성과 지표(IC · 수익률)는 계산하지 않는다 — 측정은 시스템 표준 계약이 한다.
"""
from __future__ import annotations

import argparse
import os
import sys
import time

_ap = argparse.ArgumentParser()
_ap.add_argument("--start"); _ap.add_argument("--end")
_ap.add_argument("--workers", type=int, default=4)
_ap.add_argument("--budget", type=int, default=None, help="FLAML 시행 수(max_iter) — 기본 = 설정 automl.max_iter(스모크 = smoke.max_iter)")
_ap.add_argument("--targets", default="earn,val,dist,ret")
_ap.add_argument("--smoke", action="store_true")
_ap.add_argument("--history", default=None, help="학습 이력 시작 YYYY-MM(기본 = 측정 축 시작 · 스모크 = start − smoke.history_months)")
_ap.add_argument("--no-linear", action="store_true")
_ap.add_argument("--engine", default="flaml",
                 help="flaml | autosklearn | tpot | all | 쉼표 목록 — 엔진마다 같은 행렬 · 표적 · 시간순 분할(설정 engines 절)")
ARGS = _ap.parse_args()
if ARGS.workers < 1 or ARGS.workers > 4:
    sys.exit("[nlff] --workers 는 1~4(같은 PC 재빌드 보호 · 설정 automl.max_workers)")
for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "LOKY_MAX_CPU_COUNT"):
    os.environ[_v] = str(ARGS.workers)

import json  # noqa: E402
import ctypes  # noqa: E402

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

import nlff_data as D  # noqa: E402
import nlff_automl as A  # noqa: E402


def peak_rss_gb() -> float:
    """Windows 프로세스 최대 작업 집합(GB) — K32GetProcessMemoryInfo(PROCESS_MEMORY_COUNTERS)."""
    try:
        from ctypes import wintypes

        class PMC(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] +                        [(n, ctypes.c_size_t) for n in ("PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                                                        "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage",
                                                        "PagefileUsage", "PeakPagefileUsage")]
        k = ctypes.WinDLL("kernel32", use_last_error=True)
        k.GetCurrentProcess.restype = wintypes.HANDLE
        k.K32GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(PMC), wintypes.DWORD]
        k.K32GetProcessMemoryInfo.restype = wintypes.BOOL
        c = PMC(); c.cb = ctypes.sizeof(PMC)
        if not k.K32GetProcessMemoryInfo(k.GetCurrentProcess(), ctypes.byref(c), c.cb):
            return float("nan")
        return c.PeakWorkingSetSize / 1e9
    except Exception:
        return float("nan")


def ym(d) -> np.ndarray:
    s = pd.DatetimeIndex(d)
    return (s.year * 12 + s.month).to_numpy()


def shift_months(ymstr: str, k: int) -> str:
    t = pd.Period(ymstr, "M") + k
    return f"{t.year:04d}-{t.month:02d}"


def outlier_selftest(prepare, ri, months, Xraw, feats, X, yraw, task, ac, budget, P_base, factor=1e6, margin=0.01):
    """극단치 자가 시험(양성 대조 1건 · 스모크 · FLAML): 한 종목의 원 입력 · 원 표적을 factor 배로 키운 뒤 같은 절차로 다시 만든 예측에서
    다른 종목들의 예측 순위가 얼마나 바뀌는지 잰다(날짜별 단면 Spearman — 예측끼리의 일치도이지 성과 지표가 아니다).
    모델 설정은 원 자료 탐색 결과로 고정(자료 효과만 분리). 대조 팔 = 극단치 제어를 끈 판(원값 입력 + 원값 표적)."""
    from scipy.stats import spearmanr
    dts = X["Date"].to_numpy().astype("datetime64[D]")
    tick = X["Ticker"].to_numpy()
    idx, pidx = P_base["idx"], P_base["pidx"]
    cand = pd.Series(tick[idx]).value_counts()
    cand = [t for t in cand.index if t in set(tick[pidx])]
    k = cand[0]
    mask = tick == k
    Xi = Xraw.copy(); Xi[mask] *= np.float32(factor)
    yi = yraw.copy(); yi[mask] *= factor

    def ranked(M):
        R = D.rank_centered(pd.DataFrame(M, columns=feats).assign(Date=X["Date"].to_numpy()), feats)
        return R.to_numpy(np.float32), R.isna().mean(axis=1).astype(np.float32).to_numpy()
    Xm0, ms0 = ranked(Xraw); Xm1, ms1 = ranked(Xi)
    msr = np.isnan(Xraw).mean(axis=1).astype(np.float32)
    members = A.fit_refit(task, P_base["Xtr"], P_base["ytr"], P_base["Xva"], P_base["yva"], ac, budget, 1, int(ac["seed"]), {},
                          dates_va=P_base["dva"])

    def pred(P):
        return A.predict_ens(A.refit_models(task, members, P["Xwin"], P["yall"], 1), P["Xp"], task)

    def agree(pa, pb):
        other = tick[pidx] != k
        out = []
        for d in np.unique(dts[pidx]):
            m = other & (dts[pidx] == d)
            out.append(float(spearmanr(pa[m], pb[m]).correlation))
        return round(min(out), 6), round(float(np.mean(out)), 6)
    P0 = prepare(ri, months, Xm0, ms0, yraw)
    rk = bool(np.array_equal(P0["Xwin"], P_base["Xwin"]) and np.array_equal(P0["Xp"], P_base["Xp"]))   # 재구성 = 본 실행 설계 행렬(같음 단정)
    on0 = pred(P0); on1 = pred(prepare(ri, months, Xm1, ms1, yi))
    off0 = pred(prepare(ri, months, Xraw, msr, yraw, rank_target=False)); off1 = pred(prepare(ri, months, Xi, msr, yi, rank_target=False))
    on_min, on_mean = agree(on0, on1); off_min, off_mean = agree(off0, off1)
    # 진단 팔(11-16 첫 스모크 뒤 추가 · 판정 문턱은 바꾸지 않음): 그 종목을 표본에서 아예 뺐을 때의 일치도 = 종목 하나가 바뀔 때의 기본 민감도
    Xd = Xraw.copy(); Xd[mask] = np.nan; yd = yraw.copy(); yd[mask] = np.nan
    Xmd, msd = ranked(Xd)
    del_min, del_mean = agree(on0, pred(prepare(ri, months, Xmd, msd, yd)))
    return {"ticker": str(k), "factor": factor, "n_rows_injected": int(mask.sum()), "target": "earn", "refit_date": str(P_base["Rd"]),
            "control_on_spearman_min_mean": [on_min, on_mean], "control_off_spearman_min_mean": [off_min, off_mean],
            "diag_drop_ticker_spearman_min_mean": [del_min, del_mean],
            "rebuild_equals_main_design": rk,
            # 판정 = 상대 기준(도훈 11-16 '권장안대로 진행'): 주입 일치도(최소) ≥ 종목 빼기 일치도(최소) − margin
            "rule": f"control_on_min >= drop_ticker_min - {margin}", "margin": margin,
            "pass": bool(on_min >= del_min - margin and rk)}


def main():
    t0 = time.time()
    cfg = D.load_cfg()
    ax = D.axis_params(cfg)
    sm = cfg["smoke"]; ac = cfg["automl"]; oc = cfg["output"]
    A.SEED = int(ac["seed"]); A.FIXED_HP = A.fixed_hp()
    A.IC_MIN_N = int(ac["selection_metric"]["min_names_per_month"])
    start = ARGS.start or (sm["start"] if ARGS.smoke else ax["start"][:7])
    end = ARGS.end or (sm["end"] if ARGS.smoke else None)
    if end is None:
        sys.exit("[nlff] --end 필요")
    hist = max(shift_months(start, -int(sm["history_months"])), ax["start"][:7]) if ARGS.smoke else ax["start"][:7]
    if ARGS.history:
        hist = max(ARGS.history, ax["start"][:7])
    budget = ARGS.budget or (sm["max_iter"] if ARGS.smoke else ac["max_iter"])
    targets = [t for t in ARGS.targets.split(",") if t]
    engines = list(A.ENGINES) if ARGS.engine == "all" else [e for e in ARGS.engine.split(",") if e]
    bad = [e for e in engines if e not in A.ENGINES]
    if bad:
        sys.exit(f"[nlff] 모르는 엔진 {bad} — {A.ENGINES}")
    out_root = D.p(cfg["paths"]["out_dir"]) / ("smoke" if ARGS.smoke else "")
    out_dirs = {e: out_root / e for e in engines}
    out_dirs["linear"] = out_root / "linear"            # 선형 대조 = 엔진 무관 · 한 번만
    for d in out_dirs.values():
        d.mkdir(parents=True, exist_ok=True)
    xfer_root = D.p(cfg["paths"]["out_dir"]) / "_xfer"
    try:
        fl_ver = __import__("flaml").__version__
    except Exception:
        fl_ver = None
        if "flaml" in engines:
            sys.exit("[nlff] 이 파이썬에 flaml 이 없다 — .venv_nlff_automl 또는 .venv_qvest_ml 로 실행")
    log = {"args": vars(ARGS), "start": start, "end": end, "history_start": hist, "budget_max_iter_flaml": budget,
           "engines": engines, "engine_cfg": {e: cfg["engines"][e] for e in engines},
           "epoch": ax["epoch"], "flaml_version": fl_ver, "python": sys.version.split()[0], "refits": [], "timing": {}}
    print(f"[nlff] {start}~{end} · 학습 이력 {hist}~ · 엔진 {engines} · FLAML 시행 {budget} · 워커 {ARGS.workers} · 표적 {targets}", flush=True)

    # ---------------------------------------------------------------- 입력 패널
    me = D.month_ends(cfg, hist, end)
    spec = D.feature_spec(cfg)
    tickers = D.all_tickers(cfg)
    if ARGS.smoke and int(sm["tickers_limit"]) > 0:
        tickers = tickers[: int(sm["tickers_limit"])]
    parts = []
    for i in range(0, len(tickers), 400):
        parts.append(D.build_chunk(cfg, spec, tickers[i:i + 400], me))
    F = pd.concat(parts, ignore_index=True); del parts
    F["Date"] = F["Date"].astype("datetime64[s]")
    log["timing"]["features_s"] = round(time.time() - t0, 1)
    print(f"[nlff] 입력 {len(F):,}행 · {log['timing']['features_s']}s · 최대 메모리 {peak_rss_gb():.2f} GB", flush=True)
    if ARGS.smoke:   # 미래 행 잘라내기 불변성(입력 PIT 자가 시험)
        tk = tickers[: int(sm["pit_selftest_tickers"])]
        sub = F[F["Ticker"].isin(tk)]
        log["pit_selftest_features"] = D.pit_selftest_features(cfg, spec, tk, me, sub, n_months=2)
        print(f"[nlff] 입력 PIT 자가 시험 통과 {log['pit_selftest_features']}", flush=True)
    t1 = time.time()
    PP = D.price_panel(cfg, me, ax)
    PP["Date"] = PP["Date"].astype("datetime64[s]")
    log["timing"]["price_panel_s"] = round(time.time() - t1, 1)
    X = PP.merge(F, on=["Date", "Ticker"], how="left"); del F, PP     # 위생 멤버 행만
    feats = [c for c in spec["features"] if c in X.columns]
    Xraw = X[feats].to_numpy(np.float32) if ARGS.smoke else None       # 극단치 자가 시험용 원값(스모크만)
    R = D.rank_centered(X, feats)                                       # 월별 단면 안에서만 · 순위 = 극단치 제어(README §14)
    miss = R.isna().mean(axis=1).astype(np.float32).to_numpy()
    Xmat = R.to_numpy(np.float32); del R
    for c in feats:
        del X[c]
    X["Date"] = X["Date"].astype("datetime64[s]")
    dts = X["Date"].to_numpy().astype("datetime64[D]")
    log["n_rows_panel"] = int(len(X)); log["n_features"] = len(feats) + 1
    print(f"[nlff] 패널 {len(X):,}행 × 입력 {len(feats)}+1 · {time.time()-t0:.0f}s · 최대 메모리 {peak_rss_gb():.2f} GB", flush=True)

    # ---------------------------------------------------------------- 표적
    Y, AV = {}, {}
    if "earn" in targets:
        # 순위 표적(rank_reg)은 여기서 순위를 매기지 않는다 — 재학습마다 '그때 실현된 표본' 안에서만 순위(재학습 루프의 rank_reg 절)
        Y["earn"] = X["y_earn"].where(X["avail_earn"] >= 0).to_numpy(np.float64)
        AV["earn"] = np.where(X["avail_earn"].fillna(-1).to_numpy() >= 0, X["avail_earn"].fillna(0).to_numpy().astype("int64"), -1).astype("datetime64[D]")
    if "ret" in targets:
        Y["ret"] = X["y_ret"].to_numpy(np.float64)
        AV["ret"] = X["avail_h"].to_numpy().astype("datetime64[D]")
    if "dist" in targets:
        Y["dist"] = X["y_dist"].to_numpy(np.float64)
        AV["dist"] = X["avail_h"].to_numpy().astype("datetime64[D]")
    if "val" in targets:
        # 극단치 제어(README §14): 같은 날짜 단면 1% / 99% 윈저 → 단면 평균 차감(전 표본 분위 없음)
        wl, wh = cfg["targets"]["val"]["winsor_q"]
        ls = X["logsize"]; gq = ls.groupby(X["Date"])
        lsw = ls.clip(gq.transform(lambda v: v.quantile(wl)), gq.transform(lambda v: v.quantile(wh)))
        Y["val"] = (lsw - lsw.groupby(X["Date"]).transform("mean")).to_numpy(np.float64)
        AV["val"] = dts.copy()                                          # 지평 0: 시가총액은 그날 안다
    # 표적 방향 단정: 지평 > 0 표적의 실현일은 결정일보다 뒤
    for k in ("earn", "ret", "dist"):
        if k in Y:
            ok = np.isfinite(Y[k]) & ~np.isnat(AV[k])
            if (AV[k][ok] <= dts[ok]).any():
                raise AssertionError(f"[nlff PIT] {k} 표적 실현일 <= 결정일")

    ymx = ym(dts)
    out_mask_all = (dts >= np.datetime64(pd.Timestamp(start).date())) & (ymx <= ym([pd.Timestamp(end) + pd.offsets.MonthEnd(0)])[0])
    folds = D.ticker_fold(X["Ticker"], int(cfg["targets"]["val"]["group_folds"]), salt="nlff") if "val" in targets else None
    rows_out = {e: [] for e in engines}; rows_out["linear"] = []
    failed = {}                                                        # 엔진 실패 = 그 엔진 결과 전부 버림(부분 산출 없음)
    use_lin = cfg["linear_control"]["enabled"] and not ARGS.no_linear

    # ---------------------------------------------------------------- 표적별 걸어가는 학습
    for T in targets:
        tc = cfg["targets"][T]
        task = "classification" if tc["kind"] == "binary" else "regression"
        every, rmon = int(tc["refit_every_months"]), int(tc["refit_month"])
        me_ym = ym(me)
        refit_idx = [i for i in range(len(me)) if (pd.Timestamp(me[i]).month - rmon) % every == 0]
        out_months = sorted(set(dts[out_mask_all]))
        assign = {}
        for t in out_months:
            cand = [i for i in refit_idx if me[i] <= t]
            if cand:
                assign.setdefault(cand[-1], []).append(t)
        min_tr = int(tc["min_train_months"])
        if ARGS.smoke:
            min_tr = min(min_tr, int(sm["min_train_months_cap"]))
        av = AV[T]

        def prepare(ri, months, Xm, ms, yraw, rank_target=True):
            """재학습 1회의 설계 행렬(엔진 · 선형 대조 · 자가 시험 공통). 반환 = dict 또는 건너뜀 사유 문자열."""
            y = yraw
            Rd = me[ri]
            cut = np.datetime64((pd.Timestamp(Rd) - pd.DateOffset(months=int(oc["embargo_months"]))).date())
            base = np.isfinite(y) & ~np.isnat(av) & (av <= cut) & (dts <= cut)
            if tc["window"] == "rolling":
                lo = np.datetime64((pd.Timestamp(cut) - pd.DateOffset(months=int(tc["window_months"]))).date())
                base &= dts > lo
            base &= ((ymx - me_ym[ri]) % int(tc["sample_every_months"])) == 0
            idx = np.flatnonzero(base)
            nd = len(np.unique(dts[idx]))
            if nd < min_tr:
                return f"표본월 {nd} < 하한 {min_tr}"
            if tc["kind"] == "rank_reg" and rank_target:
                # 표적 단면 순위 → (−1, 1): 같은 표본월 안에서, 재학습일 − 엠바고까지 실현된 표본끼리만(아직 실현 안 된 동료 값이 순위에 안 섞인다)
                # = 극단치 제어(README §14 — earn · ret 는 순위 표적)
                yr = D.rank_centered(pd.DataFrame({"Date": dts[idx], "_y": y[idx]}), ["_y"])["_y"].to_numpy(np.float64)
                y = np.full(len(yraw), np.nan); y[idx] = yr
            # 입력 범위(as-of): 학습 창 표본의 결측 아닌 비율 >= 문턱
            cov = 1.0 - np.isnan(Xm[idx]).mean(axis=0)
            cols = np.flatnonzero(cov >= float(cfg["features"]["min_coverage_asof"]))

            def mk(ii):
                Z = np.nan_to_num(Xm[np.ix_(ii, cols)], nan=float(ac["missing_fill"]))
                return np.hstack([Z, ms[ii, None]]).astype(np.float32)

            tr_m, va_m = A.time_split(dts[idx], av[idx], float(cfg["validation"]["frac"]), cut)
            if tr_m is None or tr_m.sum() == 0 or (task == "classification" and len(np.unique(y[idx][tr_m])) < 2):
                return "정화 뒤 학습 부분이 비거나 한 범주"
            itr, iva = idx[tr_m], idx[va_m]
            ytr, yva = y[itr], y[iva]
            if task == "classification":
                ytr, yva = ytr.astype(int), yva.astype(int)
            pidx = np.flatnonzero(np.isin(dts, np.array(months, dtype="datetime64[D]")))
            assert av[idx].max() <= cut and cut < min(months), "[nlff PIT] 학습 표적 실현일이 예측일 − 엠바고 뒤"
            yall = y[idx].astype(int) if task == "classification" else y[idx]
            return {"Rd": Rd, "cut": cut, "y": y, "idx": idx, "nd": nd, "cols": cols, "itr": itr, "iva": iva, "ytr": ytr, "yva": yva,
                    "pidx": pidx, "yall": yall, "Xtr": mk(itr), "Xva": mk(iva), "Xwin": mk(idx), "Xp": mk(pidx),
                    "dva": dts[iva]}

        for ri, months in sorted(assign.items()):
            tR = time.time()
            Rd = me[ri]
            cut = np.datetime64((pd.Timestamp(Rd) - pd.DateOffset(months=int(oc["embargo_months"]))).date())
            rec = {"target": T, "refit_date": str(Rd), "cut": str(cut), "predict_months": [str(m) for m in months]}
            P_ = prepare(ri, months, Xmat, miss, Y[T])
            if isinstance(P_, str):
                rec["skipped"] = P_; log["refits"].append(rec)
                print(f"[nlff] {T} {Rd} 건너뜀 — {rec['skipped']}", flush=True)
                continue
            y, idx, nd, cols, itr, iva = P_["y"], P_["idx"], P_["nd"], P_["cols"], P_["itr"], P_["iva"]
            ytr, yva, pidx, yall, dva = P_["ytr"], P_["yva"], P_["pidx"], P_["yall"], P_["dva"]
            Xtr_m, Xva_m, Xwin_m, Xp_m = P_["Xtr"], P_["Xva"], P_["Xwin"], P_["Xp"]
            if ARGS.smoke and T in ("earn",) and "outlier_selftest" not in log and fl_ver is not None:
                log["outlier_selftest"] = outlier_selftest(prepare, ri, months, Xraw, feats, X, Y[T], task, ac, budget, P_,
                                                  margin=float(cfg["outlier_control"]["selftest_margin"]))
                print(f"[nlff] 극단치 자가 시험 {log['outlier_selftest']}", flush=True)
            if T == "val":
                wfold, pfold = folds[idx].astype(np.int64), folds[pidx].astype(np.int64)
            else:
                wfold, pfold = np.full(len(idx), -1, np.int64), np.full(len(pidx), -1, np.int64)
            name = oc["factor_names"][T]
            actual = y[pidx]
            rec["engines"] = {}

            def emit(key, raw, fname):
                fr = pd.DataFrame({"Date": dts[pidx].astype("datetime64[s]"), "Ticker": X["Ticker"].to_numpy()[pidx],
                                   "Factor_Name": fname, "Raw_Value": raw})
                rows_out[key].append(fr[np.isfinite(fr["Raw_Value"])])

            for E in engines:
                if E in failed or T not in cfg["engines"][E]["targets"]:     # 엔진별 실행 표적(설정 engines.<e>.targets)
                    continue
                er = {}; tE = time.time()
                try:
                    if E == "flaml":
                        members = A.fit_refit(task, Xtr_m, ytr, Xva_m, yva, ac, budget, ARGS.workers, int(ac["seed"]), er, dates_va=dva)
                        if T == "val":   # 종목 묶음 교차 적합(자기 시가총액 기억 차단) — 설정은 같은 탐색 결과 · 적합만 묶음마다
                            pred = np.full(len(pidx), np.nan)
                            for k in np.unique(pfold):
                                keep = wfold != k
                                mods = A.refit_models(task, members, Xwin_m[keep], yall[keep], ARGS.workers)
                                sel = pfold == k
                                pred[sel] = A.predict_ens(mods, Xp_m[sel], task)
                        else:
                            pred = A.predict_ens(A.refit_models(task, members, Xwin_m, yall, ARGS.workers), Xp_m, task)
                    else:
                        pred = A.fit_external(E, task, Xtr_m, ytr, Xva_m, yva, Xwin_m, yall, wfold, Xp_m, pfold,
                                              cfg["engines"], ARGS.smoke, ARGS.workers, int(ac["seed"]),
                                              xfer_root / f"{E}_{T}_{str(Rd)[:10]}", D.HERE, D.ROOT, er, dates_va=dva,
                                              dates_tr=dts[itr])
                    assert len(pred) == len(pidx)
                except Exception as ex:
                    failed[E] = f"{T} {Rd}: {type(ex).__name__}: {str(ex)[:1500]}"
                    er["error"] = failed[E]
                    rec["engines"][E] = er
                    print(f"[nlff] ★{E} 실패 — 이 엔진 결과는 쓰지 않는다: {failed[E][:400]}", flush=True)
                    continue
                emit(E, (pred - actual) if T == "val" else pred, name)     # val = 적정가치 추정 − 실제(저평가 +)
                er["seconds"] = round(time.time() - tE, 1)
                rec["engines"][E] = er
                print(f"[nlff] {T} {Rd} · {E} · 학습 {len(itr):,} 검증 {len(iva):,} · 고른 모델 {er.get('best_estimator')} · "
                      f"앙상블 {er.get('ensemble_weights', er.get('ensemble_members'))} · 시행 {er.get('n_trials')} · {er['seconds']}s"
                      + (f" · 작업기 메모리 {er.get('peak_rss_tree_gb')} GB" if E != "flaml" else ""), flush=True)
            if use_lin:
                lin, linfo = A.fit_linear(task, Xtr_m, ytr, Xva_m, yva, cfg["linear_control"], dates_va=dva)
                if T == "val":
                    from sklearn.linear_model import Ridge
                    predl = np.full(len(pidx), np.nan)
                    for k in np.unique(pfold):
                        keep = wfold != k; sel = pfold == k
                        predl[sel] = Ridge(alpha=linfo["alpha"]).fit(Xwin_m[keep], yall[keep]).predict(Xp_m[sel])
                    rawl = predl - actual
                else:
                    rawl = A.predict_linear(lin, Xp_m, task)
                emit("linear", rawl, name + oc["lin_suffix"])
                rec["linear"] = linfo
            rec.update({"n_train": int(len(itr)), "n_val": int(len(iva)), "n_refit_full": int(len(idx)), "n_sample_months": nd,
                        "n_inputs": int(len(cols) + 1), "n_pred": int(len(pidx)), "seconds": round(time.time() - tR, 1),
                        "peak_rss_gb_driver": round(peak_rss_gb(), 2)})
            log["refits"].append(rec)

    # ---------------------------------------------------------------- 쓰기
    log["failed_engines"] = failed
    log["output_rows"] = {}
    for key, parts in rows_out.items():
        if key in failed or not parts:
            continue
        O = pd.concat(parts, ignore_index=True)
        for fname, g in O.groupby("Factor_Name"):
            g.sort_values(["Date", "Ticker"]).to_parquet(out_dirs[key] / f"{fname}.parquet", index=False)
        log["output_rows"][key] = O.groupby("Factor_Name").size().to_dict()
    log["timing"]["total_s"] = round(time.time() - t0, 1)
    log["peak_rss_gb"] = round(peak_rss_gb(), 2)
    etag = "all" if ARGS.engine == "all" else "-".join(engines)
    ttag = "" if targets == ["earn", "val", "dist", "ret"] else "_" + "-".join(targets)
    tag = f"smoke_{etag}{ttag}" if ARGS.smoke else f"run_{etag}{ttag}_{start}_{end}"
    # 산출 메타(엔진별): 재학습마다 시행 수 · 고른 모델 · auto-sklearn 재적합 대체 경로 여부
    for E in engines:
        if E in failed or E not in log["output_rows"]:
            continue
        meta = {"engine": E, "run_tag": tag, "targets": [t for t in targets if t in cfg["engines"][E]["targets"]],
                "start": start, "end": end, "epoch": ax["epoch"], "written_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "refits": [{"target": r["target"], "refit_date": r["refit_date"],
                            "n_trials": r["engines"][E].get("n_trials"),
                            "best_estimator": r["engines"][E].get("best_estimator"),
                            "refit_fallback": r["engines"][E].get("refit_fallback"),
                            "refit_fallback_reason": r["engines"][E].get("refit_fallback_reason")}
                           for r in log["refits"] if E in r.get("engines", {})]}
        with open(out_dirs[E] / f"NLFF_meta{ttag}.json", "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2, default=str)
    log["refit_fallbacks"] = [{"engine": E, "target": r["target"], "refit_date": r["refit_date"]}
                              for r in log["refits"] for E, er in r.get("engines", {}).items() if er.get("refit_fallback")]
    if log["refit_fallbacks"]:
        print(f"[nlff] ★재적합 대체 경로 {len(log['refit_fallbacks'])}건: {log['refit_fallbacks']}", flush=True)
    with open(D.HERE / f"{tag}_log.json", "w", encoding="utf-8") as f:
        json.dump(log, f, ensure_ascii=False, indent=2, default=str)
    print(f"[nlff] 끝 · {log['timing']['total_s']}s · 드라이버 최대 메모리 {log['peak_rss_gb']} GB · 실패 {failed or '없음'} · 출력 {log['output_rows']}", flush=True)
    return 3 if failed else 0           # 엔진 실패 = 종료 코드 3(run_full.sh 가 그 엔진만 멈춘다)


if __name__ == "__main__":
    sys.exit(main() or 0)
