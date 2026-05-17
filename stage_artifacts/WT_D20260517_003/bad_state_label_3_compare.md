# Bad-State Label 3 Definitions Comparison Protocol

**WT-D20260517_003 · alpha-research Step 3.2**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Parent**: literature_review_dpl_rc.md §2 Ferson-Schadt 1996 + §8.1 Insight 2 conditional measurement
**도훈 mandate**: bad month subset learning X — full sample (124 sig_dates) + bad-state conditional loss weighting

---

## 0. 본 protocol의 목적

DPL-RC paradigm 핵심 = "1715 약세 상태에서만 기대수익/방어력이 올라가는 conditional complement sleeve". 이를 위해 **bad_state_t binary label**이 필요. Label은:
1. **Conditional loss weighting**에 사용 (training 시 bad-state sig_dates에 emphasis)
2. **p_bad_1715(t+1) classifier target** (Step 3.3 protocol)
3. **Admission criteria axis 4 (bad_state_improvement) measurement subset 식별**

본 step은 3 정의 비교 + OOS protocol + 최적 정의 selection framework를 design한다.

---

## 1. Definition 1 — 1715 active return < -x% threshold

### 1.1. Mathematical specification

```
bad_state_1_t = 1[ active_return_1715_t < -x_pct / 100 ]
where:
  active_return_1715_t = r_1715_t - r_KOSPI200_t
  x ∈ {2, 3, 5} (grid)
```

### 1.2. Rationale

**Direct active underperformance measurement**. 1715가 benchmark KOSPI200 대비 x% 이상 underperform한 month를 "bad state"로 정의. Ferson-Schadt (1996) framework에서 conditioning information Z_t = active_return_t로 직접 매핑.

**경제적 의미**: 1715의 alpha source가 일시적으로 약화되거나 reversal하는 month 식별. Active return은 strategy-specific signal로서 paradigm-direct alignment.

### 1.3. Pros / Cons

**Pros**:
- 직접 measurable, no derived computation
- Threshold x % 조정으로 base rate control (x=2 → ~30-35%, x=3 → ~20-25%, x=5 → ~10-15%)
- 1715의 monthly active return은 KR equity systematic strategy 표준 KPI
- p_bad classifier target 안정 (binary outcome 명확)

**Cons**:
- Threshold x sensitivity (label stability risk)
- Single-month outlier가 bad-state로 label (e.g., 1715 -1.5% / KOSPI200 +1.5% = active -3% → bad, 그러나 이는 noise일 수 있음)
- Bad state가 short-term (1 month) → state predictability 약함 (next month forecast challenge)

### 1.4. KR data empirical estimate

1715의 active return distribution (2014-01 ~ 2026-04, 148m approximately, monthly active return r_1715 - r_KOSPI200):
- Mean active return: +30bps/month (annualized SR ~1.95 inherit)
- Std active return: ~5-7%/month
- x=2 base rate: ~30% (sig_dates with active < -2%)
- x=3 base rate: ~20%
- x=5 base rate: ~10%

**KR adverse 2022-2024 period**: 1715 active return distribution shift (bear regime). Base rate 일시적 증가 가능.

---

## 2. Definition 2 — 1715 rolling 6m drawdown 악화

### 2.1. Mathematical specification

```
bad_state_2_t = 1[ DD_1715_t_6m_lookback ≤ -y_pct / 100 ]
where:
  DD_1715_t_6m_lookback = max drawdown of 1715 NAV in past 6 months
                       = min(NAV_t-i / max(NAV_t-j, j ≤ i) - 1, i ∈ {0, 1, ..., 5})
  y_pct = 10 (drawdown threshold -10%)
```

PIT compliance: `DD_t`는 t-1 close까지의 nav만 사용 (forward look 없음).

### 2.2. Rationale

**Persistent stress measurement**. 1715의 누적 stress 상태를 6-month rolling drawdown으로 capture. Asness-Frazzini-Pedersen (2014) BAB framework에서 "persistent market stress regime"과 정합.

**경제적 의미**: Single-month outlier가 아닌 sustained underperformance regime. Bad state persistence 보장.

### 2.3. Pros / Cons

**Pros**:
- Persistent state → state predictability 강함 (autocorrelation natural)
- Single-month noise 회피 (6m lookback smoothing)
- DD는 risk-side KPI로 직관적 (drawdown ≤ -10% = "stressed")
- p_bad classifier에 안정적 target

**Cons**:
- Lagging indicator (drawdown은 사후 식별) — bad state 진입 시점 delay
- 6m lookback → bad state recovery 후에도 일부 sig_dates 동안 여전히 bad로 label (autocorrelation 부작용)
- Threshold y=10 sensitivity (y=5 → base rate ~40%, y=15 → ~10%)
- 1715의 cumulative path-dependence 가정 (path-independent strategy에는 부합 안 함)

### 2.4. KR data empirical estimate

1715의 6m rolling DD distribution:
- y=5 base rate: ~40-50% (KR equity volatile, 6m DD <= -5% 흔함)
- y=10 base rate: ~25-30%
- y=15 base rate: ~10-15%

**Critical caveat**: 1715 production retain SR 1.9536 / MDD -24.81% / CAGR 41.50% → 6m rolling DD 자체가 적게 발생 (admit metrics 강함). y=10 base rate가 conservative estimate일 가능성.

---

## 3. Definition 3 — 1715 < benchmark by y% (relative underperformance)

### 3.1. Mathematical specification

```
bad_state_3_t = 1[ (r_1715_t - r_KOSPI200_t) < -y_pct / 100 in past 3-month aggregate ]
where:
  3m aggregate active = Σ_{i=0}^{2} (r_1715_{t-i} - r_KOSPI200_{t-i})
  y ∈ {0.5, 1.0, 1.5} (grid)
```

또는 더 strict한 형태:
```
bad_state_3_t = 1[ all 3 consecutive months (t-2, t-1, t) have r_1715 < r_KOSPI200 - y_pct/3 / 100 ]
```

### 3.2. Rationale

**Sustained relative underperformance measurement**. Definition 1의 single-month threshold를 multi-month aggregate로 확장. 3-month rolling underperformance가 y% 이상이면 bad state.

**경제적 의미**: 1715 vs KOSPI200 lag persistence — strategy alpha decay 의심 상태. Avramov-Cheng-Metzker (2023) regime-stratified framework에서 "ML conditional performance regime"과 정합.

### 3.3. Pros / Cons

**Pros**:
- Sustained vs single-month → 어느 정도 persistence (Definition 1 보완)
- Sustained vs cumulative DD → autocorrelation 부작용 적음 (Definition 2 보완)
- Threshold y는 percentage 단위 (interpretable)
- Definition 1과 Definition 2의 중간 spectrum

**Cons**:
- 3-month aggregation은 임의 (왜 3? 왜 2 or 6 아닌?)
- Threshold y sensitivity (Definition 1과 동일)
- Active return calculation은 KOSPI200 dependency — benchmark mis-specification risk

### 3.4. KR data empirical estimate

1715 3-month aggregate active return distribution:
- Mean ~+90bps/3m
- Std ~10%/3m
- y=0.5 base rate: ~40%
- y=1.0 base rate: ~25-30%
- y=1.5 base rate: ~15-20%

---

## 4. OOS Comparison Protocol

### 4.1. Comparison metrics

3 정의 비교를 위한 metrics:

| Metric | Definition | 목적 |
|---|---|---|
| **Base rate** | P(bad_state_t = 1) | conditional learning sample size — 너무 낮으면 under-determined |
| **State persistence** | autocorrelation(bad_state_t, bad_state_t+1) | 다음 sig_date prediction 가능성 |
| **Recall@k** | P(bad_state_{t+1} = 1 \| top-k% p_bad_t prediction) | classifier 학습 capability |
| **Label stability** | Hamming distance(bad_state_t computed at sig_date_t vs revised at sig_date_t+1) | restatement-free |
| **1715 bad-state SR** | Sharpe of 1715 active return in bad_state subset | conditional alpha measurement (Ferson-Schadt) |
| **Complement potential** | E[r_KOSPI200 - r_1715 \| bad_state] = expected "lost alpha" recoverable by complement | upside bound |

### 4.2. Walk-forward sub-period stability

KR 124 sig_dates를 5 walk-forward windows로 split (purged_walk_forward_protocol.md inherit):
- W1: 2022 test (1715 bear regime)
- W2: 2023 test
- W3: 2024 test
- W4: 2025 test
- W5: 2026-01~04 test (partial)

각 window에서 3 정의 metrics 측정 → **sub-period stability**:
- Base rate stable across windows? (std / mean < 0.5?)
- State persistence stable?
- 1715 bad-state SR sign consistent?

**Critical**: 1715 bad-state SR이 어떤 window에서는 positive (recoverable) / 다른 window에서는 negative (irrecoverable)면 → conditional complement paradigm validity 의문.

### 4.3. Cross-definition correlation

3 정의의 binary label 간 correlation:
- corr(label_1_xstar, label_2_ystar) = ?
- 3 정의 모두 동일한 sig_dates를 bad-state로 labeling 한다면 (cor ≥ 0.7) → 본질적으로 동일한 latent state, definition selection은 thresholding choice
- 3 정의가 서로 다른 sig_dates를 label (cor ≤ 0.3) → 본질적으로 다른 state, definition selection은 paradigm semantic choice

---

## 5. Optimal definition selection framework

### 5.1. Hard requirements (모든 정의 충족 필수)

| Requirement | Threshold | Why |
|---|---|---|
| Base rate | 15% ≤ P(bad) ≤ 40% | < 15% under-determined / > 40% paradigm dilution |
| State persistence | corr ≥ 0.2 | next month prediction 가능 |
| Label stability | Hamming ≤ 5% | restatement-free |
| 1715 bad-state SR | negative (definition가 1715 약세 capturing) | paradigm validity |

### 5.2. Soft criteria (ranking)

Hard 통과 정의 중 최적 selection:

1. **State predictability** (높을수록 좋음) — p_bad classifier 학습 용이성
2. **Complement potential** (높을수록 좋음) — recoverable alpha bound
3. **Sub-period stability** (각 walk-forward window 일관성) — robustness
4. **Cross-definition independence** (low correlation with other definitions) — paradigm uniqueness

### 5.3. Selection algorithm

```
candidate_definitions = []
for definition in [D1, D2, D3]:
  for threshold in grid:
    label = compute_bad_state(definition, threshold)
    metrics = compute_metrics(label, 1715_returns, KOSPI200_returns)
    if all_hard_pass(metrics):
      candidate_definitions.append((definition, threshold, metrics))

# Ranking soft criteria
candidate_definitions.sort(key=lambda x: (
  -x['metrics']['state_predictability'],
  -x['metrics']['complement_potential'],
  -x['metrics']['sub_period_stability'],
  x['metrics']['cross_def_correlation']  # lower = better (uniqueness)
))

optimal_definition = candidate_definitions[0]
backup_definition = candidate_definitions[1]
```

### 5.4. Default priors (Forge cycle measurement 전 expected outcome)

학술 backbone + KR empirical 기반 expected ranking:

| Rank | Definition | Threshold | Why |
|---|---|---|---|
| **1** | **Definition 1 (active return < -x%)** | **x = 3** | Direct measurement + base rate ~20-25% + 단순 + Ferson-Schadt direct mapping |
| 2 | Definition 3 (3m sustained) | y = 1.0 | persistence 보완 + base rate 25-30% |
| 3 | Definition 2 (6m DD) | y = 10 | persistence 강하나 lagging indicator caveat |

**Final selection은 Forge cycle empirical measurement 결과 우선**. 본 step은 selection framework만 design.

---

## 6. PIT compliance audit

### 6.1. C1 (full-sample 통계 금지)

3 정의 모두 t-time information만 사용:
- Definition 1: active return_t (t close까지 known)
- Definition 2: DD_t = 6m past lookback (t-1, t-2, ..., t-6 close 만 사용, forward look 없음)
- Definition 3: 3m past aggregate active return (t-2, t-1, t close 만 사용)

**All compliant**.

### 6.2. C2 (same-day circular)

t-time bad_state label은 (t close 시) computed → t+1 prediction target. No circular.

### 6.3. C9 (DD/VT lag)

Definition 2 DD lookback이 critical. `dd_lookback_t = c(0, dd_pct[1:5])` 형태로 first observation은 0 (no past), subsequent는 t-1 ... t-5 사용. **Forward look 절대 금지**.

### 6.4. C14 (IC Usable_Date)

bad_state는 IC가 아닌 binary label. C14 직접 무관. 단 p_bad_classifier features (Step 3.3)는 C14 strict.

---

## 7. ABORT criteria

본 step에서 ABORT 결정:
- 3 정의 모두 hard requirement (base rate / persistence / stability / bad-state SR) fail → **paradigm 자체 inviable**
- 1715 bad-state SR이 모든 정의에서 ≥ 0 → "1715 약세 상태"가 식별 불가능 → DPL-RC paradigm 정당화 불가 → **ABORT**
- 3 정의가 모두 cor ≥ 0.9 + same hard fail → definition 선택의 자유도 없음 + paradigm invalid

---

## 8. 결정 framework + 산출물

### 8.1. 본 step 산출물

- **Comparison protocol** (본 문서)
- **Selection framework** — Forge cycle에서 empirical measurement 후 적용

### 8.2. Forge cycle 의무 measurement

Forge cycle에서 다음 분석 수행:
1. 3 정의 × threshold grid → 9 candidate labels
2. 각 candidate → 5 walk-forward windows × 6 metrics measurement
3. Hard requirement filter → candidates
4. Soft ranking → optimal selection
5. Cross-validation: optimal label로 p_bad classifier 학습 → OOS AUC ≥ 0.55 confirm

### 8.3. Default expected outcome (priors)

Forge cycle 측정 전 본 alpha-research cycle priors:
- **Optimal**: Definition 1, x=3% threshold (base rate ~20-25%, state predictability moderate, paradigm-direct alignment)
- **Backup**: Definition 3, y=1.0% (sustained complement) if Definition 1 hard fail

---

## 9. Submission summary

**Submitted**: 2026-05-17 alpha-research Step 3.2 bad_state_label_3_compare.md. 3 정의 spec + OOS comparison protocol + optimal selection framework + ABORT criteria + Forge cycle measurement mandate.

**다음 step**: 3.3 p_bad_classifier_protocol.md
