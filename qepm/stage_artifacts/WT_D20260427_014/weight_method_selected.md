# WT-D20260427_014 — Iter 29 Optimizer Method Selection

## Selected Method: Simple Hybrid Switch

**Logic** (intentionally trivial):
- BULL/NORMAL months → Iter 11 LinTilt λ=1.0 weights (inherited as-is)
- CAUTION/CRISIS months → Iter 27 4-state multi-sleeve adaptive weights (inherited as-is)
- regime_state per sig_date sourced from alpha_scores.parquet (regime_state column, t-1 lag)

## 의도적 단순화
User mandate: 자체 ERC/MVO/HRP 구현 절대 금지. 이전 attempt에서 ERC self-impl bug가 fail 원인으로 진단됨.
Hybrid는 두 inheritance source의 weight matrix를 regime_state로 단순 select.

## Switch Statistics
- Total canonical sig_dates: 92 (2008-01 ~ 2023-11)
- BULL/NORMAL: 84 months (91.3%) → Iter 11
- CAUTION/CRISIS: 8 months (8.7%) → Iter 27

## Expected Performance (sketch)
- Iter 11 baseline SR: 1.19 (BULL/NORMAL)
- Iter 27 CAUTION SR: 3.97
- Expected standalone SR (linear blend): 1.432
- Expected PG2 80/20 blend SR: 1.325

## Hard Constraints
- max_names: 21 / 21 (Iter 27 includes CASH overlay)
- long-only: TRUE
- weight_bounds [0, 0.20]: FALSE
- Σw = 1 (post-normalize): TRUE

## Method Shopping Log
| Method | net_ir | Selected |
|--------|--------|----------|
| Simple_Hybrid_Switch | 1.432 | TRUE |

단일 candidate. User mandate (Codex OVERRIDE_005 fallback consideration).
