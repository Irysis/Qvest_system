# Plan v0.4.2 Phase 1 Validation Summary

**Target**: y_tail_q15
**N**: 2531 (events 530 / 20.94%)
**Date**: 2026-05-19 15:39:00

## Gates

| # | Gate | Result | Status |
|---|---|---|---|
| 1 | DM test (HAC lag ≥21) | stat=-2.303 / p=0.9894 | ❌ FAIL |
| 2 | Brier Skill Score | BSS=-0.0792 | ❌ FAIL |
| 3 | Calibration | slope=0.625 / ECE=0.1402 | ❌ FAIL |
| 4 | Event-level recall (top 20%) | recall=0.345 / lift=0.145 | ❌ FAIL |
| 5 | PR-AUC | 0.3248 (lift 55.09%) | ✅ PASS |

## Uncertainty Report
- Bootstrap CI (block 12m, N=1000): BSS = -0.0623 [-0.1835, 0.0371]

## Phase 2 이동 lock (의무)
- Harvey-t (NW) — portfolio return 적용
- DSR (Bailey-LdP)
- AX-001 v2 crisis_alpha
- Net-of-cost simulation

**Phase 1 = forecast validity only. Trading alpha로 해석 금지.**

