# Plan v0.4.2 Phase 1 Validation Summary

**Target**: y_onset
**N**: 2531 (events 254 / 10.04%)
**Date**: 2026-05-19 16:14:53

## Gates

| # | Gate | Result | Status |
|---|---|---|---|
| 1 | DM test (HAC lag ≥21) | stat=-0.781 / p=0.7825 | ❌ FAIL |
| 2 | Brier Skill Score | BSS=-0.0281 | ❌ FAIL |
| 3 | Calibration | slope=0.745 / ECE=0.0501 | ❌ FAIL |
| 4 | Event-level recall (top 20%) | recall=0.291 / lift=0.091 | ❌ FAIL |
| 5 | PR-AUC | 0.1272 (lift 26.72%) | ✅ PASS |

## Uncertainty Report
- Bootstrap CI (block 12m, N=1000): BSS = -0.0588 [-0.2261, 0.0071]

## Phase 2 이동 lock (의무)
- Harvey-t (NW) — portfolio return 적용
- DSR (Bailey-LdP)
- AX-001 v2 crisis_alpha
- Net-of-cost simulation

**Phase 1 = forecast validity only. Trading alpha로 해석 금지.**

