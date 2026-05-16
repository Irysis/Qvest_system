# Qvest ML Pipeline — GPU-accelerated Walk-forward CV

**Built**: 2026-05-14 Session 81 도훈 mandate ("GPU 활용 가능 ML 파이프라인 인프라").

Reusable Python pipeline for ML alpha cycles. Inherits features_master.parquet (R-built, e.g. WT-D20260514_008) and produces predictions.parquet + summary_metrics.json.

## Setup (one-time, already done)

```bash
python3 -m venv /home/quant/qvest_ml_venv
source /home/quant/qvest_ml_venv/bin/activate
pip install numpy pandas pyarrow scikit-learn
pip install torch --index-url https://download.pytorch.org/whl/cu124
pip install xgboost lightgbm
# Fix libcusparseLt path (one-time):
cp /home/quant/qvest_ml_venv/lib/python3.12/site-packages/nvidia/cusparselt/lib/libcusparseLt.so.0 \
   /home/quant/qvest_ml_venv/lib/python3.12/site-packages/cusparselt/lib/libcusparseLt.so.0
```

## GPU verified

- **NVIDIA GeForce RTX 4080 SUPER** (16 GB)
- **CUDA 13.1 (driver) / CUDA 12.4 (torch wheel)**
- torch 2.6.0+cu124 ✅
- xgboost 3.2.0 (built-in GPU via `device=cuda`) ✅
- lightgbm 4.6.0 (CPU; GPU optional via `device='gpu'`)

## Usage

### Base (5 ML + Ensemble)

```bash
source /home/quant/qvest_ml_venv/bin/activate
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

python 02_Infrastructure/ml_pipeline/run_ml_cycle.py \
    --features-master stage_artifacts/WT_D20260514_008/features_master.parquet \
    --returns-panel   stage_artifacts/WT_D20260514_008/returns_monthly_panel.parquet \
    --out-dir         stage_artifacts/WT_D20260514_010 \
    --train-months 60 --val-months 12 --step-months 12 --lockbox-folds 2
```

### Phase 1.A — Uncertainty-aware (Liao 2025 RFS)

```bash
python 02_Infrastructure/ml_pipeline/run_ml_cycle.py \
    --features-master ... --returns-panel ... --out-dir ... \
    --enable-uncertainty --bootstraps 50 --k-discount 1.0 \
    --uncertainty-base M1_Ridge
```

추가 산출: `predictions_with_ci.parquet` (mean / std / p05 / p25 / p50 / p75 / p95 / discounted)
+ summary_metrics.json 안 `ConfidentHighLow_{base}_{mode}` 항목.

### Phase 1.B — Cost-aware (Jensen-Kelly-Malamud-Pedersen 2022)

```bash
python 02_Infrastructure/ml_pipeline/run_ml_cycle.py \
    --features-master ... --returns-panel ... --out-dir ... \
    --enable-cost-aware --gamma 0.001 --cost-bps-oneway 15 --top-n 20
```

추가 산출: `M7_XGB_CostAware` 후보 candidate + summary_metrics.json 안 `gross_port_sr` / `net_port_sr` / `cost_drag_pp` / `annualized_turnover` per model.

### Phase 1 Full (A + B 동시)

```bash
python 02_Infrastructure/ml_pipeline/run_ml_cycle.py \
    --features-master ... --returns-panel ... --out-dir ... \
    --enable-uncertainty --enable-cost-aware --gamma 0.001
```

## Pipeline modules

- `feature_loader.py` — features_master.parquet read + quality screening (KEEP only)
- `walk_forward_cv.py` — PIT-strict walk-forward fold generator (60mo train + 12mo val + roll 12mo)
- `ml_models.py` — 5(+2) ML candidates + ensemble:
  - M1 Ridge (sklearn)
  - M2 LASSO (sklearn)
  - M3 ElasticNet (sklearn)
  - M4 XGBoost-GPU (RTX 4080 via `device=cuda`)
  - M5 LightGBM (CPU)
  - M6 Ensemble (rank-average)
  - **M7 XGBoost-GPU CostAware** (Phase 1.B, `--enable-cost-aware`): stronger L2 + smoother subsample → lower turnover
  - **Phase 1.A** bootstrap CI helpers: `bootstrap_predictions()` + `uncertainty_discounted_alpha()`
- `quality_metrics.py` — graduation gates:
  - rank_IC (Spearman per sig_date)
  - ICIR (mean / std)
  - Newey-West t-stat (lag 6)
  - DSR Bailey-Lopez de Prado 2014 (N=5 ex-ante)
  - Q1-Q10 decile monotonicity (Spearman rank-cor)
  - Pareto 6-axis portfolio realized cor (vs admit benchmark)
  - **Phase 1.A**: `confident_high_low_evaluation()` (Liao 2025 RFS) + `ci_coverage()` calibration
  - **Phase 1.B**: `portfolio_turnover_per_date()` + `cost_adjusted_ic()` net-of-cost SR
- `run_ml_cycle.py` — orchestrator

## PIT C1-C15 정합

- **C1**: Rolling walk-forward only (full-sample 금지)
- **C2**: features_master inherit (R-built, already t-1 lag applied)
- **C13**: Z_Score_Aligned (R features_master 검증)
- Walk-forward: training window slides forward, no peek-ahead
- OOS lockbox: 마지막 N folds (default 2) held out from model selection

## R 통합 path

Python pipeline output (`predictions.parquet`) → R alpha-research agent inherit:

```r
# In R alpha-research agent
pred <- read_parquet("stage_artifacts/WT_D20260514_010/predictions.parquet")
best_model_pred <- pred[model == "M6_Ensemble" & mode != "lockbox", ]
# Then build alpha_package.json with these scores + Codex Round 5단계 흐름
```

## Output

```
out-dir/
├── predictions.parquet         sig_date × Ticker × {model, score, fold_id, mode}
├── predictions_with_ci.parquet (Phase 1.A) sig_date × Ticker × {pred_mean, pred_std, p05~p95, pred_discounted}
├── fold_metrics.parquet        per fold per model {ic_mean, ic_std, [+turnover Phase 1.B]}
├── summary_metrics.json        overall + Phase 1 extensions
└── manifest.json               Phase 1 reproducibility (flags, gamma, k_discount, candidates)
```

## Phase 1 학술 출처

- **Phase 1.A** Liao H., Ma A., Neuhierl A., Schilling L. (2025) "Confidence Interval for ML Asset Pricing." *Review of Financial Studies* (forthcoming).
- **Phase 1.B** Jensen T.I., Kelly B., Malamud S., Pedersen L.H. (2022) "Machine Learning and the Implementable Efficient Frontier." SSRN 4187217.

## Graduation gates (alpha_package.json mandate)

| Gate | Threshold |
|---|---|
| rank_IC | ≥ 0.04 |
| ICIR | ≥ 0.20 |
| Newey-West t-stat (lag 6) | ≥ 3.0 (Charter §10 statistical defense) |
| DSR (Bailey-LdP) N=5 ex-ante | ≥ 0.5 strict |
| Monotonicity Q1-Q10 | ≥ 0.70 |
| Pareto cor vs STR_1715 admit | < 0.40 |
| OOS lockbox vs IS divergence | small (overfitting audit) |
