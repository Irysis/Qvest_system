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


def main():
    t0 = time.time()
    cfg = D.load_cfg()
    ax = D.axis_params(cfg)
    sm = cfg["smoke"]; ac = cfg["automl"]; oc = cfg["output"]
    A.SEED = int(ac["seed"]); A.FIXED_HP = A.fixed_hp()
    start = ARGS.start or (sm["start"] if ARGS.smoke else ax["start"][:7])
    end = ARGS.end or (sm["end"] if ARGS.smoke else None)
    if end is None:
        sys.exit("[nlff] --end 필요")
    hist = max(shift_months(start, -int(sm["history_months"])), ax["start"][:7]) if ARGS.smoke else ax["start"][:7]
    if ARGS.history:
        hist = max(ARGS.history, ax["start"][:7])
    budget = ARGS.budget or (sm["max_iter"] if ARGS.smoke else ac["max_iter"])
    targets = [t for t in ARGS.targets.split(",") if t]
    out_dir = D.p(cfg["paths"]["out_dir"]) / ("smoke" if ARGS.smoke else "")
    out_dir.mkdir(parents=True, exist_ok=True)
    log = {"args": vars(ARGS), "start": start, "end": end, "history_start": hist, "budget_max_iter": budget,
           "epoch": ax["epoch"], "flaml_version": __import__("flaml").__version__, "refits": [], "timing": {}}
    print(f"[nlff] {start}~{end} · 학습 이력 {hist}~ · 시행 {budget} · 워커 {ARGS.workers} · 표적 {targets}", flush=True)

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
    R = D.rank_centered(X, feats)                                       # 월별 단면 안에서만
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
        Y["val"] = (X["logsize"] - X.groupby("Date")["logsize"].transform("mean")).to_numpy(np.float64)
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
    rows_out = []

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
        for ri, months in sorted(assign.items()):
            y = Y[T]
            tR = time.time()
            Rd = me[ri]
            cut = np.datetime64((pd.Timestamp(Rd) - pd.DateOffset(months=int(oc["embargo_months"]))).date())
            rec = {"target": T, "refit_date": str(Rd), "cut": str(cut), "predict_months": [str(m) for m in months]}
            base = np.isfinite(y) & ~np.isnat(av) & (av <= cut) & (dts <= cut)
            if tc["window"] == "rolling":
                lo = np.datetime64((pd.Timestamp(cut) - pd.DateOffset(months=int(tc["window_months"]))).date())
                base &= dts > lo
            base &= ((ymx - me_ym[ri]) % int(tc["sample_every_months"])) == 0
            idx = np.flatnonzero(base)
            nd = len(np.unique(dts[idx]))
            if nd < min_tr:
                rec["skipped"] = f"표본월 {nd} < 하한 {min_tr}"; log["refits"].append(rec)
                print(f"[nlff] {T} {Rd} 건너뜀 — {rec['skipped']}", flush=True)
                continue
            if tc["kind"] == "rank_reg":
                # 표적 단면 순위 → (−1, 1): 같은 표본월 안에서, 재학습일 − 엠바고까지 실현된 표본끼리만(아직 실현 안 된 동료 값이 순위에 안 섞인다)
                yr = D.rank_centered(pd.DataFrame({"Date": dts[idx], "_y": y[idx]}), ["_y"])["_y"].to_numpy(np.float64)
                y = np.full(len(Y[T]), np.nan); y[idx] = yr
            # 입력 범위(as-of): 학습 창 표본의 결측 아닌 비율 >= 문턱
            cov = 1.0 - np.isnan(Xmat[idx]).mean(axis=0)
            cols = np.flatnonzero(cov >= float(cfg["features"]["min_coverage_asof"]))

            def mk(ii):
                Z = np.nan_to_num(Xmat[np.ix_(ii, cols)], nan=float(ac["missing_fill"]))
                return np.hstack([Z, miss[ii, None]]).astype(np.float32)

            tr_m, va_m = A.time_split(dts[idx], av[idx], float(cfg["validation"]["frac"]), cut)
            if tr_m is None or tr_m.sum() == 0 or (task == "classification" and len(np.unique(y[idx][tr_m])) < 2):
                rec["skipped"] = "정화 뒤 학습 부분이 비거나 한 범주"; log["refits"].append(rec)
                print(f"[nlff] {T} {Rd} 건너뜀 — {rec['skipped']}", flush=True)
                continue
            itr, iva = idx[tr_m], idx[va_m]
            ytr, yva = y[itr], y[iva]
            if task == "classification":
                ytr, yva = ytr.astype(int), yva.astype(int)
            members = A.fit_refit(task, mk(itr), ytr, mk(iva), yva, ac, budget, ARGS.workers, int(ac["seed"]), rec)
            if cfg["linear_control"]["enabled"] and not ARGS.no_linear:
                lin, linfo = A.fit_linear(task, mk(itr), ytr, mk(iva), yva, cfg["linear_control"])
            # 예측 대상 행: 이 재학습이 맡은 달 · 단정 = 모든 학습 표적은 예측일 − 엠바고 이전에 실현
            pmask = np.isin(dts, np.array(months, dtype="datetime64[D]"))
            pidx = np.flatnonzero(pmask)
            assert av[idx].max() <= cut and cut < min(months), "[nlff PIT] 학습 표적 실현일이 예측일 − 엠바고 뒤"
            yall = y[idx].astype(int) if task == "classification" else y[idx]
            name = oc["factor_names"][T]
            if T == "val":   # 종목 묶음 교차 적합(자기 시가총액 기억 차단) — 설정은 같은 탐색 결과 · 적합만 묶음마다
                pred = np.full(len(pidx), np.nan); predl = np.full(len(pidx), np.nan)
                for k in np.unique(folds):
                    keep = folds[idx] != k
                    mods = A.refit_models(task, members, mk(idx[keep]), yall[keep], ARGS.workers)
                    sel = folds[pidx] == k
                    if sel.any():
                        pred[sel] = A.predict_ens(mods, mk(pidx[sel]), task)
                    if cfg["linear_control"]["enabled"] and not ARGS.no_linear:
                        from sklearn.linear_model import Ridge
                        lk = Ridge(alpha=linfo["alpha"]).fit(mk(idx[keep]), yall[keep])
                        if sel.any():
                            predl[sel] = lk.predict(mk(pidx[sel]))
                actual = y[pidx]
                raw = pred - actual; rawl = predl - actual                    # 적정가치 추정 − 실제(저평가 +)
            else:
                mods = A.refit_models(task, members, mk(idx), yall, ARGS.workers)
                raw = A.predict_ens(mods, mk(pidx), task)
                rawl = A.predict_linear(lin, mk(pidx), task) if (cfg["linear_control"]["enabled"] and not ARGS.no_linear) else None
            fr = pd.DataFrame({"Date": dts[pidx].astype("datetime64[s]"), "Ticker": X["Ticker"].to_numpy()[pidx],
                               "Factor_Name": name, "Raw_Value": raw})
            rows_out.append(fr[np.isfinite(fr["Raw_Value"])])
            if rawl is not None:
                fl = fr.assign(Factor_Name=name + oc["lin_suffix"], Raw_Value=rawl)
                rows_out.append(fl[np.isfinite(fl["Raw_Value"])])
            rec.update({"n_train": int(len(itr)), "n_val": int(len(iva)), "n_refit_full": int(len(idx)), "n_sample_months": nd,
                        "n_inputs": int(len(cols) + 1), "n_pred": int(len(pidx)), "seconds": round(time.time() - tR, 1),
                        "peak_rss_gb": round(peak_rss_gb(), 2)})
            if cfg["linear_control"]["enabled"] and not ARGS.no_linear:
                rec["linear"] = linfo
            log["refits"].append(rec)
            print(f"[nlff] {T} {Rd} · 학습 {len(itr):,} 검증 {len(iva):,} · 고른 모델 {rec['best_estimator']} · 앙상블 {rec['ensemble_weights']} · "
                  f"{rec['seconds']}s · 최대 메모리 {rec['peak_rss_gb']} GB", flush=True)

    # ---------------------------------------------------------------- 쓰기
    if rows_out:
        O = pd.concat(rows_out, ignore_index=True)
        for fname, g in O.groupby("Factor_Name"):
            g.sort_values(["Date", "Ticker"]).to_parquet(out_dir / f"{fname}.parquet", index=False)
        log["output_rows"] = O.groupby("Factor_Name").size().to_dict()
    log["timing"]["total_s"] = round(time.time() - t0, 1)
    log["peak_rss_gb"] = round(peak_rss_gb(), 2)
    tag = "smoke" if ARGS.smoke else f"run_{start}_{end}"
    with open(D.HERE / f"{tag}_log.json", "w", encoding="utf-8") as f:
        json.dump(log, f, ensure_ascii=False, indent=2, default=str)
    print(f"[nlff] 끝 · {log['timing']['total_s']}s · 최대 메모리 {log['peak_rss_gb']} GB · 출력 {log.get('output_rows')}", flush=True)


if __name__ == "__main__":
    main()
