---
name: ml-factor-model
description: "ML 팩터 모델 구축 시 적용 -- PIT 준수, 과적합 방지, 해석성, Stage Gate 통합. Forge가 ML 코드 작성 시 반드시 참조."
---
## ML Factor Model 표준 규칙 (v1.0)

### 학술 근거 (5편 핵심 논문)
1. Gu, Kelly & Xiu (2020, RFS): 94 characteristics x 6 ML models. Neural Net > GBT > RF >> OLS. OOS R2: NN3 ~0.40%, GBT ~0.36% (월간). 비선형 상호작용이 핵심 alpha source.
2. Feng, Giglio & Xiu (2020, JF): Double-Selection LASSO로 신규 팩터 한계기여 검증. 150+ 팩터 중 유효 팩터 ~20개. 다중검정 보정 필수.
3. Freyberger, Neuhierl & Weber (2020, RFS): Adaptive Group LASSO로 비모수적 특성-수익률 관계 추정. 롤링 윈도우에서도 소수 특성만 유의.
4. Leippold, Wang & Zhou (2022, JFE): 중국시장에서 ML 적용. PLS/RF/NN이 우월. 개인투자자 비중이 높을수록 단기 예측력 상승. 아시아 시장 구조적 특성 반영 필수.
5. Chen, Pelger & Zhu (2024, Management Science): GAN 기반 no-arbitrage 조건 + LSTM macrostate + Feedforward non-linearity. 경제적 구조(SDF) 부여가 OOS 성능 핵심.

---

### 1. PIT 준수 (최상위 -- 모든 ML 규칙보다 우선)

#### 1.1 Walk-Forward Expanding Window (C1 강화)
```r
# 구조: Training(expanding) | Validation(fixed) | OOS(1년)
# 예시: Train 1990~2009 | Val 2010~2011 | OOS 2012
#       Train 1990~2010 | Val 2011~2012 | OOS 2013
#       ...최종 OOS: 2012~2025 (14년)
TRAIN_START    <- as.Date("1990-07-01")
VAL_LENGTH     <- 24   # months (validation window)
OOS_LENGTH     <- 12   # months (test window, 1년 단위 roll)
MIN_TRAIN_YEARS <- 15  # 최소 학습 기간 (1990~2004)
```
- **full-sample 학습 절대 금지** (C1)
- **validation set = hyperparameter tuning 전용** (OOS와 분리)
- OOS 최소 10년 (통계적 신뢰도 확보)

#### 1.2 Purged & Embargoed Cross-Validation
```r
# Train/Val 사이 gap (purge) = 21 trading days (1 month)
# Target이 t+1~t+21 수익률이면, purge >= 21일
PURGE_DAYS  <- 21L
EMBARGO_DAYS <- 5L   # val 직후 embargo (autocorrelation 차단)
```
- de Prado (2018) Purged K-Fold 사용 시에도 시간순서 유지
- **절대 금지**: 무작위 train/test split (시계열 순서 파괴)

#### 1.3 Target Leakage 방지 (C2 강화)
```r
# Target: t+1 ~ t+21 누적 수익률 (월간) 또는 t+1 일간 수익률
# Feature: t 시점까지의 정보만 (Z_Score_Aligned 사용)
# 절대 금지: same-day return을 feature/target에 동시 사용
target_col <- "Ret_fwd_21d"  # shift(Ret_cum_21d, n = -21, type = "lead") -- 사전 계산
```

#### 1.4 Feature Engineering PIT 규칙
- Factor DB의 `Z_Score_Aligned`만 사용 (C13)
- `load_month_factors(sig_date)` 경유 필수 (C15)
- IC 접근: `Usable_Date <= sig_date` (C14)
- 재무제표 lag: 연간 -> 5월, 분기 -> 45일 (C4)
- **파생 feature(interaction, polynomial) 생성 시에도 PIT 원칙 동일 적용**

---

### 2. 과적합 방지 (Harvey et al. 2016 기준 유지)

#### 2.1 통계 검정
- **Harvey t > 3.0** 인식 (다중검정 보정, 309개 팩터 검색 반영)
- **DSR (Deflated Sharpe Ratio)** 필수 계산
- IS/OOS gap: `|SR_IS - SR_OOS| / SR_IS < 0.50` (50% 이상 하락 시 과적합 경고)

#### 2.2 정규화
```r
# Ridge/Lasso: glmnet(alpha = 0/1, lambda = cv_lambda_min)
# XGBoost: max_depth <= 6, min_child_weight >= 20,
#          reg_alpha (L1) > 0, reg_lambda (L2) > 0
# Neural Net: Dropout >= 0.3, weight_decay > 0
#             Early stopping on validation loss (patience = 10 epochs)
```

#### 2.3 Feature Selection (309 -> Top N)
```r
# Step 1: Mutual Information (sklearn.feature_selection.mutual_info_regression via reticulate)
#         또는 R의 infotheo::mutinformation()
# Step 2: 상위 50개 pre-select (MI 기준)
# Step 3: 모델 내 LASSO/tree importance로 최종 20~30개 자동 선택
# 절대 금지: 309개 전체를 NN에 투입 (p >> n_eff, 과적합 확실)
MAX_FEATURES_PRESELECT <- 50L
MAX_FEATURES_MODEL     <- 30L
```

#### 2.4 Hyperparameter Tuning
- **Bayesian Optimization** (mlrMBO 또는 tune::tune_bayes()) 사용 권장
- Grid search: 최대 50 combinations (조합 폭발 금지, CLAUDE.md 규칙 7)
- **validation set에서만 tuning** (OOS 절대 미사용)
- tuning 결과의 best config 1개만 OOS 평가 (cherry-picking 금지)

#### 2.5 Ensemble Averaging
- 같은 모델을 random seed 5개로 학습 -> 예측 평균 (Chen, Pelger & Zhu 방식)
- 단일 모델 결과 제출 금지 (seed sensitivity 제거)

---

### 3. 해석성 (경제적 메커니즘 연결 필수)

#### 3.1 SHAP Values 필수
```r
# XGBoost: xgboost::xgb.importance() + SHAPforxgboost::shap.values()
# NN: 근사 SHAP (kernelshap 패키지) 또는 Integrated Gradients
# 산출물: SHAP summary plot (top 20 features) + SHAP dependence plot (top 5)
```

#### 3.2 Factor Attribution
- ML score를 기존 팩터 family(V/M/Q/D/S/C/L/AC/R)로 분해
- `family_contribution = mean(|SHAP_i|)` by family
- **지배적 family 식별**: ML 전략의 economic_family 태깅 근거

#### 3.3 경제적 메커니즘 연결 (S0 규칙 유지)
- ML 전략도 `s0_record.economic_rationale` 100자+ 필수
- "ML이 비선형 상호작용을 포착" -- 이것만으로는 불충분
- 구체적으로: "Value x Momentum 상호작용 (Asness 2013), 저유동성 종목에서 Quality premium 증폭 (Novy-Marx 2013)" 수준의 설명
- **SHAP top 5 feature의 경제적 해석 보고서 필수** (S2 profiling에 포함)

#### 3.4 Black Box 경고
- NN/Deep Learning 모델: `interpretability_penalty = -5` (hurdle score에서 차감)
- Tree 모델: `interpretability_penalty = 0`
- Linear 모델: `interpretability_bonus = +3`
- **NN 전략이 Grade A 도달하려면 SHAP + factor attribution + 경제적 해석 3중 통과 필수**

---

### 4. 데이터 구조

#### 4.1 Panel Data 구성
```r
# 일간 Factor DB 사용 (309 features x ~5,700 trading days x ~2,000 stocks)
# 구조: Date | Ticker | Feature_1 | ... | Feature_309 | Ret_fwd_21d
# 월말 cross-section만 추출하면 ~280 time points (p > n 문제 완화)
```

#### 4.2 Target 정의
```r
# Option A: t+1 일간 수익률 (고빈도, 노이즈 높음)
# Option B: t+1 ~ t+21 누적 수익률 (월간, 권장 -- 기존 인프라 호환)
# Option C: t+1 ~ t+63 분기 수익률 (저빈도, 신호 강함, 학습 데이터 감소)
# 권장: Option B (기존 backtest_harness.R와 월간 리밸런싱 호환)
TARGET_HORIZON <- 21L  # trading days
```

#### 4.3 Cross-Sectional 정규화
- 기존 `Z_Score_Aligned` 그대로 사용 (Factor DB에서 이미 정규화)
- **ML 모델 내 추가 정규화**: `rank_transform` 또는 `quantile_normalize` 권장
  - Tree 모델: rank transform으로 충분
  - NN: quantile normalize + batch normalization

#### 4.4 결측치 처리
```r
# Strategy 1: Median imputation (cross-sectional, 각 Date별)
# Strategy 2: -999 sentinel + model-aware (XGBoost는 자체 처리)
# 절대 금지: forward-fill across time (미래참조 위험)
# 절대 금지: full-sample median (C1 위반)
```

---

### 5. 모델 선택 (계층적)

#### 5.1 Tier 1: Linear Baseline (필수)
```r
# Ridge Regression (L2): glmnet(alpha = 0)
# Elastic Net (L1+L2): glmnet(alpha = 0.5)
# 목적: baseline + 해석성 최고 + 기존 z-score 합산과 비교 기준
```

#### 5.2 Tier 2: Tree-Based (주력)
```r
# XGBoost: xgboost(max_depth = 4~6, eta = 0.01~0.05, nrounds = 500~2000)
# LightGBM: lightgbm(num_leaves = 31~63, learning_rate = 0.01~0.05)
# Random Forest: ranger(num.trees = 500, mtry = sqrt(p), max.depth = 8)
# 목적: 비선형 상호작용 포착 (GKX 논문의 핵심 alpha source)
```

#### 5.3 Tier 3: Neural Network (선택적)
```r
# Feedforward NN: 3-layer (32-16-8), ReLU, Dropout 0.3, BatchNorm
# 또는 brulee::brulee_mlp() / torch::nn_module()
# 목적: 고차 비선형성. 단, 해석성 감점(-5) + SHAP 필수
# 조건: Tier 2 대비 OOS SR 10%+ 개선 시에만 채택
```

#### 5.4 Tier 4: 구조적 Deep Learning (고급, 논문 근거 필수)
```r
# Conditional Autoencoder (Gu, Kelly & Xiu 2021): 잠재 팩터 추출
# GAN-SDF (Chen, Pelger & Zhu 2024): no-arbitrage 조건 + adversarial
# 조건: 논문 1편+ 피어리뷰 근거 + S0 debate APPROVE 필수
# 해석성 감점: -8 (SHAP + factor attribution + 경제적 해석 + SDF 구조 설명 4중 통과)
```

#### 5.5 Model Ensemble (최종)
```r
# Simple Average: (Ridge + XGBoost + RF) / 3
# 또는 Stacking: Tier 1 predictions as meta-features -> Ridge meta-learner
# 단일 모델 제출 금지 (seed sensitivity + model risk 분산)
# 최소 2개 모델 앙상블 필수
```

---

### 6. 백테스트 통합

#### 6.1 ML Score -> 기존 파이프라인 연동
```r
# ML 모델 출력 = 종목별 expected return (또는 rank score)
# 이를 기존 factor_engine.R의 composite score로 대체
# run_monthly_simulation()에 그대로 투입
#
# ml_score[t] = model.predict(features[t])  # t 시점 feature만 사용
# portfolio[t+1] = top_30(ml_score[t])      # t+1 리밸런싱
```

#### 6.2 리밸런싱 주기
- **학습**: 월간 (매월 expanding window 재학습) 또는 분기 (3개월마다 재학습)
- **리밸런싱**: 월간 (기존 인프라 호환)
- **절대 금지**: 일간 리밸런싱 (transaction cost 폭발)

#### 6.3 Transaction Cost & Constraints
- Commission: 15bps (기존과 동일)
- 유동성 필터: 20일 평균 거래대금 >= 2억원
- 종목수: 최대 20개 (v53)
- Buffer zone: 기존 keep_n/entry_n 패턴 유지

#### 6.4 Rcpp 엔진 활용
```r
# Rcpp 23x 엔진으로 백테스트 실행
# ML 학습은 R (glmnet/xgboost/torch) + 백테스트는 Rcpp
# 학습과 백테스트 분리: 학습 결과(score)를 .cache/에 저장 후 백테스트 투입
```

---

### 7. Stage Gate 통합 (ML 전략도 동일 파이프라인)

#### 7.1 S0 (Scout)
- 논문 근거 필수 (GKX 2020, Feng et al. 2020, Chen et al. 2024 등)
- `economic_rationale`: ML 메커니즘 + 경제적 해석 양쪽 필수
- `expected_role`: ML 전략의 역할 선언 (core_alpha가 일반적)

#### 7.2 S1 (Forge)
- Walk-forward OOS 성과 보고
- IS/OOS gap 명시
- PIT 체크리스트 C1~C15 + ML 추가 체크 (MC1~MC5, 아래 참조)

#### 7.3 S2 (Profiling)
- SHAP summary plot 첨부 필수
- Factor family attribution 보고
- ICIR >= 0.20 확인 (Alpha Lab Gate)

#### 7.4 S6 (Judge 검증)
- **과적합 집중 검증**:
  - IS/OOS SR gap < 50%
  - Feature stability: 상위 10 feature가 시간 안정적인가 (rolling SHAP)
  - Hyperparameter sensitivity: best config 근방 +-20%에서 성과 급변 여부
  - DSR > 1.0
- **미래참조 집중 검증**:
  - MC1: walk-forward expanding window 확인 (full-sample 학습 금지)
  - MC2: purge/embargo gap 확인
  - MC3: target leakage 확인 (same-day return 미사용)
  - MC4: feature engineering에서 미래 데이터 미사용
  - MC5: hyperparameter tuning이 validation set에서만 수행되었는지

---

### 8. ML 전용 체크리스트 (MC1~MC5)

| 코드 | 규칙 | 위반 예 |
|------|------|---------|
| MC1 | Walk-forward expanding window만 | 전체 데이터 학습 후 IS/OOS split |
| MC2 | Purged CV: train/val 사이 purge >= 21일 | 연속 데이터로 무작위 K-Fold |
| MC3 | Target = t+1 이후 수익률만 | same-day return을 target에 포함 |
| MC4 | Feature = t 시점까지 정보만 | 미래 SHAP/importance로 feature 선택 |
| MC5 | Tuning = validation set에서만 | OOS 데이터로 hyperparameter 조정 |

---

### 9. 한국시장 적용 주의사항

#### 9.1 데이터 특성
- 종목수: ~2,000 (미국 ~5,000 대비 소규모)
- 기간: 1990~ (미국 1960~ 대비 짧음)
- 개인투자자 비중 높음 -> 단기 과잉반응 (Leippold et al. 2022 발견 적용)
- Value/Quality 장기 부진 구간 존재 (L-003 참조)

#### 9.2 p >> n 위험
- 월간: 280 time points x 309 features = 심각한 과적합 위험
- 일간: 5,700 time points x 309 features = 상대적으로 안전하나 여전히 주의
- **대응**: 공격적 feature selection (MI 기준 50 -> 모델 내 20~30개)
- **대응**: 강한 정규화 (Ridge/Elastic Net 우선, Tree depth 제한)

#### 9.3 거래비용 민감도
- 한국시장 유동성: 대형주 집중, 소형주 슬리피지 높음
- ML 포트폴리오의 높은 회전율 주의 (Turnover < 1,100% hard fail)
- Buffer zone 필수

#### 9.4 국면 의존성
- GFC/EuDebt/COVID/2022긴축 스트레스 구간에서 ML 성능 보고 필수
- Regime Engine v7.1과의 조합은 S5 mutation에서만 (S1은 순수 ML 신호)

---

### 10. 코드 템플릿 (run_all.R 골격)

```r
cat("=== STR_XXXX: ML Factor Model ===\n")
## 핵심아이디어: [논문 기반 설명]
## 참조논문: [GKX 2020 / Feng et al. 2020 / etc.]
## ML Model: [XGBoost / Ridge+XGBoost Ensemble / etc.]
## PIT: Walk-forward expanding, purge=21d, target=Ret_fwd_21d

source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/factor_db_connector.R")

# ---- ML Configuration ----
ML_CONFIG <- list(
  train_start     = SIGNAL_START_DATE,
  val_length      = 24L,          # months
  oos_length      = 12L,          # months
  purge_days      = 21L,
  embargo_days    = 5L,
  max_features    = 30L,
  target_horizon  = 21L,          # trading days
  n_seeds         = 5L,           # ensemble averaging
  rebalance_freq  = "monthly"
)

# ---- Feature Selection (MI-based pre-filter) ----
# [구현: mutual information 상위 50개 -> 모델 내 자동 선택]

# ---- Walk-Forward Loop ----
# for each oos_year in (first_oos_year:last_year) {
#   train_data <- data[Date <= val_end - purge]
#   val_data   <- data[Date %between% c(val_start, val_end)]
#   oos_data   <- data[Date %between% c(oos_start, oos_end)]
#   model      <- train_model(train_data, val_data, config)
#   scores     <- predict(model, oos_data)
# }

# ---- Backtest Integration ----
# ml_scores -> run_monthly_simulation(score_col = "ml_score", ...)

# ---- SHAP Analysis ----
# [최종 모델에 대해 SHAP values 산출 + top 20 feature 보고]
```

---

### 부록: 금지 패턴 (ML 특화)

1. **전체 데이터 학습 후 "OOS"라 칭하는 행위** -- IS/OOS split != walk-forward
2. **309개 feature 전체를 NN에 투입** -- 과적합 확실
3. **hyperparameter를 OOS에서 tuning** -- triple dipping
4. **feature importance를 전체 기간에서 계산 후 feature 선택** -- 미래참조 (MC4)
5. **일간 리밸런싱** -- transaction cost 폭발 (Turnover > 1,100% hard fail)
6. **단일 seed 결과 보고** -- seed lottery
7. **SHAP 없이 ML 전략 제출** -- 해석 불가 = S0 규칙 위반
8. **"ML이니까 비선형을 잡는다"로 economic_rationale 대체** -- 구체적 메커니즘 필수
