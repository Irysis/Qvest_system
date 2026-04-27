# Iter 21 Optimizer Challenge Note

- Task ID: WT-D20260427_005
- Selected policy: P1_dyn_cash
- Generated: 2026-04-27 10:43:47.305345

## Decision Trail

1. Iter 21 mandate: Track 3 Layer (alpha unchanged + optimizer mechanism unchanged + macro overlay layer added).
2. Method shopping: 4 policies (P0 static / P1 dyn cash / P2 + dyn max_w / P3 + dyn TO budget).
3. All policies share LinTilt+EMA+CVaR mechanism (Iter 11 baseline). Differences are purely in (cash_pct, max_w, to_factor) parameter dynamics.
4. Selection rule: max(net_IR) AND TO_PASS AND MDD_PASS, with crisis_mdd_relief vs P0 baseline as layer value-add diagnostic.

## Challenge Targets Reviewed (objection=FALSE)

- alpha_vector inheritance (cor=1.0 spearman, strict ≥ 0.95 PASS)
- risk_sigma local 36m rolling LW shrinkage
- macro overlay msi_norm PIT compliance (expanding window, t-1 lag, KR-only inputs)
- L-220 avoidance (monthly base, NOT quarterly)
- L-226 remediation via LAYER addition (not optimizer mechanism change)
- L-229 Iter 11 baseline preserved (mechanism unchanged)

## Codex Round R1

- Codex CLI stall pattern observed across 6+ instances (Risk Iter 15, Optimizer Iter 15, Alpha Iter 17, Optimizer Iter 18, Alpha Iter 21 R1, ...).
- OVERRIDE_005 fallback armed: substitute evidence = self-comparison 4 candidates + infeasibility_report explicit + Forge backtest decisive.

## Honest Disclosure

- expected_IR=0.1848 << Iter 11 standalone 1.29 — Iter 11 LinTilt baseline 이미 optimal일 가능성. Forge realized 측정 결과로 결정.
- crisis_mdd_relief vs P0 = 3.86 pp (layer value-add diagnostic; PG2 portfolio-level realized SR > 1.4625 + crisis MDD 추가 완화 = Forge backtest의 결정적 평가).
- CVaR_d 2.5% breach disclosed (R12 No Silent Override; Iter 18 precedent).
