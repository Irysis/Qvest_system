# AX-001 v2: Defense Role Conditional Evaluation

**적용 일자**: 2026-04-19 (v55)
**전제**: AX-001 IMMUTABLE — "방어형 팩터를 전기간 SR/CAGR/MDD로 평가하면 Grade F. 위기 구간 alpha + Core 대비 MDD + bad/normal IC ratio로 평가."

---

## 1. 배경: 왜 v2가 필요한가

**AX-005 (methodological/negative)** 결과:
- KR defense standalone long-only (BAB, Q07+D25 등) = 구조적 실패
- 기존 정의로는 Defense가 항상 Grade F → Defense sleeve 공석

**v55 해결책**: Defense를 **multi-sleeve 컨텍스트에서만** 평가. Standalone 금지, sleeve 기여도로 측정.

---

## 2. 평가 기준 (Judge S6 Gate 추가)

### Gate 2a: Multi-Sleeve Only
- `multi_sleeve_only = TRUE` 필수
- Standalone long-only defense는 **자동 Grade F** (AX-005 준수)

### Gate 2b: Crisis Alpha
- 6대 위기 구간 alpha 측정: 1997 아시아 / 2000 닷컴 / 2008 GFC / 2011 유럽 / 2020 COVID / 2022 Rate shock
- `crisis_alpha > 0` 필수 (각 위기 구간에서 Core 대비 초과 수익)
- Side-effect: 평시 drag는 허용 (단 기회비용 지나치면 Governor veto)

### Gate 2c: Bad/Normal IC Ratio
- 4-regime IC 측정: Good / Normal / Bad / Crisis
- `IC(Bad + Crisis) / IC(Good + Normal) > 0.6` 필수
- 해석: 위기일수록 팩터가 더 잘 작동해야 Defense 자격

### Gate 2d: Core 대비 MDD 완화
- 후보 Defense 편입 전/후 포트폴리오 MDD 비교
- `MDD_after ≤ MDD_before × 0.90` 권장 (10%+ 완화)
- 완화 부족 시 CONDITIONAL_PASS (Governor 허용 범위 내)

---

## 3. 평가 제외 항목 (금지)

다음은 Defense 평가 시 **사용 금지**:
- 전기간 SR / CAGR / MDD
- Full-period alpha
- Unconditional Sharpe
- Single-period win rate

이들 지표로 Defense를 판정하면 자동 Grade F 처리. (AX-001 IMMUTABLE 위반)

---

## 4. s6_validation 스키마 확장

```json
{
  "strategy_id": "STR_XXX",
  "role": "defense",
  "role_honesty_audit": {
    "declared_role": "defense",
    "detected_role": "defense",
    "confidence": 0.87,
    "violations": [],
    "audit_date": "2026-04-19",
    "crisis_alpha_test": {
      "tested": true,
      "passed": true,
      "crisis_periods": {
        "1997_asia": {"alpha": 0.032, "passed": true},
        "2000_dotcom": {"alpha": 0.018, "passed": true},
        "2008_gfc": {"alpha": 0.041, "passed": true},
        "2011_eu": {"alpha": 0.022, "passed": true},
        "2020_covid": {"alpha": 0.055, "passed": true},
        "2022_rate": {"alpha": 0.028, "passed": true}
      },
      "all_passed": true
    },
    "bad_normal_ic_ratio": {
      "ic_bad_crisis": 0.045,
      "ic_good_normal": 0.060,
      "ratio": 0.75,
      "passed": true
    },
    "core_mdd_reduction": {
      "mdd_before": -0.2127,
      "mdd_after_with_defense": -0.1850,
      "reduction_pct": 0.13,
      "passed": true
    },
    "multi_sleeve_only": true
  },
  "consensus_stance": "SUPPORT"
}
```

---

## 5. Judge Gate 통과 기준

**Defense role 전략 Grade 결정**:
| Gate 조합 | Grade |
|----------|-------|
| 2a PASS + 2b/2c/2d 모두 PASS | **A** (또는 A_NOVEL) |
| 2a PASS + 2b/2c PASS + 2d CONDITIONAL | **B** |
| 2a FAIL (standalone) | **F** (자동) |
| 2b FAIL (crisis_alpha ≤ 0) | **F** |
| 2c FAIL (bad/normal ratio ≤ 0.6) | **C** |
| 2d FAIL (MDD 완화 없음) | **C** |

---

## 6. role_honesty_audit.R 확장 요구사항

### 기존 함수 (3종)
`audit_core_alpha()`, `audit_diversifier()`, `audit_defense()`

### v55 추가 필요
- `audit_defense_v2()` — AX-001 v2 준수 (기존 `audit_defense()` 대체)
- `audit_cash_allocation()` — opportunity_cost 측정
- `audit_regime_adaptive()` — switching_alpha + transition_cost
- `audit_ml_predictive()` — SR_OOS/SR_IS + feature concentration

### 구현 위치
`02_Infrastructure/validation/role_honesty_audit.R` (Tier 2.1 작업에서 확장)

### 핵심 함수 시그니처 (v55)

```r
audit_defense_v2 <- function(strategy_returns, core_returns, 
                              regime_series, ic_by_regime,
                              crisis_periods = list(
                                "1997_asia" = c("1997-07-01", "1998-12-31"),
                                "2000_dotcom" = c("2000-03-01", "2002-10-31"),
                                "2008_gfc" = c("2007-10-01", "2009-03-31"),
                                "2011_eu" = c("2011-07-01", "2011-12-31"),
                                "2020_covid" = c("2020-02-01", "2020-04-30"),
                                "2022_rate" = c("2022-01-01", "2022-10-31")
                              )) {
  # Gate 2a: multi-sleeve check (caller가 TRUE 전달)
  # Gate 2b: crisis_alpha 계산
  crisis_alphas <- lapply(crisis_periods, function(period) {
    mask <- strategy_returns$date >= period[1] & strategy_returns$date <= period[2]
    strategy_ret <- mean(strategy_returns$ret[mask], na.rm = TRUE) * 252
    core_ret <- mean(core_returns$ret[mask], na.rm = TRUE) * 252
    strategy_ret - core_ret
  })
  
  crisis_all_positive <- all(sapply(crisis_alphas, function(a) a > 0))
  
  # Gate 2c: bad/normal IC ratio
  ic_bad_crisis <- mean(c(ic_by_regime$Bad, ic_by_regime$Crisis), na.rm = TRUE)
  ic_good_normal <- mean(c(ic_by_regime$Good, ic_by_regime$Normal), na.rm = TRUE)
  ic_ratio <- ic_bad_crisis / ic_good_normal
  
  list(
    crisis_alpha_test = list(
      tested = TRUE,
      passed = crisis_all_positive,
      crisis_periods = crisis_alphas,
      all_passed = crisis_all_positive
    ),
    bad_normal_ic_ratio = list(
      ic_bad_crisis = ic_bad_crisis,
      ic_good_normal = ic_good_normal,
      ratio = ic_ratio,
      passed = ic_ratio > 0.6
    ),
    overall_passed = crisis_all_positive && (ic_ratio > 0.6)
  )
}
```

(추가 role 함수는 Tier 2.1에서 구현)

---

## 7. 참조

- `v55_consensus_addendum.md` §5 (AX-001 v2)
- `admission_rule_v352.md` (Tier 2.3 예정, Defense role threshold)
- `02_Infrastructure/validation/role_honesty_audit.R` (Tier 2.1 확장 대상)
- CLAUDE.md `## Axioms` AX-001 / AX-005
