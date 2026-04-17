---
name: axiom-promotion
description: "Axiom 5축 승격 절차 — candidate enrich 가이드, review_log 해석, CLAUDE.md 주입 확인, 실패 축별 보강 방법. Q-Lead/auditor 역할용."
---
## Axiom 5축 승격 절차 (v53 Sprint 4)

### 승격 경로 (L-code → AX-code)

```
stage_artifacts/l_code_*.json
  ↓ (harvester)
.cache/lcode_corpus.json
  ↓ (cluster_extractor)
qepm/memory/axioms/candidates/CAND_*.json  ← 여기서 5축 검증
  ↓ (promote.R — weighted ≥ 0.80)
qepm/memory/axioms/active/AX-XXX.json       ← 승격
  ↓ (inject.R)
CLAUDE.md ## Axioms + 6 prompts               ← 전 에이전트 전제화
```

### 5축 평가 기준

| 축 | 설명 | 합격선 |
|----|------|-------|
| **I Independence** | supporting_l_codes가 서로 다른 strategy_id / family / construction에서 나왔나 | n_strategies ≥ 2, direction_consistency ≥ 0.8 |
| **R Rigor** | 가장 약한 경로 유의성 + 다중검정 보정 | weakest SR ≥ 0.8, meta ≥ 1.0 (positive) / all_fail (negative) |
| **F Falsification** | 적극적 반증 시도 생존 | attempts ≥ 1, 기각 0건, retain ≥ 0.5 |
| **E External (OOS)** | out-of-sample 재현 | OOS ≥ 3개월, oos_vs_is ≥ 0.5 |
| **M Mechanism** | 경제적 메커니즘 설명력 | expl 존재 + type ≠ unknown + plausibility ≥ moderate |

### Type별 가중치

| Type | I | R | F | E | M |
|------|---|---|---|---|---|
| empirical (실증) | 0.25 | 0.25 | 0.20 | 0.20 | 0.10 |
| methodological (방법론) | 0.15 | 0.20 | 0.30 | 0.15 | 0.20 |

**Weighted sum ≥ 0.80 → PASS**

### 승격 실행

```r
source("02_Infrastructure/axiom/promote.R")
r <- promote_to_axiom("qepm/memory/axioms/candidates/CAND_XXX.json")
# r$passed TRUE 시:
#   - active/AX-XXX.json 이동 (번호 자동 할당)
#   - L-code 역링크 기입 (supporting_l_codes → promoted_to_axiom)
#   - QVEST_AXIOM_AUTO_INJECT=1이면 inject_axiom() 자동 호출
# r$passed FALSE 시:
#   - review_log/AX-PENDING_*.json 기록 (축별 점수 + failing_axes)
```

### 부분 통과 (review_log) 해석

`qepm/memory/axioms/review_log/AX-PENDING_CAND_XXX_<ts>.json`:
```json
{
  "weighted_score": 0.483,
  "threshold": 0.80,
  "failing_axes": ["falsification", "external", "mechanism"],
  "axes": {
    "independence": {"score": 0.78, ...},
    "rigor": {"score": 1.00, ...},
    "falsification": {"score": 0.50, "reason": "attempts=0"},
    "external": {"score": 0.10, "reason": "OOS=NA"},
    "mechanism": {"score": 0.00, "reason": "expl=MISSING"}
  }
}
```

### 실패 축별 보강 방법

**Mechanism 미달 (가장 흔함)**
candidate JSON의 `mechanism_draft` 채움:
```json
"mechanism_draft": {
  "economic_explanation": "한국 value trap 관찰: 최근 10년 value premium 약화 + ...",
  "mechanism_type": "market_structural",  // 또는 behavioral_mispricing / institutional / frictional
  "causal_plausibility": "moderate_to_high"   // moderate / moderate_to_high / high
}
```
근거 문헌 인용 필수 (L-code의 core_reference 활용).

**External (OOS) 미달**
`oos_validation_draft` 채움:
```json
"oos_validation_draft": {
  "oos_months": 8,
  "oos_effect_vs_is": 0.62,
  "note": "STR_XXX output/hurdle_result.json rolling Sharpe 근거"
}
```

**Falsification 미달**
`falsification_draft.attempts` 추가 (반증 시도 명시):
```json
"falsification_draft": {
  "attempts": [
    {"description": "sub-sample 2016 이후 재검증", "result": "survived", "effect_retained": 0.75},
    {"description": "transaction cost 3x 적용", "result": "survived", "effect_retained": 0.55}
  ]
}
```
또는 evidence_summary/ + role_honesty_*.json에 반증 실험이 이미 있으면 promote.R가 자동 카운트.

**Independence 미달**
supporting_l_codes가 같은 strategy 중심이면 다른 construction/family의 L-code 추가 수집 필요. cluster_extractor 재실행.

**Rigor 미달 (positive/conditional만)**
supporting strategies가 grade_a_catalog에 매칭되지 않으면 축 낮음. Grade A 전략 근거 확보 필요.

### 재시도 흐름

1. `qepm/memory/axioms/candidates/CAND_XXX.json` 직접 편집 (mechanism/OOS/falsification draft 채움)
2. `Rscript 02_Infrastructure/axiom/promote.R qepm/memory/axioms/candidates/CAND_XXX.json`
3. Pass 시 active 이동 + inject
4. 여전히 Fail 시 축별 점수 재확인 → 추가 보강

### 승격 후 확인

```r
# 1. 활성 axiom 조회
source("qepm/R/axiom_dashboard.R")
axiom_status()

# 2. L-code 역링크 확인
source("02_Infrastructure/memory/axiom_memory_interface.R")
sg_axiom_lcode_trace(axiom_id = "AX-003")$supporting_l_codes

# 3. CLAUDE.md 주입 확인
grep "^### AX-003" CLAUDE.md
```

### Inject (CLAUDE.md + 6 prompts)

```bash
# dry-run (권장, 첫 검토)
QVEST_AXIOM_AUTO_INJECT=0 Rscript 02_Infrastructure/axiom/inject.R \
  qepm/memory/axioms/active/AX-003.json
# → .cache/axiom_inject_AX-003_<ts>.diff 생성, 파일 미변경

# 실제 주입
QVEST_AXIOM_AUTO_INJECT=1 Rscript 02_Infrastructure/axiom/inject.R \
  qepm/memory/axioms/active/AX-003.json
```

영향 범위:
- `CLAUDE.md` `## Axioms (auto-injected ...)` 섹션 append
- `02_Infrastructure/prompts/{scout,forge,judge,governor,risk_manager,qlead}_init.md`의 `<!-- AXIOM_INJECT_START --> ... <!-- AXIOM_INJECT_END -->` 블록

### Review / Deprecate

```r
source("02_Infrastructure/axiom/review.R")
review_axiom("AX-003")   # 분기별 또는 열화 의심 시
# OOS 열화(IS 대비 <50%) 또는 반증 L-code 2건+ → deprecated/ 이동
```

### 자동화 (cron)

```cron
0 3 * * 1     bash 02_Infrastructure/ops/axiom_weekly.sh       # 매주 월 03:00
0 4 1 */3 *   bash 02_Infrastructure/ops/axiom_quarterly.sh    # 분기 1일 04:00
```

주간: harvester → cluster → promote 전수 시도
분기: review_all_active_axioms()

### IMMUTABLE 제외

AX-000/001/002는 `grade: "IMMUTABLE"` 필드 보유. D075, review_axiom 모두 자동 skip.

### 운영 팁

- **부분 통과 누적**: `review_log/`에 같은 candidate 여러 번 PENDING이 쌓이면 그 영역은 mechanism/OOS 증거가 원천 부족. 새 L-code 실험 필요.
- **Grade A catalog 갱신**: `04_Research/grade_a_catalog.json`이 최신이어야 Rigor 축이 정확. Sprint 2.15 builder가 자동 갱신.
- **IMMUTABLE을 empirical로 혼동 금지**: IMMUTABLE은 연구 프로세스 axiom (AX-001 Defense 조건부 평가 등). 실증 axiom은 "한국시장에서 X family는 Y"처럼 정량적.
