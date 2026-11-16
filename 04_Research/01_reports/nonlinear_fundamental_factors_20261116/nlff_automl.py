"""nlff_automl.py — 재학습 1회분의 AutoML(FLAML CASH) + 시간순 Caruana 앙상블 + 최종 재적합.

흐름(재학습일 R 하나):
  1. time_split — 학습 창 표본(실현일 <= R − 엠바고)을 시간순으로 학습 / 검증으로 나눈다(검증 = 마지막 20% 표본월 ·
     학습 부분은 실현일 < 검증 첫 달 = 정화). 단정 검사로 순서를 확인한다.
  2. FLAML AutoML.fit(X_tr, y_tr, X_val=X_va, y_val=y_va) — 모델 패밀리 선택 + 하이퍼파라미터 탐색(라이브러리 기본 목록 · 공간 · 지표).
  3. 패밀리별 최선 설정을 학습 부분으로 적합 → 검증 구간 예측 → Caruana 탐욕 선택(복원 추출 · 크기 50)으로 가중.
  4. 가중이 0 이 아닌 설정을 학습 + 검증 전체로 다시 적합(refit_full) → 예측 함수.
선형 대조(lin)는 AutoML 과 섞지 않는 별도 짝이다(능형 벌점도 같은 시간순 검증으로 고른다).
"""
from __future__ import annotations

import logging
import warnings

import numpy as np

logging.getLogger("flaml.automl.logger").setLevel(logging.ERROR)
logging.getLogger("flaml").setLevel(logging.ERROR)


# ---------------------------------------------------------------------------------------------- 시간순 분할(단정 포함)
def time_split(dates: np.ndarray, avail: np.ndarray, frac: float, refit_cut: np.datetime64):
    """dates · avail = datetime64[D]. 반환 = (학습 행 mask, 검증 행 mask).
    검증 = 표본월 중 시간순 마지막 frac(최소 1달). 학습 = Date < 검증 첫 달 ∧ 실현일 < 검증 첫 달(정화)."""
    if not (avail <= refit_cut).all():
        raise AssertionError("[nlff PIT] 학습 표본에 재학습일 − 엠바고 뒤 실현 표적이 있다")
    ud = np.unique(dates)
    n_val = max(1, int(round(len(ud) * frac)))
    if len(ud) - n_val < 1:
        return None, None
    v0 = ud[-n_val]
    va = dates >= v0
    tr = (dates < v0) & (avail < v0)
    # ---- 단정: 시간 순서(검증은 학습보다 엄격히 뒤 · 학습 표적은 검증 시작 전에 실현) ----
    if tr.any():
        assert dates[tr].max() < dates[va].min(), "[nlff PIT] 학습 Date >= 검증 Date"
        assert avail[tr].max() < dates[va].min(), "[nlff PIT] 학습 표적 실현일 >= 검증 첫 달(정화 실패)"
    assert (avail[va] <= refit_cut).all()
    return tr, va


# ---------------------------------------------------------------------------------------------- 도우미
def _est_class(task: str, name: str):
    from flaml.automl.task.factory import task_factory
    return task_factory(task).estimator_class_from_str(name)


SEED = 20261116   # nlff_run 이 설정 automl.seed 로 덮는다


def fixed_hp() -> dict:
    """재현성 고정값(탐색 차원이 아니다 · 결과를 보고 고른 값도 아니다): 난수 학습기 씨앗 · LightGBM 결정적 모드
    (LightGBM 은 행/열 방향 다중 스레드를 시간 측정으로 고르므로 실행마다 미세하게 달라진다 → force_row_wise + deterministic)."""
    h = {k: {"random_state": {"domain": SEED}} for k in ("rf", "extra_tree", "sgd")}
    h["lgbm"] = {"deterministic": {"domain": True}, "force_row_wise": {"domain": True}, "random_state": {"domain": SEED}}
    return h


FIXED_HP = fixed_hp()


def _make(task, name, cfg, n_jobs):
    """FLAML 학습기 생성 — 재현성 고정값(fixed_hp)을 설정에 덧붙인다(FLAML 탐색 결과에 이미 있으면 그대로)."""
    c = dict(cfg)
    for k, v in FIXED_HP.get(name, {}).items():
        c.setdefault(k, v["domain"])
    return _est_class(task, name)(task=task, n_jobs=n_jobs, **c)


def _pred(est, X, task):
    if task == "classification":
        return np.asarray(est.predict_proba(X))[:, 1].astype(np.float64)
    return np.asarray(est.predict(X), np.float64)


def _score(y, p, task):
    """크게 = 좋게. 회귀 = −MSE(고정 검증 구간에서 r2 와 순서가 같다) · 이진 = AUC(FLAML 기본 지표와 같음)."""
    if task == "classification":
        from sklearn.metrics import roc_auc_score
        if len(np.unique(y)) < 2:
            return 0.0
        return float(roc_auc_score(y, p))
    return -float(np.mean((y - p) ** 2))


def caruana(preds: dict, y: np.ndarray, task: str, size: int) -> dict:
    """Caruana et al. 2004 탐욕 선택(복원 추출). 시작 = 빈 앙상블 · 매 단계 점수를 가장 올리는 모델 하나를 더한다."""
    names = sorted(preds)
    cnt = {k: 0 for k in names}
    cur = np.zeros_like(y, dtype=np.float64)
    for i in range(size):
        best, best_s = None, -np.inf
        for k in names:
            s = _score(y, (cur * i + preds[k]) / (i + 1), task)
            if s > best_s + 1e-15:
                best, best_s = k, s
        cnt[best] += 1
        cur = (cur * i + preds[best]) / (i + 1)
    return {k: c / size for k, c in cnt.items() if c > 0}


# ---------------------------------------------------------------------------------------------- 재학습 1회
def fit_refit(task: str, Xtr, ytr, Xva, yva, acfg: dict, max_iter: int, n_jobs: int, seed: int, log: dict):
    """FLAML 탐색 → Caruana 가중. 반환 = [(이름, 설정, 가중)] — 최종 적합은 refit_models 가 한다."""
    from flaml import AutoML
    metric = acfg["metric"]["binary" if task == "classification" else "regression"]
    am = AutoML()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        am.fit(Xtr, ytr, X_val=Xva, y_val=yva, task=task, metric=metric, estimator_list=acfg["estimator_list"],
               max_iter=max_iter, time_budget=acfg["time_budget"], sample=acfg["sample"], eval_method=acfg["eval_method"],
               retrain_full=acfg["retrain_full"], ensemble=False, n_jobs=n_jobs, seed=seed, verbose=0,
               # 탐색 공간은 FLAML 기본 그대로 — 난수 학습기의 씨앗만 상수로 고정(재현성 · 탐색 차원 추가 아님)
               custom_hp=FIXED_HP)
    cfgs = {k: v for k, v in am.best_config_per_estimator.items() if v is not None}
    losses = {k: float(v) for k, v in am.best_loss_per_estimator.items() if k in cfgs and np.isfinite(v)}
    # 패밀리별 최선 설정 → 학습 부분 적합 → 검증 예측(시간순 검증 구간만 본다)
    vp = {}
    for k in losses:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            est = _make(task, k, cfgs[k], n_jobs)
            est.fit(Xtr, ytr)
            vp[k] = _pred(est, Xva, task)
    w = caruana(vp, yva, task, int(acfg["ensemble"]["size"]))
    log.update({"best_estimator": am.best_estimator, "n_trials": int(sum(s.total_iter for s in am._search_states.values())),
                "best_loss_per_estimator": losses, "ensemble_weights": w,
                "best_configs": {k: {a: (float(b) if isinstance(b, (np.floating,)) else b) for a, b in cfgs[k].items()} for k in w}})
    return [(k, cfgs[k], wt) for k, wt in w.items()]


def refit_models(task, members, X, y, n_jobs):
    out = []
    for k, cfg, wt in members:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            est = _make(task, k, cfg, n_jobs)
            est.fit(X, y)
        out.append((est, wt))
    return out


def predict_ens(models, X, task):
    return sum(wt * _pred(est, X, task) for est, wt in models)


# ---------------------------------------------------------------------------------------------- 선형 대조
def fit_linear(task, Xtr, ytr, Xva, yva, lc: dict):
    """능형 벌점 = 시간순 검증 구간 MSE 최소(학습 창 안) → 학습 + 검증 전체 재적합. 이진 = L2 로지스틱(C 고정)."""
    X = np.vstack([Xtr, Xva]); yy = np.concatenate([ytr, yva])
    if task == "classification":
        from sklearn.linear_model import LogisticRegression
        m = LogisticRegression(C=lc["logit_C"], max_iter=2000).fit(X, yy.astype(int))
        return m, {}
    from sklearn.linear_model import Ridge
    a = lc["ridge_alphas_log10"]
    best = None
    for al in np.logspace(a[0], a[1], int(a[2])):
        mse = float(np.mean((Ridge(alpha=al).fit(Xtr, ytr).predict(Xva) - yva) ** 2))
        if best is None or mse < best[1]:
            best = (al, mse)
    return Ridge(alpha=best[0]).fit(X, yy), {"alpha": float(best[0])}


def predict_linear(m, X, task):
    return (m.decision_function(X) if task == "classification" else m.predict(X)).astype(np.float64)
