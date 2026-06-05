# Phase 1 — KOSPI200 Forward Bearish Forecast Model

**Plan Version**: v0.4.2 (2026-05-19)
**Owner**: 도훈 (Quant RA)
**Q-Lead**: Claude Opus 4.7 (1M context)
**Status**: S1 진입 진행 중

---

## Scope

- **Phase 1 (current)**: KOSPI200 1개월 후 약세 확률 `p_bear(t, h=21d)` 예측 모델 자체 구축
- **Phase 2 (분리 cycle)**: decision system 설계 (model → book-level action)
- **Phase 3 (분리 cycle)**: STR_1715_AR_on_M4_R05_overlay_PG2 overlay 적용

## Target

```
Y_onset(t) = 1{ DD_252(t-1) > -0.10
                AND ∃ τ ∈ [t, t+h]: DD_252(τ) ≤ -0.10 최초 crossing }   # primary
Y_tail_Q15(t) = 1{ r(t, t+h) ≤ q_Q15_purged(t) }                        # secondary
Y_tail_Q10(t) = 1{ r(t, t+h) ≤ q_Q10_purged(t) }                        # high-confidence
```

## Feature Blocks (8~10 hard cap)

| Block | Features | Source | Train 1995-01 cover |
|---|---|---|---|
| H3 파생 stress | vkospi_z / otm_skew_25d | krx_options/ 4023 daily | NA imputation (2010~) |
| H4 rates/credit | kr_term_spread / kr_credit_spread | ecos_bond_rates.parquet | partial (2000-12~) |
| H5 글로벌 전이 | **macro_risk_score** / vix_log_diff_ewma_21d | macro_regime.parquet / fred_macro_wide.parquet | ✅ **1990-01~** |
| H6 flow/공매도 | foreign_netbuy_20d_z / short_interest_20d_z | flow_features_daily.parquet (X only, fwd_* denylist) | NA imputation (2000~) |
| **H7 valuation** | **q08_composite_quality** / v12_composite_value / sue_z | factor_db + consensus | NA imputation (2005-05~) |
| State engine | sjm_state / state_age / distance_to_centroid + m4 + r05 | factor_db + regime | ✅ 1990-01~ |
| ~~H1 모멘텀~~ | DROP | — | — |
| ~~H2 변동성~~ | **DROP (도훈 mandate)** | — | — |

## Model

```
Baseline 0: Prevalence + lagged-Y_{t-h-1} naive (DM test reference)
1차: Elastic-Net Logistic (R glmnet, observable state only)
2차: shallow XGBoost (depth ≤ 3, Platt calibration)
3차 격하: SJM state engine (KR-013 method transfer)
Ensemble: Equal-weight (default) / BMA / Ridge-stacked
```

## Evaluation (Phase 1 = forecast validity only)

5 performance gates + 1 uncertainty report:
1. **DM test** (HAC lag ≥ 21) — p < 0.05
2. **Brier Skill Score** — > 0
3. **Calibration** (slope ∈ [0.8, 1.2] + ECE < 0.05)
4. **Event-level recall** @ fixed alert-days — baseline +20%
5. **PR-AUC** — baseline +20%
6. **Bootstrap CI on p_bear** (uncertainty report, NOT gate)

Phase 2 이동: Harvey-t / DSR / AX-001 crisis_alpha / Net-of-cost.

## Walk-forward

```
Train       1995-01 ~ 2009-12   (15년, leave-one-crisis-out)
Validation  2010-01 ~ 2015-12   (6년, threshold + ensemble weight median lock)
OOS         2016-01 ~ 2026-04   (10년+, event-level + daily metric)
purge       ≥ 21 trading days
embargo     21~63 trading days
HAC lag     ≥ 21 trading days
```

## PIT Manifest (S1 첫 gate — `pit_manifest_loader.R`)

- denylist `^fwd_|^future_|^lead_|^next_|^t_plus_|^forward_|^ahead_`
- timestamp allowlist 의무 (`config/feature_lag_table.csv` 참조)
- fail-closed: 미정의 column → `stop()`
- unit test (`tests/test_pit_manifest_loader.R`) — mock leakage data로 stop() 검증

## 진화 이력

| Version | Date | 핵심 |
|---|---|---|
| v0.1 | 2026-05-19 | Initial draft |
| v0.2 | 2026-05-19 | 인프라 자원 매핑 |
| v0.3 | 2026-05-19 | .cache parquet 활용 |
| v0.4 | 2026-05-19 | 3-round Codex dialectic (WEAK → ACCEPTABLE → STRONG) |
| v0.4.1 | 2026-05-19 | 5 추가 자원 통합 (macro_regime / fund_dart / krx_options / consensus / universe_v2) + Q-Lead 부정확 3건 인정 |
| **v0.4.2** | **2026-05-19** | **H7 source 변경: fund_dart → factor_db Q08+V12 (GIGO 정합) + 1990 FRED/ECOS 확장 + Q-Lead 자체 결정 4건** |

## 작업 디렉토리

```
04_Research/decision_framework/bearish_forecast_v1/
├── README.md                          # 본 문서
├── config/
│   ├── feature_lag_table.csv          # PIT manifest 변수별 publish lag
│   └── feature_set_v1.json            # selected features + source mapping
├── scripts/
│   ├── 00_pit_manifest_loader.R       # ★ S1 첫 gate (fail-closed loader)
│   ├── 01_feature_assembler.R         # H3~H7 + State block panel build
│   ├── 02_target_builder.R            # Y_onset + Y_tail_Q15/Q10
│   ├── 03_orthogonality_audit.R       # cor vs MRS/KTRI/M4/R05 baseline
│   ├── 04_model_runner.R              # Elastic-Net + XGBoost + (SJM state) + Ensemble
│   ├── 05_validation_suite.R          # 5 gates + 1 uncertainty
│   └── 06_net_of_cost_sim.R           # (Phase 2 예약, retain for reference)
├── tests/
│   └── test_pit_manifest_loader.R     # mock leakage stop() 검증
├── outputs/
│   ├── 01_data/
│   ├── 02_targets/
│   ├── 03_models/{elastic_net, xgboost, markov_switching, stacking_ensemble}/
│   ├── 04_evaluation/
│   ├── 05_orthogonality/
│   └── 06_reports/
├── codex_round_log/                   # Codex dialectic markdown 산출물
└── 06_reports/
    └── plan_v0_4_1_amendment.md       # v0.4 → v0.4.1 변경점 (v0.4.2 amendment 진행 중)
```

## 참조

- 본 plan SOT: `06_reports/plan_v0_4_1_amendment.md` (v0.4.2 보강 진행 중)
- 헌법: `CLAUDE.md` + `.claude/rules/*.md`
- 학술 근거 KR catalog: `01_Literature/Korea_Research/paper_catalog.md` (23편)
- Fundamental 인프라: `04_Research/FUNDAMENTAL_DATA_GAP_ANALYSIS.md` + `FUNDAMENTAL_DATA_TECHNICAL_SPECS.md`
- Factor DB: `02_Infrastructure/factor_db/factor_registry.json` (330 factor 정의)
