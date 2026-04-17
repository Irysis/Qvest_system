# R7 Axiom Store — 설계안

## 정의

Axiom은 "반복해서 느낀 것"이 아니라 **"통계적으로 반박할 수 없게 된 것"**이다.
인간의 "진리 형성"을 모방하지 않는다.
과학에서 법칙이 확립되는 과정을 따른다:
  다수의 독립 실험 → 재현 → 반증 시도 생존 → 메커니즘 규명 → 조건부 범위 확정

---

## R0~R6 → R7 전체 흐름

```
R0  Raw Artifact      : 실험 1건의 원본 (불변)
R1  Experiment Digest  : 실험 1건의 구조화된 요약 (규칙 기반)
R2  Family Memory      : 동일 family 내 패턴 일반화 ("이 family에서 뭐가 통하나")
R3  Statistical Evidence: 통계 검증 결과 축적 ("통계적으로 유의한가")
R4  Regime Payoff      : 국면 조건부 성과 ("어떤 상황에서 통하는가")
R5  Portfolio Policy   : 포트폴리오 수준 배분 정책 ("어떻게 섞어야 하는가")
R6  Post-Trade Learning: 이론 vs 실현 비교 ("실전에서도 맞았는가")

          ↓ 여기서부터 신규

R7  Axiom Store        : 더 이상 개별 실험마다 재검증하지 않아도 되는 확립된 원칙
                         에이전트 프롬프트에 자동 주입 → 다음 연구의 전제로 작동
```

---

## Axiom이 아닌 것 (명확한 경계)

- ❌ "momentum이 좋다" — 너무 모호. 어떤 시장, 어떤 construction, 어떤 국면에서?
- ❌ "Sharpe 1 이상이면 좋은 전략이다" — 정의/기준이지 발견이 아님
- ❌ "한국시장은 비효율적이다" — 검증 불가능한 일반론

## Axiom인 것 (예시)

- ✅ "한국시장에서 idioVol 기반 long-short 전략은 Normal/Stress 국면 모두에서 양의 risk-adjusted alpha를 생성한다. FF5 alpha t > 2.5, 3개 독립 construction에서 확인, OOS 6개월 이상 유지."
- ✅ "국면 전환 시 turnover > 40%/month이면 비용이 alpha를 잠식한다. 5개 이상 배분 실험에서 일관, 비용 2x 시나리오에서도 동일 결론."
- ✅ "quality factor의 defensive 역할은 Stress 국면에서 MDD 감소 5%p 이상으로 안정적이다. 3개 family × 2개 이상 국면에서 확인."

핵심 차이: **구체적이고, 조건부이고, 정량적이고, 반증 가능**하다.

---

## Axiom 구조 (JSON)

```json
{
  "axiom_id": "AX-001",
  "statement": "idioVol LS는 Normal/Stress에서 FF5 alpha 양(+)이다",
  "scope": {
    "market": "KR",
    "strategy_type": "long-short",
    "factor_family": "idioVol",
    "applicable_regimes": ["normal", "stress"],
    "not_tested_regimes": ["euphoria"],
    "construction_types": ["sector_neutral", "beta_neutral", "cap_weighted"]
  },
  "evidence": {
    "independent_families": 1,
    "independent_constructions": 3,
    "total_supporting_experiments": 12,
    "strongest_effect": { "metric": "ff5_alpha_t", "value": 3.21 },
    "weakest_effect": { "metric": "ff5_alpha_t", "value": 2.14 },
    "effect_direction_consistency": 1.0,
    "meta_effect_size": 0.018,
    "meta_effect_se": 0.005
  },
  "falsification": {
    "attempts": [
      {
        "description": "euphoria 국면에서만 테스트",
        "result": "inconclusive",
        "reason": "euphoria 샘플 부족"
      },
      {
        "description": "2016 이전 데이터 제외 후 재검증",
        "result": "survived",
        "effect_retained": 0.85
      },
      {
        "description": "transaction cost 3x 적용",
        "result": "survived",
        "effect_retained": 0.62
      }
    ],
    "total_attempts": 3,
    "survived": 2,
    "inconclusive": 1,
    "falsified": 0
  },
  "oos_validation": {
    "oos_months": 8,
    "oos_effect_significant": true,
    "oos_effect_vs_is": 0.73,
    "r6_confirmations": 4
  },
  "mechanism": {
    "economic_explanation": "고유변동성이 높은 종목은 정보 비대칭이 크고, 개인투자자 비중이 높아 mispricing이 체계적으로 발생",
    "mechanism_type": "behavioral_mispricing",
    "causal_plausibility": "moderate_to_high"
  },
  "metadata": {
    "first_evidence_date": "2025-09-15",
    "promoted_date": "2026-03-15",
    "promoted_by": "auditor",
    "confidence_at_promotion": 0.87,
    "review_schedule": "quarterly",
    "next_review": "2026-06-15",
    "status": "active",
    "version": 1
  }
}
```

---

## 승격 조건 (통계/과학적 기준)

```r
promote_to_axiom <- function(candidate) {

  # ═══════════════════════════════════════════
  # 축 1: 증거의 독립성 (Independence)
  # ═══════════════════════════════════════════
  # "같은 실험 30번"이 아니라 "서로 다른 경로에서 같은 결론"
  
  independence <- list(
    # 서로 다른 construction(sector_neutral vs beta_neutral 등)에서 확인
    independent_constructions = candidate$evidence$independent_constructions >= 2,
    
    # 효과 방향이 모든 경로에서 일관
    direction_consistency = candidate$evidence$effect_direction_consistency >= 0.8
  )

  # ═══════════════════════════════════════════
  # 축 2: 통계적 확실성 (Statistical Rigor)
  # ═══════════════════════════════════════════
  # 횟수가 아니라 검정력
  
  rigor <- list(
    # 가장 약한 경로에서도 유의
    weakest_still_significant = candidate$evidence$weakest_effect$value >= 1.96,
    
    # 메타 분석 효과 크기가 SE의 2배 이상
    meta_significant = (candidate$evidence$meta_effect_size / 
                        candidate$evidence$meta_effect_se) >= 2.0,
    
    # 다중검정 보정 후에도 유의 (family 내 trial 수 고려)
    survives_multiple_testing = TRUE  # FDR/DSR 통과 확인
  )

  # ═══════════════════════════════════════════
  # 축 3: 반증 생존 (Falsification Survival)
  # ═══════════════════════════════════════════
  # 반증 "횟수"가 아니라 반증 "강도"
  
  falsification <- list(
    # 최소 1회 이상의 적극적 반증 시도
    attempted = candidate$falsification$total_attempts >= 1,
    
    # 반증 시도 중 실제로 기각된 것이 없음
    none_falsified = candidate$falsification$falsified == 0,
    
    # 반증 생존 시 효과 보존율이 50% 이상
    effect_retained = all(
      sapply(candidate$falsification$attempts, function(a) {
        a$result != "survived" || a$effect_retained >= 0.5
      })
    )
  )

  # ═══════════════════════════════════════════
  # 축 4: 외부 타당성 (Out-of-Sample)
  # ═══════════════════════════════════════════
  # "같은 데이터에서 100번"이 아니라 "새 데이터에서 1번"이 더 강력
  
  external <- list(
    # OOS에서 확인 (최소 3개월)
    oos_confirmed = candidate$oos_validation$oos_months >= 3,
    oos_significant = candidate$oos_validation$oos_effect_significant,
    
    # OOS 효과가 IS의 50% 이상 유지 (심한 열화면 과적합 의심)
    oos_not_degraded = candidate$oos_validation$oos_effect_vs_is >= 0.5
  )

  # ═══════════════════════════════════════════
  # 축 5: 인과적 설명력 (Causal Mechanism)
  # ═══════════════════════════════════════════
  # "왜 작동하는가"를 설명할 수 있는가
  # 설명 없는 통계적 유의성은 data mining artifact일 수 있음
  
  mechanism <- list(
    # 경제적 메커니즘이 식별됨 ("unknown"이 아님)
    identified = candidate$mechanism$mechanism_type != "unknown",
    
    # 인과적 타당성이 최소 moderate
    plausible = candidate$mechanism$causal_plausibility %in% 
      c("moderate", "moderate_to_high", "high")
  )

  # ═══════════════════════════════════════════
  # 최종 판정
  # ═══════════════════════════════════════════
  # 5축 전부 통과해야 Axiom
  # 어느 하나라도 실패하면 "어떤 축이 부족한지" 보고
  
  axes <- list(
    independence = all(unlist(independence)),
    rigor = all(unlist(rigor)),
    falsification = all(unlist(falsification)),
    external = all(unlist(external)),
    mechanism = all(unlist(mechanism))
  )
  
  list(
    promoted = all(unlist(axes)),
    axes = axes,
    failing_axes = names(axes)[!unlist(axes)]
  )
}
```

---

## Axiom의 프롬프트 자동 주입

Axiom이 승격되면 CLAUDE.md의 `## Axioms` 섹션에 자동 추가된다.
모든 에이전트가 다음 세션에서 이 공리를 전제로 사고한다.

```r
inject_axiom <- function(axiom, claude_md_path = "CLAUDE.md") {
  
  axiom_block <- glue::glue("
### {axiom$axiom_id}: {axiom$statement}
- 범위: {paste(axiom$scope$applicable_regimes, collapse='/')} 국면, {paste(axiom$scope$construction_types, collapse='/')}
- 강도: 가장 약한 경로 t={axiom$evidence$weakest_effect$value}, 메타 효과={axiom$evidence$meta_effect_size}
- 반증: {axiom$falsification$total_attempts}회 시도, {axiom$falsification$survived}회 생존, 기각 0회
- OOS: {axiom$oos_validation$oos_months}개월 확인, IS 대비 {round(axiom$oos_validation$oos_effect_vs_is*100)}% 유지
- 메커니즘: {axiom$mechanism$economic_explanation}
- 확정: {axiom$metadata$promoted_date} | 다음 검토: {axiom$metadata$next_review}
")
  
  # CLAUDE.md에 삽입
  md <- readLines(claude_md_path)
  axiom_section <- grep("^## Axioms", md)
  
  if (length(axiom_section) == 0) {
    # 섹션이 없으면 생성
    md <- c(md, "", "## Axioms (자동 주입 — 에이전트의 전제 조건)", "", axiom_block)
  } else {
    # 기존 섹션 끝에 추가
    insert_at <- axiom_section + 1
    while (insert_at <= length(md) && !grepl("^## ", md[insert_at])) {
      insert_at <- insert_at + 1
    }
    md <- c(md[1:(insert_at-1)], axiom_block, md[insert_at:length(md)])
  }
  
  writeLines(md, claude_md_path)
}
```

### 에이전트별 Axiom 활용 방식

Axiom이 주입된 후, 각 에이전트는 이렇게 활용한다:

**strategist**: "AX-001이 전제이므로, idioVol 계열 신규 전략은 Normal/Stress에서의 alpha를 이미 확인된 것으로 보고, **Euphoria 국면에서의 행동**이나 **새로운 construction variant**에 집중한다."
→ 이미 확립된 영역을 재탐색하지 않음. 탐색 효율 증가.

**auditor**: "AX-001 범위 내의 전략이 Gate 4에서 FF5 alpha t < 1.96이면, Axiom과 모순 → **데이터 문제나 implementation 오류를 먼저 의심**한다."
→ 공리에 반하는 결과가 나오면 결과가 아니라 실험을 의심.

**researchops**: "AX-001이 커버하는 영역(idioVol, Normal/Stress)은 이미 확립됐으므로, **orthogonal_search 예산을 다른 family에 배분**한다."
→ 연구 자원을 미확립 영역에 집중.

**blender**: "AX-001에 따라 idioVol 전략의 Normal/Stress 성과는 안정적이므로, **해당 전략의 core role 배정에 높은 confidence를 부여**한다."
→ 배분 결정에서 불확실성 감소.

---

## Axiom 생명주기 관리

### 정기 검토 (Quarterly)

```r
review_axiom <- function(axiom_id) {
  axiom <- load_axiom(axiom_id)
  
  # 1. 최근 3개월 R6 데이터에서 Axiom과 일치하는지 확인
  recent_r6 <- load_recent_r6(months = 3)
  consistency <- check_axiom_consistency(axiom, recent_r6)
  
  # 2. 새로운 반증 증거가 축적됐는지 확인
  new_evidence <- load_new_experiments_since(axiom$metadata$promoted_date)
  contradictions <- find_contradicting_experiments(axiom, new_evidence)
  
  # 3. 판정
  if (consistency$score >= 0.7 && length(contradictions) == 0) {
    # 건강함 — 유지
    return(list(action = "MAINTAIN", next_review = quarter_later()))
  } else if (consistency$score >= 0.5 || length(contradictions) <= 2) {
    # 약화 징후 — 범위 축소 또는 조건 추가
    return(list(
      action = "NARROW",
      suggestion = "Axiom의 적용 범위를 축소하거나 조건을 추가",
      contradictions = contradictions
    ))
  } else {
    # 심각한 모순 — 폐기 검토
    return(list(
      action = "DEPRECATE_REVIEW",
      reason = "최근 증거와 심각한 모순",
      contradictions = contradictions
    ))
  }
}
```

### Axiom 상태 전이

```
CANDIDATE → ACTIVE → NARROWED → DEPRECATED
                ↑         ↓
                └── RESTORED (재검증 후 복원)
```

- **ACTIVE**: 프롬프트에 주입, 에이전트가 전제로 사용
- **NARROWED**: 적용 범위가 축소됨 (예: "모든 국면" → "Normal만")
- **DEPRECATED**: 프롬프트에서 제거, 단 memory/axioms/deprecated/에 보존
- **RESTORED**: 폐기 후 새 증거로 재확인되어 복원

### 폐기 시 안전장치

```r
deprecate_axiom <- function(axiom_id, reason) {
  axiom <- load_axiom(axiom_id)
  
  # 1. CLAUDE.md에서 제거
  remove_from_claude_md(axiom_id)
  
  # 2. 폐기 사유 기록
  axiom$metadata$status <- "deprecated"
  axiom$metadata$deprecated_date <- now_kst()
  axiom$metadata$deprecation_reason <- reason
  
  # 3. deprecated 디렉토리로 이동 (삭제하지 않음)
  save_json(axiom, file.path("memory/axioms/deprecated", paste0(axiom_id, ".json")))
  
  # 4. 모든 에이전트에 통지
  #    "AX-001이 폐기됨. 이유: {reason}. 
  #     이 공리를 전제로 한 전략/판단을 재검토할 필요가 있음."
  notify_all_agents(axiom_id, reason)
  
  # 5. 이 공리에 의존하던 전략들 플래그
  dependent_strategies <- find_strategies_depending_on(axiom_id)
  for (s in dependent_strategies) {
    flag_for_review(s, paste("의존 Axiom", axiom_id, "폐기됨"))
  }
}
```

---

## Axiom 후보 자동 탐지

영구기관 루프에서 R3/R4/R5를 스캔하여 Axiom 후보를 자동 발견:

```r
scan_axiom_candidates <- function() {
  # R3 Statistical Evidence에서:
  # - 동일 결론이 2개 이상 독립 construction에서 확인된 것
  # - 가장 약한 경로에서도 t >= 1.96
  
  r3_evidence <- load_all_r3()
  
  candidates <- r3_evidence %>%
    group_by(conclusion_cluster) %>%
    filter(n_distinct(construction_type) >= 2) %>%
    filter(min(t_stat) >= 1.96) %>%
    ungroup()
  
  # R4에서 국면별 확인 여부 추가
  for (c in candidates) {
    c$regime_coverage <- get_regime_coverage(c, load_r4())
  }
  
  # R6에서 OOS 확인 여부 추가
  for (c in candidates) {
    c$oos_status <- get_oos_confirmation(c, load_r6())
  }
  
  # 5축 평가
  for (c in candidates) {
    c$axiom_readiness <- promote_to_axiom(c)
  }
  
  # 결과 보고 — auditor가 최종 검토
  return(candidates)
}
```

### 영구기관 통합

```
perpetual_research 루프에 추가:

  - id: axiom_scan
    schedule: "매월 (리밸런싱 후)"
    description: "R3/R4/R5/R6를 스캔하여 Axiom 후보 탐지"
    skills: [qepm-memory]
    instructions: |
      scan_axiom_candidates()를 실행하고:
      1. 5축 전부 통과 → auditor에게 승격 심사 요청
      2. 4축 통과 + 1축 부족 → "이 축만 보강하면 Axiom" 리포트
      3. 기존 Axiom 정기 검토 (quarterly)

  - id: axiom_review
    agent: auditor
    condition: "axiom_scan에서 후보 또는 검토 대상 발견"
    description: "Axiom 승격/유지/축소/폐기 심사"
    instructions: |
      확장 사고로 심사:
      1. 5축 증거의 품질을 비판적으로 검토
      2. "이 결론이 틀릴 수 있는 시나리오"를 명시적으로 나열
      3. 승격/유지/축소/폐기 판정 + 근거
      4. 승격 시: inject_axiom() 실행
      5. 폐기 시: deprecate_axiom() 실행 + 의존 전략 재검토 플래그
```

---

## 디렉토리 구조

```
memory/
  ├── ...기존 R0~R6...
  ├── axioms/
  │   ├── active/           # 현재 활성 Axiom JSON
  │   ├── candidates/       # 승격 대기 후보
  │   ├── deprecated/       # 폐기된 Axiom (보존)
  │   └── review_log/       # 정기 검토 기록
```

---

## 핵심 원칙 요약

1. **횟수가 아니라 증거 품질**: "30번 확인"이 아니라 "독립 경로 × 통계적 확실성 × 반증 생존 × OOS × 메커니즘"
2. **구체적이고 조건부**: "momentum이 좋다"가 아니라 "한국시장 sector-neutral momentum LS가 Normal/Stress에서 FF5 alpha 양(+)"
3. **반증 가능**: 모든 Axiom은 "이런 증거가 나오면 폐기한다"는 조건을 내장
4. **자동 주입 + 자동 검토**: CLAUDE.md에 주입되어 에이전트의 전제가 되고, quarterly 검토로 유효성 확인
5. **폐기 안전**: 폐기 시 의존 전략 플래그 + 전 에이전트 통지
6. **인간 인지 모방 금지**: confirmation bias, belief perseverance를 설계에 넣지 않음
