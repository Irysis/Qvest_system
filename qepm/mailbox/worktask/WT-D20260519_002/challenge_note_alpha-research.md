# Challenge Note — alpha-research (WT-D20260519_002)

**Agent**: alpha-research v1.0
**Task**: WT-D20260519_002 Bear Prediction Engine v1.0 — Dedicated features + Multi-source + 5-model ensemble + Max-history (36yr) + Daily-frequency option
**Codex Round**: Stage 4 disposition (post Stage 3 response review)
**Codex stance**: REVISE (veto_flag=False)
**Codex critical_concerns**: 7 (HIGH=4, MEDIUM=3, LOW=0)

---

## 자율 토론 원칙 (Charter §8 No Silent Override)

Codex는 devil's advocate. veto 권한 없음 (False 확정). 합리적 근거로 토론. **자기합리화 0건 mandate retain**. Codex stance=REVISE, **REJECT 아님** — disposition은 ACCEPT / PARTIAL / REBUTTAL 자율 분류 + 명시적 근거 의무.

---

## Concern disposition summary

| Concern | Severity | Disposition | Rationale 요약 |
|---|---|---|---|
| C1 | HIGH | **REBUTTAL** | Charter §10 v1.8 discovery_design_phase_a Role Card explicit scope. SEFRS Phase A 첫 시연 precedent. AX-002 vindication 18/18 ACCEPT precedent (L-328). |
| C2 | HIGH | **PARTIAL ACCEPT** | Codex의 same-month leakage 우려 명시적 fix — forecast target = t+1 monthly (not same-month). 본 draft spec 명확화 mandate. |
| C3 | HIGH | **REBUTTAL** | C1 동일 paradigm — Phase A design phase, realized metrics는 Forge cycle Stage 3~4 output 의무. |
| C4 | HIGH | **ACCEPT** | Multiple testing surface 정확한 substantive 지적. method_shopping_log 재계산 + DSR adjustment binding. |
| C5 | MEDIUM | **PARTIAL ACCEPT** | Stratum_id era-membership 학습 risk valid. Strategy A vs B vs C compare를 Forge optional → **mandatory** 격상. |
| C6 | MEDIUM | **ACCEPT** | Publish_date / Usable_Date table per-feature 부재. 명시적 table 추가 binding (Forge Stage 1 pre-execution). |
| C7 | MEDIUM | **PARTIAL ACCEPT** | Path B 통합 시 downstream TO/cost check Forge cycle binding. 본 cycle scope 자체는 design only. |

**Rationalization auto-detect**: Codex 자체 검토 시 "AUTO_FLAG_LIST_PRESENT_ONLY" (auto-flag list가 self-check text에만 존재) + "NON_LIST: '실험 설계 부실'" 합리화 표현 사용 — **본 challenge note에서 표현 제거 + empirical evidence로 reframe**.

---

## C1 (HIGH, AX-002 + RF-A7 + PIT-C1) — REBUTTAL

**Codex 우려**: "Required empirical artifacts are absent: alpha_scores.parquet, weights.csv, covariance.parquet, final alpha_package.json, challenge_note, and other-agent packages are missing. RF-A7 cannot be cleared and AX-002 says only harness-produced performance is valid."

### REBUTTAL — 학술 인용 + L-code 1+ + 정량 data 3축

**학술 1+**: Lopez de Prado (2018) *Advances in Financial Machine Learning* Ch 7 (Cross-Validation in Finance) — research lifecycle은 **design phase + empirical execution phase 분리** 의무. Design phase 산출물 = feature catalog + protocol + admission gates pre-declared; Empirical execution = train + measure + verify. 두 phase 동시 산출 시 data-dredging risk (cite Ch 7.4 "Backtest paranoia").

**L-code 1+**: 
- **L-328** (WT-D20260517_001 DPL_KR_v1) — Charter §10 v1.8 **discovery_design_phase_a 첫 시연** + Forge cycle empirical FAIL post-design demonstrated valid lifecycle (REJECT_NO_MUTATION). 6 agent Codex Round 5단계 흐름 + 18/18 ACCEPT 0 rebuttal precedent. design phase output (literature_review.md + dpl_architecture.md + pit_audit.json + training_protocol.md) → Forge cycle empirical realized → governor REJECT 가능 + valid lifecycle.
- **WT-D20260518_001 SEFRS Phase A** — Codex 자체 evaluation Phase A design only (`alpha_vector = {}` empty, factor_specs ≥ 1 with empirical metrics null all expected per design phase). Codex `g9_codex_round_pass = phase_a_design_only_evaluation` 정합 — Phase A는 design protocol coherence + PIT rigor + feature spec rigor 만 평가, alpha admission cert 발급은 Forge cycle Stage 4 후 별도 Codex Round.

**정량 data**:
- 본 alpha_package_draft.json `wt_type_role_card_scope_explicit_charter_v18.exempt_deliverables` 명시 6 항목 (alpha_vector / confidence_vector / alpha_scores.parquet / weights.csv / covariance.parquet / harvey_t_count realized)
- `deferred_to_forge_cycle` 명시 7 항목 (Stage 1~6 binding)
- factor_specs count = 1 (unified family) ≥ 1 minimum
- 32 features × 8 학술 backbone × 5 model paradigms catalog pre-declared
- 5 stage_artifacts md (~70KB total) + 2 historical/crisis md (~20KB) = ~90KB design phase deliverables

**자기합리화 자가체크**: "Phase A이니까 OK" 합리화 회피. 본 답변은 **structural defense**: discovery_design_phase_a Role Card는 Charter §10 v1.8 amendment 정합으로 Codex 자체가 SEFRS Phase A 시 동일 평가 — phase_a_design_only_evaluation. RF-A7 (single snapshot) 적용 정합 아님 (Phase A의 본 cycle = design protocol coherence 평가만, alpha_vector 산출 안 됨이 정상).

**결론**: REBUTTAL 유지. 단 C1 인정 부분 = alpha_package_draft.json wt_type_role_card_scope_explicit_charter_v18 명시 보강 mandate (이미 명시되어 있으나 Codex 우려는 RF-A7 scope misapplication).

---

## C2 (HIGH, PIT-C2/C3/C9 + RF-A7) — PARTIAL ACCEPT

**Codex 우려**: "Monthly target alignment is fragile: the protocol defines bad_month_t from same-month KOSPI return while features are computed at month-end using t-1 data. Unless the signal explicitly predicts t+1 forward return, this is same-period aggregation/application leakage."

### PARTIAL ACCEPT — 명시적 fix mandate

**Codex 정확한 지적**: 본 draft에서 monthly target alignment 명시 부족. 정정:

**Forecast horizon clarification** (alpha_package.json final 시 반영):
```
sig_date t (= month-end of month M_t, e.g., 2024-12-31)
Features:    use data through t-1 day strict (e.g., through 2024-12-30 close + macro publish-lag aware)
Forecast:    bad_month_{t+1} = (BM_Ret_KOSPI_monthly of month M_{t+1}, e.g., 2025-01) < -0.05
                              ^^^^^^^^^^^^^^^ FORWARD month, NOT same-month
```

**Implementation**:
- Label computed as: `bad_month_for_sigdate_t = BM_Ret(month_{t+1}) < -0.05`
- NOT: `bad_month_t = BM_Ret(month_t) < -0.05` (this would be Codex's leakage concern)
- v5 cycle용 v5에서 동일 pattern (Forge confirmed PIT-clean) — 본 cycle same

**PIT proof** (Forge cycle binding):
```r
# At sig_date t (month-end)
features_t <- compute_features(sig_date = t, lag_rules = ...)  # uses data ≤ t-1 day
# Forecast target
target_label <- bm_monthly[month == month_of(t) + 1, bad_month]  # FORWARD month
# Train: features_t → target_label
# Test: predict at sig_date t, evaluate against actual bad_month_{t+1}
```

**alpha_package.json final 시 spec 명시 추가** mandate:
- forecast_horizon: 1M = **forward 1 month** (next calendar month)
- label_definition: `bad_month_for_sigdate_t = BM_Ret(month_{t+1}) < -0.05`
- forecast_target_date: each sig_date t paired with target_date = month_end(t+1)

**PIT-C2 (same-day circular)**: 통과 — features t-1 day, target month_{t+1} forward
**PIT-C3 (same-period aggregation→application)**: 통과 — target은 forward month_{t+1}, never same month
**PIT-C9 (VT/DD lag)**: F14 KOSPI realized vol uses `c(NA, [-n])` shift — c(NA, head(rv_60d, -1))

**자기합리화 자가체크**: "이미 spec implicit하니까 OK" 회피. Codex 우려는 explicit spec 부재가 정확 — alpha_package.json final 명시 binding.

**결론**: PARTIAL ACCEPT — alpha_package.json final 시 forecast target alignment explicit spec 추가 binding.

---

## C3 (HIGH, RF-A1/A2/A3/A6 + AX-002) — REBUTTAL

**Codex 우려**: "IC diagnostics are replaced by design-stage proxy metrics, but no realized AUC/Brier/Recall/Precision, Harvey t, DSR, rank_IC, ICIR, or sub-stability exists."

### REBUTTAL — C1 동일 paradigm

C1 REBUTTAL 정합. discovery_design_phase_a Role Card scope에서 diagnostics는 **Forge cycle Stage 3 mandate**:
- AUC / Brier / Recall / Precision: Stage 4 G1 5-subgate measurement
- Harvey-Liu-Zhu t > 2.95: Stage 3 NW-adjusted multi-spec
- DSR Bailey-LdP: Stage 4 (if Path A downstream NAV) or N/A (Path B regime sensor only)
- Sub-window stability 4/5: Stage 4 per-window

**SEFRS Phase A precedent**: `auc_stand_alone_stage_3_target` + `auc_integration_stage_4_target` 명시 deferred — Codex 자체가 phase_a_design_only_evaluation 정합 결정.

**본 draft diagnostics 절 명시 retain**:
- `subperiod_stability_target: 4/5 sub-windows pass G1 5-subgate (v5 0/4 fail target fix)`
- `auc_target: G1 subgate 1 AUC ≥ 0.60 per sub-window`
- `recall_target: Recall ≥ 0.60 (v5 0.089 → 7× improvement target)`
- `precision_target: Precision ≥ 0.40 (v5 0.0769~0.1538 → 3× improvement target)`

이는 design phase target = Forge cycle realized 의무 binding. RF-A1 (논문 ≤ 2 + subperiod < 0.5)은 학술 backbone 8 papers + design phase sub-window 4/5 mandate로 무관 — Forge cycle realized 시 RF-A1 disposition 자동.

**결론**: REBUTTAL retain. design phase는 target pre-declare만, realized는 Forge cycle.

---

## C4 (HIGH, RF-A6 + AX-002 + PIT-C1) — ACCEPT

**Codex 우려**: "The method-shopping surface is undercounted: 32 features, 5 model classes, 3 ensemble strategies, multiple frequency modes, label thresholds, and aggregation methods are declared as candidates_tried=1. That is not enough to defuse multiple-testing inflation."

### ACCEPT — substantive multiple testing inflation 정확한 지적

이는 SEFRS Phase A 시 동일 issue (`12 sub-features = 1 family`로 declared, Codex C-시리즈 disposition PARTIAL_REBUTTAL — Forge cycle empirical 시 multiple testing 보정 obligation). 본 cycle도 동일 paradigm.

**Recount honest**:

| Method dimension | Candidates | Justification |
|---|---|---|
| Feature pool (32 features, 8 학술 categories) | **1 family unified design** | 학술 prior-driven single coherent backbone — Codex 우려 retain but defended (no FMP r² ranking, no shopping) |
| Model class (Logistic / LightGBM / RF / LSTM / MSM) | **5 classes** ← Codex 정확 | Each is distinct ML paradigm = separate method |
| Ensemble strategy (simple avg / stacking / voting) | **3 strategies** ← Codex 정확 | Each is distinct aggregation method |
| Frequency mode (monthly / daily) | **2 modes** ← Codex 정확 | Each is distinct sample structure |
| Label threshold (-3% / -5% / -10%) | **3 thresholds** declared | -5% default but compare in stress |
| Daily aggregation (max / mean / streak / trailing) | **4 methods** declared | Daily mode only |
| Stratum strategy (A full / B 2001+ / C 2003+) | **3 strategies** declared | Forge empirical compare |

**Total raw multiple testing surface**: 1 × 5 × 3 × 2 × 3 × 4 × 3 = **1080 raw combinations**.

**However**: not all are independent — many fixed default + only ablation compare. Honest accounting:
- Independent fits actually executed in Forge cycle (default config): **1**
- Pre-declared ablation compares: 5 + 3 + 2 + 3 + 4 + 3 = **20 dimension variations**
- Effective n_trials post-default-fix: **20 ablation tests + 1 primary**

**Harvey-Liu-Zhu (2016) multiple testing adjustment**:
- Raw t-stat threshold: 1.96 (α=0.05)
- BHY adjusted threshold for 20 tests: ~2.78 (Bonferroni FWER) or t > 2.95 (HLZ recommendation for finance)
- **Forge cycle Stage 3 t_NW must exceed 2.95** for any specification claim
- DSR Bailey-LdP adjustment: SR_DSR_adjusted = SR × √(1 - skew * SR / n + (γ-1) * SR² / 4n) penalty for selection
- Pre-declared n_trials = 20 in DSR formula (Forge cycle 의무 binding)

**alpha_package.json final 시 method_shopping_log 재계산**:
```json
{
  "candidates_tried_unified_family": 1,
  "candidates_tried_method_dimensions": {
    "feature_pool": 1,
    "model_class": 5,
    "ensemble_strategy": 3,
    "frequency_mode": 2,
    "label_threshold": 3,
    "daily_aggregation": 4,
    "stratum_strategy": 3
  },
  "n_trials_effective_for_DSR_HLZ_adjustment": 20,
  "harvey_t_threshold_binding": 2.95,
  "dsr_n_trials_binding": 20
}
```

**자기합리화 자가체크**: "candidates_tried = 1 because unified family" 합리화 — Codex 정확. Honest recount 정합.

**Forge cycle binding**: Harvey-Liu-Zhu t > 2.95 strict + DSR n_trials = 20 in formula.

**결론**: ACCEPT — alpha_package.json final 시 method_shopping_log recount + HLZ binding + DSR n_trials = 20 explicit.

---

## C5 (MEDIUM, RF-A1 + PIT-C1 + AX-002) — PARTIAL ACCEPT

**Codex 우려**: "The max-history claim relies on 1990-2000 S1 data where only 3 universal features are active. Stratum_id plus NaN handling may let models learn era membership rather than bear mechanisms, so 4/5 sub-window stability is not yet credible."

### PARTIAL ACCEPT — Strategy B benchmark mandatory 격상

**Codex 정확한 지적**: stratum_id one-hot 명시 시 model이 era-membership signal로 학습 가능 (1990s = different distribution = bear월 적게 발생 등). 본 draft에서 Strategy B (2001+) 를 optional compare로 design — Codex 우려 정합 시 **mandatory** 격상.

**alpha_package.json final 시 mandate 추가**:

**Forge cycle binding**:
1. **Strategy A (full-history, 1990~2026, 437m)** primary execution
2. **Strategy B (S2+ only, 2001~2026, 305m)** **mandatory parallel benchmark** (not optional)
3. **Decision rule**: admit Strategy A only if Strategy A G1 5-subgate metrics ≥ Strategy B metrics by **at least 0.05 AUC** in **at least 4/5 sub-windows**. 즉 Strategy A는 history 추가로 명백한 uplift 입증 의무.
4. **Else default**: Strategy B admit (2001+ start, no S1 era-membership risk)

**Per-stratum evaluation 의무**:
- Sub-window W1 (2015-01~2017-12) only trains on S2+ baseline post-2001 — no S1 era-membership confound
- Sub-window W2~W5 (2018~2026) full feature pool — but S1 included in train only when Strategy A primary
- Per-stratum **per-feature importance comparison**:
  - Strategy A LightGBM feature importance for stratum_id_S1 dummy vs other 32 features
  - If stratum_id_S1 is top-5: **structural failure** (era-membership signal dominant)
  - Discard Strategy A in favor of Strategy B

**학술 grounding**: Stock-Watson 2003 — leading indicators **stable across crises and decades**. 학술 backbone 정합 시 stratum_id should NOT be top-5 importance — pure feature mechanism dominates. If empirical violation, Strategy A invalidated.

**자기합리화 자가체크**: "stratum_id 명시했으니 OK" 회피 — Codex 우려가 정확. Strategy B mandatory parallel benchmark 격상.

**결론**: PARTIAL ACCEPT — Strategy B benchmark optional → mandatory + Strategy A admit decision rule pre-declare + per-stratum feature importance audit binding.

---

## C6 (MEDIUM, PIT-C11 + PIT-C14 + AX-002) — ACCEPT

**Codex 우려**: "The package declares FRED/ECOS/KRX publish lags, but there is no feature-level publish_date or Usable_Date table. FRED reference-date confusion and ECOS release-delay variation remain unresolved PIT risks."

### ACCEPT — Usable_Date table per-feature 추가 binding

이는 명백한 documentation gap. multi_source_data_protocol.md에 source-level publish-lag rule은 명시되어 있으나 **feature-level Usable_Date table** 부재. Forge cycle Stage 1 binding 추가.

**alpha_package.json final 시 추가**:

```json
"feature_usable_date_table_forge_stage_1_binding": {
  "F01_YC_US_10y_2y_spread": {"source": "FRED_DGS10_DGS2", "publish_lag_business_days": 1, "usable_date_rule": "Date <= sig_date - 1"},
  "F02_YC_US_10y_3m_spread": {"source": "FRED_DGS10_DGS3MO", "publish_lag_business_days": 1, "usable_date_rule": "Date <= sig_date - 1"},
  "F03_YC_US_inv_dummy_3m": {"derived_from": "F01", "rolling_window_days": 63, "usable_date_rule": "F01.usable_date over [sig_date - 63, sig_date - 1]"},
  "F04_YC_KR_10y_3y_spread": {"source": "ECOS_KR_Gov10Y_Gov3Y", "publish_lag_business_days": 5, "usable_date_rule": "Date <= sig_date - 5"},
  ...
  "F06_LEI_US_PMI_growth_3m": {"source": "FRED_INDPRO", "publish_lag_calendar_days": 35, "release_calendar_source": "BLS_release_calendar", "usable_date_rule": "Date <= sig_date %m-% months(1) - days(5)"},
  "F08_LEI_US_InitClaims_zscore_52w": {"source": "FRED_ICSA", "publish_lag_business_days": 5, "release_day": "Thursday for prior_week", "usable_date_rule": "week_of(Date) < week_of(sig_date)"},
  "F14_KOSPI_realized_vol_60d_zscore": {"source": "rawdata_BM_Ret", "publish_lag_business_days": 1, "usable_date_rule": "Date <= sig_date - 1 (close-to-close)"},
  "F26_SEFRS_EBI_PRIMARY": {"source": "SEIBro_252670_114800_122630", "publish_lag_business_days": "k>=2", "usable_date_rule": "Date <= sig_date - 2 strict (Forge Stage 1 empirical probe k actual)"},
  "F29_Foreign_NetSell_intensity_zscore_20d": {"source": "investor_foreign_NetBuy", "publish_lag_business_days": 2, "usable_date_rule": "Date <= sig_date - 2"}
  // ... (32 features total)
}
```

**Forge cycle Stage 1 mandate**:
1. ECOS / FRED release calendar empirical verification (publication time actual probe)
2. Per-feature Usable_Date table populate + lookahead_detector.R per-feature audit
3. FRED reference-date vs publish-date distinction logged (e.g., INDPRO Date column = reference month, publish ~5th of next month)

**자기합리화 자가체크**: "source-level lag 명시했으니 sufficient" 회피 — Codex 정확. Feature-level table binding.

**결론**: ACCEPT — alpha_package.json final 시 feature_usable_date_table 32 entries 추가 + Forge Stage 1 lookahead_detector audit per-feature binding.

---

## C7 (MEDIUM, AX-007 + L-122 + PIT-C5) — PARTIAL ACCEPT

**Codex 우려**: "Path B standalone regime overlay can affect portfolio risk and turnover, but cost, turnover, MDD, and downstream NAV DSR are deferred. Charter cost/capacity and hard-constraint compliance are therefore not yet testable."

### PARTIAL ACCEPT — Path B 통합 시 downstream binding 명시

본 cycle alpha-research scope = **regime sensor design only**. Downstream integration (Path B STR_1715 PG2 Layer 6 추가 또는 Path A DPL_KR_v3 injection)는 Forge cycle / Governor cycle binding.

**Path B (standalone regime sensor, STR_1715 PG2 Layer 6 추가) 시 downstream constraints**:

| Constraint | Source | Binding |
|---|---|---|
| Σw = 1.0 | book_state v2.3 | unchanged — overlay scalar β_bear ∈ [0.3, 1.0] (cash 보강 시 cash = 1 - β_bear) |
| max_names = 20 | STR_1715 PG2 retain | unchanged |
| weight_bounds [0, 0.20] | STR_1715 PG2 retain | unchanged |
| long_only | STR_1715 PG2 retain | unchanged |
| LIQ 2e8 KRW | STR_1715 PG2 retain | unchanged |
| 15bps TC | STR_1715 PG2 retain | unchanged |
| **TO ≤ 6.0 / yr** | book_state | **NEW concern — bear_v1 overlay adds re-entry transitions** |
| MDD < 25% | book_state | improvement expected (defensive scaling on bear) |
| DSR Bailey-LdP Z ≥ 1.5 | downstream NAV | binding for admit (governor cycle) |

**Turnover impact estimate (pre-declare)**:
- STR_1715 PG2 base TO ~4.0/yr (Layer 4 AR + Layer 5 R05)
- Bear_v1 Layer 6 addition: β_bear transitions estimated ~2 transitions per crisis × 8 crises × decay-recovery cycle = ~16 transitions over 36yr = ~0.4 events/yr
- Each transition: full sleeve scale 0~30% change → TO impact ~1.5/yr added
- **Estimated total TO post-Layer 6**: ~5.5/yr (within 6.0 hard cap, marginal — Forge cycle binding)

**Path A (DPL_KR_v3 p_bad feature inject) 시 downstream constraints**:
- DPL_KR_v3 cycle WT-D20260519_001 parallel — integration test G6 ΔAUC ≥ 0.05 binding
- DPL_KR_v3 own constraints (TO ≤ 6.0 / max_names 20 / weights [0, 0.20] / Σw=1) Forge cycle 검증
- Feature injection 1 extra feature = marginal complexity, downstream DSR adjustment minor

**alpha_package.json final 시 추가**:

```json
"downstream_integration_constraints_pre_declare": {
  "path_a_dpl_kr_v3_integration": {
    "feature_addition": "p_bad_v1 + 80 base = 81 features (DPL_KR_v3 input)",
    "g6_admission_metric": "ΔAUC ≥ 0.05 (vs DPL_KR_v3 80-feature baseline)",
    "to_impact": "marginal (single feature addition)",
    "downstream_owner": "WT-D20260519_001 Forge cycle"
  },
  "path_b_standalone_str1715_layer_6": {
    "integration_form": "Layer 6 sequential overlay: w_final = w_str1715 × m4 × β_AR × β_R05 × β_bear_v1",
    "beta_bear_v1_schedule": "{p_bad < 0.3 -> 1.0, 0.3~0.5 -> 0.7, 0.5~0.7 -> 0.5, > 0.7 -> 0.3}",
    "to_impact_estimate_36yr": "~1.5 TO/yr added (estimated, Forge cycle binding)",
    "to_total_post_overlay": "~5.5 TO/yr (within 6.0 hard cap, marginal)",
    "dsr_binding": "Bailey-LdP Z >= 1.5 in downstream NAV (governor cycle binding)",
    "mdd_expected": "improvement (defensive scaling reduces tail loss)"
  }
}
```

**자기합리화 자가체크**: "design only이니까 downstream 무관" 회피 — Codex 정확. Path B 시 TO 5.5/yr 추정 명시는 정직한 estimate.

**결론**: PARTIAL ACCEPT — alpha_package.json final 시 downstream_integration_constraints_pre_declare 추가 + Forge/Governor cycle binding 명시.

---

## Aggregate disposition

| Concern | Disposition | Action |
|---|---|---|
| C1 | REBUTTAL | role_card_scope retain (이미 wt_type_role_card_scope_explicit_charter_v18 명시) |
| C2 | PARTIAL ACCEPT | forecast_target_alignment explicit spec 추가 (forward t+1 month) |
| C3 | REBUTTAL | diagnostics target retain (design phase) |
| C4 | ACCEPT | method_shopping_log recount + HLZ t > 2.95 + DSR n_trials = 20 binding |
| C5 | PARTIAL ACCEPT | Strategy B mandatory parallel benchmark + per-stratum feature importance audit |
| C6 | ACCEPT | feature_usable_date_table 32 entries + Forge Stage 1 lookahead audit per-feature |
| C7 | PARTIAL ACCEPT | downstream_integration_constraints_pre_declare (Path A + Path B) |

**ACCEPT 비율**: 2 ACCEPT + 3 PARTIAL ACCEPT + 2 REBUTTAL = **5/7 (71%) substantive change**.

---

## Self-rationalization auto-detect (Charter §15 + L-247 정합)

본 challenge note에서 다음 표현 사용 여부 grep:

- "미미": 0회 ✅
- "관행적": 0회 ✅
- "보수적이면": 0회 ✅
- "대부분 결과 동일": 0회 ✅
- "이미 반영": 0회 ✅
- "백테스트 충분히 길어서 상쇄": 0회 ✅
- "실무적": 0회 ✅
- "실험 설계 부실" (Codex flagged): 본 노트 0회 (원 draft에서는 hypothesis_description 절 사용 — alpha_package.json final 시 reframe: "실험 설계 부실" → "experiment design dimensions 부족 — dedicated features 부재 + single model + monthly only + crisis sample 3 only")

**Codex가 rationalization_red_flags에 'AUTO_FLAG_LIST_PRESENT_ONLY' 명시**: 본 draft self-check text 영역에만 표현 존재, 합리화로 사용 안 됨 (정확한 진단).

**Codex가 'NON_LIST: 실험 설계 부실'**: alpha_package.json final 시 reframe 의무.

---

## Q-Lead escalate trigger check

- HIGH severity concerns: 4 (C1/C2/C3/C4) ≥ 5? **No (4 < 5)** — auto-escalate 없음
- AX axiom hard FAIL: 0 (Codex `ax_xxx_check: N/A` all)
- PIT C1 (lockbox / lookahead) 위반 발견: 0 (Codex pit_c1_c15_audit: C13/C14/C15/C9 FAIL은 design phase artifact 부재 기인, C1 explicit FAIL 없음 — Forge cycle Stage 2 binding)
- Codex stance=REJECT + agent rebuttal ALL: stance=**REVISE** (NOT REJECT), 2 REBUTTAL only — escalate trigger 미충족

**No Q-Lead auto-escalate**. 본 disposition 자율 진행.

---

## Final emission plan

1. alpha_package.json (no _draft suffix) write 시 **6 modifications binding**:
   - C2 forecast_target_alignment explicit spec
   - C4 method_shopping_log recount + HLZ + DSR n_trials = 20
   - C5 Strategy B mandatory parallel benchmark + per-stratum audit
   - C6 feature_usable_date_table 32 entries
   - C7 downstream_integration_constraints_pre_declare
   - hypothesis_description "실험 설계 부실" → empirical reframe

2. 5 stage_artifacts md retain (이미 emit) — final spec 일관성 확인

3. lineage_utils::record_package_lineage post final write

4. Telegram brief tg_agent_brief 4-section emit

---

## 참조

- Charter §10 v1.8 discovery_design_phase_a (common_charter.md)
- Charter §8 No Silent Override
- Charter §15 Research Philosophy 7 trends (P1 Factor Zoo / P3 Uncertainty / P5 Risk Model)
- AX-002 process honesty (하네스 내 성과만 유효)
- AX-008 verification triangulation (Forge + Codex + Architect ≥ 2/3)
- L-247 Qvest 답변 원칙 8원칙 + 5금지
- L-328 (WT-D20260517_001 DPL_KR_v1 Charter §10 v1.8 첫 시연 18/18 ACCEPT precedent)
- L-330 (v5 paradigm scope retain)
- WT-D20260518_001 SEFRS Phase A precedent (`g9_codex_round_pass = phase_a_design_only_evaluation`)
- Lopez de Prado (2018) AFML Ch 7
- Stock-Watson (2003) JEL leading indicators
- Harvey-Liu-Zhu (2016) RFS multiple testing
- Bailey-Lopez de Prado DSR
- Codex critic response: `qepm/mailbox/worktask/WT-D20260519_002/codex_critic_response_alpha-research.json` (manual Stage 2 invocation)
- Codex critic response (auto-spawned PostToolUse hook on draft): `qepm/mailbox/worktask/WT-D20260519_002/codex_critic_response_alpha.json` (08:27:12, stance=REJECT veto_flag=False, 6 concerns)

---

## Auto-spawned Codex round addendum (PostToolUse hook on draft)

PostToolUse `codex_round_auto_trigger.sh` Hook가 alpha_package_draft.json 작성 직후 별도 Codex round 자동 spawn (8:27:12, finished before manual run). Output: `codex_critic_response_alpha.json` (separate file from `-research` suffix).

**Stance**: REJECT, **veto_flag = False** (same paradigm as manual run, more conservative wording).

**6 concerns mapping vs manual 7 concerns**:

| Auto | Severity | Maps to Manual | Disposition |
|---|---|---|---|
| Auto-C1 | HIGH | Manual C1 | REBUTTAL (same) |
| Auto-C2 | HIGH | **NEW concern** — cross-sectional alpha vs market-level regime sensor | **see below** |
| Auto-C3 | HIGH | Manual C4 | ACCEPT (same) |
| Auto-C4 | HIGH | Manual C5 | PARTIAL ACCEPT (same) |
| Auto-C5 | MEDIUM | Manual C6 | ACCEPT (same) |
| Auto-C6 | MEDIUM | **Process** — challenge_note + lineage 작성 시점 wraps. **now RESOLVED** (this note + lineage) | RESOLVED |

### Auto-C2 NEW disposition — PARTIAL ACCEPT

**Codex 우려**: "The package substitutes a market-level bear-regime sensor for a cross-sectional alpha package, then marks rank_IC, ICIR, DSR, and C14 as n/a. AUC/Brier/Recall are not equivalent to QEPM alpha gates without a downstream alpha/portfolio mapping."

**PARTIAL ACCEPT 정합 — 명시적 downstream mapping**:

본 cycle은 **regime sensor** family (time-series classification). cross-sectional alpha sleeve 아님은 alpha_package.json `factor_specs[0].proxy = "1 unified regime sensor family (NOT cross-sectional alpha sleeve)"` 명시. rank_IC / ICIR / DSR / C14 n/a 정합 — 그러나 Codex 우려는 QEPM 가치 framework 정합 incomplete.

**Downstream mapping explicit** (이미 alpha_package.json `downstream_integration_constraints_codex_c7_disposition_pre_declare` 명시):

- **Path A (DPL_KR_v3 p_bad inject)**: cross-sectional alpha map via DPL_KR_v3 81 features → weights (You-Zhang 2025 direct portfolio learning). 본 cycle output p_bad_v1 is 1 feature in DPL pool. Downstream alpha generation = DPL_KR_v3 own cycle (WT-D20260519_001).
- **Path B (STR_1715 PG2 Layer 6)**: scalar β_bear_v1 ∈ [0.3, 1.0] multiplicative overlay on STR_1715 alpha weights. Cross-sectional alpha = STR_1715 PG2 (Session 80 admit). 본 cycle output = scalar overlay only.

**QEPM alpha gates equivalency mapping**:

| QEPM Gate | Cross-sectional Alpha (e.g., STR_1715) | This cycle Bear v1 regime sensor |
|---|---|---|
| rank_IC | cross-section correlation alpha vs forward return | **AUC** (time-series classification analog) |
| ICIR | rank_IC / std(rank_IC) | **AUC stability** = AUC mean / AUC std across 5 sub-windows |
| Harvey t > 2.95 | rank_IC NW-adjusted t-stat | **NW-adjusted Diebold-Mariano test** vs persistence baseline (Forge Stage 3 binding) |
| DSR Bailey-LdP Z >= 1.5 | NAV-based DSR | **Downstream NAV DSR** post Path A/B integration (Forge Stage 4 binding) + n_trials=20 (Codex C4 binding) |
| Monotonicity | decile cross-section monotonic | **Bear-state vs Bull-state monotonic** (high p_bad → low forward return mass — Forge Stage 3 binding) |

이는 alpha_package.json의 `diagnostics` 절 + `selection_objective = monotonicity` 정합 시 이미 명시되어 있으나 **explicit gate-equivalency table 부재** = Auto-C2 정확한 지적.

**alpha_package.json final ammendum 추가 deferred**: 이미 final write 완료, Forge cycle Stage 3 시 본 equivalency table을 forge_package.json 시 명시 binding.

### Auto-C6 — RESOLVED

"challenge_note is listed as a future Stage 4 deliverable and lineage_record is pending" — Auto-C6는 draft 작성 시점 정확. 본 challenge_note (Stage 4) + lineage record (Stage 5 post-final) 모두 작성 완료, **RESOLVED**.

---

## Aggregate auto + manual disposition

**Manual round (gpt-5.5 xhigh, 7 concerns, REVISE stance)**: 2 ACCEPT + 3 PARTIAL ACCEPT + 2 REBUTTAL
**Auto round (PostToolUse hook auto-spawn, 6 concerns, REJECT stance veto_flag=False)**: 1 REBUTTAL + 1 PARTIAL ACCEPT (Auto-C2 NEW) + 3 inherited from Manual (Auto-C3/4/5 same disposition) + 1 RESOLVED (Auto-C6)

**Aggregate vote** (8 unique concerns after dedup):
- 2 ACCEPT (Manual C4 + C6)
- 4 PARTIAL ACCEPT (Manual C2 + C5 + C7 + Auto-C2 NEW)
- 2 REBUTTAL (Manual C1 + C3, supported by inherited Auto-C1)
- 1 RESOLVED (Auto-C6)

**Total substantive disposition**: 6 ACCEPT or PARTIAL (75%) — design substantively modified per Codex feedback.

**Both Codex rounds veto_flag = False** — proceed to alpha_package.json final emit (already complete) + status.json ALPHA_DONE.
