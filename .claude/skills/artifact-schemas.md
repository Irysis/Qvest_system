---
name: artifact-schemas
description: "산출물 JSON 작성 시 스키마 참조 — s0~pg3 필수 필드, L-code 규칙"
---
## Stage Artifact 필수 필드

### S0: s0_record
`factor_id`, `strategy_id`, `hypothesis`, `economic_rationale`, `expected_role`, `why_now`, `core_reference`, `lesson_check`, `overlay`="none"

### S1: s1_construction
`strategy_id`, `factor_id`, `implementation_profile`(turnover_risk, capacity_risk)

### S2: s2_profile
`strategy_id`, `factor_id`, `ic_ir`, `tag`(Strong/Moderate/Weak), `role_bias`

### S3: s3_orthogonality
`novelty_score`, `independence_class`, `candidate_role_hint`, `max_corr_value`

### S4: s4_integration
`kospi_beat`, `delta_sharpe`, `provisional_role`, `route`

### S5: s5_mutation_result
`mutations_attempted`(≥9), `f_category_count`(≥2), `synthesis_tested`=TRUE, `best_variant`

### S6: s6_validation
Gate 0~5 결과, `pit_clean`, `ff5_alpha`, `dsr`, `loo_results`, `role_honesty`

### L-code (S6/S7 EXIT CONDITION)
```json
{
  "strategy_id": "STR_XXX",
  "grade": "A",            // NOT "verdict"
  "lesson_text": "...",    // NOT "lesson"
  "core_reference": "...", // NOT "core_ref"
  "tags": ["tag1"]
}
```

### PG0~PG3
- pg0_gap_review: `cagr_gap`, `sharpe_gap`, `mdd_gap`, `sleeve_needs`
- pg1_admission: `admission_decision`(ADMIT/DEFER/REJECT), `antipattern_pass`, `loo_pass`, `role_honest`
- pg2_allocation_plan: `sleeves`, `weights`, `method`, `total_stocks`(≤30)
- pg3_monitoring/validation: `drift`, `regime_change`, `mdd_alert`
