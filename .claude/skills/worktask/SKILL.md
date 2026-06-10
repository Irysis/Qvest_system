---
name: worktask
description: QEPM Work Task lifecycle 관리. 1 Work Task = QEPM Full Pipeline 1회 (Alpha → Risk → Optimizer → Forge → Judge → Governor). 생성 / 상태 확인 / 단계 전이 / admission 트리거. 사용자 지정 25종 hard + long-only + Σw=1 자동 강제.
---

# /worktask — Work Task 관리

Work Task는 **QEPM Full Pipeline 1회**를 수행하는 표준 연구 단위.

## Usage

### 생성
```
/worktask create "Rate Hedge Defense - Duration-neutral Quality"
/worktask create "Blender regime-conditional 5-sleeve" --universe KR_top500
```

### 상태 조회
```
/worktask status WT20260423_001
/worktask list        # 진행 중 WT 모두
/worktask list --all  # completed 포함
```

### 단계 전이 (Q-Lead 수동)
```
/worktask advance WT20260423_001 ALPHA_DONE
/worktask advance WT20260423_001 RISK_PENDING
```

### Admission 트리거 (Judge + Governor)
```
/worktask promote WT20260423_001
```

## Work Task Lifecycle

```
SPEC_APPROVED
    ↓
ALPHA_PENDING → ALPHA_RUNNING → ALPHA_DONE
    ↓
RISK_PENDING → RISK_RUNNING → RISK_DONE
    ↓
OPTIMIZER_PENDING → OPTIMIZER_RUNNING → OPTIMIZER_DONE
    ↓
FORGE_PENDING → FORGE_RUNNING → FORGE_DONE
    ↓
JUDGE_PENDING → JUDGE_RUNNING → JUDGE_PASSED / JUDGE_FAILED
    ↓
GOVERNOR_PENDING → GOVERNOR_ADMITTED / GOVERNOR_REJECTED
    ↓
COMPLETED
```

## 파일 구조 (WT당)

```
qepm/mailbox/worktask/WT{YYYYMMDD}_{NNN}/
├── request.json              # Work Task Spec (schema 강제)
├── status.json               # 현 단계
├── governance_log.json       # 결정 이력
├── alpha_package.json        # Alpha Agent 산출 (ALPHA_DONE 후)
├── risk_package.json         # Risk Agent 산출 (RISK_DONE 후)
└── optimization_package.json # Optimizer Agent 산출 (OPTIMIZER_DONE 후)

stage_artifacts/WT_{id}/
├── alpha_hypothesis.json
├── alpha_scores.parquet
├── alpha_validation.json
├── risk_assessment.json
├── covariance.parquet
├── tail_risk.json
├── regime_correlation.parquet
├── optimizer_research.json
├── weights.csv
└── weight_method_selected.md
```

## 자동 강제 제약

**Hook 강제 (Level 3 hard block)**:
- `worktask_spec_validator.sh`: request.json 검증 (task_id 형식 / universe / max_names ≤ 25 / data_lag_rules)
- `worktask_sequence_enforcer.sh`: Alpha → Risk → Optimizer 순서 강제
- `agent_role_guard.sh`: 역할 침범 차단
- `worktask_constraint_enforcer.sh`: 20종 / long-only / bounds / Σw=1

**Hook 감지 (Level 2 soft gate)**:
- `worktask_artifact_validator.sh`: 3-package schema 검증
- `red_flag_detector.sh`: Red Flag 자동 주입

## Q-Lead Orchestration

Work Task 생성 → 순차 실행:

```r
# R
source("02_Infrastructure/worktask/worktask_manager.R")
wt_id <- wt_create("Rate Hedge Defense")
```

```
# Claude
Agent(subagent_type="alpha-research", prompt="Execute WT${wt_id}")
# Alpha 완료 후
Agent(subagent_type="risk-research", prompt="Execute WT${wt_id}")
# Risk 완료 후
Agent(subagent_type="optimizer-research", prompt="Execute WT${wt_id}")
# Optimizer 완료 후
Agent(subagent_type="forge", prompt="Integrate WT${wt_id} 3-agent packages → backtest")
# Forge 완료 후
Agent(subagent_type="judge", prompt="S6 cascade WT${wt_id}")
# Judge PASS 후
Agent(subagent_type="governor", prompt="PG0~PG3 admission WT${wt_id}")
```

## 병렬 실행

- **WT 내부**: 순차 강제 (Alpha → Risk → Optimizer)
- **WT 간**: 병렬 가능 (Q-Lead가 여러 WT 동시 관리)

## 기존 체계와의 관계

- **Scout 대체**: Alpha Research Agent가 S0~S5 통합 담당
- **Legacy 전략**: PG2 active (STR_1631 + STR_1656)는 그대로 유지
- **신규 연구**: Work Task 방식 사용

## 참조

- Schema: `02_Infrastructure/worktask/schema.json`
- Common Charter: `02_Infrastructure/worktask/common_charter.md`
- Red Flag Rules: `02_Infrastructure/worktask/red_flag_rules.md`
- Constraints 기본값: `02_Infrastructure/worktask/constraint_defaults.json`
- Manager: `02_Infrastructure/worktask/worktask_manager.R`
