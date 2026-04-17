---
name: s6-validation
description: "S6 Judge 검증 시 적용 — Gate 0~6 (Gate 6 tail_risk), PIT 감사, FF5/DSR, LOO, Role Audit"
hooks:
  PostToolUse:
    - matcher: "Write"
      hooks:
        - type: "prompt"
          if: "Write(stage_artifacts/l_code_*)"
          prompt: "l_code JSON 검증. 필수 필드: grade, lesson_text(100~500자), core_reference, strategy_id, tags, created_at. 필드명 정확성: grade(NOT verdict), lesson_text(NOT lesson), core_reference(NOT core_ref). 누락/오명 시 {\"ok\":false, \"reason\":\"l_code 필드 오류: [상세]\"}, 정상 시 {\"ok\":true}."
---
## S6 검증 절차

### 진입 조건 (v53 S2.6 Fast-Track 강제)
`sg_check_s6_entry(factor_id)` PASS 필수. S0~S4(+S5) artifact 전수 검증.
`unified_agent_guard.sh`가 Judge S6 Agent 스폰 시:
- S2/S4/S5 artifact 존재 확인
- `.cache/mutation_tracker.json`에서 passes_s5_rule=TRUE 확인 (9 mutations + 2 categories + synthesis_tested)
- NO_ENTRY 또는 미충족 시 **block** (s5-mutation-lab 참조)

### Gate 0~6 + D073~D075 순차 (v53 Sprint 2/3/4 통합)
| Gate | 검증 | 탈락/페널티 |
|------|------|----------------|
| 0 | PIT C1~C16 전수 (pit_engine_v3) | 1건이라도 위반 → FAIL |
| 1 | Hard fail: MDD > 45% OR TO > 600% | → F |
| 2 | FF3/Carhart4/FF5 alpha 유의성 | t < 2.0 → 경고 |
| 3 | DSR (Deflated Sharpe Ratio) | Harvey t > 3.0 |
| 4 | LOO 4종: crisis/regime/subperiod/sleeve | 전천후 검증 |
| 5 | Role Honesty Audit (자동) | 역할 위장 탐지 |
| 6 | Tail Risk (Pfaff 2016) | EVT-VaR gap < 50%, CDaR < 35%, TDC < 0.30 |
| **D073** | Combinatorial Penalty (S2.9) | grid_runs iter ≥ 50 → **-10점** |
| **D074** | DSR + FF5 Hard Gate (S2.9 strict_mode) | Grade A 경로에서 DSR !sig OR \|t_alpha\|<3.0 → **B 강등** |
| **D075** | AX Violation Suspicion (AX-P2) | active AX 범위 + 반대 결과 → suspicion_flag + **-5점** + strict 강등 |

### Gate 6: Tail Risk 검증 (Pfaff 2016)
```r
source(file.path(INFRA_DIR, "portfolio/tail_risk_engine.R"))
result <- verify_tail_risk(tail_risk_result, thresholds = list(
  evt_var_oos_gap_max = 0.50, cdar_max = 0.35, tdc_max = 0.30
))
```
- `tail_risk_result.json` 필수 (risk_gate hook 검증)

### D074 Strict Mode (v53 Sprint 2.9)
`run_hurdle_gate(..., ff5_result=NULL, strict_mode=TRUE)`:
- 기본 `QVEST_STRICT_MODE=TRUE` → Grade A/A_NOVEL/A_DEF 경로에서
  - DSR dsr_sig=FALSE → downgrade to B (이유 기록)
  - ff5_result 주입 + \|alpha_t\| < 3.0 → downgrade to B
- 우회: `QVEST_STRICT_MODE=FALSE`

### D075 AX Violation Suspicion (v53 Sprint 4 AX-P2)
active AX 범위(scope.factor_family) + 전략 name 매치되는데 polarity 반대 결과:
- AX negative인데 전략 Grade A → 실험 오류 먼저 의심
- AX positive/conditional인데 Grade F → 실험 오류 먼저 의심
- IMMUTABLE (AX-000/001/002)는 D075 대상 제외

### Role Honesty 자동 호출 (v53 Sprint 2.11)
`artifact_validator.sh`가 `s6_judge_*.json` Write 감지 시 `role_honesty_runner.R` 백그라운드 실행:
- S2/S3/S4 artifact 로드 → `sg_audit_role_honesty()` 실행
- `stage_artifacts/role_honesty_STR_*.json` 생성
- honest=FALSE + violations>0 → exit 1 (Judge는 후처리에서 Grade 재검토)

```r
# 수동 실행 (보통 자동)
Rscript 02_Infrastructure/validation/role_honesty_runner.R stage_artifacts/s6_judge_STR_XXX.json
```

### PIT 감사 — 합리화 표현 11가지 자동 격리 (P2-B)
artifact_validator가 stage_artifacts/*.json Write 시 스캔, 탐지 시 `.p2b_violation` 격리.
목록: pit-validation skill 참조.

### Gate 6: Tail Risk 검증 (Pfaff 2016 기반)
```r
source(file.path(INFRA_DIR, "portfolio/tail_risk_engine.R"))
result <- verify_tail_risk(tail_risk_result, thresholds = list(
  evt_var_oos_gap_max = 0.50, cdar_max = 0.35, tdc_max = 0.30
))
# result$pass == FALSE → FAIL
```
- `tail_risk_result.json` 필수 (Phase 2: task_complete_guard block)

### PIT 감사 — 합리화 8가지 자동 탐지
"영향 미미", "관행적 허용", "보수적이면 괜찮다", "대부분 결과 동일",
"이미 반영되어 있었을 것", "백테스트 기간이 충분히 길어서 상쇄"

### Role Honesty Audit
Core Alpha인데 실제 상관 > 0.8 → REJECT
Diversifier인데 conditional_ic < 0 → REJECT

### L-code 작성 = **S6 EXIT CONDITION**
`stage_artifacts/l_code_{strategy_id}.json` 먼저 생성 → 그 다음 DONE rename.
필드명: `grade`, `lesson_text`, `core_reference` (정확한 키명)
