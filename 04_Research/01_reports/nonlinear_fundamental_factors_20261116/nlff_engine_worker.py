"""nlff_engine_worker.py — 외부 AutoML 엔진(auto-sklearn · TPOT) 재학습 1회분 실행기.

드라이버(nlff_run.py · nlff_automl.fit_external)가 시간순 분할을 끝낸 행렬을 작업 폴더에 .npy 로 쓰면,
이 스크립트가 엔진 전용 환경에서 그 행렬만 읽어
  ① 미리 정한 시간순 분할(PredefinedSplit: 학습 부분 = −1 · 검증 = 0)로 탐색
  ② (auto-sklearn) 내장 앙상블이 그 검증 예측으로만 만들어졌는지 단정
  ③ 고른 모델(앙상블)을 재학습 창 전체로 다시 적합(val 은 종목 묶음마다) → 예측
을 하고 pred.npy · result.json 을 쓴다. 데이터 · 표적 · 분할은 드라이버가 정한다 — 여기서는 아무것도 고르지 않는다.

실행 환경(파이썬 3.9 호환 문법 — auto-sklearn 0.15 는 3.9 전용 판을 쓴다):
  · auto-sklearn : WSL Ubuntu  ~/venvs/nlff_autosklearn/bin/python nlff_engine_worker.py /mnt/g/.../job_dir
  · TPOT         : Windows     .venv_nlff_tpot/Scripts/python.exe nlff_engine_worker.py G:/.../job_dir
"""
from __future__ import annotations

import json
import os
import sys
import threading
import time
import warnings

import numpy as np

# ---------------------------------------------------------------------------------------------- 선택 지표(회귀 = 월별 단면 IC)
# 정의 = nlff_ic.ic_mean(피클 가능한 별도 모듈 · 날짜는 환경 변수 파일 · 길이 단정). 이 폴더를 경로 앞에 둔다(하위 프로세스는 PYTHONPATH 로).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["PYTHONPATH"] = os.path.dirname(os.path.abspath(__file__)) + os.pathsep + os.environ.get("PYTHONPATH", "")
from nlff_ic import ic_mean  # noqa: E402


# ---------------------------------------------------------------------------------------------- 메모리(프로세스 나무 합계 최대)
class PeakMem:
    """psutil 로 자기 + 모든 자식 프로세스 RSS 합을 0.5 초마다 재 최대값을 남긴다(dask · pynisher 자식 포함)."""

    def __init__(self):
        import psutil
        self.p = psutil.Process()
        self.peak = 0
        self._stop = False
        self.t = threading.Thread(target=self._run, daemon=True)
        self.t.start()

    def _run(self):
        while not self._stop:
            try:
                tot = self.p.memory_info().rss
                for c in self.p.children(recursive=True):
                    try:
                        tot += c.memory_info().rss
                    except Exception:
                        pass
                self.peak = max(self.peak, tot)
            except Exception:
                pass
            time.sleep(0.5)

    def stop(self):
        self._stop = True
        return round(self.peak / 1e9, 2)


def load(job_dir, name):
    return np.load(os.path.join(job_dir, name + ".npy"), allow_pickle=False)


def split_obj(n_tr, n_va):
    """미리 정한 시간순 분할 — 행 순서 = [학습 부분(시간순 앞) · 검증(시간순 마지막 20%)]. 드라이버의 time_split 결과 그대로."""
    from sklearn.model_selection import PredefinedSplit
    tf = np.concatenate([np.full(n_tr, -1, dtype=int), np.zeros(n_va, dtype=int)])
    ps = PredefinedSplit(tf)
    sp = list(ps.split())
    # 단정: 분할이 정확히 [0, n_tr) / [n_tr, n_tr + n_va) 하나뿐(무작위 · 다겹 없음)
    assert len(sp) == 1, "[nlff split] 분할이 하나가 아니다"
    tr_i, va_i = sp[0]
    assert np.array_equal(tr_i, np.arange(n_tr)) and np.array_equal(va_i, np.arange(n_tr, n_tr + n_va)), "[nlff split] 시간순 분할 불일치"
    return ps


def pred_of(model, X, task):
    if task == "classification":
        return np.asarray(model.predict_proba(X))[:, 1].astype(np.float64)
    return np.asarray(model.predict(X), np.float64).ravel()


# ---------------------------------------------------------------------------------------------- auto-sklearn
def run_autosklearn(job, Xtr, ytr, Xva, yva, res):
    import autosklearn
    import autosklearn.metrics as M
    from autosklearn.classification import AutoSklearnClassifier
    from autosklearn.regression import AutoSklearnRegressor
    ec = job["engine_cfg"]
    task = job["task"]
    X = np.vstack([Xtr, Xva]); y = np.concatenate([ytr, yva])
    ps = split_obj(len(Xtr), len(Xva))
    metric = M.roc_auc if task == "classification" else M.make_scorer(
        "monthly_spearman_ic", ic_mean, optimum=1.0, worst_possible_result=-1.0, greater_is_better=True)
    cls = AutoSklearnClassifier if task == "classification" else AutoSklearnRegressor
    tmp = os.path.join(os.path.expanduser(ec["tmp_root"]), "%s_%d" % (job["tag"], os.getpid()))
    est = cls(time_left_for_this_task=int(job["time_left_s"]), per_run_time_limit=job.get("per_run_s"),
              initial_configurations_via_metalearning=int(ec["initial_configurations_via_metalearning"]),
              ensemble_nbest=int(ec["ensemble_nbest"]), ensemble_kwargs={"ensemble_size": int(ec["ensemble_size"])},
              seed=int(job["seed"]) % (2 ** 31), memory_limit=int(ec["memory_limit_mb"]), n_jobs=int(job["n_jobs"]),
              resampling_strategy=ps, metric=metric, tmp_folder=tmp, delete_tmp_folder_after_terminate=False,   # 앙상블 표적 단정 뒤 직접 지운다
              smac_scenario_args={"runcount_limit": int(job["max_trials"])},
              # 무작위 행 줄이기(subsample)를 끈다 — 줄이면 미리 정한 분할의 행 번호가 어긋난다 · 정밀도 줄이기만 남김
              dataset_compression={"memory_allocation": 0.1, "methods": ["precision"]})
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        est.fit(X, y)
    am = est.automl_
    # ---- 단정: 내장 앙상블 표적 = 시간순 검증 구간 표적 그대로(순서 · 길이) ----
    tgt = np.asarray(am._backend.load_targets_ensemble()).ravel()
    ok = (len(tgt) == len(yva)) and np.allclose(tgt.astype(np.float64), yva.astype(np.float64))
    res["ensemble_targets_equal_time_val"] = bool(ok)
    if not ok:
        raise AssertionError("[nlff autosklearn] 내장 앙상블 표적이 시간순 검증 구간과 다르다 — 엔진 사용 중단")
    assert am._resampling_strategy is ps, "[nlff autosklearn] 분할 객체가 바뀌었다"
    rh = am.runhistory_
    n_runs = len(rh.data)
    mw = est.get_models_with_weights()
    members = []
    for w, pipe in mw:
        step = pipe.steps[-1][1]
        choice = getattr(step, "choice", None)
        members.append({"weight": round(float(w), 4), "model": type(choice).__name__ if choice is not None else type(step).__name__})
    res.update({"library": "auto-sklearn", "version": autosklearn.__version__, "n_trials": int(n_runs),
                "selection_metric": "roc_auc" if task == "classification" else "monthly_spearman_ic",
                "ensemble_members": members, "best_estimator": max(members, key=lambda d: d["weight"])["model"] if members else None})
    try:
        lb = est.leaderboard(detailed=False)
        res["leaderboard_top"] = [{"model": str(r["type"]), "ensemble_weight": float(r["ensemble_weight"]), "cost": float(r["cost"])}
                                  for _, r in lb.head(10).iterrows()]
    except Exception as e:  # 진단용 — 실패해도 결과에 영향 없음
        res["leaderboard_err"] = str(e)[:200]

    def refit_predict(Xf, yf, Xp):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            est.refit(Xf, yf)
        return pred_of(est, Xp, task)
    refit_predict.cleanup = lambda: __import__("shutil").rmtree(tmp, ignore_errors=True)
    return refit_predict


# ---------------------------------------------------------------------------------------------- TPOT
def run_tpot(job, Xtr, ytr, Xva, yva, res):
    import sklearn.base
    import tpot
    from tpot import TPOTClassifier, TPOTRegressor
    ec = job["engine_cfg"]
    task = job["task"]
    X = np.vstack([Xtr, Xva]); y = np.concatenate([ytr, yva])
    ps = split_obj(len(Xtr), len(Xva))
    cls = TPOTClassifier if task == "classification" else TPOTRegressor
    import sklearn.metrics
    sc = "roc_auc" if task == "classification" else sklearn.metrics.make_scorer(ic_mean, greater_is_better=True)
    est = cls(search_space=ec["search_space"], scorers=[sc], scorers_weights=[1], cv=ps,
              validation_strategy="none",            # TPOT 의 무작위 train_test_split 검증을 쓰지 않는다
              max_time_mins=float(job["time_left_s"]) / 60.0, max_eval_time_mins=float(ec["max_eval_time_mins"]),
              n_jobs=int(job["n_jobs"]), random_state=int(job["seed"]) % (2 ** 31), verbose=0,
              population_size=int(job["population_size"]), generations=int(job["generations"]))
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        est.fit(X, y)
    # ---- 단정: TPOT 가 쓴 분할 = 미리 정한 시간순 분할 ----
    assert est.cv_gen is ps or isinstance(est.cv_gen, type(ps)), "[nlff tpot] 분할 객체가 바뀌었다"
    sp = list(est.cv_gen.split(X, y))
    assert len(sp) == 1 and np.array_equal(sp[0][1], np.arange(len(Xtr), len(X))), "[nlff tpot] 시간순 분할 불일치"
    ev = est.evaluated_individuals
    n_eval = int(len(ev)) if ev is not None else -1
    try:
        sco = [c for c in ev.columns if "score" in str(c).lower() or "roc_auc" in str(c) or "ic_mean" in str(c)]
        n_ok = int(np.isfinite(ev[sco[0]].astype(float)).sum()) if sco else -1
        res["score_columns"] = [str(c) for c in sco][:5]
    except Exception:
        n_ok = -1
    pipe = est.fitted_pipeline_
    res.update({"library": "tpot", "version": tpot.__version__, "n_trials": n_eval, "n_trials_scored": n_ok,
                "selection_metric": "roc_auc" if task == "classification" else "monthly_spearman_ic",
                "best_pipeline": str(pipe)[:2000],
                "best_estimator": type(pipe.steps[-1][1]).__name__ if hasattr(pipe, "steps") else type(pipe).__name__,
                "ensemble_members": [{"weight": 1.0, "model": type(pipe.steps[-1][1]).__name__ if hasattr(pipe, "steps") else type(pipe).__name__}]})

    def refit_predict(Xf, yf, Xp):
        m = sklearn.base.clone(pipe)
        # 재적합은 단일 프로세스 — 탐색 공간이 학습기에 박아 둔 n_jobs=1 을 워커 수로 올린다(나무 학습기 결과는 n_jobs 와 무관 · 시간만 준다)
        nj = {k: int(job["n_jobs"]) for k, v in m.get_params(deep=True).items() if k.split("__")[-1] == "n_jobs" and v in (None, 1)}
        if nj:
            m.set_params(**nj)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            m.fit(Xf, yf)
        return pred_of(m, Xp, task)
    return refit_predict


# ---------------------------------------------------------------------------------------------- 본체
def main(job_dir):
    t0 = time.time()
    pm = PeakMem()
    with open(os.path.join(job_dir, "job.json"), encoding="utf-8") as f:
        job = json.load(f)
    os.environ["NLFF_VAL_DATES"] = os.path.join(job_dir, "val_dates.npy")
    os.environ["NLFF_TRAIN_DATES"] = os.path.join(job_dir, "train_dates.npy")
    os.environ["NLFF_IC_MIN_N"] = str(int(job.get("ic_min_n", 30)))
    res = {"engine": job["engine"], "tag": job["tag"], "python": sys.version.split()[0], "platform": sys.platform}
    Xtr, ytr, Xva, yva = load(job_dir, "Xtr"), load(job_dir, "ytr"), load(job_dir, "Xva"), load(job_dir, "yva")
    Xwin, ywin, wfold = load(job_dir, "Xwin"), load(job_dir, "ywin"), load(job_dir, "win_fold")
    Xp, pfold = load(job_dir, "Xpred"), load(job_dir, "pred_fold")
    if job["task"] == "classification":
        ytr, yva, ywin = ytr.astype(int), yva.astype(int), ywin.astype(int)
    res["n_train"], res["n_val"], res["n_window"], res["n_pred"] = len(Xtr), len(Xva), len(Xwin), len(Xp)
    runner = {"autosklearn": run_autosklearn, "tpot": run_tpot}[job["engine"]]
    rp = runner(job, Xtr, ytr, Xva, yva, res)
    res["search_s"] = round(time.time() - t0, 1)
    pred = np.full(len(Xp), np.nan)
    if (pfold < 0).all():                                      # 한 번: 재학습 창 전체 → 예측 행 전체
        pred[:] = rp(Xwin, ywin, Xp)
    else:                                                      # val: 종목 묶음 k 를 뺀 창으로 적합 → 묶음 k 예측
        for k in np.unique(pfold):
            keep = wfold != k
            sel = pfold == k
            pred[sel] = rp(Xwin[keep], ywin[keep], Xp[sel])
    if hasattr(rp, "cleanup"):
        rp.cleanup()
    np.save(os.path.join(job_dir, "pred.npy"), pred)
    res["seconds"] = round(time.time() - t0, 1)
    res["peak_rss_tree_gb"] = pm.stop()
    with open(os.path.join(job_dir, "result.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=2, default=str)


if __name__ == "__main__":
    main(sys.argv[1])
