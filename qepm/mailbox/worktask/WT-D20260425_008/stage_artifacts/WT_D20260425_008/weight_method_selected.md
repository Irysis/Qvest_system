# Optimizer Iter 3 — Method Selected: HRP_lw

**WT**: WT-D20260425_008
**Date**: 2026-04-25 14:27 KST
**Selection objective**: net_ir (turnover-adjusted)

## Selection rationale

Heavy-tail tie-breaker: HRP_lw selected over top-net_ir MinVar (within 5% net_ir, M08 Hill α=0.46 + SubStab decay 우선 대응)

## Top 5 method comparison (by net_ir)

| Rank | Method | net_IR | IR | TE | n | HHI | max_w | turnover |
|---|---|---|---|---|---|---|---|---|
| 1 | MinVar | 12.7076 | 12.8305 | 0.1470 | 16 | 0.1111 | 0.1500 | 1.0036 |
| 2 | HRP_lw | 12.2905 | 12.3633 | 0.1560 | 20 | 0.0843 | 0.1500 | 0.6308 |
| 3 | HRP_alpha_tilt_05 | 12.0078 | 12.0672 | 0.1713 | 20 | 0.0760 | 0.1500 | 0.5644 |
| 4 | ERC | 11.1950 | 11.2288 | 0.1717 | 20 | 0.0601 | 0.1296 | 0.3226 |
| 5 | ERC_alpha_tilt_05 | 10.9850 | 11.0247 | 0.1926 | 20 | 0.0629 | 0.1162 | 0.4255 |

## Heavy-tail handling (Iter 3 specific)

- M08 Hill α = 0.458 → very heavy tail (Daniel-Moskowitz 2016)
- M08 SubStab = 0.188 → recent decay (P1 0.062 → P3 0.012)
- Returns history simulation: Student-t df=4 (honours heavy tail)
- Tie-breaker rule: heavy-tail-aware methods preferred within 5% of best net_ir
- m08_decay_overlay: conditional spec emitted (vol_target 18%, engaged only if Forge OOS P3 IC < baseline)

## Final portfolio metrics

- N = 20 / 20 (max_names = 20)
- Σw = 1.0000 (target 1.0)
- HHI = 0.0843 (cap 0.12)
- max_w = 0.1500 (user cap 0.20)
- AR = 1.9289 / TE = 0.1560 / IR = 12.3633 / net_IR = 12.2905
- turnover = 0.6308 / cost_ann = 0.0114
- CVaR_95 (sim) = 0.0895 / CVaR_99 (sim) = 0.1137
- beta_port (vs EW bench) = 0.7576

## Q07-M08 joint exposure monitor

- Panel cor (full universe) = 0.0021
- Top-20 portfolio-level cor = -0.2902 (negative → diversifier)
- TDC iter3 = 0.1667 vs baseline 0.4762 (Δ -30.95%)
- Joint top-5 weight share = 0.5614 (alert if > 0.50)
- Top-10 concentration = 0.7692

## Binding constraints

- weight_bound_upper (max=0.1500)
- cvar_95_cap_breach (0.0895)

## PIT compliance

- C2: alpha t-1 lag inherited from alpha_package
- C9: regime-Σ inherited from risk_package
- C13: Z_Score_Aligned only — no manual sign flip in optimizer
- Optimizer scope: weight selection only (no alpha re-interpretation, no Σ re-estimation)
