---
name: risk-research
description: QEPM Risk Research Agent 자율 리서치 루프. Alpha Agent가 생성한 alpha_package를 받아 공동위험 구조 Σ = BΩB' + D + tail risk + stress 진단 생성. 공분산 추정기 자율 선택 (Sample/Ledoit-Wolf/Gerber/DCC-Copula). alpha 수정/weight 제안 절대 금지 (Hook 강제).
---

# /risk-research {WT_id}

Risk Research Agent를 Work Task에 spawn하여 risk_package.json을 자율 생성.

## Prerequisite

- `qepm/mailbox/worktask/{WT_id}/alpha_package.json` 존재 필수
- `worktask_sequence_enforcer.sh` Hook이 선행 검증

## Usage

```
/risk-research WT20260423_001
```

## 5-Step Pipeline

1. Exposure model (B)
2. Factor covariance (Ω)
3. Specific risk (D)
4. Security covariance Σ = BΩB' + D
5. Stress + crowding + liquidity + emission

## 산출

- `qepm/mailbox/worktask/{WT_id}/risk_package.json`
- `stage_artifacts/WT_{id}/covariance.parquet`
- `stage_artifacts/WT_{id}/tail_risk.json`
- `stage_artifacts/WT_{id}/regime_correlation.parquet`

## 제약

- Common Charter 8원칙 강제
- Hook: `agent_role_guard.sh` (Alpha 수정 차단)
- Hook: `worktask_sequence_enforcer.sh` (alpha_package 선행 검증)
- Red Flag 자동 감지

## 완료 후

`/optimizer-research {WT_id}` 다음 단계.
