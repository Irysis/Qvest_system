# SEFRS v1.0 — Mini-Forge 4-Stage Protocol + 9 Admission Gates

**Task ID**: WT-D20260518_001
**Phase**: Alpha-Research Phase A Step 5 (Mini-Forge Protocol Design)
**Date**: 2026-05-18
**Author**: Alpha Research Agent (autonomous mode)
**Scope**: Design only. Forge cycle 진입 (실제 실행) = Q-Lead 명시 confirm 후

---

## 0. Overall Flow

```
┌────────────────────────────────────────────────────────────────┐
│ Stage 1: Data Feasibility (1h)                                 │
│ - SEIBro 3 ETF × 일별 5 fields 수집 + 12 PIT audit            │
│ - Pass: 9 gates G1+G2 → Stage 2 진입                          │
│ - Fail: HARD ABORT (RC1 또는 RC2)                              │
├────────────────────────────────────────────────────────────────┤
│ Stage 2: Event Study Decile (2h)                               │
│ - Primary EBI decile assignment + top/bottom Newey-West       │
│ - 1M forward KOSPI200 return + STR_1715 bad-state             │
│ - Pass: G3+G4+G5 → Stage 3 진입                                │
│ - Fail: DEFER (RC4)                                            │
├────────────────────────────────────────────────────────────────┤
│ Stage 3: Predictive Model Incremental (3~4h)                   │
│ - Logistic → Elastic Net → LightGBM purged WF                 │
│ - Stand-alone AUC + uplift vs baseline                        │
│ - Pass: G6+G8 → Stage 4 진입                                   │
│ - Fail: DEFER                                                   │
├────────────────────────────────────────────────────────────────┤
│ Stage 4: DPL-RC Integration (2~3h)                             │
│ - 80 features baseline vs 88 features (SEFRS inject)          │
│ - p_bad_1715 classifier AUC uplift test                       │
│ - Pass: G7 → ADMIT 후보 (Codex Round + Judge)                  │
│ - Fail: DEFER (재설계)                                          │
└────────────────────────────────────────────────────────────────┘
```

**Total estimated time**: 8~12h pure compute + 2~4h artifact prep + Q-Lead/Codex review.

---

## 1. Stage 1: Data Feasibility Audit (1h)

### 1.1 입력 + 출력

- **Input**: SEIBro / KRX 외부 source (도훈 confirm + API key 발급 후)
- **Output**:
  - `.cache/seibro_etf_flow/seibro_3etf_raw.parquet` (raw 수집)
  - `stage_artifacts/WT_D20260518_001/sefrs_features.parquet` (12 features computed)
  - `stage_artifacts/WT_D20260518_001/pit_audit_result.json` (12-item audit result)

### 1.2 실행 sub-steps

1. **API 인증**: data.go.kr 한국예탁결제원 주식정보서비스 (15001145) key 발급 — 0.5h
2. **Collector 신규 구축**: `02_Infrastructure/data/seibro_etf_flow_collector.R` (≈ 6~8h estimated 사전 구축 → Stage 1 진입 시 이미 완료된 상태)
3. **3 ETF × 일별 raw 수집** (2017-01-01 ~ 2026-04-30) — ~30 min compute
4. **Cross-source verification** (SEIBro vs KRX, 가능 시) — ~10 min
5. **PIT audit 12-item 실행** (pit_audit_protocol.md §1~6) — ~15 min
6. **Feature 계산 12개** (feature_spec_v1.md §1~3) — < 10 sec (computational complexity §7)

### 1.3 Stage 1 → Stage 2 transition gates

- **G1 Data Completeness**: 3 ETF × 5 fields × coverage ≥ 95% — PASS
- **G2 PIT Audit**: 12-item all PASS (hard fail 0) — PASS

**둘 모두 PASS**: Stage 2 진입.
**G1 FAIL**: ABORT (RC1 — SEIBro fundamental impossible).
**G2 hard fail 1건 이상**: HARD ABORT (RC2 — lookahead 발견).

### 1.4 시간 budget

| Sub-step | Time |
|----------|------|
| API key 신청 | 0.5h (1회만) |
| Collector 신규 구축 | 6~8h (1회만, Stage 1 이전 완료) |
| 일별 raw 수집 | 0.5h |
| Cross-source verify | 0.2h |
| PIT audit 12-item | 0.3h |
| Feature 계산 12개 | 0.01h |
| Audit report 작성 | 0.2h |
| **Stage 1 total** | **~1h** (collector + key 이미 준비된 상태) |

---

## 2. Stage 2: Event Study Decile (2h)

### 2.1 입력 + 출력

- **Input**: `sefrs_features.parquet` (12 features), KOSPI200 returns, STR_1715 bad-state label
- **Output**:
  - `stage_artifacts/WT_D20260518_001/event_study_decile_result.csv`
  - `stage_artifacts/WT_D20260518_001/event_study_summary.json`
  - `stage_artifacts/WT_D20260518_001/event_study_plots.pdf` (decile bar charts)

### 2.2 STR_1715 bad-state label 정의 (inherit DPL-RC v3)

WT-D20260517_003 request.json 명시:
- **Definition 1**: 1715 active return < -x% (x ∈ {2, 3, 5})
- **Definition 2**: 1715 rolling 6m drawdown ≤ -10%
- **Definition 3**: 1715 < benchmark by y% (y ∈ {0.5, 1.0, 1.5})

→ Stage 2에서 3 정의 모두 compute + OOS comparison.

### 2.3 Event study sub-steps

1. **Decile assignment** (per sig_date):
   ```r
   df[, EBI_decile := ntile(ETF_Bear_Imbalance, 10), by = month]
   ```
   - Decile 1 (lowest, < q10) ~ Decile 10 (highest, > q90)

2. **Top/Bottom 1M forward return**:
   ```r
   df[, fwd_ret_1m := shift(KOSPI200_ret_20d, type = "lead"), by = NULL]
   summary <- df[, .(
     mean_fwd_ret = mean(fwd_ret_1m, na.rm = TRUE),
     median_fwd_ret = median(fwd_ret_1m, na.rm = TRUE),
     mean_fwd_dd = mean(KOSPI_fwd_dd_1m, na.rm = TRUE),
     mean_fwd_vol = mean(KOSPI_fwd_vol_1m, na.rm = TRUE),
     n_obs = .N
   ), by = EBI_decile]
   ```

3. **Newey-West t-stat** (autocorrelation-robust):
   ```r
   # Top decile (10) vs Bottom decile (1) difference
   diff_returns <- df[EBI_decile == 10, fwd_ret_1m] - df[EBI_decile == 1, fwd_ret_1m]
   nw_test <- sandwich::NeweyWest(lm(diff_returns ~ 1), lag = 5)
   t_stat_nw <- coef(lm(diff_returns ~ 1))[1] / sqrt(diag(nw_test))
   ```

4. **Monotonicity test**:
   ```r
   # Decile 1 → 10 mean_fwd_ret이 monotonic pattern?
   monotonic_score <- cor(1:10, summary$mean_fwd_ret, method = "spearman")
   # |1.0| = strict monotonic, 0 = no pattern
   ```

5. **Sign flip test** (non-linear detection):
   ```r
   # Decile 1, 5, 10 sign pattern
   # 예상 (contrarian extreme hypothesis):
   #   Decile 1 (very low EBI): + 또는 0
   #   Decile 5 (middle):       0
   #   Decile 10 (very high EBI): + (contrarian reversal)
   # → "U-shape" or "inverted U"
   sign_pattern <- sign(summary$mean_fwd_ret)
   non_linear <- (sign_pattern[1] == sign_pattern[10]) && (sign_pattern[5] != sign_pattern[1])
   ```

6. **STR_1715 bad-state event study** (additional):
   - 동일 decile assignment + label = STR_1715_bad_state_dummy_1m forward
   - Bad-state Δprobability between Decile 1 vs Decile 10 + Newey-West t-stat

### 2.4 Stage 2 → Stage 3 transition gates

- **G3 Feature Stability**: Primary EBI ADF p<0.05 OR KPSS p>0.10 — PASS
- **G4 Event Study Significance**: top/bottom decile NW |t|≥2.0 on 1M forward KOSPI200 return OR STR_1715 bad-state — PASS
- **G5 Monotonicity OR Non-linearity**: |spearman cor (decile, fwd_ret)| ≥ 0.6 OR documented non-linear regime-conditional pattern — PASS

**셋 모두 PASS**: Stage 3 진입.
**G4 FAIL**: DEFER (RC4 — economic significance 부재).
**G5 FAIL + G4 PASS**: regime-conditional 재설계 검토 (Stage 3 진입 가능, 단 ML scorer non-linear 우선).

### 2.5 Codex Critic readiness (mid-stage)

Stage 2 완료 시 mid-stage Codex review (선택적). Stage 3 진입 전.

---

## 3. Stage 3: Predictive Model Incremental (3~4h)

### 3.1 입력 + 출력

- **Input**: 12 SEFRS features + KOSPI200 baseline features (return / vol / mom)
- **Output**:
  - `stage_artifacts/WT_D20260518_001/predictive_model_result.csv`
  - `stage_artifacts/WT_D20260518_001/feature_importance.csv`
  - `stage_artifacts/WT_D20260518_001/walk_forward_oos_metrics.json`

### 3.2 Label: STR_1715 bad-state dummy (1M forward)

DPL-RC v1.0 정합. Stage 2에서 3 정의 중 best label 선택 (highest OOS AUC).

### 3.3 Incremental scorer

#### 3.3.1 Logistic regression baseline

```r
# Stage 3.1: Logistic
features_baseline <- c("KOSPI_ret_20d", "KOSPI_vol_60d", "KOSPI_mom_21d")
features_sefrs <- c("ETF_Bear_Imbalance", "F2_cum5d", ..., "I3_x_rv_q")  # 12 features

# Baseline model
fit_baseline <- glm(bad_state ~ ., data = train[, c(features_baseline, "bad_state")], family = "binomial")
# SEFRS-augmented model
fit_sefrs <- glm(bad_state ~ ., data = train[, c(features_baseline, features_sefrs, "bad_state")], family = "binomial")

# OOS AUC + ΔAUC
auc_baseline <- compute_auc(predict(fit_baseline, test, type = "response"), test$bad_state)
auc_sefrs <- compute_auc(predict(fit_sefrs, test, type = "response"), test$bad_state)
delta_auc <- auc_sefrs - auc_baseline
```

#### 3.3.2 Elastic Net (regularized)

```r
library(glmnet)
X_train <- model.matrix(bad_state ~ ., data = train[, c(features_baseline, features_sefrs, "bad_state")])[, -1]
y_train <- train$bad_state
fit_en <- cv.glmnet(X_train, y_train, family = "binomial", alpha = 0.5)
# OOS prediction + AUC
```

#### 3.3.3 LightGBM (non-linear, interaction)

```r
library(lightgbm)
dtrain <- lgb.Dataset(data = as.matrix(train_features), label = train$bad_state)
params <- list(
  objective = "binary",
  metric = "auc",
  num_leaves = 31,
  learning_rate = 0.05,
  feature_fraction = 0.8
)
fit_lgb <- lgb.train(params, dtrain, nrounds = 200, valids = list(test = dtest), early_stopping_rounds = 20)
```

### 3.4 Purged Walk-Forward (López de Prado 2018)

```r
# Window definition
walk_windows <- list(
  list(train_start = "2017-01", train_end = "2020-12", test_start = "2021-01", test_end = "2021-12"),
  list(train_start = "2017-01", train_end = "2021-12", test_start = "2022-01", test_end = "2022-12"),
  list(train_start = "2017-01", train_end = "2022-12", test_start = "2023-01", test_end = "2023-12"),
  list(train_start = "2017-01", train_end = "2023-12", test_start = "2024-01", test_end = "2024-12"),
  list(train_start = "2017-01", train_end = "2024-12", test_start = "2025-01", test_end = "2025-12")
  # 2026-01 ~ 2026-04 = paper trade lockbox (Alpha agent 접근 금지, lockbox-scope.md)
)

# Embargo: 1M between train_end and test_start
# Purge: any sample whose label horizon overlaps with test_start
purged_walk_forward <- function(df, windows, embargo_months = 1) {
  for (w in windows) {
    train_end <- as.Date(w$train_end)
    purge_cutoff <- train_end - 30  # 1M embargo
    train_sub <- df[Date <= purge_cutoff]
    test_sub <- df[Date >= as.Date(w$test_start) & Date <= as.Date(w$test_end)]
    
    # Fit + predict
    # Store OOS predictions + actuals
  }
}
```

### 3.5 Sub-period stability

5 walk-forward windows 각각의 AUC 측정:
```r
auc_per_window <- c(0.58, 0.55, 0.61, 0.57, 0.60)  # example
sign_stability <- all(auc_per_window > 0.5)  # 5/5 above random
mean_auc <- mean(auc_per_window)
std_auc <- sd(auc_per_window)
```

### 3.6 Stage 3 → Stage 4 transition gates

- **G6 STR_1715 Bad-State Predictive Power**: Stand-alone AUC ≥ 0.55 OR baseline 대비 ΔAUC ≥ 0.02 — PASS
- **G8 No Redundancy**: max abs(cor) with existing 80 features ≤ 0.70 (information complement) — PASS

**둘 PASS**: Stage 4 진입.
**G6 FAIL**: DEFER (RC4 — predictive power 부재).
**G8 FAIL**: 일부 SEFRS feature 제외 후 재시도. 전부 fail 시 DEFER.

### 3.7 Sub-period stability gate (parallel)

G8b sub-period: 5 windows 중 ≥ 4/5에서 AUC > 0.50 (sign stability). Fail 시 regime-conditional 별도 검토.

---

## 4. Stage 4: DPL-RC Integration (2~3h)

### 4.1 입력 + 출력

- **Input**:
  - Baseline 80 features (DPL-RC v2 inherit, feature_allowlist_v2.csv sha256 `b3d667...`)
  - SEFRS 12 features (Stage 1~3 검증된 것)
  - DPL-RC p_bad_1715 classifier (LightGBM, WT-D20260517_003 production)
- **Output**:
  - `stage_artifacts/WT_D20260518_001/dpl_rc_integration_uplift.json`
  - `stage_artifacts/WT_D20260518_001/feature_allowlist_v3_88.csv` (80 + 12 = 88, sha256 fresh)

### 4.2 Integration sub-steps

1. **Feature pool union**:
   ```r
   features_v2_80 <- read_csv("stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv")$name
   features_sefrs_12 <- c("SEFRS_EBI_PRIMARY", ..., "SEFRS_X_RV_QUINTILE")
   features_v3_88 <- c(features_v2_80, features_sefrs_12)
   
   stopifnot(length(features_v3_88) == 88)
   stopifnot(length(unique(features_v3_88)) == 88)  # no duplicates
   ```

2. **Re-train p_bad_1715 classifier**:
   - Same hyperparameters as DPL-RC v1.0 baseline
   - Same walk-forward 5 windows (purged + embargo 1M)
   - Same label (STR_1715 bad-state best definition from Stage 2)

3. **AUC uplift measurement**:
   ```r
   auc_80 <- mean(walk_forward_auc(features = features_v2_80))
   auc_88 <- mean(walk_forward_auc(features = features_v3_88))
   delta_auc <- auc_88 - auc_80
   
   # G7 admission gate
   assert(delta_auc >= 0.01)  # positive uplift
   ```

4. **Brier score check**:
   ```r
   brier_80 <- mean(walk_forward_brier(features = features_v2_80))
   brier_88 <- mean(walk_forward_brier(features = features_v3_88))
   assert(brier_88 <= brier_80)  # calibration not worse
   ```

5. **Feature importance (SHAP)**:
   ```r
   library(lightgbm)
   shap_v3 <- predict(fit_lgb_v3, X_test, predcontrib = TRUE)
   shap_importance <- colMeans(abs(shap_v3[, -ncol(shap_v3)]))
   # Top 12 SEFRS features이 top 30 importance에 ≥ 4건 inclusion 권장
   ```

### 4.3 Stage 4 → ADMIT gate

- **G7 DPL-RC Integration Uplift**: ΔAUC (88 - 80) ≥ 0.01 — PASS
- **G9 Codex Round Pass**: Codex stance ∈ {APPROVE, APPROVE_CONDITIONAL} — PASS

**G7+G9 PASS**: ADMIT 후보 (Judge + Governor 단계 진입).
**G7 FAIL**: DEFER (재설계).
**G9 REJECT veto=true**: DEFER (RC3).

---

## 5. 9 Admission Gates Summary

| Gate | Stage | Measurement | Threshold | Decision if FAIL |
|------|-------|-------------|-----------|------------------|
| **G1** | 1 | 3 ETF × 5 fields coverage | ≥ 95% per ETF | ABORT (RC1) |
| **G2** | 1 | 12-item PIT audit | 12/12 PASS, hard_fail=0 | HARD ABORT (RC2) |
| **G3** | 2 | Primary EBI stationarity | ADF p<0.05 OR KPSS p>0.10 | Investigate (regime-conditional?) |
| **G4** | 2 | Top/bottom decile NW t-stat | \|t\|≥2.0 on 1M forward | DEFER (RC4) |
| **G5** | 2 | Monotonicity OR non-linearity | \|spearman cor\|≥0.6 OR doc U-shape | Stage 3 with non-linear ML |
| **G6** | 3 | STR_1715 bad-state predictive power | stand-alone AUC≥0.55 OR ΔAUC≥0.02 vs baseline | DEFER (RC4) |
| **G7** | 4 | DPL-RC integration uplift | ΔAUC (88-80) ≥ 0.01 | DEFER (재설계) |
| **G8** | 3 | No redundancy | max abs(cor) with 80 features ≤ 0.70 | feature subset retry |
| **G9** | 4 | Codex Round Pass | stance ∈ {APPROVE, APPROVE_CONDITIONAL} | DEFER (RC3 if REJECT veto=true) |

---

## 6. 4 Rejection Criteria — Precise Triggers

### RC1 — SEIBro Data Fundamental Impossible

- **Trigger**: Path A (Public Data Portal) + Path B (SEIBro Open API) + Path C (manual export) 3건 모두 실패 + 운용사 (Samsung Asset Management) 직접 접촉도 거부 또는 응답 없음
- **Decision**: ABORT (이론적으로 valid이나 practically impossible)
- **Documentation**: `stage_artifacts/WT_D20260518_001/abort_rc1_data_impossible.json` 작성 + Q-Lead 보고

### RC2 — PIT Hard Fail

- **Trigger**: 12-item PIT audit 중 P1, P2, P4, P6, P7, P8, P9, P12 (hard fail 분류) 중 1건 이상 FAIL
- **Decision**: HARD ABORT (자기합리화 금지)
- **Documentation**: hard_fail item + specific evidence + remediation plan

### RC3 — Codex Reject Veto

- **Trigger**: Codex Critic Round stance = REJECT + veto = true
- **Decision**: DEFER
- **Documentation**: `challenge_note_alpha-research.md` REBUTTAL 작성 가능 but veto=true 시 Q-Lead 최종 결정

### RC4 — Predictive Power + Integration Uplift Both Fail

- **Trigger**: G4 (event study significance) FAIL + G6 (predictive power) FAIL 동시 OR G6+G7 둘 다 FAIL
- **Decision**: DEFER (재설계)
- **Documentation**: feature subset / definition 변경 옵션 listed

---

## 7. Codex Critic Round Mandate (Step 6, 별도 문서)

Stage 1~4 모두 PASS 시 Codex Round 5단계 실행 (`.claude/rules/codex-round.md`):

1. `alpha_package_draft.json` 작성 (`_draft` suffix)
2. PostToolUse Hook 자동 spawn (`codex_round_auto_trigger.sh`)
3. ~9-15 min wait
4. `codex_critic_response_alpha-research.json` 분석
5. `challenge_note_alpha-research.md` (concern disposition: ACCEPT / PARTIAL / REBUTTAL)
6. `alpha_package.json` final (PreToolUse `codex_round_pre_enforcer.sh` 통과)

---

## 8. Time Budget Summary

| Stage | Time | Cumulative |
|-------|------|-----------|
| Stage 1 Data Feasibility | 1h | 1h |
| Stage 2 Event Study | 2h | 3h |
| Stage 3 Predictive Model | 3~4h | 6~7h |
| Stage 4 DPL-RC Integration | 2~3h | 8~10h |
| Codex Round | 1~1.5h | 9~11.5h |
| Artifact prep + Judge handover | 1h | 10~12.5h |
| **Total Forge cycle** | **10~12.5h** | — |

**Phase A (current Design)**: 3~4h (이미 진행 중).
**Phase B (Forge cycle)**: 10~12.5h (Q-Lead confirm 후).

---

## 9. Risk Items + Mitigation (Forge cycle)

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| SEIBro API 인증 거부 | LOW | Path B (SEIBro Open API) + Path C fallback |
| Cross-source diff > 1% | MEDIUM | SEIBro 우선 + audit log + 운용사 contact |
| 252670 pre-listing handling | LOW | 2017-01 sample start로 회피 |
| Stage 2 monotonicity 약함 (non-linear pattern) | MEDIUM | Stage 3 LightGBM 우선 활용 |
| Stage 3 OOS AUC < 0.55 stand-alone | MEDIUM | Stage 4 integration uplift만 check; G6 OR-clause 발동 |
| Stage 4 ΔAUC < 0.01 | MEDIUM | feature subset (top-importance only) retry |
| Codex REJECT | LOW~MEDIUM | challenge_note 학술 1+ + L-code 1+ + 정량 data 3축 rebuttal |
| Compute time > 12.5h | LOW | parallel R workers (future_lapply) for walk-forward windows |

---

## 10. Self-rationalization 자동 검사

Forge 단계 매 Stage 완료 시:

```bash
# 금지 표현 grep
phrases=("영향 미미" "관행적 허용" "보수적이면 괜찮다" "대부분 결과 동일" 
         "이미 반영되어 있었을 것" "백테스트 기간이 충분히 길어서 상쇄"
         "실무적으로 유의미" "이 정도면 괜찮다")
for p in "${phrases[@]}"; do
  if grep -r "$p" stage_artifacts/WT_D20260518_001/; then
    echo "VIOLATION: self-rationalization '$p' 발견 → hard stop"
    exit 1
  fi
done
```

**Auto re-review trigger**: hit 1건 → Forge hard stop + 도훈 + Codex review.

---

## 11. Decision Matrix Summary

| Final state | Trigger | Action |
|-------------|---------|--------|
| **ADMIT 후보** | G1~G9 all PASS + Codex APPROVE / APPROVE_CONDITIONAL | Judge cycle 진입 + DPL-RC 88-feature pool inject 권고 |
| **ADMIT_CONDITIONAL** | G1~G9 PASS but Codex APPROVE_CONDITIONAL with revisions | revisions 반영 후 finalize |
| **DEFER** | G6 OR G7 FAIL (predictive 부족) | 재설계 (feature engineering 변경) |
| **DEFER (RC3)** | Codex REJECT veto=true | rebuttal 작성 후 Q-Lead 최종 결정 |
| **HARD ABORT (RC1)** | SEIBro 수집 fundamental impossible | 폐기 — 데이터 가용성 회복 후 재시도 |
| **HARD ABORT (RC2)** | 12-item PIT 중 hard_fail 1건+ | 폐기 — 재설계 (PIT-safe redesign) |

---

## 12. Codex Critic readiness checklist

- [x] 4 stages 각 sub-step + time budget
- [x] 9 admission gates 각 threshold + measurement method + decision matrix
- [x] 4 rejection criteria precise triggers
- [x] STR_1715 bad-state label 3 정의 inherit DPL-RC v3
- [x] Purged walk-forward (López de Prado 2018) 5 windows + embargo 1M
- [x] DPL-RC integration sub-steps (feature pool union + re-train + AUC uplift + Brier + SHAP)
- [x] Risk items + mitigation
- [x] Self-rationalization 자동 grep
- [x] Decision matrix (ADMIT / ADMIT_CONDITIONAL / DEFER / HARD ABORT)

**Audit complete. Phase A design Step 5 DONE. Step 6 = Codex Round + alpha_package finalize.**
