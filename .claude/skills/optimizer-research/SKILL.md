---
name: optimizer-research
description: QEPM Optimizer Research Agent 자율 리서치 루프. Alpha의 α̂ + Risk의 Σ로 target weights 결정. 방법론 자율 탐색(MVO/HRP/CVaR/ERC/BL/Genetic/PPO RL/Ensemble). SR 최대화 방법론을 스스로 발견. 20종 hard + long-only + Σw=1 Hook 강제. Alpha/Risk 재해석 절대 금지.
---

# /optimizer-research {WT_id}

Optimizer Research Agent를 Work Task에 spawn하여 optimization_package.json을 자율 생성.

## Prerequisite

- `qepm/mailbox/worktask/{WT_id}/alpha_package.json`
- `qepm/mailbox/worktask/{WT_id}/risk_package.json`

둘 다 존재 필수. `worktask_sequence_enforcer.sh` Hook이 선행 검증.

## Usage

```
/optimizer-research WT20260423_001
```

## 6-Step Pipeline

1. Feasibility check
2. Objective construction (max x'α̂ - λ/2 x'Σx - φTC(x))
3. Constraint binding (hard + soft + no-trade)
4. **Cost-aware optimization — 방법론 자율 탐색 10+**
5. Sensitivity report
6. Optimization package emission

## 방법론 자율 탐색

Agent가 주어진 Alpha + Risk에서 SR 최대화 방법론 **스스로 발견**:

- Classical MVO / Black-Litterman
- Risk-parity (ERC, HRP)
- Robust (Shrinkage, Worst-case MVO)
- Tail-aware (CVaR LP, CDaR LP)
- Entropy (Max Div, Entropy Pooling)
- ML (Neural portfolio)
- RL (PPO/SAC policy gradient, Genetic)
- Ensemble (meta-weight)

각 방법론 결과 `method_comparison` 기록 (SR/TE/IR/turnover/cost).

## 산출

- `qepm/mailbox/worktask/{WT_id}/optimization_package.json`
- `stage_artifacts/WT_{id}/weights.csv` (monthly)
- `stage_artifacts/WT_{id}/weight_method_selected.md`

## Hard Constraints (Hook 강제)

- max_names ≤ 20
- long-only (weights ≥ 0)
- weight_bounds [0, 0.10]
- Σw = 1 (absolute) / = 0 (active)

## 실패 시

`infeasibility_report` 출력 (제약 완화 금지). HOLD 권고 가능.

## 완료 후

`Forge` spawn → 3-agent 산출물 통합 → backtest.
