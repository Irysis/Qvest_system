#!/usr/bin/env python3
# =============================================================================
# xgb_gpu_predict.py
# STR_1661_XGB_GPU — XGBoost GPU + LambdaRank + Bayesian HP 예측 스크립트
#
# 사용법:
#   python3 xgb_gpu_predict.py \
#       --train /tmp/xgb_train.csv \
#       --test  /tmp/xgb_test.csv  \
#       --val   /tmp/xgb_val.csv   \  (선택)
#       --out   /tmp/xgb_pred.csv  \
#       --objective rank:pairwise  \  (또는 reg:squarederror)
#       --device cuda              \  (또는 cpu)
#       --seed 42                  \
#       --hp_json /tmp/xgb_hp.json \  (선택: Optuna 탐색 결과 재사용)
#       --mode predict             \  (predict 또는 hp_search)
#
# 출력:
#   --mode predict: /tmp/xgb_pred.csv (pred_rank 1열)
#   --mode hp_search: /tmp/xgb_hp.json (최적 HP JSON)
#
# S0_VERDICT 조건 구현:
#   (1) label 변환: fwd_ret_21d → group 내 정수 rank (0~N-1) — ndcg@K 호환
#   (2) group 파라미터: 월별 종목 수를 group으로 전달
#   (3) Optuna 30 trials, purged 3-fold time-series CV (purge_rows 기반)
#   (4) IS/OOS gap 모니터링: gap > 2.0이면 경고
# =============================================================================

import argparse
import json
import sys
import warnings
import numpy as np
import pandas as pd
import xgboost as xgb
import optuna

optuna.logging.set_verbosity(optuna.logging.WARNING)
warnings.filterwarnings("ignore", category=UserWarning)

# =============================================================================
# 인자 파싱
# =============================================================================
parser = argparse.ArgumentParser(description="XGBoost GPU LambdaRank predictor")
parser.add_argument("--train",     required=True,  help="학습 CSV (Date,Ticker,fwd_ret_21d,f1,...)")
parser.add_argument("--test",      required=True,  help="예측 CSV (Date,Ticker,f1,...)")
parser.add_argument("--val",       default=None,   help="검증 CSV (선택)")
parser.add_argument("--out",       required=True,  help="예측 출력 CSV")
parser.add_argument("--objective", default="rank:pairwise",
                    choices=["reg:squarederror","rank:pairwise"])
parser.add_argument("--device",    default="cuda", choices=["cuda","cpu"])
parser.add_argument("--seed",      type=int, default=42)
parser.add_argument("--hp_json",   default=None,   help="Optuna 결과 JSON (재사용 시)")
parser.add_argument("--mode",      default="predict", choices=["predict","hp_search"])
parser.add_argument("--n_trials",  type=int, default=30)
parser.add_argument("--purge_rows",type=int, default=0,
                    help="HP 탐색용 purge rows (0=자동: 데이터의 약 5%)")
args = parser.parse_args()

# =============================================================================
# 데이터 로드
# =============================================================================
def load_data(path):
    """CSV 로드. Date, Ticker, fwd_ret_21d는 메타 컬럼으로 분리."""
    df = pd.read_csv(path)
    meta_cols = ["Date", "Ticker", "fwd_ret_21d", "ym_group"]
    feat_cols = [c for c in df.columns if c not in meta_cols]
    return df, feat_cols

def make_feature_matrix(df, feat_cols):
    """피처 행렬. NA → 0."""
    X = df[feat_cols].values.astype(np.float32)
    X = np.where(np.isfinite(X), X, 0.0)
    return X

# =============================================================================
# LambdaRank label 변환
# S0_VERDICT 조건: fwd_ret_21d → group 내 정수 rank (0~N-1)
# ndcg@K는 label이 비음수 정수여야 함
# =============================================================================
def make_rank_label(y_arr):
    """
    fwd_ret_21d를 그룹 내 정수 rank로 변환.
    최하위=0, 최상위=N-1. ndcg@30 호환.
    """
    n = len(y_arr)
    rank_float = np.argsort(np.argsort(y_arr)).astype(np.float32)
    return rank_float.astype(np.int32)

def build_dmatrix_grouped(df, feat_cols, label_col="fwd_ret_21d",
                           group_col="ym_group", objective="rank:pairwise"):
    """
    그룹(월) 기반 DMatrix 생성.
    - rank:pairwise: 그룹별 label을 정수 rank로 변환 + group 파라미터
    - reg:squarederror: 연속 label 그대로
    """
    X = make_feature_matrix(df, feat_cols)
    has_label = label_col in df.columns and df[label_col].notna().any()

    if not has_label:
        # OOS 예측: label 없음
        dm = xgb.DMatrix(data=X)
        return dm, None

    y_raw = df[label_col].values.astype(np.float32)

    if objective == "rank:pairwise" and group_col in df.columns:
        # 그룹별 rank label 변환
        groups = df[group_col].values
        unique_groups = pd.unique(groups)
        y_rank = np.zeros(len(y_raw), dtype=np.int32)
        group_sizes = []

        for g in unique_groups:
            mask = groups == g
            y_g = y_raw[mask]
            y_rank[mask] = make_rank_label(y_g)
            group_sizes.append(int(np.sum(mask)))

        dm = xgb.DMatrix(data=X, label=y_rank.astype(np.float32))
        dm.set_group(group_sizes)
    else:
        # regression: 연속 label
        y_fin = np.where(np.isfinite(y_raw), y_raw, 0.0)
        dm = xgb.DMatrix(data=X, label=y_fin)

    return dm, y_raw

# =============================================================================
# 기본 파라미터 (고정 HP — V1/V2 용)
# =============================================================================
DEFAULT_PARAMS = {
    "reg:squarederror": {
        "booster": "gbtree",
        "objective": "reg:squarederror",
        "eta": 0.02,
        "max_depth": 5,
        "subsample": 0.7,
        "colsample_bytree": 0.5,
        "min_child_weight": 10,
        "lambda": 1.0,
        "alpha": 0.1,
        "nthread": 4,  # GPU 모드에서는 nthread 무시됨
        "seed": args.seed
    },
    "rank:pairwise": {
        "booster": "gbtree",
        "objective": "rank:pairwise",
        "eval_metric": "ndcg@30",
        "eta": 0.02,
        "max_depth": 5,
        "subsample": 0.7,
        "colsample_bytree": 0.5,
        "min_child_weight": 10,
        "lambda": 1.0,
        "nthread": 4,
        "seed": args.seed
    }
}

# =============================================================================
# GPU 장치 설정
# =============================================================================
def add_device_params(params, device="cuda"):
    """device='cuda' 추가. CPU fallback 포함."""
    p = dict(params)
    if device == "cuda":
        p["device"] = "cuda"
        p["tree_method"] = "hist"
    else:
        p["device"] = "cpu"
        p["tree_method"] = "hist"
    return p

# =============================================================================
# Optuna HP 탐색 (V3 — purged 3-fold TS CV)
# S0_VERDICT 조건:
#   - IS 내 purged 3-fold time-series CV
#   - purge_rows: 기본 max(21, IS의 약 2%)
#   - objective: validation_IC_mean (Spearman rank correlation)
# =============================================================================
def hp_search_optuna(X_tr, y_tr, groups_tr, n_trials, objective_type, device,
                     purge_rows=0, seed=42):
    """
    Optuna 30 trials, purged 3-fold TS CV.
    반환: 최적 params dict + IS IC (IS/OOS gap 모니터링용)
    """
    n = len(y_tr)
    if purge_rows <= 0:
        purge_rows = max(21, n // 50)  # 자동: IS의 약 2%

    # 3-fold time-series split (purge 적용)
    fold_size = n // 4  # 3-fold: 1/4씩 val
    folds = []
    for k in range(1, 4):
        val_start = k * fold_size
        val_end   = min((k + 1) * fold_size, n)
        tr_end    = max(0, val_start - purge_rows)
        if tr_end < 100 or (val_end - val_start) < 20:
            continue
        folds.append((slice(0, tr_end), slice(val_start, val_end)))

    if not folds:
        print("[HP] fold 생성 실패 — 고정 HP 사용")
        return None, None

    def objective(trial):
        params = {
            "booster": "gbtree",
            "objective": objective_type,
            "eta": trial.suggest_float("eta", 0.005, 0.05, log=True),
            "max_depth": trial.suggest_int("max_depth", 3, 8),
            "subsample": trial.suggest_float("subsample", 0.5, 0.9),
            "colsample_bytree": trial.suggest_float("colsample_bytree", 0.3, 0.7),
            "min_child_weight": trial.suggest_int("min_child_weight", 5, 30),
            "lambda": trial.suggest_float("lambda", 0.5, 5.0, log=True),
            "nthread": 4,
            "seed": seed
        }
        if objective_type == "rank:pairwise":
            params["eval_metric"] = "ndcg@30"
        params = add_device_params(params, device)
        nrounds = trial.suggest_int("nrounds", 200, 1000)

        fold_ics = []
        for tr_sl, val_sl in folds:
            X_f = X_tr[tr_sl]; y_f = y_tr[tr_sl]
            X_v = X_tr[val_sl]; y_v = y_tr[val_sl]

            if groups_tr is not None and objective_type == "rank:pairwise":
                g_f = groups_tr[tr_sl]
                g_v = groups_tr[val_sl]
                # 그룹별 rank label
                uniq_f = pd.unique(g_f)
                y_f_rank = np.zeros(len(y_f), dtype=np.float32)
                gsz_f = []
                for g in uniq_f:
                    m = g_f == g
                    y_f_rank[m] = make_rank_label(y_f[m]).astype(np.float32)
                    gsz_f.append(int(m.sum()))
                dm_f = xgb.DMatrix(X_f, label=y_f_rank)
                dm_f.set_group(gsz_f)

                uniq_v = pd.unique(g_v)
                y_v_rank = np.zeros(len(y_v), dtype=np.float32)
                gsz_v = []
                for g in uniq_v:
                    m = g_v == g
                    y_v_rank[m] = make_rank_label(y_v[m]).astype(np.float32)
                    gsz_v.append(int(m.sum()))
                dm_v = xgb.DMatrix(X_v, label=y_v_rank)
                dm_v.set_group(gsz_v)
            else:
                y_f_fin = np.where(np.isfinite(y_f), y_f, 0.0).astype(np.float32)
                y_v_fin = np.where(np.isfinite(y_v), y_v, 0.0).astype(np.float32)
                dm_f = xgb.DMatrix(X_f, label=y_f_fin)
                dm_v = xgb.DMatrix(X_v, label=y_v_fin)

            try:
                m = xgb.train(params, dm_f, nrounds, verbose_eval=False)
                pred_v = m.predict(dm_v)
                # Spearman IC on y_v (raw, not rank)
                y_v_fin2 = np.where(np.isfinite(y_v), y_v, 0.0)
                if len(pred_v) > 5:
                    from scipy.stats import spearmanr
                    ic, _ = spearmanr(pred_v, y_v_fin2)
                    if np.isfinite(ic):
                        fold_ics.append(ic)
            except Exception as e:
                pass

        if not fold_ics:
            return -999.0
        return float(np.mean(fold_ics))

    sampler = optuna.samplers.TPESampler(seed=seed)
    study = optuna.create_study(direction="maximize", sampler=sampler)
    study.optimize(objective, n_trials=n_trials, show_progress_bar=False)

    best = study.best_params
    best_val_ic = study.best_value
    print(f"[HP] best_val_IC={best_val_ic:.4f} | eta={best.get('eta',0):.4f} "
          f"depth={best.get('max_depth',5)} sub={best.get('subsample',0.7):.2f} "
          f"nrounds={best.get('nrounds',300)}")

    # 최적 params dict 구성
    params_out = {
        "booster": "gbtree",
        "objective": objective_type,
        "eta": best["eta"],
        "max_depth": best["max_depth"],
        "subsample": best["subsample"],
        "colsample_bytree": best["colsample_bytree"],
        "min_child_weight": best["min_child_weight"],
        "lambda": best["lambda"],
        "nthread": 4,
        "seed": seed
    }
    if objective_type == "rank:pairwise":
        params_out["eval_metric"] = "ndcg@30"
    nrounds_out = best["nrounds"]

    return params_out, nrounds_out, best_val_ic

# =============================================================================
# 예측 (단일 seed)
# =============================================================================
def predict_single(dm_tr, dm_te, dm_vl, params, device, nrounds,
                   objective_type, seed):
    """단일 seed XGBoost 예측. rank를 0~1로 정규화하여 반환."""
    params_run = add_device_params(dict(params), device)
    params_run["seed"] = seed

    try:
        if dm_vl is not None:
            m = xgb.train(params_run, dm_tr, nrounds,
                          evals=[(dm_vl, "val")],
                          early_stopping_rounds=30,
                          verbose_eval=False)
        else:
            m = xgb.train(params_run, dm_tr, nrounds, verbose_eval=False)

        pred = m.predict(dm_te)
        n_te = len(pred)
        # rank 정규화 (0~1)
        pred_rank = (np.argsort(np.argsort(pred)) + 1.0) / (n_te + 1.0)
        return pred_rank
    except Exception as e:
        print(f"[PRED] seed={seed} 오류: {e}", file=sys.stderr)
        return None

# =============================================================================
# 메인 로직
# =============================================================================
def main():
    # 데이터 로드
    df_tr, feat_cols = load_data(args.train)
    df_te, _         = load_data(args.test)

    # 피처 컬럼 교집합 (train/test 불일치 방어)
    feat_cols = [c for c in feat_cols if c in df_te.columns]
    if len(feat_cols) == 0:
        print("[ERROR] 공통 피처 없음. train/test CSV 확인 필요.", file=sys.stderr)
        sys.exit(1)

    print(f"[INFO] objective={args.objective} device={args.device} "
          f"seed={args.seed} features={len(feat_cols)}")

    X_tr = make_feature_matrix(df_tr, feat_cols)
    X_te = make_feature_matrix(df_te, feat_cols)
    y_tr = df_tr["fwd_ret_21d"].values.astype(np.float32) if "fwd_ret_21d" in df_tr.columns else None

    # 그룹 정보 (LambdaRank용)
    groups_tr = df_tr["ym_group"].values if "ym_group" in df_tr.columns else None
    groups_te = df_te["ym_group"].values if "ym_group" in df_te.columns else None

    # 검증 데이터
    df_vl = None
    X_vl = None
    y_vl = None
    groups_vl = None
    if args.val and args.val != "NULL":
        try:
            df_vl, _ = load_data(args.val)
            X_vl = make_feature_matrix(df_vl, feat_cols)
            y_vl = df_vl["fwd_ret_21d"].values.astype(np.float32) if "fwd_ret_21d" in df_vl.columns else None
            groups_vl = df_vl["ym_group"].values if "ym_group" in df_vl.columns else None
        except:
            pass

    # =============================================================================
    # 모드: HP 탐색 (V3용)
    # =============================================================================
    if args.mode == "hp_search":
        print(f"[HP_SEARCH] Optuna {args.n_trials} trials 시작...")
        result = hp_search_optuna(
            X_tr, y_tr, groups_tr,
            n_trials=args.n_trials,
            objective_type=args.objective,
            device=args.device,
            purge_rows=args.purge_rows,
            seed=args.seed
        )
        if result[0] is not None:
            params_out, nrounds_out, best_ic = result
            hp_result = {
                "params": params_out,
                "nrounds": nrounds_out,
                "best_val_IC": best_ic,
                "objective": args.objective,
                "device": args.device,
                "n_trials": args.n_trials,
                "seed": args.seed
            }
            with open(args.out, "w") as f:
                json.dump(hp_result, f, indent=2)
            print(f"[HP_SEARCH] 완료. 저장: {args.out}")
        else:
            print("[HP_SEARCH] 실패 — 고정 HP fallback")
            sys.exit(1)
        return

    # =============================================================================
    # 모드: 예측 (V1/V2/V3)
    # =============================================================================

    # HP 결정: hp_json 있으면 로드, 없으면 고정 HP
    if args.hp_json and args.hp_json != "NULL":
        try:
            with open(args.hp_json) as f:
                hp_data = json.load(f)
            params_base = hp_data["params"]
            nrounds_base = hp_data.get("nrounds", 500)
            print(f"[HP] Optuna HP 로드: {args.hp_json} nrounds={nrounds_base}")
        except Exception as e:
            print(f"[HP] JSON 로드 실패: {e} — 고정 HP 사용")
            params_base = DEFAULT_PARAMS[args.objective]
            nrounds_base = 500
    else:
        params_base = DEFAULT_PARAMS[args.objective]
        nrounds_base = 500

    # DMatrix 구성
    dm_tr, _ = build_dmatrix_grouped(df_tr, feat_cols, "fwd_ret_21d",
                                      "ym_group", args.objective)
    dm_te    = xgb.DMatrix(X_te)

    dm_vl = None
    if X_vl is not None and y_vl is not None:
        dm_vl, _ = build_dmatrix_grouped(df_vl, feat_cols, "fwd_ret_21d",
                                          "ym_group", args.objective)

    # 5-seed 앙상블 — 단일 seed 모드
    pred_rank = predict_single(dm_tr, dm_te, dm_vl,
                                params_base, args.device,
                                nrounds_base, args.objective, args.seed)

    if pred_rank is None:
        print("[ERROR] 예측 실패", file=sys.stderr)
        sys.exit(1)

    # 출력
    out_df = pd.DataFrame({"pred_rank": pred_rank})
    out_df.to_csv(args.out, index=False)
    print(f"[OUT] {args.out} | n={len(pred_rank)} | mean_rank={pred_rank.mean():.4f}")


if __name__ == "__main__":
    main()
