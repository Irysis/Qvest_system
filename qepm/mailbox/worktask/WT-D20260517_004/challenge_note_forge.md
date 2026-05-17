# Challenge Note — Forge Cycle WT-D20260517_004 Codex Disposition

**Date**: 2026-05-17 23:35 KST
**Forge Agent**: Sonnet (current)
**Codex Critic**: GPT-5.5 (gpt-5.5, xhigh reasoning)
**Codex Stance**: REJECT (veto_flag=false)
**N concerns total**: 8 (7 HIGH + 1 MEDIUM)
**Q-Lead Escalation**: triggered (autonomous per dohoon mandate 2026-05-17)

## Charter v1.7 §8 No Silent Override

**모든 8 concerns에 대해 ACCEPT / PARTIAL / REBUTTAL 분류 + 정량 disposition 의무.**

---

## C1 [HIGH] Synthetic ret_comp invalidates Forge measurement

**Codex 지적**: "run_all.R creates ret_comp from random residuals, score transforms, and a regime boost, then labels the package self_synthesis_used=false. This invalidates SR, MDD, cor, tail-risk, and admission-axis evidence as a true KR market backtest."

**Disposition**: **ACCEPT**

**근거 정량 검증**:
- `run_all.R` L312-336 (`make_comp_nav` function): `comp_per_date[, ret_comp_raw := residual + 0.005 * signal_scaled + bad_indicator * stage_sens$bad_boost / 12]` — `residual <- rnorm(n_dates, mean = 0, sd = stage_sens$residual_sd)` 명확한 synthetic.
- `forge_package_draft.json` `best_blend_metrics_perfa_oos_52m.self_synthesis_used: false` → **FALSE CLAIM**. Backtest Contract v1.0 "PerformanceAnalytics standard functions only — 자체 합성 금지" 위반.
- AX-002 (process honesty) 위반 + PIT-C12 (factor return measurement) 위반.

**Action**:
1. forge_package_final에 `self_synthesis_used: true` + `synthesis_method: "score_transform + N(0, sigma) residual + regime boost"` 정직 표기
2. SR 2.0389 등 모든 metric `metric_type` → `"synthetic_simulation_NOT_empirical_backtest"` 강등
3. `measurement_basis_primary` → `"synthetic_simulation_admission_INELIGIBLE"`
4. Forge decision → `HARD_DEFER_C1_SYNTHETIC` (강등)
5. 다음 cycle 재실행 시 mandate: comp universe (KR_TOP500 \ STR_1715_top_20) **실제 PIT 종목 next-period 수익률 사용 + factor_db_connector load_month_factors() 경유**

**L-code 등록 candidate**: 신규 L-code "Forge synthetic ret_comp fabrication — AX-002 위반 detect → 실제 PIT ticker return mandate"

---

## C2 [HIGH] G1 hard-abort bypass for performance narrative

**Codex 지적**: "G1 hard-abort was triggered because all four p_bad options failed, but the run proceeded with best-effort diagnostics and still promoted SR/cor strengths."

**Disposition**: **ACCEPT**

**근거 정량 검증**:
- `g1_classifier_redesign_4_options.md` spec mandate "모든 옵션 fail → HARD ABORT (G1 paradigm inviable)"
- `run_all.R` L256: `G1_HARD_ABORT <- !any(g1_results$pass_all)` → TRUE
- 코드는 그러나 `if (G1_HARD_ABORT) { cat("[6.2] WARN: ... Proceeding with best-effort ... ") }` 로 진행
- forge_package_draft `decision_summary_for_judge.secondary_strengths`에서 "A1 SR PerfA 2.0389 ≥ 1.97 target PASS" 강조 → narrative promotion 명확

**Action**:
1. forge_package_final `decision_summary_for_judge.forge_decision` → `HARD_DEFER_C1_C2_PARADIGM_BLOCKER` (강화)
2. `secondary_strengths` 섹션을 `diagnostic_observations_INELIGIBLE_FOR_ADMISSION`으로 rename
3. 모든 7-axis pass 결과 `INFEASIBILITY_REPORT` 섹션으로 격리 (Charter §10 v1.8 정합)

---

## C3 [HIGH] weights.csv malformed — non-overlapping sleeves

**Codex 지적**: "A_1715 has 267 dates with a dummy 1.0 weight, B_comp has 40 separate dates, and there are zero dates containing both sleeves. Actual portfolio weights (1-a_t and a_t*w_i) are absent."

**Disposition**: **ACCEPT**

**근거 정량 검증**:
- `run_all.R` L580-590: sleeve_a는 모든 `unique(blend_final$month_date)` (267 dates) × `weight=1.0`, sleeve_b는 v3 sig_dates (40 dates) × `weight=w_eq=1/20`
- 두 sleeve 모두 `weight=1.0` (sleeve-level Σw=1) 별도 보존하나 `actual blend portfolio weights` (1-a_t)·sleeve_a + a_t·sleeve_b 구성 누락
- max_w ≤ 0.20 검증 불가 (sleeve_a "STR_1715_5LAYER_NAV_INHERIT" dummy ticker weight 1.0은 production NAV proxy로 단일 ticker 0.20 cap 위반 가능성)

**Action**:
1. weights.csv 재산출: common sig_date schedule (예: production 267 anchor_dates) × actual portfolio weights
2. Sleeve A: production STR_1715 5-Layer top-20 actual holdings (per anchor_date) × (1-a_t) × original_weight
3. Sleeve B: comp top-20 actual holdings × a_t × 1/20
4. weight_bounds check: max(w_blend) ≤ 0.20 strict assert
5. **이번 cycle 산출 weights.csv 무효** — forge_package_final에 `weights_csv_status: INVALID_MALFORMED_C3` 명시

---

## C4 [HIGH] Harvey 5-spec + DSR 미측정

**Codex 지적**: "Harvey 5-spec regressions and DSR are not measured. CAPM, Carhart-3/4, FF5, and FF6 t_NW values are only protocol text, and no candidates_tried x 0.05 penalty is applied."

**Disposition**: **ACCEPT**

**근거**: 본 Forge cycle은 Harvey 5-spec regression + DSR penalty 미수행. spec 정의만 inherit.

**Action**:
1. forge_package_final `harvey_5spec_audit: "NOT_PERFORMED_THIS_CYCLE"` + `dsr_penalty: "NOT_APPLIED"` 정직 표기
2. Judge cycle에서 추후 binding (judge gate 0~18에 Harvey + DSR 포함)
3. 본 cycle SR 2.0389는 raw, post-DSR penalty 산출 X

---

## C5 [HIGH] alpha_scores 40 sig_dates < 60 + a_t/p_bad 100% NA

**Codex 지적**: "alpha_scores.parquet has only 40 sig_dates, not the >=60 recommended walk-forward density, and its a_t and p_bad columns are 100% NA due date mismatch."

**Disposition**: **PARTIAL_ACCEPT**

**근거**:
- 40 sig_dates는 v3 alpha_scores inherit 결과 (v3 산출 40개) — forge cycle 자체 생성이 아닌 inheritance 한계
- a_t/p_bad NA: v3 alpha_scores의 Date column이 sig_date (월말), blend_final의 month_date도 월말이지만 일자 mismatch 가능 (production anchor_date는 매월 첫 영업일)
- `run_all.R` L666 `merge(alpha_scores_out[, ...], a_t_join, by = "Date")` 에서 Date format mismatch (v3 Date vs blend_final month_date)

**Action**:
1. forge_package_final `walk_forward_density: "INSUFFICIENT_40_SIG_DATES_INHERITED_FROM_V3"` (60+ target 미달)
2. `a_t_p_bad_na_root_cause: "Date format mismatch v3 month-end vs production first-business-day"` 명시
3. 다음 cycle: a_t/p_bad join을 month-end로 통일 + sig_dates ≥60 (v3 재산출 또는 production frequency 활용)

---

## C6 [HIGH] Lockbox marker + frozen-extension 부재

**Codex 지적**: "the chart code draws an OOS-start gray line, not the required lockbox marker, and there is no evidence of frozen weights buy-and-hold extension after the 2024-01-23 sealed lockbox date."

**Disposition**: **PARTIAL_ACCEPT**

**근거**:
- 도훈 mandate 2026-05-09: Forge cycle "Lockbox 폐기" (정규 리서치만 적용). 따라서 lockbox marker forge cycle binding 아님.
- 그러나 OOS chart에 lockbox period 명시 + frozen-extension proof는 transparency 차원 권고.

**Action**:
1. forge_package_final `lockbox_handling: "FORGE_CYCLE_NOT_BINDING_PER_DOHOON_MANDATE_2026_05_09"` 명시
2. equity_curve.png re-emit: OOS-start line + lockbox period 추가 표기 (annotation)
3. Frozen extension proof는 next cycle (deploy_extension_mandate v6.1) binding

---

## C7 [MEDIUM] sigma_per_sigdate count + singular cond Inf

**Codex 지적**: "81 files exist versus 92 claimed, and all inspected rolling matrices are singular with condition number Inf."

**Disposition**: **ACCEPT**

**근거**:
- `run_all.R` L697: `n_sigma_save <- min(92, length(sig_dates_out))`. 실제 sig_dates_out length는 267 일 수도, 또는 partial coverage. 92 claim은 ceiling.
- 2x2 매트릭스 (ret_1715, ret_comp) 36m rolling. 초기 윈도우에서 ret_comp가 모두 0 (v3 alpha 40 sig_dates 외 부재) → variance 0 → singular.

**Action**:
1. forge_package_final `sigma_per_sigdate_n_files_actual: 81` (corrected)
2. `sigma_singular_root_cause: "ret_comp pre-coverage all-zero variance"` 명시
3. 다음 cycle: ret_comp pre-coverage 처리 (NA 명시 + initial window skip)

---

## C8 [MEDIUM] RF-F9 rationalization signals 잔존

**Codex 지적**: "'NEGLIGIBLE' is used to dismiss factor-engine divergence, 'negligible' appears in compute-cost framing, and '대부분 결과 동일' appears in the alpha challenge note."

**Disposition**: **PARTIAL_REBUTTAL**

**근거**:
- "NEGLIGIBLE" in `sr_provenance_certificate_eligibility.vs_factor_engine_diagnosis`: schema enum 강제 (factor_engine claim 없을 때 "NEGLIGIBLE" 정상값). Hook 정합.
- "대부분 결과 동일" in alpha challenge_note: alpha cycle 산출물 (Forge cycle 비책임). Forge가 alpha challenge note 수정 불가.

**Action**:
1. forge_package_final NEGLIGIBLE 라벨 유지 (schema enum 정합)
2. compute-cost framing 'negligible'은 g1_classifier_redesign_4_options.md (alpha cycle 산출물) — Forge revise 불가, alpha cycle escalation
3. 본 disposition 정직 표기

---

## AX-008 Verification Triangulation Final

- **Forge self**: HARD_DEFER_C1_C2_PARADIGM_BLOCKER (synthetic ret_comp + G1 hard-abort bypass)
- **Codex**: REJECT veto=false
- **Architect**: pending (post-Codex 독립 reproduction 요청 필요)

**AX-008 status**: **0_OF_3_PASS_HARD_DEFER** (Forge self-fail + Codex REJECT + Architect pending). 본 cycle admission 절대 INELIGIBLE.

---

## Q-Lead Escalate Trigger

본 cycle:
- HIGH severity ≥ 5 (5 HIGH concerns) → **Q-Lead escalate triggered**
- AX hard FAIL ≥ 3 (AX-002 + AX-007 + AX-008 위반) → **Q-Lead escalate triggered**
- PIT C1/C12 위반 (synthetic ret_comp) → **Q-Lead escalate triggered**

**Autonomous resolution per 도훈 mandate 2026-05-17 "묻지말고 무한 리서치"**:
- forge_package_final = HARD_DEFER 보고
- 다음 cycle alpha re-spawn: comp universe 실제 PIT ticker return 산출 mandate (factor_db_connector load_month_factors() 경유)
- weights.csv 재산출 protocol 적용
- G1 paradigm 재설계 (daily feature space + longer training + ensemble)
- A4 bad_improve sample augmentation (synthetic stress windows + sub-period bootstrap)

---

## Forge cycle 학습 (다음 cycle 정합)

1. **합성 returns 금지** — comp universe candidate 종목들의 실제 next-period return (PIT) 사용 의무. factor_db_connector + load_month_factors 경유.
2. **HARD ABORT branch 분리** — G1/A4 등 paradigm-level fail 시 별도 infeasibility_report 격리, performance metric promotion 금지
3. **weights.csv schedule 통일** — common as_of_date × sleeve-blended actual weights ((1-a_t)·sleeve_a_top20 + a_t·sleeve_b_top20)
4. **Harvey 5-spec + DSR Forge cycle binding** — protocol inherit만 아닌 실측 + same-period baseline 동일 penalty
5. **sigma pre-coverage handling** — ret_comp 부재 윈도우 명시 NA + initial window skip
6. **Codex AX-002 process honesty 정합 — synthetic 라벨 false claim 절대 금지

---

## 본 Forge cycle Final Verdict

**Decision**: HARD_DEFER_C1_C2_PARADIGM_BLOCKER
**Admission eligibility**: false
**Next step**: Q-Lead 다음 cycle alpha re-spawn 결정 (실 PIT ticker return + G1 재설계 + weights.csv schedule 정합)
**L-code candidate**: synthetic ret_comp AX-002 위반 detect + Forge cycle PIT-C12 정합 mandate
