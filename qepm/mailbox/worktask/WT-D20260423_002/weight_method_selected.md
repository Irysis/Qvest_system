# Weight Method Selected — WT-D20260423_002

## Selection Summary
- **Task**: WT-D20260423_002 (Discovery WT)
- **As-of date**: 2026-04-23
- **Selection objective**: net_ir (R4 P3 HARD)
- **Method selected**: MVO_lam2.0_psi0.3
- **Net IR**: 0.2525
- **N names**: 14 / 20

## Method Rationale
### Why MVO_lam2.0_psi0.3?
1. Risk Agent LOW flag: idio_risk_share_pct=49.6% (>50% → Sigma sparse → MVO 불안정). HRP/ERC 권고.
2. Alpha context: GRAD_FAIL 4/5 (rank_ic=0.0123, icir=0.134, val_ic=-0.0353). 신호 강도 불충분.
3. net_ir 비교 결과 MVO_lam2.0_psi0.3 최우수.
4. Alpha FAIL context에서 risk-parity 방법이 알파 오염 최소화.

## Method Comparison
| Method | net_ir | IR | TE | N |
|--------|--------|----|----|---|
| HRP                            | -0.0629 | -0.0407 | 0.0676 | 20 |
| ERC                            | 0.0293 | 0.0594 | 0.0498 | 20 |
| MVO_lam0.5_psi0.3              | 0.2385 | 0.2579 | 0.0773 | 15 |
| MVO_lam1.0_psi0.3              | 0.2442 | 0.2643 | 0.0747 | 14 |
| MVO_lam2.0_psi0.3              | 0.2525 | 0.2739 | 0.0702 | 14 |
| HRP_alpha_tilt                 | 0.1485 | 0.1680 | 0.0771 | 9 |
| ERC_confidence                 | 0.2038 | 0.2314 | 0.0545 | 12 |

## v6.1 Compliance
- R4 P3: selection_objective = net_ir CONFIRMED
- R4-A: confidence_vector 전달 (MVO candidates)
- R3: Challenge review 완료 (objection=FALSE)
- R11: Lineage 직접 호출 완료
- R12: Silent override 없음. 모든 hard constraint 통과.

## Hard Constraints
- max_names <= 20: 14 PASS
- long-only: PASS
- weight_bounds [0, 0.20]: PASS
- Sigma w = 1: 1.000000 PASS

## Alpha FAIL Note
Discovery WT이므로 breadth 20~30 허용.
신호 재설계 alt_A (KR rate regime 조건부) 또는 alt_C (4-factor OLS) 검토 후 Deployment WT 전환 필요.

